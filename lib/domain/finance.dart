// FinanceData: one immutable snapshot of everything, with derived numbers the UI shows.
import '../core/dates.dart';
import '../core/money.dart';
import '../data/models.dart';
import 'bills.dart' as billing;
import 'ledger.dart';

/// The vault that holds money set aside for bills.
const billSavingsName = 'Bill savings';

class CategoryStatus {
  final Category category;
  final int limit, extra, rollover, spent, previousSpent;
  const CategoryStatus(this.category, this.limit, this.extra, this.rollover, this.spent, this.previousSpent);
  int get budget => limit + extra + rollover;
  int get remaining => budget - spent;
  bool get hasLimit => category.limitCents != null;
  bool get over => hasLimit && spent > budget;
  int get pct => percentOf(spent, budget);
}

class GoalStatus {
  final SavingsGoal goal;
  final int saved, deposits, withdrawals, emergencyWithdrawals, goalSpending;
  final DateTime? forecast;
  const GoalStatus(this.goal, this.saved, this.deposits, this.withdrawals, this.emergencyWithdrawals, this.goalSpending, this.forecast);
  int get remaining => (goal.goalCents - saved).clamp(0, goal.goalCents);
  int get pct => percentOf(saved, goal.goalCents).clamp(0, 100);
  bool get complete => saved >= goal.goalCents;
}

class FinanceData {
  final List<MoneyAccount> accounts;
  final List<Category> categories;
  final List<SavingsGoal> goals;
  final List<Bill> bills;
  final List<BillOverride> overrides;
  final List<IncomeSchedule> schedules;
  final List<BudgetAllocation> budgetAllocations;
  final List<Trip> trips;
  final List<TripBudgetItem> tripItems;
  final List<TripEntry> tripEntries;
  final Ledger ledger;
  final Prefs prefs;
  final DateTime now;

  FinanceData({
    List<MoneyAccount> accounts = const [],
    List<Category> categories = const [],
    List<SavingsGoal> goals = const [],
    List<Bill> bills = const [],
    List<BillOverride> overrides = const [],
    List<IncomeSchedule> schedules = const [],
    List<BudgetAllocation> budgetAllocations = const [],
    List<Trip> trips = const [],
    List<TripBudgetItem> tripItems = const [],
    this.tripEntries = const [],
    List<LedgerEvent> events = const [],
    Prefs? prefs,
    DateTime? now,
  })  : accounts = accounts.where((e) => !e.deleted).toList(),
        categories = categories.where((e) => !e.deleted).toList(),
        goals = goals.where((e) => !e.deleted).toList(),
        bills = bills.where((e) => !e.deleted).toList(),
        overrides = overrides.where((e) => !e.deleted).toList(),
        schedules = schedules.where((e) => !e.deleted).toList(),
        budgetAllocations = budgetAllocations.where((e) => !e.deleted).toList(),
        trips = trips.where((e) => !e.deleted).toList(),
        tripItems = tripItems.where((e) => !e.deleted).toList(),
        ledger = Ledger(events),
        prefs = prefs ?? Prefs(),
        now = now ?? DateTime.now();

  DateTime get todayDate => today(now);
  int get weekStart => prefs.weekStart;

  // ---------------------------------------------------------------- lookups
  MoneyAccount? account(String? id) => accounts.where((a) => a.id == id).firstOrNull;
  Category? category(String? id) => categories.where((c) => c.id == id).firstOrNull;
  SavingsGoal? goal(String? id) => goals.where((g) => g.id == id).firstOrNull;
  Bill? bill(String? id) => bills.where((b) => b.id == id).firstOrNull;
  Trip? trip(String? id) => trips.where((t) => t.id == id).firstOrNull;
  Category? categoryByTag(String tag) => categories.where((c) => c.tag == tag && !c.archived).firstOrNull;

  // ---------------------------------------------------------------- core balances
  int get totalMoney => ledger.totalBalance(accounts.map((a) => a.id));
  int get totalSaved => goals.fold(0, (s, g) => s + ledger.goalBalance(g.id));

  /// Vault balances that belong to vacation goals.
  int get vacationSaved => goals.where((g) => g.tripId != null).fold(0, (s, g) => s + ledger.goalBalance(g.id));

