import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/allocation.dart';
import 'package:stackd/domain/finance.dart';
import 'package:stackd/state/app_state.dart';
import 'package:stackd/ui/common.dart';
import 'package:stackd/ui/sheets/allocation_sheet.dart';
import 'package:stackd/ui/theme.dart';

import 'helpers.dart';

final money = MoneyAccount(id: 'm', name: 'Money');
final pay = IncomeSchedule(id: 'p', name: 'Job', frequency: 'weekly', anchorDate: day(2026, 11, 20), expectedCents: 29500);
final food = Category(id: 'food', name: 'Food', color: 0, limitCents: 12000, essential: true);
final gas = Category(id: 'gas', name: 'Gas', color: 0, limitCents: 3000, essential: true);
final insurance = Bill(id: 'ins', name: 'Insurance', amountCents: 20000, frequency: 'monthly', firstDue: day(2026, 12, 16));

AppState fresh() {
  final app = AppState(LocalDb.memory(), clock: () => now);
  app.createAccount(money, 0);
  app.save(pay);
  app.save(food);
  app.save(gas);
  app.save(insurance);
  return app;
}

void main() {
  test('later monthly bills get an even share each paycheck', () {
    final f = FinanceData(accounts: [money], bills: [insurance], schedules: [pay], now: now);
    final later = laterBills(f);
    expect(later.single.name, 'Insurance');
    // Paycheck today (Nov 18) + paydays Nov 20, 27, Dec 4, 11 before the Dec 16 due date = 5 -> $40 each
    expect(later.single.paychecksLeft, 5);
    expect(later.single.perPaycheck, 4000);
    expect(billSavingsNeed(f), 4000);
    final p = suggestPaycheck(f, 29500);
    final line = p.lines.where((l) => l.kind == TargetKind.billSavings).single;
    expect(line.cents, 4000);
    expect(line.targetId, 'ins');
  });

  test('money already in Bill savings lowers what the paycheck needs to add', () {
    final vault = SavingsGoal(id: 'bs', name: billSavingsName, goalCents: 20000, contributionFreq: 'none');
    final f = FinanceData(accounts: [money], bills: [insurance], goals: [vault], schedules: [pay],
        events: [ev('opening', 50000, acct: 'm'), ev('goal_deposit', 18000, goal: 'bs')], now: now);
    // Untagged envelope money is never assigned to a bill silently...
    expect(f.billEnvelopeUnassigned, 18000);
    expect(billSavingsNeed(f), 4000);
    // ...but the user can choose to use it: then only $20 is still missing, spread over 5 paychecks.
    final p = suggestPaycheck(f, 29500, useUnassigned: true);
    expect(p.assign, {'ins': 18000});
    expect(p.lines.where((l) => l.kind == TargetKind.billSavings).single.cents, 400);
  });

  testWidgets('editing a budget line in the split really changes that budget; removing one sets it to 0', (t) async {
    final app = fresh();
    final proposal = suggestPaycheck(app.data, 29500);
    app.record([app.event(kind: 'income', amountCents: 29500, accountId: 'm', incomeSource: 'paycheck', groupId: 'g')]);
    t.view.physicalSize = const Size(500, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppScope(
      app: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: AllocationSheet(title: 'Split', amount: 29500, groupId: 'g', date: t0, suggested: proposal)),
      ),
    ));
    await t.pump();
    // Food line: 120 -> 100
    final foodField = find.descendant(
        of: find.ancestor(of: find.textContaining('Food budget'), matching: find.byType(Row)).first, matching: find.byType(TextField));
    await t.enterText(foodField, '100');
    // remove the Gas line
    final gasRow = find.ancestor(of: find.textContaining('Gas budget'), matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: gasRow, matching: find.byIcon(Icons.close_rounded)));
    await t.pump();
    await t.ensureVisible(find.text('Accept split'));
    await t.tap(find.text('Accept split'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.widgetWithText(FilledButton, 'Confirm'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final d = app.data;
    expect(d.categoryStatus(d.category('food')!).remaining, 10000);
    expect(d.categoryStatus(d.category('gas')!).remaining, 0);
    expect(d.ledger.goalBalance(d.goals.firstWhere((g) => g.name == billSavingsName).id), 4000); // bill envelope deposited
    expect(d.billEarmarks, {'ins': 4000}); // ...set aside for Insurance
    // money: 295 total, 40 bill envelope, 100 food, 0 gas -> 155 spare
    expect(d.availableToSpend, 29500 - 4000 - 10000);
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox());
  });

  test('paying a bill from Bill savings keeps spare money the same', () async {
    final app = fresh();
    app.record([app.event(kind: 'income', amountCents: 50000, accountId: 'm', incomeSource: 'paycheck')]);
    final vault = SavingsGoal(id: 'bs', name: billSavingsName, goalCents: 20000, contributionFreq: 'none');
    app.save(vault);
    app.record([app.event(kind: 'goal_deposit', amountCents: 20000, goalId: 'bs')]);
    final before = app.data.availableToSpend;
    app.record([
      app.event(kind: 'bill_payment', amountCents: 20000, accountId: 'm', billId: 'ins', billOccurrence: 0),
      app.event(kind: 'goal_withdraw', amountCents: 20000, goalId: 'bs', reason: 'planned'),
    ]);
    expect(app.data.availableToSpend, before);
    expect(app.data.totalMoney, 30000);
    await Future<void>.delayed(const Duration(seconds: 4));
  });
}
