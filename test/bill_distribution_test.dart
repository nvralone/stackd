// Regression tests for per-bill paycheck distribution (Bill envelope earmarks). Isolated fixtures only.
import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/allocation.dart';
import 'package:stackd/domain/finance.dart';
import 'package:stackd/state/app_state.dart';

import 'helpers.dart';

/// Friday Nov 20 2026, a payday.
final payday = DateTime(2026, 11, 20, 12);
final money = MoneyAccount(id: 'm', name: 'Money');
final weekly = IncomeSchedule(id: 'p', name: 'Job', frequency: 'weekly', anchorDate: day(2026, 11, 20), expectedCents: 50000);
final env = SavingsGoal(id: 'bs', name: billSavingsName, goalCents: 50000, contributionFreq: 'none');
// Due Mon Dec 7: paydays Nov 20, Nov 27, Dec 4 come before it -> 3 paychecks.
Bill insurance({DateTime? due}) => Bill(id: 'ins', name: 'Insurance', amountCents: 30000, frequency: 'monthly', firstDue: due ?? day(2026, 12, 7));

FinanceData fin({List<Bill>? bills, List<LedgerEvent> events = const [], List<IncomeSchedule>? schedules, DateTime? at, List<SavingsGoal>? goals}) =>
    FinanceData(accounts: [money], bills: bills ?? [insurance()], goals: goals ?? [env], schedules: schedules ?? [weekly],
        events: [ev('opening', 100000, acct: 'm', on: day(2026, 11, 1)), ...events], now: at ?? payday);

BillNeed need(FinanceData f, [String id = 'ins']) => billNeeds(f).firstWhere((n) => n.bill.id == id && !n.beforePayday);

