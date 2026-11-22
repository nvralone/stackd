import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/allocation.dart';
import 'package:stackd/domain/bills.dart';
import 'package:stackd/domain/finance.dart';

import 'helpers.dart';

final cash = MoneyAccount(id: 'cash', name: 'Cash');
final pay = IncomeSchedule(id: 'p', name: 'Job', frequency: 'weekly', anchorDate: day(2026, 11, 27), expectedCents: 42000);

void main() {
  test('auto split spreads the whole amount across goals and categories', () {
    final gas = Category(id: 'gas', name: 'Gas', color: 0, limitCents: 3000);
    final food = Category(id: 'ff', name: 'Fast Food', color: 0, limitCents: 12000);
    final ef = SavingsGoal(id: 'ef', name: 'E-FUND', goalCents: 150000, contributionCents: 5000, contributionFreq: 'weekly');
    final trip = SavingsGoal(id: 'trip', name: 'Trip', goalCents: 300000);
    final f = FinanceData(accounts: [cash], categories: [gas, food], goals: [ef, trip], schedules: [pay],
        events: [ev('opening', 50000, acct: 'cash')], now: now);
    final p = suggestExtra(f, 34000);
    expect(p.allocated, 34000); // every cent placed
    final targets = p.lines.map((l) => l.targetId).toSet();
    expect(targets.containsAll({'gas', 'ff', 'ef', 'trip'}), isTrue); // not just one destination
    expect(p.lines.where((l) => l.kind == TargetKind.unallocated), isEmpty);
    expect(p.lines.every((l) => l.cents < 34000), isTrue);
  });

  test('a bills shortfall never takes more than half of extra money', () {
    final rent = Bill(id: 'r', name: 'Rent', amountCents: 90000, frequency: 'monthly', firstDue: addDays(t0, 3));
    final ef = SavingsGoal(id: 'ef', name: 'E-FUND', goalCents: 150000);
    final f = FinanceData(accounts: [cash], bills: [rent], goals: [ef], schedules: [pay], events: [ev('opening', 1000, acct: 'cash')], now: now);
    final p = suggestExtra(f, 10000);
    expect(p.lines.firstWhere((l) => l.kind == TargetKind.bills).cents, 5000);
    expect(p.allocated, 10000);
  });

  test('new recurring bills dated in the past start at the next due date', () {
    expect(rollForward(day(2026, 11, 16), 'monthly', day(2026, 11, 22)), day(2026, 12, 16));
    expect(rollForward(day(2026, 11, 20), 'weekly', day(2026, 11, 22)), day(2026, 11, 27));
    expect(rollForward(day(2026, 12, 1), 'monthly', day(2026, 11, 22)), day(2026, 12, 1)); // already upcoming
  });
}