  /// Next expected payday across active, regular schedules.
  DateTime? get nextPayday {
    DateTime? best;
    for (final s in schedules) {
      if (!s.active || s.frequency == 'irregular') continue;
      final d = nextOccurrence(s.anchorDate, s.frequency, addDays(todayDate, 1));
      if (d != null && (best == null || d.isBefore(best))) best = d;
    }
    return best;
  }

  /// End of the safe-to-spend window (inclusive day): next payday, or 14 days out without a schedule.
  DateTime get horizonEnd => nextPayday ?? addDays(todayDate, 14);

  /// Bills due before payday, minus Bill envelope money already set aside for those exact bills
  /// (that money is counted in Saved, so it must not be held a second time here).
  int get reservedForBills =>
      billing.obligationsUntil(bills, ledger, overrides, addDays(horizonEnd, 1), now: now, earmarks: billEarmarks);

  // ---------------------------------------------------------------- bill envelope
  SavingsGoal? get billEnvelope => goals.where((g) => g.name == billSavingsName && !g.archived).firstOrNull;
  int get billEnvelopeBalance => billEnvelope == null ? 0 : ledger.goalBalance(billEnvelope!.id);

  /// Envelope money set aside for a specific bill: deposits tagged with that bill, minus money
  /// taken out for it (a running total that never goes below zero). If money was taken back out
  /// of the envelope so it holds less than all of these, the bills due last lose their share first.
  late final Map<String, int> billEarmarks = _earmarks();

  /// Envelope money not set aside for any particular bill. It is never assigned to a bill silently.
  int get billEnvelopeUnassigned =>
      (billEnvelopeBalance - billEarmarks.values.fold<int>(0, (s, v) => s + v)).clamp(0, 1 << 40).toInt();

  Map<String, int> _earmarks() {
    final g = billEnvelope;
    if (g == null) return const {};
    final tagged = ledger.active.where((e) => e.goalId == g.id && e.billId != null).toList();
    final order = {for (var i = 0; i < tagged.length; i++) tagged[i]: i};
    tagged.sort((a, b) {
      final c = a.occurredOn.compareTo(b.occurredOn);
      return c != 0 ? c : order[a]!.compareTo(order[b]!);
    });
    final run = <String, int>{};
    for (final e in tagged) {
      final v = (run[e.billId!] ?? 0) + (e.kind == 'goal_deposit' ? e.amountCents : -e.amountCents);
      run[e.billId!] = v < 0 ? 0 : v;
    }
    run.removeWhere((_, v) => v == 0);
    var over = run.values.fold(0, (s, v) => s + v) - ledger.goalBalance(g.id);
    if (over > 0) {
      DateTime dueOf(String id) {
        final b = bill(id);
        return (b == null ? null : billing.nextOpen(b, ledger, overrides, now: now)?.due) ?? DateTime.utc(9999);
      }
      for (final id in run.keys.toList()..sort((a, b) => dueOf(b).compareTo(dueOf(a)))) {
        final cut = over < run[id]! ? over : run[id]!;
        run[id] = run[id]! - cut;
        over -= cut;
        if (over == 0) break;
      }
      run.removeWhere((_, v) => v == 0);
    }
    return run;
  }

  /// What's still unspent in this period's budgets (categories with a limit). That money is spoken for.
  int get budgetedRemaining =>
      categoryStatuses.where((s) => s.hasLimit).fold(0, (sum, s) => sum + (s.remaining > 0 ? s.remaining : 0));

  /// Free money: not in a vault, not needed for bills before payday, not already in a budget.
  int get availableToSpend => totalMoney - totalSaved - reservedForBills - budgetedRemaining;

  int get daysUntilHorizon => daysBetween(todayDate, horizonEnd).clamp(1, 366);

  int get dailySafeSpend => availableToSpend <= 0 ? 0 : availableToSpend ~/ daysUntilHorizon;

  // ---------------------------------------------------------------- periods
  ({DateTime start, DateTime end}) get thisWeek => periodOf(todayDate, 'weekly', weekStart);
  ({DateTime start, DateTime end}) get lastWeek {
    final w = thisWeek;
    return (start: addDays(w.start, -7), end: w.start);
  }

  PeriodTotals get weekTotals => ledger.totals(thisWeek.start, thisWeek.end);
  PeriodTotals get lastWeekTotals => ledger.totals(lastWeek.start, lastWeek.end);

