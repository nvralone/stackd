import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stackd/clover/voice.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/state/app_state.dart';
import 'package:stackd/ui/app.dart';

import 'helpers.dart';

AppState app0() {
  final app = AppState(LocalDb.memory(), clock: () => now);
  app.ensureDefaults();
  app.createAccount(MoneyAccount(id: 'cash', name: 'Cash'), 20000);
  app.savePrefs((p) => p.onboarded = true);
  return app;
}

void main() {
  test('deleting a vault returns its money to safe-to-spend; history stays', () async {
    final app = app0();
    app.save(SavingsGoal(id: 'g', name: 'Trip', goalCents: 50000));
    app.record([app.event(kind: 'goal_deposit', amountCents: 5000, goalId: 'g')]);
    expect(app.data.availableToSpend, 15000);
    app.deleteItems([app.data.goal('g')!]);
    expect(app.data.goal('g'), isNull);
    expect(app.data.availableToSpend, 20000);
    expect(app.data.ledger.all.any((e) => e.goalId == 'g'), isTrue);
    expect(app.pendingSync, greaterThan(0)); // the delete is queued for sync
    await Future<void>.delayed(const Duration(seconds: 4));
  });

  test('deleting a bill stops reserving money but keeps recorded payments', () async {
    final app = app0();
    final b = Bill(id: 'b', name: 'Gym', amountCents: 3000, frequency: 'weekly', firstDue: addDays(t0, 1));
    app.save(b);
    app.record([app.event(kind: 'bill_payment', amountCents: 3000, accountId: 'cash', billId: 'b', billOccurrence: 0)]);
    app.deleteItems([app.data.bill('b')!]);
    expect(app.data.reservedForBills, 0);
    expect(app.data.totalMoney, 17000);
    await Future<void>.delayed(const Duration(seconds: 4));
  });

  testWidgets('Bills tab: menu → Delete asks first, then removes the bill', (t) async {
    final app = app0();
    app.save(Bill(id: 'b', name: 'Gym', amountCents: 3000, frequency: 'weekly', firstDue: addDays(t0, 10)));
    t.view.physicalSize = const Size(430, 932);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(StackdApp(app: app));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.byIcon(Icons.event_note_outlined)));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.byTooltip('Options').first);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.text('Delete').last);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Delete Gym?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pump(const Duration(milliseconds: 400));
    expect(app.data.bill('b'), isNull);
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox());
  });

  test('TTS text: shouty words spoken as words, dollar signs read out', () {
    expect(speakable('BROTHER. That is \$5.00'), 'brother. That is dollars 5.00');
  });
}
