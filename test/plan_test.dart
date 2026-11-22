import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/finance.dart';
import 'package:stackd/domain/plan.dart';

import 'helpers.dart';

final pay = IncomeSchedule(id: 'p', name: 'Job', frequency: 'weekly', anchorDate: day(2026, 11, 20), expectedCents: 50000);

void main() {
  test('per-week conversion', () {
    expect(perWeek(120000, 'monthly'), 27692); // 1200 * 12 / 52
    expect(perWeek(1000, 'biweekly'), 500);
    expect(perWeek(5200, 'yearly'), 100);
  });

  test('bills and essentials first, goals to hit date, spending limits, rest buffer', () {
    final rent = Bill(id: 'r', name: 'Rent', amountCents: 52000, frequency: 'monthly', firstDue: day(2026, 12, 1));
    final groc = Category(id: 'g', name: 'Groceries', color: 0, essential: true, limitCents: 6000);
    final fun = Category(id: 'f', name: 'Fun', color: 0, limitCents: 4000);
    final trip = SavingsGoal(id: 't', name: 'Trip', goalCents: 20000, targetDate: addDays(t0, 70)); // 10 weeks
    final f = FinanceData(schedules: [pay], bills: [rent], categories: [groc, fun], goals: [trip], now: now);
    final p = buildWeeklyPlan(f);
    expect(p.income, 50000);
    expect(p.shortfall, 0);
    expect(p.of(PlanKind.bill).single.weekly, 12000); // 520 * 12 / 52
    expect(p.of(PlanKind.essential).single.weekly, 6000);
    expect(p.of(PlanKind.spending).single.weekly, 4000);
    // goal: 2000/wk to hit date, plus half of the surplus, capped at what's left to save
    expect(p.of(PlanKind.goal).single.weekly, greaterThanOrEqualTo(2000));
    expect(p.planned, p.income); // every cent accounted for
  });

  test('not enough money: wants scale down, never negative, never above income', () {
    final fun = Category(id: 'f', name: 'Fun', color: 0, limitCents: 40000);
    final g = SavingsGoal(id: 'g', name: 'EF', goalCents: 100000, contributionCents: 30000, contributionFreq: 'weekly');
    final rent = Bill(id: 'r', name: 'Rent', amountCents: 10000, frequency: 'weekly', firstDue: day(2026, 11, 20));
    final p = buildWeeklyPlan(FinanceData(schedules: [pay], bills: [rent], categories: [fun], goals: [g], now: now));
    expect(p.planned, 50000);
    expect(p.lines.every((l) => l.weekly >= 0), isTrue);
    expect(p.of(PlanKind.goal).single.why, contains('scaled down'));
  });

  test('fixed costs above income report a shortfall', () {
    final rent = Bill(id: 'r', name: 'Rent', amountCents: 60000, frequency: 'weekly', firstDue: day(2026, 11, 20));
    final p = buildWeeklyPlan(FinanceData(schedules: [pay], bills: [rent], now: now));
    expect(p.shortfall, 10000);
  });

  test('paid-off debts drop out of the plan', () {
    final loan = Bill(id: 'l', name: 'Borrow', kind: 'debt_owed', amountCents: 1000, frequency: 'weekly', firstDue: day(2026, 11, 13), principalCents: 2000);
    final paid = [ev('bill_payment', 1000, acct: 'a', bill: 'l', occ: 0), ev('bill_payment', 1000, acct: 'a', bill: 'l', occ: 1)];
    expect(buildWeeklyPlan(FinanceData(schedules: [pay], bills: [loan], now: now)).of(PlanKind.bill), isNotEmpty);
    expect(buildWeeklyPlan(FinanceData(schedules: [pay], bills: [loan], events: paid, now: now)).of(PlanKind.bill), isEmpty);
  });
}
