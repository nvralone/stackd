// Allocation proposals for paychecks and extra money. Pure: nothing is committed here.
import '../core/dates.dart';
import '../data/models.dart';
import '../core/money.dart';
import 'bills.dart' as billing;
import 'finance.dart';
import 'plan.dart';

export 'finance.dart' show billSavingsName;

/// goal = vault deposit; category = extra budget boost; covered = this period's budget for a category (editing it
/// changes that budget); billSavings = deposit into the Bill envelope for one bill (targetId = bill id);
/// bills = money that stays in your accounts for a bill due before payday (targetId = bill id); unallocated = free.
enum TargetKind { goal, category, bills, covered, billSavings, unallocated }

int _intervalDays(String freq) => switch (freq) { 'weekly' => 7, 'biweekly' => 14, 'semimonthly' => 15, 'monthly' => 30, 'yearly' => 365, _ => 100000 };

// ---------------------------------------------------------------- paydays

/// Regular paydays from every active schedule in [from, to). Irregular income is never assumed.
List<DateTime> paydaysBetween(FinanceData f, DateTime from, DateTime to) {
  final out = <DateTime>{};
  for (final s in f.schedules) {
    if (!s.active || s.frequency == 'irregular') continue;
    var d = nextOccurrence(s.anchorDate, s.frequency, from);
    for (var guard = 0; d != null && d.isBefore(to) && guard < 500; guard++) {
      out.add(d);
      d = nextOccurrence(s.anchorDate, s.frequency, addDays(d, 1));
    }
  }
  return out.toList()..sort();
}

/// The payday this paycheck belongs to: the last regular payday on or before today (today if there is none).
DateTime currentPayday(FinanceData f) {
  final recent = paydaysBetween(f, addDays(f.todayDate, -40), addDays(f.todayDate, 1));
  return recent.isEmpty ? f.todayDate : recent.last;
}

/// Paychecks that can still go toward something due on [due], counting the current one.
/// A payday on the due date itself does not count (the money may arrive too late).
int paychecksUntil(FinanceData f, DateTime due) {
  final regular = f.schedules.any((s) => s.active && s.frequency != 'irregular');
  if (!regular) return ceilDiv(daysBetween(f.todayDate, due), f.paydayIntervalDays).clamp(1, 1000);
  final start = currentPayday(f);
  final current = paydaysBetween(f, start, addDays(start, 1)).isEmpty ? 1 : 0; // today isn't a payday
  return (paydaysBetween(f, start, due).length + current).clamp(1, 1000);
}

// ---------------------------------------------------------------- per-bill needs

/// One existing bill's place in a paycheck plan. All amounts in cents.
class BillNeed {
  final Bill bill;
  final DateTime due; // earliest unpaid due date
  final int amount; // what the open payment(s) cost
  final int paid; // partial payments already made on them
  final int inEnvelope; // Bill envelope money set aside for this bill
  final int fromMoneyYouHave; // bills before payday: covered by money already in your accounts
  final int paychecksLeft; // paychecks before the due date, counting this one
  final int recommended; // suggested from this paycheck
  final bool beforePayday; // due before the next payday: all of it is needed now
  const BillNeed(this.bill, this.due, this.amount, this.paid, this.inEnvelope, this.fromMoneyYouHave, this.paychecksLeft,
      this.recommended, this.beforePayday);
  String get name => bill.name;
  int get setAside => inEnvelope + fromMoneyYouHave;
  int get stillNeeded => (amount - paid - setAside).clamp(0, amount);
  int get perPaycheck => recommended;
}

