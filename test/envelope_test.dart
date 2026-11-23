import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/allocation.dart';
import 'package:stackd/state/app_state.dart';

import 'helpers.dart';

AppState setup() {
  final app = AppState(LocalDb.memory(), clock: () => now);
  app.createAccount(MoneyAccount(id: 'm', name: 'Money'), 30000);
  app.save(IncomeSchedule(id: 'p', name: 'Job', frequency: 'weekly', anchorDate: day(2026, 11, 20), expectedCents: 29500));
  app.save(Bill(id: 'ins', name: 'Insurance', amountCents: 20000, frequency: 'monthly', firstDue: day(2026, 12, 16)));
  return app;
}

void main() {
  test('bill envelope from spare money: spare down, total same, recommendation shrinks', () async {
    final app = setup();
    final spare = app.data.availableToSpend;
    final need = billSavingsNeed(app.data);
    expect(need, 5000);
    app.addToBillEnvelope(need);
    final d = app.data;
    expect(d.totalMoney, 30000);
    expect(d.availableToSpend, spare - 5000);
    expect(billSavingsNeed(d), 5000); // next paycheck's share: still owed $150 over 4 paychecks
    await Future<void>.delayed(const Duration(seconds: 4));
  });

  test('bill envelope from new cash: total up, spare unchanged', () async {
    final app = setup();
    final spare = app.data.availableToSpend;
    app.addToBillEnvelope(5000, newCash: true);
    expect(app.data.totalMoney, 35000);
    expect(app.data.availableToSpend, spare);
    app.takeFromBillEnvelope(2000);
    expect(app.data.availableToSpend, spare + 2000);
    await Future<void>.delayed(const Duration(seconds: 4));
  });

  test('paid with cash not in the app: bill paid, accounts untouched', () async {
    final app = setup();
    app.save(Bill(id: 'nick', name: 'Nice', amountCents: 2500, frequency: 'biweekly', firstDue: addDays(t0, 1)));
    final spare = app.data.availableToSpend;
    expect(app.data.reservedForBills, 2500);
    app.record([
      app.event(kind: 'bill_payment', amountCents: 2500, accountId: 'm', billId: 'nick', billOccurrence: 0, groupId: 'g'),
      app.event(kind: 'adjustment', amountCents: 2500, accountId: 'm', groupId: 'g', note: 'Paid with cash not in the app'),
    ]);
    final d = app.data;
    expect(d.totalMoney, 30000);
    expect(d.reservedForBills, 0);
    expect(d.availableToSpend, spare + 2500); // the money that was held for it is free again
    await Future<void>.delayed(const Duration(seconds: 4));
  });
}