void main() {
  group('spec examples', () {
    test('\$300 due after 3 paychecks, nothing reserved -> \$100 per paycheck', () {
      final n = need(fin());
      expect(n.paychecksLeft, 3);
      expect(n.recommended, 10000);
    });

    test('\$90 already reserved for it -> the remaining \$210 over 3 = \$70', () {
      final f = fin(events: [ev('goal_deposit', 9000, goal: 'bs', bill: 'ins', on: day(2026, 11, 13))]);
      expect(f.billEarmarks, {'ins': 9000});
      final n = need(f);
      expect(n.inEnvelope, 9000);
      expect(n.stillNeeded, 21000);
      expect(n.recommended, 7000);
    });

    test('only 2 paychecks left with \$90 reserved -> \$105', () {
      // Due Mon Nov 30: paydays Nov 20 and Nov 27 come before it.
      final f = fin(bills: [insurance(due: day(2026, 11, 30))], events: [ev('goal_deposit', 9000, goal: 'bs', bill: 'ins', on: day(2026, 11, 13))]);
      final n = need(f);
      expect(n.paychecksLeft, 2);
      expect(n.recommended, 10500);
    });
  });

  test('money added for a bill this pay period counts toward this paycheck (never asked twice)', () {
    final f = fin(events: [ev('goal_deposit', 9000, goal: 'bs', bill: 'ins', on: day(2026, 11, 20))]);
    expect(need(f).recommended, 1000); // share is $100; $90 was already added today
    final full = fin(events: [ev('goal_deposit', 10000, goal: 'bs', bill: 'ins', on: day(2026, 11, 20))]);
    expect(need(full).recommended, 0);
    // next payday: $200 left over 2 paychecks
    final next = fin(events: [ev('goal_deposit', 10000, goal: 'bs', bill: 'ins', on: day(2026, 11, 20))], at: DateTime(2026, 11, 27, 12));
    expect(need(next).paychecksLeft, 2);
    expect(need(next).recommended, 10000);
  });

  test('partial payments are subtracted', () {
    final f = fin(events: [ev('bill_payment', 6000, acct: 'm', bill: 'ins', occ: 0, on: day(2026, 11, 19))]);
    final n = need(f);
    expect(n.paid, 6000);
    expect(n.stillNeeded, 24000);
    expect(n.recommended, 8000);
  });

  test('envelope money for a bill due before payday is not held twice', () {
    // Due Wed Nov 25, before next payday (Nov 27).
    final b = insurance(due: day(2026, 11, 25));
    final without = fin(bills: [b]);
    expect(without.reservedForBills, 30000);
    final f = fin(bills: [b], events: [ev('goal_deposit', 30000, goal: 'bs', bill: 'ins', on: day(2026, 11, 13))]);
    expect(f.reservedForBills, 0); // fully covered by its envelope money
    expect(f.availableToSpend, without.availableToSpend); // $300 moved into the envelope, $300 less held -> same spare
    final n = billNeeds(f).firstWhere((n) => n.beforePayday);
    expect(n.inEnvelope, 30000);
    expect(n.recommended, 0);
  });

  test('unassigned envelope money is never assigned silently', () {
    final f = fin(events: [ev('goal_deposit', 12000, goal: 'bs', on: day(2026, 11, 13))]);
    expect(f.billEarmarks, isEmpty);
    expect(f.billEnvelopeUnassigned, 12000);
    expect(need(f).recommended, 10000);
    final p = suggestPaycheck(f, 50000);
    expect(p.assign, isEmpty);
    final asked = suggestPaycheck(f, 50000, useUnassigned: true);
    expect(asked.assign, {'ins': 12000});
    expect(asked.lines.firstWhere((l) => l.kind == TargetKind.billSavings).cents, 6000); // $180 left over 3
  });

  test('taking money out of the envelope: bills due last lose their share first', () {
    final soon = Bill(id: 'a', name: 'Phone', amountCents: 5000, frequency: 'monthly', firstDue: day(2026, 12, 5));
    final late = Bill(id: 'b', name: 'Car', amountCents: 8000, frequency: 'monthly', firstDue: day(2026, 12, 15));
    final f = fin(bills: [soon, late], events: [
      ev('goal_deposit', 4000, goal: 'bs', bill: 'a', on: day(2026, 11, 13)),
      ev('goal_deposit', 4000, goal: 'bs', bill: 'b', on: day(2026, 11, 13)),
      ev('goal_withdraw', 5000, goal: 'bs', reason: 'planned', on: day(2026, 11, 14)), // back to spare
    ]);
    expect(f.billEnvelopeBalance, 3000);
    expect(f.billEarmarks, {'a': 3000}); // Car (due last) lost all 40, Phone lost 10
    expect(f.billEnvelopeUnassigned, 0);
  });

  test('using more than a bill had set aside never makes its share negative', () {
    final f = fin(events: [
      ev('goal_deposit', 20000, goal: 'bs', on: day(2026, 11, 10)), // unassigned
      ev('goal_deposit', 7000, goal: 'bs', bill: 'ins', on: day(2026, 11, 11)),
      ev('goal_withdraw', 9000, goal: 'bs', bill: 'ins', reason: 'planned', on: day(2026, 11, 12)),
      ev('goal_deposit', 5000, goal: 'bs', bill: 'ins', on: day(2026, 11, 13)),
    ]);
    expect(f.billEarmarks, {'ins': 5000}); // 70 - 90 -> 0, then +50
    expect(f.billEnvelopeBalance, 23000);
    expect(f.billEnvelopeUnassigned, 18000);
  });

  test('several bills on the same day and a paycheck too small: soonest first, the rest is reported short', () {
    final a = Bill(id: 'a', name: 'Phone', amountCents: 6000, frequency: 'monthly', firstDue: day(2026, 11, 24));
    final b = Bill(id: 'b', name: 'Net', amountCents: 6000, frequency: 'monthly', firstDue: day(2026, 11, 24));
    final c = Bill(id: 'c', name: 'Car', amountCents: 30000, frequency: 'monthly', firstDue: day(2026, 12, 7));
    final f = FinanceData(accounts: [money], bills: [a, b, c], goals: [env], schedules: [weekly], now: payday);
    final p = suggestPaycheck(f, 9000);
    final near = p.lines.where((l) => l.kind == TargetKind.bills).toList();
    expect(near.map((l) => l.targetId), containsAll(['a', 'b']));
    expect(near.fold(0, (s, l) => s + l.cents), 9000); // all of it to the two bills due before payday
    expect(p.lines.where((l) => l.kind == TargetKind.billSavings && l.cents > 0), isEmpty);
    expect(p.leftover, 0);
    expect(p.lines.every((l) => l.cents >= 0), isTrue);
  });

  group('pay schedules', () {
    test('biweekly', () {
      final s = IncomeSchedule(id: 'p', name: 'Job', frequency: 'biweekly', anchorDate: day(2026, 11, 20));
      final f = fin(schedules: [s], bills: [Bill(id: 'ins', name: 'Insurance', amountCents: 30000, frequency: 'yearly', firstDue: day(2027, 1, 10))]);
      expect(need(f).paychecksLeft, 4); // Nov 20, Dec 4, Dec 18, Jan 1
      expect(need(f).recommended, 7500);
    });

    test('semimonthly', () {
      final s = IncomeSchedule(id: 'p', name: 'Job', frequency: 'semimonthly', anchorDate: day(2026, 11, 5));
      final f = fin(schedules: [s], bills: [Bill(id: 'ins', name: 'Insurance', amountCents: 30000, frequency: 'yearly', firstDue: day(2027, 1, 10))],
          at: DateTime(2026, 11, 20, 12));
      expect(need(f).paychecksLeft, 4); // Nov 20, Dec 5, Dec 20, Jan 5
    });

    test('monthly pay: a yearly bill is spread across the months left', () {
      final s = IncomeSchedule(id: 'p', name: 'Job', frequency: 'monthly', anchorDate: day(2026, 11, 20));
      final f = fin(schedules: [s], bills: [Bill(id: 'ins', name: 'Insurance', amountCents: 30000, frequency: 'yearly', firstDue: day(2027, 2, 10))]);
      expect(need(f).paychecksLeft, 3); // Nov 20, Dec 20, Jan 20
      expect(need(f).recommended, 10000);
    });

    test('irregular income is never assumed: falls back to a cautious interval', () {
      final s = IncomeSchedule(id: 'p', name: 'Gigs', frequency: 'irregular', anchorDate: day(2026, 11, 20));
      final f = fin(schedules: [s]);
      expect(paydaysBetween(f, day(2026, 11, 1), day(2027, 1, 1)), isEmpty);
      expect(need(f).paychecksLeft, greaterThanOrEqualTo(1));
    });
  });

  test('suggestions never create bills, touch savings, or withdraw from vaults', () {
    final vault = SavingsGoal(id: 'v', name: 'Vault', goalCents: 100000, contributionCents: 2000);
    final f = fin(goals: [env, vault], events: [ev('goal_deposit', 5000, goal: 'v', on: day(2026, 11, 2))]);
    final p = suggestPaycheck(f, 1000); // far too small for anything
    expect(p.lines.every((l) => l.cents >= 0), isTrue);
    expect(p.allocated, 1000);
    expect(f.bills.length, 1);
    expect(f.ledger.goalBalance('v'), 5000);
  });

  test('computing or cancelling a suggestion writes nothing; accepting writes only the bill deposit', () async {
    final app = AppState(LocalDb.memory(), clock: () => payday);
    app.createAccount(money, 100000);
    app.save(weekly);
    app.save(insurance());
    final rowsBefore = app.db.db.select('select count(*) c from rows').first['c'];
    final p = suggestPaycheck(app.data, 50000);
    suggestPaycheck(app.data, 50000, useUnassigned: true);
    expect(app.db.db.select('select count(*) c from rows').first['c'], rowsBefore);
    // accepting the envelope line for Insurance
    final line = p.lines.firstWhere((l) => l.kind == TargetKind.billSavings);
    app.addToBillEnvelope(line.cents);
    final d = app.data;
    expect(d.billEarmarks, {'ins': 10000});
    expect(d.bills.length, 1);
    expect(d.bills.single.firstDue, day(2026, 12, 7)); // due date untouched
    expect(d.totalMoney, 100000); // money only moved, never created
    await Future<void>.delayed(const Duration(seconds: 4));
  });

  test('paying a bill from its envelope money uses up its share', () {
    final b = insurance(due: day(2026, 11, 25));
    final f = fin(bills: [b], events: [
      ev('goal_deposit', 30000, goal: 'bs', bill: 'ins', on: day(2026, 11, 13)),
      ev('bill_payment', 30000, acct: 'm', bill: 'ins', occ: 0, on: day(2026, 11, 25)),
      ev('goal_withdraw', 30000, goal: 'bs', bill: 'ins', reason: 'planned', on: day(2026, 11, 25)),
    ], at: DateTime(2026, 11, 25, 12));
    expect(f.billEarmarks, isEmpty);
    expect(f.ledger.paidFor('ins', 0), 30000); // envelope deposits/withdrawals never count as bill payments
    expect(f.reservedForBills, 0);
  });
}
