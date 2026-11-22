// Deterministic forecast + what-if scenarios. Reads FinanceData, never writes anything.
import '../core/dates.dart';
import '../core/money.dart';
import '../data/models.dart';
import 'bills.dart' as billing;
import 'finance.dart';

/// Changes to simulate. All values in cents; negative weeklySpendDelta = spend less.
class Scenario {
  final int weeklySpendDelta, extraSavingPerPayday, newMonthlyBill, oneTimeIncome;
  final String? goalId; // goal whose target date moves
  final int goalDateShiftDays;
  const Scenario({this.weeklySpendDelta = 0, this.extraSavingPerPayday = 0, this.newMonthlyBill = 0,
      this.oneTimeIncome = 0, this.goalId, this.goalDateShiftDays = 0});
  bool get isEmpty => weeklySpendDelta == 0 && extraSavingPerPayday == 0 && newMonthlyBill == 0 && oneTimeIncome == 0 && goalDateShiftDays == 0;
}

class ForecastPoint {
  final DateTime date;
  final int balance; // projected money in accounts
  final int free; // projected money not in vaults
  const ForecastPoint(this.date, this.balance, this.free);
}

class Forecast {
  final List<ForecastPoint> weekly; // one point per week, index 0 = today
  final int balanceAtPayday;
  final DateTime? payday;
  final int lowestFree;
  final int dailyAllowance;
  final int weeklySpendAssumed;
  final int expectedIncome;
  final int scheduledBills;
  final Map<String, DateTime?> goalCompletion;
  final Map<String, int> goalNeededPerWeek; // to hit target date
  const Forecast(this.weekly, this.balanceAtPayday, this.payday, this.lowestFree, this.dailyAllowance,
      this.weeklySpendAssumed, this.expectedIncome, this.scheduledBills, this.goalCompletion, this.goalNeededPerWeek);

  ForecastPoint at(int week) => weekly[week.clamp(0, weekly.length - 1)];

  /// 'healthy' (>= 1 week of spending free at the lowest point), 'tight' (>= 0), 'short' (< 0).
  String get bufferStatus => lowestFree < 0 ? 'short' : (lowestFree >= weeklySpendAssumed ? 'healthy' : 'tight');
}

Forecast buildForecast(FinanceData f, {int weeks = 8, Scenario s = const Scenario()}) {
  final start = f.todayDate;
  final end = addDays(start, weeks * 7);
  final dailySpend = f.avgDailySpend();
  final weeklySpend = (dailySpend * 7 + s.weeklySpendDelta).clamp(0, 1 << 40);

  // Day-indexed deltas.
  final balanceDelta = List<int>.filled(weeks * 7 + 1, 0);
  final savedDelta = List<int>.filled(weeks * 7 + 1, 0);
  var income = 0, billsTotal = 0;

  // Expected income from schedules (assumption: expected amount on each payday).
  final paydays = <DateTime>{};
  for (final sch in f.schedules.where((x) => x.active && x.frequency != 'irregular')) {
    var d = nextOccurrence(sch.anchorDate, sch.frequency, addDays(start, 1));
    var n = 0;
    while (d != null && !d.isAfter(end) && n++ < 200) {
      final i = daysBetween(start, d);
      balanceDelta[i] += sch.expectedCents;
      income += sch.expectedCents;
      paydays.add(d);
      // planned goal contributions each payday (virtual: reduce free money, not balance)
      for (final g in f.goalStatuses.where((g) => !g.complete && g.goal.contributionFreq == 'payday')) {
        savedDelta[i] += g.goal.contributionCents;
      }
      savedDelta[i] += s.extraSavingPerPayday;
      d = nextOccurrence(sch.anchorDate, sch.frequency, addDays(d, 1));
    }
  }
  for (final g in f.goalStatuses.where((g) => !g.complete)) {
    if (g.goal.contributionFreq == 'weekly') {
      for (var w = 1; w <= weeks; w++) { savedDelta[w * 7] += g.goal.contributionCents; }
    }
  }

  // Scheduled bills (outgoing unpaid occurrences; overdue counted today).
  for (final b in f.bills.where((b) => !b.archived && !b.incoming)) {
    for (final o in billing.occurrences(b, f.ledger, f.overrides, addDays(end, 1), now: f.now)) {
      if (!o.open) continue;
      final i = daysBetween(start, o.due).clamp(0, weeks * 7);
      balanceDelta[i] -= o.remainingCents;
      billsTotal += o.remainingCents;
    }
  }
  if (s.newMonthlyBill > 0) {
    for (var m = 0; m * 30 <= weeks * 7; m++) {
      final i = (m * 30 + 1).clamp(0, weeks * 7);
      balanceDelta[i] -= s.newMonthlyBill;
      billsTotal += s.newMonthlyBill;
    }
  }
  if (s.oneTimeIncome != 0) {
    balanceDelta[1.clamp(0, weeks * 7)] += s.oneTimeIncome;
    income += s.oneTimeIncome;
  }
  // Discretionary spending spread daily (assumption from recent history, adjusted by scenario).
  final perDay = splitEvenly(weeklySpend, 7);
  for (var i = 1; i <= weeks * 7; i++) { balanceDelta[i] -= perDay[(i - 1) % 7]; }

  var bal = f.totalMoney, saved = f.totalSaved, lowest = bal - saved;
  final points = <ForecastPoint>[ForecastPoint(start, bal, bal - saved)];
  int? atPayday;
  final payday = f.nextPayday;
  for (var i = 1; i <= weeks * 7; i++) {
    bal += balanceDelta[i];
    saved += savedDelta[i];
    final d = addDays(start, i);
    if (bal - saved < lowest) lowest = bal - saved;
    // balance the evening before payday money lands
    if (payday != null && d == addDays(payday, -1)) atPayday = bal;
    if (i % 7 == 0) points.add(ForecastPoint(d, bal, bal - saved));
  }

  // Daily allowance under the scenario: free money minus bills to payday, plus one-time income.
  final scenarioBills = s.newMonthlyBill > 0 && f.daysUntilHorizon >= 1 ? s.newMonthlyBill : 0;
  final avail = f.availableToSpend + s.oneTimeIncome - scenarioBills - s.extraSavingPerPayday;
  final daily = avail <= 0 ? 0 : avail ~/ f.daysUntilHorizon;

  final completion = <String, DateTime?>{};
  final needed = <String, int>{};
  for (final g in f.goalStatuses) {
    final extra = (s.goalId == null || s.goalId == g.goal.id) ? s.extraSavingPerPayday : 0;
    completion[g.goal.id] = f.forecastGoal(g.goal, g.saved, extraPerPeriod: extra);
    var target = g.goal.targetDate;
    if (target != null && g.goal.id == s.goalId) target = addDays(target, s.goalDateShiftDays);
    if (target != null && !g.complete) {
      final wk = (daysBetween(f.todayDate, target) ~/ 7).clamp(1, 1000);
      needed[g.goal.id] = ceilDiv(g.remaining, wk);
    }
  }

  return Forecast(points, atPayday ?? (payday == null ? bal : f.totalMoney), payday, lowest, daily, weeklySpend,
      income, billsTotal, completion, needed);
}

/// Goal for the "move a vacation date" what-if.
SavingsGoal? goalForTrip(FinanceData f, String tripId) => f.goals.where((g) => g.tripId == tripId).firstOrNull;
