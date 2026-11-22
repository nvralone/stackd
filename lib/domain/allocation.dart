// Allocation proposals for paychecks and extra money. Pure: nothing is committed here.
import '../core/money.dart';
import 'finance.dart';

enum TargetKind { goal, category, bills, unallocated }

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

/// Paycheck: bills shortfall, then each goal's planned payday contribution, rest is spending money.
Proposal suggestPaycheck(FinanceData f, int amount) {
  final lines = <AllocationLine>[];
  var left = amount;
  final bills = billShortfall(f).clamp(0, left);
  if (bills > 0) {
    lines.add(AllocationLine(TargetKind.bills, null, 'Keep for upcoming bills', bills));
    left -= bills;
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
  if (left > 0) lines.add(AllocationLine(TargetKind.unallocated, null, 'Spending money', left));
  return Proposal(amount, lines);
}

/// Extra money: bills shortfall, overspent categories, then half of the rest to goals by remaining need.
Proposal suggestExtra(FinanceData f, int amount) {
  final lines = <AllocationLine>[];
  var left = amount;
  final bills = billShortfall(f).clamp(0, left);
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
  final open = f.goalStatuses.where((g) => !g.complete).toList();
  if (open.isNotEmpty && left > 0) {
    final toGoals = left ~/ 2;
    final parts = splitByWeights(toGoals, [for (final g in open) g.remaining]);
    for (var i = 0; i < open.length; i++) {
      final p = parts[i].clamp(0, open[i].remaining);
      if (p > 0) {
        lines.add(AllocationLine(TargetKind.goal, open[i].goal.id, open[i].goal.name, p));
        left -= p;
      }
    }
  }
  if (left > 0) lines.add(AllocationLine(TargetKind.unallocated, null, 'Unallocated', left));
  return Proposal(amount, lines);
}
