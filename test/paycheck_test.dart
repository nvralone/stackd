import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/allocation.dart';
import 'package:stackd/domain/finance.dart';
import 'package:stackd/state/app_state.dart';

import 'helpers.dart';

final money = MoneyAccount(id: 'm', name: 'Money');
final pay = IncomeSchedule(id: 'p', name: 'Job', frequency: 'weekly', anchorDate: day(2026, 11, 20), expectedCents: 29500);
final food = Category(id: 'food', name: 'Food', color: 0, limitCents: 12000, essential: true);
final gas = Category(id: 'gas', name: 'Gas', color: 0, limitCents: 3000, essential: true);
final fun = Category(id: 'fun', name: 'Fun', color: 0, limitCents: 4000);
final nick = Bill(id: 'n', name: 'Nice', amountCents: 2500, frequency: 'biweekly', firstDue: addDays(t0, 1));
final self = Bill(id: 's', name: 'Self', amountCents: 2500, frequency: 'weekly', firstDue: addDays(t0, 1));
final vault = SavingsGoal(id: 'v', name: 'The VAULT', goalCents: 200000, contributionCents: 3000, contributionFreq: 'payday');
final efund = SavingsGoal(id: 'e', name: 'E-FUND', goalCents: 150000, contributionCents: 2000, contributionFreq: 'payday');

void main() {
  test('paycheck of \$295 with nothing else: bills, then budgets, then savings, then free', () {
    final f = FinanceData(accounts: [money], categories: [food, gas, fun], bills: [nick, self], goals: [vault, efund],
        schedules: [pay], now: now);
    final p = suggestPaycheck(f, 29500);
    int line(TargetKind k, [String? id]) => p.lines.where((l) => l.kind == k && (id == null || l.targetId == id)).fold(0, (s, l) => s + l.cents);
    expect(line(TargetKind.bills), 5000); // Nice + Self before payday
    expect(line(TargetKind.covered, 'food'), 12000);
    expect(line(TargetKind.covered, 'gas'), 3000);
    expect(line(TargetKind.covered, 'fun'), 4000);
    // Nice is every 2 weeks with weekly pay: part of its next payment is saved ahead in Bill savings
    final billSave = line(TargetKind.billSavings);
    expect(billSave, greaterThan(0));
    final leftForGoals = 29500 - 5000 - 19000 - billSave;
    expect(line(TargetKind.goal, 'v') + line(TargetKind.goal, 'e'), leftForGoals < 5000 ? leftForGoals : 5000);
    expect(line(TargetKind.goal, 'v'), greaterThan(line(TargetKind.goal, 'e'))); // scaled in proportion 30:20
    expect(p.allocated, 29500);
  });

  test('short paycheck: bills and essentials first, savings get what is left', () {
    final f = FinanceData(accounts: [money], categories: [food, gas, fun], bills: [nick, self], goals: [vault, efund],
        schedules: [pay], now: now);
    final p = suggestPaycheck(f, 20000);
    expect(p.lines.first.kind, TargetKind.bills);
    expect(p.lines.where((l) => l.targetId == 'food').single.cents, 12000);
    expect(p.lines.where((l) => l.targetId == 'gas').single.cents, 3000);
    expect(p.allocated, 20000);
    expect(p.lines.where((l) => l.kind == TargetKind.goal).fold(0, (s, l) => s + l.cents), 0); // nothing left for savings
  });

  test('money you already have covers bills and budgets before the paycheck does', () {
    final f = FinanceData(accounts: [money], categories: [food], bills: [nick], schedules: [pay],
        events: [ev('opening', 10000, acct: 'm')], now: now);
    final p = suggestPaycheck(f, 29500);
    expect(p.lines.where((l) => l.kind == TargetKind.bills), isEmpty); // $25 bill covered by the $100 on hand
    expect(p.lines.where((l) => l.targetId == 'food').single.cents, 12000 - 7500); // remaining $75 goes to food first
  });

  test('start fresh clears money but keeps vault savings, bills and budgets', () async {
    final app = AppState(LocalDb.memory(), clock: () => now);
    app.createAccount(money, 30000);
    app.save(vault);
    app.save(food);
    app.save(nick);
    app.record([app.event(kind: 'goal_deposit', amountCents: 3000, goalId: 'v'), app.event(kind: 'expense', amountCents: 2000, accountId: 'm', categoryId: 'food')]);
    app.startFresh();
    final d = app.data;
    expect(d.totalMoney, 0);
    expect(d.totalSaved, 3000);
    expect(d.bills.length, 1);
    expect(d.categoryStatus(d.category('food')!).spent, 0);
    await Future<void>.delayed(const Duration(seconds: 4));
  });
}
