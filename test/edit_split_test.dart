import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/core/ids.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/state/app_state.dart';

import 'helpers.dart';

AppState setup() {
  final app = AppState(LocalDb.memory(), clock: () => now);
  app.createAccount(MoneyAccount(id: 'm', name: 'Money'), 0);
  app.save(SavingsGoal(id: 'vault', name: 'The VAULT', goalCents: 200000));
  app.save(Category(id: 'gas', name: 'Gas', color: 0, limitCents: 3000));
  app.save(Category(id: 'food', name: 'Food', color: 0, limitCents: 12000));
  // Extra money $340: $30 to vault, $30 boost to Gas
  app.record([
    app.event(kind: 'income', amountCents: 34000, accountId: 'm', incomeSource: 'sale', groupId: 'g'),
    app.event(kind: 'goal_deposit', amountCents: 3000, goalId: 'vault', groupId: 'g'),
  ], also: [BudgetAllocation(id: newId(), categoryId: 'gas', periodStart: weekStartOf(t0, 1), amountCents: 3000, groupId: 'g')]);
  return app;
}

void main() {
  test('edit split moves money without touching the income', () async {
    final app = setup();
    expect(app.data.categoryStatus(app.data.category('gas')!).budget, 6000);
    app.replaceSplit('g', [
      app.event(kind: 'goal_deposit', amountCents: 5000, goalId: 'vault', groupId: 'g'),
    ], [BudgetAllocation(id: newId(), categoryId: 'food', periodStart: weekStartOf(t0, 1), amountCents: 2000, groupId: 'g')]);
    final d = app.data;
    expect(d.totalMoney, 34000); // income untouched
    expect(d.ledger.goalBalance('vault'), 5000);
    expect(d.categoryStatus(d.category('gas')!).budget, 3000); // Gas back to its limit
    expect(d.categoryStatus(d.category('food')!).extra, 2000);
    expect(d.ledger.all.where((e) => e.kind == 'reversal').length, 1); // old deposit reversed, history kept
    await Future<void>.delayed(const Duration(seconds: 4));
  });

  test('restore brings back a reversed entry', () async {
    final app = setup();
    final income = app.data.ledger.active.firstWhere((e) => e.kind == 'income');
    app.reverse(income);
    expect(app.data.totalMoney, 0);
    app.restore(app.data.ledger.all.firstWhere((e) => e.id == income.id));
    expect(app.data.totalMoney, 34000);
    await Future<void>.delayed(const Duration(seconds: 4));
  });

  test('undo whole entry reverses income, deposits and boosts', () async {
    final app = setup();
    app.reverseGroup('g');
    final d = app.data;
    expect(d.totalMoney, 0);
    expect(d.totalSaved, 0);
    expect(d.categoryStatus(d.category('gas')!).budget, 3000);
    await Future<void>.delayed(const Duration(seconds: 4));
  });

  test('removing a single boost only lowers that category', () async {
    final app = setup();
    app.removeBoost(app.data.budgetAllocations.single);
    expect(app.data.categoryStatus(app.data.category('gas')!).budget, 3000);
    expect(app.data.ledger.goalBalance('vault'), 3000);
    await Future<void>.delayed(const Duration(seconds: 4));
  });
}