/// What every existing bill still needs from paychecks. Nothing is created or changed.
/// - Bills due before the next payday need everything still unpaid, minus envelope money set aside for
///   them, minus money you already have in your accounts ([pool], applied soonest due first).
/// - Bills that come less often than you get paid (monthly insurance when paid weekly), due later within
///   ~3 months, get an even share per paycheck: what's still needed / paychecks left. Money already added
///   for a bill since the last payday counts toward this paycheck's share, so it's never asked for twice.
/// [extraHeld]: envelope money the user chose to assign to a bill (on top of what's already set aside).
List<BillNeed> billNeeds(FinanceData f, {int pool = 0, Map<String, int> extraHeld = const {}}) {
  final until = addDays(f.horizonEnd, 1);
  final window = addDays(f.todayDate, 96);
  final interval = f.paydayIntervalDays;
  final payday = currentPayday(f);
  final env = f.billEnvelope;
  final since = <String, int>{};
  if (env != null) {
    for (final e in f.ledger.active) {
      if (e.goalId == env.id && e.billId != null && e.kind == 'goal_deposit' && !e.occurredOn.isBefore(payday)) {
        since[e.billId!] = (since[e.billId!] ?? 0) + e.amountCents;
      }
    }
  }
  final near = <BillNeed>[], later = <BillNeed>[];
  for (final b in f.bills.where((b) => !b.archived && !b.incoming)) {
    final open = billing.occurrences(b, f.ledger, f.overrides, window, now: f.now).where((o) => o.open).toList();
    if (open.isEmpty) continue;
    final soon = open.where((o) => o.due.isBefore(until)).toList();
    var held = (f.billEarmarks[b.id] ?? 0) + (extraHeld[b.id] ?? 0);
    if (soon.isNotEmpty) {
      final amount = soon.fold(0, (s, o) => s + o.amountCents);
      final paid = soon.fold(0, (s, o) => s + o.paidCents);
      final env = held.clamp(0, amount - paid);
      held -= env; // whatever is left of the envelope money goes toward the bill's next payment
      near.add(BillNeed(b, soon.first.due, amount, paid, env, 0, 1, amount - paid - env, true));
    }
    // Bills that come less often than paydays also save ahead for their next payment after payday.
    final o = open.where((o) => !o.due.isBefore(until)).firstOrNull;
    if (o != null && _intervalDays(b.frequency) > interval) {
      final env = held.clamp(0, o.remainingCents);
      final n = paychecksUntil(f, o.due);
      final s = (since[b.id] ?? 0).clamp(0, env);
      final atStart = o.remainingCents - (env - s); // still needed when this pay period began
      final rec = (ceilDiv(atStart, n) - s).clamp(0, o.remainingCents - env);
      later.add(BillNeed(b, o.due, o.amountCents, o.paidCents, env, 0, n, rec, false));
    }
  }
  near.sort((a, b) => a.due.compareTo(b.due));
  later.sort((a, b) => a.due.compareTo(b.due));
  // Money you already have covers bills before payday first, soonest due first.
  var left = pool;
  final covered = [
    for (final n in near)
      () {
        final use = n.recommended.clamp(0, left);
        left -= use;
        return BillNeed(n.bill, n.due, n.amount, n.paid, n.inEnvelope, use, 1, n.recommended - use, true);
      }(),
  ];
  return [...covered, ...later];
}

/// Bills due after the next payday that the Bill envelope is saving for.
List<BillNeed> laterBills(FinanceData f) => billNeeds(f).where((n) => !n.beforePayday).toList();

/// How much this paycheck should add to the Bill envelope (sum of the later bills' shares).
int billSavingsNeed(FinanceData f) => laterBills(f).fold(0, (s, n) => s + n.recommended);

/// Splits [cents] going into the Bill envelope across later bills by their recommended shares, soonest first.
/// Anything beyond the recommendations stays unassigned (no bill).
Map<String?, int> envelopeSplit(FinanceData f, int cents) {
  final out = <String?, int>{};
  var left = cents;
  for (final n in laterBills(f)) {
    final take = n.recommended.clamp(0, left);
    if (take > 0) out[n.bill.id] = take;
    left -= take;
  }
  if (left > 0) out[null] = left;
  return out;
}

class AllocationLine {
  final TargetKind kind;
  final String? targetId;
  final String label;
  int cents;
  /// Bill lines: the numbers behind the suggestion (due date, already set aside, paychecks left).
  final BillNeed? need;
  AllocationLine(this.kind, this.targetId, this.label, this.cents, {this.need});
  AllocationLine copy() => AllocationLine(kind, targetId, label, cents, need: need);
}

