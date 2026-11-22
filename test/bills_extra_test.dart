import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/bills.dart';
import 'package:stackd/domain/finance.dart';
import 'package:stackd/services/notifications.dart';
import 'package:stackd/state/app_state.dart';

import 'helpers.dart';

void main() {
  final nick = Bill(id: 'n', name: 'Nice', amountCents: 2500, frequency: 'biweekly', firstDue: addDays(t0, 2));

  test('set aside: still due and reserved, balance unchanged', () {
    final ov = BillOverride(id: 'o', billId: 'n', occurrence: 0, setAside: true);
    final f = FinanceData(accounts: [MoneyAccount(id: 'm', name: 'Money')], bills: [nick], overrides: [ov],
        events: [ev('opening', 10000, acct: 'm')], now: now);
    final o = occurrences(nick, f.ledger, [ov], addDays(t0, 10), now: now).first;
    expect(o.setAside, isTrue);
    expect(o.open, isTrue);
    expect(f.totalMoney, 10000);
    expect(f.reservedForBills, 2500);
  });

  test('last payment: schedule ends and the reminder says cancel', () {
    final meshy = Bill(id: 'x', name: 'Meshy', amountCents: 2000, frequency: 'monthly', firstDue: addDays(t0, 3), paymentCount: 1);
    final f = FinanceData(bills: [meshy], now: now);
    final occ = occurrences(meshy, f.ledger, const [], addDays(t0, 400), now: now);
    expect(occ.length, 1);
    expect(occ.single.isLast, isTrue);
    expect(planReminders(f, nowLocal: now).firstWhere((r) => r.key.startsWith('bill:x')).title, 'Last payment: cancel it');
  });

  test('deleting a duplicate account removes its balance from total money', () async {
    final app = AppState(LocalDb.memory(), clock: () => now);
    app.createAccount(MoneyAccount(id: 'a', name: 'Cash App'), 1000);
    app.createAccount(MoneyAccount(id: 'b', name: 'Cash App'), 0);
    app.deleteItems([app.data.account('b')!]);
    expect(app.data.accounts.length, 1);
    expect(app.data.totalMoney, 1000);
    await Future<void>.delayed(const Duration(seconds: 4));
  });
}
