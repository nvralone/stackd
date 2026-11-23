// Analytics + weekly recap built from real ledger data.
import '../core/dates.dart';
import '../core/money.dart';
import '../data/models.dart';
import 'finance.dart';
import 'ledger.dart';

class SeriesPoint {
  final DateTime start;
  final int income, spent, saved;
  const SeriesPoint(this.start, this.income, this.spent, this.saved);
}

/// Last [n] weeks, oldest first.
List<SeriesPoint> weeklySeries(FinanceData f, {int n = 8}) {
  final cur = f.thisWeek.start;
  return [
    for (var i = n - 1; i >= 0; i--)
      () {
        final s = addDays(cur, -7 * i);
        final t = f.ledger.totals(s, addDays(s, 7));
        return SeriesPoint(s, t.income, t.netSpent, t.netSaved);
      }()
  ];
}

/// Last [n] calendar months, oldest first.
List<SeriesPoint> monthlySeries(FinanceData f, {int n = 6}) {
  final cur = monthStartOf(f.todayDate);
  return [
    for (var i = n - 1; i >= 0; i--)
      () {
        final s = addMonths(cur, -i);
        final t = f.ledger.totals(s, addMonths(s, 1));
        return SeriesPoint(s, t.income, t.netSpent, t.netSaved);
      }()
  ];
}

class CategorySlice {
  final Category? category; // null = uncategorized
  final int cents, previous;
  const CategorySlice(this.category, this.cents, this.previous);
  int get change => cents - previous;
}

/// Spending by category in [start,end) vs the same-length previous range, largest first.
List<CategorySlice> categoryBreakdown(FinanceData f, DateTime start, DateTime end) {
  final len = daysBetween(start, end);
  final pStart = addDays(start, -len);
  Map<String?, int> sum(DateTime a, DateTime b) {
    final m = <String?, int>{};
    for (final e in f.ledger.between(a, b)) {
      final sign = switch (e.kind) { 'expense' || 'bill_payment' => 1, 'refund' => -1, _ => 0 };
      if (sign != 0) m[e.categoryId] = (m[e.categoryId] ?? 0) + sign * e.amountCents;
    }
    return m;
  }
  final now = sum(start, end), prev = sum(pStart, start);
  final keys = {...now.keys, ...prev.keys};
  return [for (final k in keys) CategorySlice(f.category(k), now[k] ?? 0, prev[k] ?? 0)]
    ..removeWhere((s) => s.cents == 0 && s.previous == 0)
    ..sort((a, b) => b.cents.compareTo(a.cents));
}

class ReductionIdea {
  final Category category;
  final int currentWeekly, typicalWeekly;
  const ReductionIdea(this.category, this.currentWeekly, this.typicalWeekly);
  int get possibleSaving => currentWeekly - typicalWeekly;
}

/// Non-essential categories where this week is above the 4-week average. Suggestions only.
List<ReductionIdea> reductionIdeas(FinanceData f) {
  final w = f.thisWeek;
  final out = <ReductionIdea>[];
  for (final c in f.categories.where((c) => !c.essential && !c.archived)) {
    final cur = f.ledger.categorySpent(c.id, w.start, w.end);
    final prev4 = f.ledger.categorySpent(c.id, addDays(w.start, -28), w.start) ~/ 4;
    if (cur > prev4 && cur > 0) out.add(ReductionIdea(c, cur, prev4));
  }
  return out..sort((a, b) => b.possibleSaving.compareTo(a.possibleSaving));
}

/// Monthly cost of recurring bills (normalised).
List<(Bill, int)> recurringMonthly(FinanceData f) => [
      for (final b in f.bills.where((b) => !b.archived && !b.isDebt && b.frequency != 'once'))
        (b, switch (b.frequency) {
          'weekly' => b.amountCents * 52 ~/ 12,
          'biweekly' => b.amountCents * 26 ~/ 12,
          'yearly' => b.amountCents ~/ 12,
          _ => b.amountCents,
        })
    ]..sort((a, b) => b.$2.compareTo(a.$2));