class Proposal {
  final int total;
  final List<AllocationLine> lines;
  /// Every bill looked at, including ones already fully set aside (recommended 0).
  final List<BillNeed> bills;
  /// Unassigned Bill envelope money the user chose to assign: bill id -> cents (moved inside the envelope).
  final Map<String, int> assign;
  Proposal(this.total, this.lines, {this.bills = const [], this.assign = const {}});
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
/// 1. bills due before the next payday (each bill, soonest first),
/// 2. essential budgets for this period (food, gas...),
/// 3. each later bill's share into the Bill envelope (monthly insurance, subscriptions), soonest first,
/// 4. the other budgets for this period,
/// 5. each savings goal's planned contribution (scaled down if money runs short),
/// 6. whatever is left is free money.
/// Money you already had covers bills and budgets first, so the paycheck only fills the gap.
/// Only existing bills are used. Savings are never touched. Computed BEFORE the paycheck is recorded;
/// nothing is committed here. [useUnassigned]: let unassigned Bill envelope money count toward bills
/// (soonest first) - only when the user asks for it.
Proposal suggestPaycheck(FinanceData f, int amount, {bool useUnassigned = false}) {
  final lines = <AllocationLine>[];
  var left = amount;
  var pool = (f.totalMoney - f.totalSaved).clamp(0, 1 << 40); // money you already have outside vaults

  var needs = billNeeds(f, pool: pool);
  final assign = <String, int>{};
  if (useUnassigned) {
    var u = f.billEnvelopeUnassigned;
    for (final n in needs) {
      // before payday: only what money you have doesn't cover; later: up to the whole remaining amount
      final want = n.beforePayday ? n.recommended : n.stillNeeded;
      final take = want.clamp(0, u);
      if (take > 0) assign[n.bill.id] = (assign[n.bill.id] ?? 0) + take;
      u -= take;
    }
    if (assign.isNotEmpty) needs = billNeeds(f, pool: pool, extraHeld: assign);
  }
  final nearAssigned = needs.where((n) => n.beforePayday).fold<int>(0, (s, n) => s + (assign[n.bill.id] ?? 0));
  pool = (pool - f.reservedForBills + nearAssigned).clamp(0, 1 << 40).toInt();

  String dueText(BillNeed n) => n.due.isBefore(f.todayDate) ? 'overdue' : 'due ${prettyDate(n.due)}';
  for (final n in needs.where((n) => n.beforePayday && n.recommended > 0)) {
    final c = n.recommended.clamp(0, left);
    lines.add(AllocationLine(TargetKind.bills, n.bill.id, '${n.name} (${dueText(n)})', c, need: n));
    left -= c;
  }

  final budgets = f.categoryStatuses.where((s) => s.hasLimit && s.remaining > 0).toList();
  void fund(Iterable<CategoryStatus> list) {
    for (final s in list) {
      final fromPool = s.remaining.clamp(0, pool);
      pool -= fromPool;
      final need = (s.remaining - fromPool).clamp(0, left);
      if (need > 0) {
        lines.add(AllocationLine(TargetKind.covered, s.category.id, '${s.category.name} budget (${s.category.period == 'monthly' ? 'this month' : 'this week'})', need));
        left -= need;
      }
    }
  }

  fund(budgets.where((s) => s.category.essential));
  for (final n in needs.where((n) => !n.beforePayday && n.recommended > 0)) {
    final c = n.recommended.clamp(0, left);
    if (c > 0 || left == 0) lines.add(AllocationLine(TargetKind.billSavings, n.bill.id, '${n.name} (${dueText(n)})', c, need: n));
    left -= c;
  }
  fund(budgets.where((s) => !s.category.essential));
  final wants = [
    for (final s in f.goalStatuses)
      if (!s.complete && s.goal.name != billSavingsName && s.goal.contributionCents > 0 && s.goal.contributionFreq != 'none')
        (s, s.goal.contributionCents.clamp(0, s.remaining))
  ];
  final totalWant = wants.fold(0, (a, w) => a + w.$2);
  final shares = totalWant <= left ? [for (final w in wants) w.$2] : splitByWeights(left, [for (final w in wants) w.$2]);
  for (var i = 0; i < wants.length; i++) {
    if (shares[i] > 0) lines.add(AllocationLine(TargetKind.goal, wants[i].$1.goal.id, wants[i].$1.goal.name, shares[i]));
    left -= shares[i];
  }
  if (left > 0) lines.add(AllocationLine(TargetKind.unallocated, null, 'Free money (no job yet)', left));
  return Proposal(amount, lines, bills: needs, assign: assign);
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
