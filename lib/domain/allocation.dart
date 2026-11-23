// Allocation proposals for paychecks and extra money. Pure: nothing is committed here.
import '../core/money.dart';
import 'finance.dart';
import 'plan.dart';

/// goal = vault deposit; category = extra budget boost; bills / covered (an existing budget) / unallocated = money stays put.
enum TargetKind { goal, category, bills, covered, unallocated }

class AllocationLine {
  final TargetKind kind;
  final String? targetId;
  final String label;
  int cents;
  AllocationLine(this.kind, this.targetId, this.label, this.cents);
  AllocationLine copy() => AllocationLine(kind, targetId, label, cents);
}

class Proposal {
  final int total;
  final List<AllocationLine> lines;
  Proposal(this.total, this.lines);
  int get allocated => lines.fold(0, (s, l) => s + l.cents);
  int get leftover => total - allocated;
  bool get valid => leftover >= 0 && lines.every((l) => l.cents >= 0);
}

/// How much of new money should stay free to cover bills before the following payday.
int billShortfall(FinanceData f) {
  final free = f.totalMoney - f.totalSaved;
  return (f.reservedForBills - free).clamp(0, f.reservedForBills);
}

/// Paycheck split, in order of what can't be missed:
/// 1. bills due before the next payday,
/// 2. this period's budgets (essentials first: food, gas...), so the week is actually funded,
/// 3. each savings goal's planned contribution (scaled down if money runs short),
/// 4. whatever is left is free money.
/// Money you already had covers bills and budgets first, so the paycheck only fills the gap.
/// Computed BEFORE the paycheck is recorded.
Proposal suggestPaycheck(FinanceData f, int amount) {
  final lines = <AllocationLine>[];
  var left = amount;
  var pool = (f.totalMoney - f.totalSaved).clamp(0, 1 << 40); // money you already have outside vaults

  final billsNeed = (f.reservedForBills - pool).clamp(0, left);
  pool = (pool - f.reservedForBills).clamp(0, 1 << 40);
  if (billsNeed > 0) {
    lines.add(AllocationLine(TargetKind.bills, null, 'Keep for upcoming bills', billsNeed));
    left -= billsNeed;
  }

  final budgets = f.categoryStatuses.where((s) => s.hasLimit && s.remaining > 0).toList()
    ..sort((a, b) => (b.category.essential ? 1 : 0) - (a.category.essential ? 1 : 0));
  for (final s in budgets) {
    final fromPool = s.remaining.clamp(0, pool);
    pool -= fromPool;
    final need = (s.remaining - fromPool).clamp(0, left);
    if (need > 0) {
      lines.add(AllocationLine(TargetKind.covered, s.category.id, '${s.category.name} budget (${s.category.period == 'monthly' ? 'this month' : 'this week'})', need));
      left -= need;
    }
  }
  final wants = [
    for (final s in f.goalStatuses)
      if (!s.complete && s.goal.contributionCents > 0 && s.goal.contributionFreq != 'none')
        (s, s.goal.contributionCents.clamp(0, s.remaining))
  ];
  final totalWant = wants.fold(0, (a, w) => a + w.$2);
  final shares = totalWant <= left ? [for (final w in wants) w.$2] : splitByWeights(left, [for (final w in wants) w.$2]);
  for (var i = 0; i < wants.length; i++) {
    if (shares[i] > 0) lines.add(AllocationLine(TargetKind.goal, wants[i].$1.goal.id, wants[i].$1.goal.name, shares[i]));
    left -= shares[i];
  }
  if (left > 0) lines.add(AllocationLine(TargetKind.unallocated, null, 'Free money (no job yet)', left));
  return Proposal(amount, lines);
}

/// Extra money auto-split. Spreads the WHOLE amount:
/// 1. covers a real bills shortfall (at most half the money),
/// 2. covers non-essential categories that are already over budget,
/// 3. splits everything left across your goals and budget categories in the same proportions as
///    your weekly plan (goal targets + category limits). Every line can be edited or removed.
Proposal suggestExtra(FinanceData f, int amount) {
  final lines = <AllocationLine>[];
  var left = amount;
  final bills = billShortfall(f).clamp(0, amount ~/ 2);
  if (bills > 0) {
    lines.add(AllocationLine(TargetKind.bills, null, 'Keep for upcoming bills', bills));
    left -= bills;
  }
  for (final c in f.categoryStatuses.where((c) => c.over && !c.category.essential)) {
    final cover = (-c.remaining).clamp(0, left);
    if (cover > 0) {
      lines.add(AllocationLine(TargetKind.category, c.category.id, 'Cover ${c.category.name} overspend', cover));
      left -= cover;
    }
  }
  if (left <= 0) return Proposal(amount, lines);

  // Targets weighted by the weekly plan; goals with no target date still get a share by remaining need.
  final plan = buildWeeklyPlan(f);
  final targets = <(TargetKind, String, String, int)>[];
  for (final l in plan.lines) {
    if (l.id == null || l.weekly <= 0) continue;
    if (l.kind == PlanKind.goal) targets.add((TargetKind.goal, l.id!, l.name, l.weekly));
    if (l.kind == PlanKind.spending || l.kind == PlanKind.essential) targets.add((TargetKind.category, l.id!, l.name, l.weekly));
  }
  final planned = {for (final t in targets) t.$2};
  for (final g in f.goalStatuses.where((g) => !g.complete && !planned.contains(g.goal.id))) {
    targets.add((TargetKind.goal, g.goal.id, g.goal.name, (g.remaining ~/ 52).clamp(1, 1 << 40)));
  }
  if (targets.isEmpty) {
    lines.add(AllocationLine(TargetKind.unallocated, null, 'Unallocated', left));
    return Proposal(amount, lines);
  }
  final parts = splitByWeights(left, [for (final t in targets) t.$4]);
  var rest = 0;
  for (var i = 0; i < targets.length; i++) {
    var p = parts[i];
    if (targets[i].$1 == TargetKind.goal) {
      final g = f.goalStatuses.firstWhere((g) => g.goal.id == targets[i].$2);
      if (p > g.remaining) {
        rest += p - g.remaining; // never overfill a goal
        p = g.remaining;
      }
    }
    if (p > 0) lines.add(AllocationLine(targets[i].$1, targets[i].$2, targets[i].$3, p));
  }
  if (rest > 0) lines.add(AllocationLine(TargetKind.unallocated, null, 'Unallocated', rest));
  return Proposal(amount, lines);
}
