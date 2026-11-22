// Weekly plan: recommends how much of a typical week's income goes to bills, essentials,
// savings goals and spending categories. Pure suggestion; applying it requires confirmation.
import '../core/dates.dart';
import '../core/money.dart';
import '../data/models.dart';
import 'bills.dart' as billing;
import 'finance.dart';

enum PlanKind { bill, essential, goal, spending, buffer }

class PlanLine {
  final PlanKind kind;
  final String? id; // bill / category / goal id
  final String name, why;
  final int weekly; // recommended cents per week
  final int current; // what's set today, per week (limit / contribution), 0 if none
  const PlanLine(this.kind, this.id, this.name, this.weekly, this.current, this.why);
}

class WeeklyPlan {
  final int income; // weekly income the plan is built on
  final String incomeSource; // where that number came from
  final List<PlanLine> lines;
  final int shortfall; // fixed costs (bills + essentials) above income
  const WeeklyPlan(this.income, this.incomeSource, this.lines, this.shortfall);
  int get planned => lines.fold(0, (s, l) => s + l.weekly);
  Iterable<PlanLine> of(PlanKind k) => lines.where((l) => l.kind == k);
  int total(PlanKind k) => of(k).fold(0, (s, l) => s + l.weekly);
}

/// Converts an amount on a schedule into a per-week amount (exact integer math, rounded down).
int perWeek(int cents, String frequency) => switch (frequency) {
      'weekly' => cents,
      'biweekly' => cents ~/ 2,
      'semimonthly' => cents * 24 ~/ 52,
      'monthly' => cents * 12 ~/ 52,
      'yearly' => cents ~/ 52,
      _ => 0,
    };

int _limitPerWeek(Category c) => c.limitCents == null ? 0 : (c.period == 'monthly' ? c.limitCents! * 12 ~/ 52 : c.limitCents!);