({int total, int visits, int previousTotal}) fastFood(FinanceData f) {
  final c = f.categoryByTag('fast_food');
  if (c == null) return (total: 0, visits: 0, previousTotal: 0);
  final w = f.thisWeek, p = f.lastWeek;
  final visits = f.ledger.between(w.start, w.end).where((e) => e.categoryId == c.id && e.kind == 'expense').length;
  return (total: f.ledger.categorySpent(c.id, w.start, w.end), visits: visits, previousTotal: f.ledger.categorySpent(c.id, p.start, p.end));
}

// ---------------------------------------------------------------- weekly recap
class WeeklyRecap {
  final DateTime start, end;
  final PeriodTotals totals, previous;
  final List<CategorySlice> categories;
  final List<CategoryStatus> overBudget;
  final int emergencyWithdrawals, otherWithdrawals;
  final int billsNext7, availableNow;
  final List<GoalStatus> vacations;
  final List<GoalStatus> completedGoals;
  final int fastFoodTotal, fastFoodVisits;
  final int weeksImproving; // consecutive weeks net spending went down
  const WeeklyRecap(this.start, this.end, this.totals, this.previous, this.categories, this.overBudget,
      this.emergencyWithdrawals, this.otherWithdrawals, this.billsNext7, this.availableNow, this.vacations,
      this.completedGoals, this.fastFoodTotal, this.fastFoodVisits, this.weeksImproving);

  bool get empty => totals.income == 0 && totals.netSpent == 0 && totals.saved == 0 && totals.withdrawn == 0;
  /// Bills reserved before payday exceed free money.
  bool get billsAtRisk => billsNext7 > 0 && availableNow < 0;
  int get spendChange => totals.netSpent - previous.netSpent;
}

/// Recap for the week starting [weekStartDate] (defaults to last completed week).
WeeklyRecap buildRecap(FinanceData f, {DateTime? weekStartDate}) {
  final s = weekStartDate ?? f.lastWeek.start;
  final e = addDays(s, 7);
  final t = f.ledger.totals(s, e);
  final p = f.ledger.totals(addDays(s, -7), s);
  var emergency = 0, other = 0;
  for (final ev in f.ledger.between(s, e).where((x) => x.kind == 'goal_withdraw')) {
    ev.reason == 'emergency' ? emergency += ev.amountCents : other += ev.amountCents;
  }
  final over = [for (final c in f.categories.where((c) => !c.archived && c.limitCents != null)) f.categoryStatus(c, at: s)]
      .where((c) => c.over)
      .toList();
  final upcoming = f.upcomingBills(days: 7).where((o) => !o.bill.incoming).fold(0, (a, o) => a + o.remainingCents);
  final vac = f.goalStatuses.where((g) => g.goal.tripId != null).toList();
  final completed = f.goalStatuses.where((g) => g.complete).toList();
  final ffc = f.categoryByTag('fast_food');
  var ffTotal = 0, ffVisits = 0;
  if (ffc != null) {
    ffTotal = f.ledger.categorySpent(ffc.id, s, e);
    ffVisits = f.ledger.between(s, e).where((x) => x.categoryId == ffc.id && x.kind == 'expense').length;
  }
  var improving = 0;
  for (var i = 0; i < 8; i++) {
    final a = f.ledger.totals(addDays(s, -7 * i), addDays(s, -7 * i + 7)).netSpent;
    final b = f.ledger.totals(addDays(s, -7 * (i + 1)), addDays(s, -7 * i)).netSpent;
    if (a < b) {
      improving++;
    } else {
      break;
    }
  }
  return WeeklyRecap(s, e, t, p, categoryBreakdown(f, s, e), over, emergency, other, upcoming, f.totalMoney - f.totalSaved - f.reservedForBills,
      vac, completed, ffTotal, ffVisits, improving);
}

String pctChange(int now, int before) {
  if (before == 0) return now == 0 ? '0%' : 'new';
  final p = (now - before) * 100 ~/ before;
  return '${p > 0 ? '+' : ''}$p%';
}

String money(int c) => formatCents(c);