  // ---------------------------------------------------------------- categories
  CategoryStatus categoryStatus(Category c, {DateTime? at}) {
    final p = periodOf(at ?? todayDate, c.period, weekStart);
    final prevStart = c.period == 'monthly' ? addMonths(p.start, -1) : addDays(p.start, -7);
    final limit = c.limitCents ?? 0;
    final spent = ledger.categorySpent(c.id, p.start, p.end);
    final prev = ledger.categorySpent(c.id, prevStart, p.start);
    int extraFor(DateTime start) => budgetAllocations
        .where((a) => a.categoryId == c.id && a.periodStart == start)
        .fold(0, (s, a) => s + a.amountCents);
    // Rollover carries one period: unused (or overspent) amount from the previous period.
    final roll = c.rollover && c.limitCents != null ? limit + extraFor(prevStart) - prev : 0;
    return CategoryStatus(c, limit, extraFor(p.start), roll, spent, prev);
  }

  List<CategoryStatus> get categoryStatuses =>
      [for (final c in categories.where((c) => !c.archived)) categoryStatus(c)];

  // ---------------------------------------------------------------- goals
  GoalStatus goalStatus(SavingsGoal g) {
    final f = ledger.goalFlows(g.id);
    final saved = ledger.goalBalance(g.id);
    final spending = g.tripId == null
        ? 0
        : ledger.active.where((e) => e.tripId == g.tripId && e.kind == 'expense').fold(0, (s, e) => s + e.amountCents);
    return GoalStatus(g, saved, f.deposits, f.withdrawals, f.emergency, spending, forecastGoal(g, saved));
  }

  List<GoalStatus> get goalStatuses => [for (final g in goals.where((g) => !g.archived)) goalStatus(g)];

  /// Forecast completion: planned contributions if set, else average net deposits of the last 8 weeks.
  DateTime? forecastGoal(SavingsGoal g, int saved, {int extraPerPeriod = 0}) {
    final remaining = g.goalCents - saved;
    if (remaining <= 0) return todayDate;
    final contrib = g.contributionCents + extraPerPeriod;
    if (contrib > 0 && g.contributionFreq != 'none') {
      final days = switch (g.contributionFreq) {
        'weekly' => 7,
        'monthly' => 30,
        _ => paydayIntervalDays,
      };
      return addDays(todayDate, ceilDiv(remaining, contrib) * days);
    }
    final start = addDays(todayDate, -56);
    var net = 0;
    for (final e in ledger.active) {
      if (e.goalId != g.id || e.occurredOn.isBefore(start)) continue;
      if (e.kind == 'goal_deposit') net += e.amountCents;
      if (e.kind == 'goal_withdraw') net -= e.amountCents;
    }
    final perWeek = net ~/ 8 + extraPerPeriod;
    if (perWeek <= 0) return null;
    return addDays(todayDate, ceilDiv(remaining, perWeek) * 7);
  }

  int get paydayIntervalDays {
    final s = schedules.where((s) => s.active && s.frequency != 'irregular').firstOrNull;
    return switch (s?.frequency) { 'weekly' => 7, 'biweekly' => 14, 'semimonthly' => 15, 'monthly' => 30, _ => 14 };
  }

  // ---------------------------------------------------------------- bills
  List<billing.BillOccurrence> upcomingBills({int days = 30}) {
    final until = addDays(todayDate, days + 1);
    final out = <billing.BillOccurrence>[];
    for (final b in bills.where((b) => !b.archived)) {
      out.addAll(billing.occurrences(b, ledger, overrides, until, now: now).where((o) => o.open));
    }
    out.sort((a, b) => a.due.compareTo(b.due));
    return out;
  }

  // ---------------------------------------------------------------- spending stats
  /// Average daily discretionary spending (expenses, not bill payments) over the last [days] days.
  int avgDailySpend({int days = 28}) {
    final start = addDays(todayDate, -days);
    final s = ledger.active
        .where((e) => e.kind == 'expense' && !e.occurredOn.isBefore(start) && e.occurredOn.isBefore(addDays(todayDate, 1)))
        .fold(0, (s, e) => s + e.amountCents);
    final refunds = ledger.active
        .where((e) => e.kind == 'refund' && !e.occurredOn.isBefore(start))
        .fold(0, (s, e) => s + e.amountCents);
    return ((s - refunds) ~/ days).clamp(0, 1 << 40);
  }

  int spentInTag(String tag, DateTime start, DateTime end) {
    final c = categoryByTag(tag);
    return c == null ? 0 : ledger.categorySpent(c.id, start, end);
  }

  bool get hasAnyData => ledger.all.isNotEmpty;
}