WeeklyPlan buildWeeklyPlan(FinanceData f) {
  // 1. Income: expected paychecks, else the last 8 weeks' average earned income.
  var income = 0;
  for (final s in f.schedules.where((s) => s.active)) {
    income += perWeek(s.expectedCents, s.frequency);
  }
  var source = 'your payday schedule';
  if (income == 0) {
    income = f.ledger.totals(addDays(f.thisWeek.start, -56), f.thisWeek.start).income ~/ 8;
    source = 'your average income (last 8 weeks)';
  }

  final lines = <PlanLine>[];

  // 2. Bills: recurring per-week cost; debts only while something is still owed.
  for (final b in f.bills.where((b) => !b.archived && !b.incoming)) {
    if (b.frequency == 'once') {
      final o = billing.nextOpen(b, f.ledger, f.overrides, now: f.now);
      if (o == null) continue;
      final weeks = (daysBetween(f.todayDate, o.due) ~/ 7).clamp(1, 520);
      lines.add(PlanLine(PlanKind.bill, b.id, b.name, ceilDiv(o.remainingCents, weeks), 0, 'one-time, due ${prettyDate(o.due)}'));
      continue;
    }
    final left = billing.remainingOwed(b, f.ledger);
    if (left != null && left <= 0) continue;
    final w = perWeek(b.amountCents, b.frequency);
    lines.add(PlanLine(PlanKind.bill, b.id, b.name, left == null ? w : w.clamp(0, left), w, '${b.frequency} bill'));
  }

  // 3. Essential categories: keep their limits (or recent pace if no limit).
  final cats = f.categories.where((c) => !c.archived).toList();
  int pace(Category c) => f.ledger.categorySpent(c.id, addDays(f.thisWeek.start, -28), f.thisWeek.start) ~/ 4;
  for (final c in cats.where((c) => c.essential)) {
    final w = c.limitCents != null ? _limitPerWeek(c) : pace(c);
    if (w > 0) lines.add(PlanLine(PlanKind.essential, c.id, c.name, w, _limitPerWeek(c), c.limitCents != null ? 'your limit' : 'recent spending'));
  }

  final fixed = lines.fold(0, (s, l) => s + l.weekly);
  final shortfall = (fixed - income).clamp(0, 1 << 40);
  var left = (income - fixed).clamp(0, 1 << 40);

  // 4. Wants: goals (to hit target date, else planned contribution) and spending categories.
  final goalWants = <(GoalStatus, int, String)>[];
  for (final g in f.goalStatuses.where((g) => !g.complete)) {
    final t = g.goal.targetDate;
    if (t != null && t.isAfter(f.todayDate)) {
      goalWants.add((g, ceilDiv(g.remaining, (daysBetween(f.todayDate, t) ~/ 7).clamp(1, 520)), 'to finish by ${prettyDate(t)}'));
    } else if (g.goal.contributionCents > 0 && g.goal.contributionFreq != 'none') {
      final freq = g.goal.contributionFreq == 'payday'
          ? (f.schedules.where((s) => s.active && s.frequency != 'irregular').firstOrNull?.frequency ?? 'weekly')
          : g.goal.contributionFreq;
      goalWants.add((g, perWeek(g.goal.contributionCents, freq), 'your planned contribution'));
    } else {
      goalWants.add((g, 0, 'share of what\'s left'));
    }
  }
  final spendWants = <(Category, int, String)>[
    for (final c in cats.where((c) => !c.essential))
      if (c.limitCents != null) (c, _limitPerWeek(c), 'your limit') else if (pace(c) > 0) (c, pace(c), 'recent spending')
  ];

  final wantTotal = goalWants.fold<int>(0, (s, g) => s + g.$2) + spendWants.fold<int>(0, (s, c) => s + c.$2);
  List<int> give;
  if (wantTotal > left) {
    // Not enough: scale every want down proportionally.
    give = splitByWeights(left, [...goalWants.map((g) => g.$2), ...spendWants.map((c) => c.$2)]);
    left = 0;
  } else {
    give = [...goalWants.map((g) => g.$2), ...spendWants.map((c) => c.$2)];
    left -= wantTotal;
  }

  // 5. Extra: half of any surplus to goals (by remaining need), the rest stays as a buffer.
  final extra = List<int>.filled(goalWants.length, 0);
  if (left > 0 && goalWants.isNotEmpty) {
    final toGoals = left ~/ 2;
    final parts = splitByWeights(toGoals, [for (final g in goalWants) g.$1.remaining]);
    for (var i = 0; i < parts.length; i++) {
      extra[i] = parts[i];
    }
    left -= parts.fold<int>(0, (s, p) => s + p);
  }

  for (var i = 0; i < goalWants.length; i++) {
    final (g, want, why) = goalWants[i];
    final w = (give[i] + extra[i]).clamp(0, g.remaining);
    left += give[i] + extra[i] - w; // anything over the remaining goal returns to buffer
    final cur = g.goal.contributionFreq == 'weekly' ? g.goal.contributionCents : 0;
    lines.add(PlanLine(PlanKind.goal, g.goal.id, g.goal.name, w, cur, give[i] < want ? '$why (scaled down to fit)' : why));
  }
  for (var j = 0; j < spendWants.length; j++) {
    final (c, want, why) = spendWants[j];
    final w = give[goalWants.length + j];
    lines.add(PlanLine(PlanKind.spending, c.id, c.name, w, _limitPerWeek(c), w < want ? '$why (scaled down to fit)' : why));
  }
  if (left > 0) lines.add(PlanLine(PlanKind.buffer, null, 'Free / buffer', left, 0, 'unplanned money for anything else'));

  return WeeklyPlan(income, source, lines, shortfall);
}

/// Converts a weekly amount to the category's own period for saving as its limit.
int limitForPeriod(int weekly, String period) => period == 'monthly' ? weekly * 52 ~/ 12 : weekly;
