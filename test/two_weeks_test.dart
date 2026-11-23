// End-to-end: two real weeks of using STACKD the way it's meant to be used.
import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/core/ids.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/allocation.dart';
import 'package:stackd/state/app_state.dart';

void main() {
  test('two weeks: split free money always equals dashboard spare; week resets cleanly', () async {
    var clock = DateTime(2026, 11, 20, 10); // Friday payday
    final app = AppState(LocalDb.memory(), clock: () => clock);
    app.savePrefs((p) => p..weekStart = 5..onboarded = true);
    app.createAccount(MoneyAccount(id: 'm', name: 'Money'), 0);
    app.save(IncomeSchedule(id: 'pay', name: 'Job', frequency: 'weekly', anchorDate: day(2026, 11, 20), expectedCents: 29500));
    app.save(Category(id: 'food', name: 'Food', color: 0, limitCents: 12000, essential: true));
    app.save(Category(id: 'gas', name: 'Gas', color: 0, limitCents: 3000, essential: true));
    app.save(Category(id: 'fun', name: 'Fun', color: 0, limitCents: 4000));
    app.save(Bill(id: 'self', name: 'Self', amountCents: 2500, frequency: 'weekly', firstDue: day(2026, 11, 22)));
    app.save(Bill(id: 'ins', name: 'Insurance', amountCents: 20000, frequency: 'monthly', firstDue: day(2026, 12, 16)));
    app.save(SavingsGoal(id: 'vault', name: 'The VAULT', goalCents: 200000, contributionCents: 3000, contributionFreq: 'payday'));

    /// Logs a paycheck and accepts the suggested split exactly like the split screen does. Returns the free line.
    int paycheck(int cents) {
      final p = suggestPaycheck(app.data, cents);
      final g = newId();
      app.record([app.event(kind: 'income', amountCents: cents, accountId: 'm', incomeSource: 'paycheck', groupId: g)]);
      for (final l in p.lines) {
        if (l.kind == TargetKind.goal) app.record([app.event(kind: 'goal_deposit', amountCents: l.cents, goalId: l.targetId, groupId: g)]);
        if (l.kind == TargetKind.billSavings) {
          var bs = app.data.goals.where((x) => x.name == billSavingsName).firstOrNull;
          if (bs == null) {
            bs = SavingsGoal(id: newId(), name: billSavingsName, goalCents: 20000, contributionFreq: 'none');
            app.save(bs);
          }
          app.record([app.event(kind: 'goal_deposit', amountCents: l.cents, goalId: bs.id, groupId: g)]);
        }
      }
      expect(p.allocated, cents);
      return p.lines.where((l) => l.kind == TargetKind.unallocated).fold(0, (s, l) => s + l.cents);
    }

    // ---------------- week 1
    final free1 = paycheck(29500);
    var d = app.data;
    expect(d.totalMoney, 29500);
    expect(d.availableToSpend, free1); // what the split promised is what the dashboard shows
    expect(d.availableToSpend, greaterThanOrEqualTo(0));
    expect(d.weekTotals.income, 29500);

    // eat out $20: food goes down, spare does not change
    app.record([app.event(kind: 'expense', amountCents: 2000, accountId: 'm', categoryId: 'food')]);
    d = app.data;
    expect(d.categoryStatus(d.category('food')!).remaining, 10000);
    expect(d.availableToSpend, free1);

    // pay Self ($25, reserved before payday): spare does not change
    app.record([app.event(kind: 'bill_payment', amountCents: 2500, accountId: 'm', billId: 'self', billOccurrence: 0)]);
    d = app.data;
    expect(d.availableToSpend, free1);

    // found $30 more cash for gas: total up, spare unchanged
    app.record([app.event(kind: 'adjustment', amountCents: 3000, accountId: 'm', note: 'Cash for Gas')],
        also: [BudgetAllocation(id: newId(), categoryId: 'gas', periodStart: day(2026, 11, 20), amountCents: 3000)]);
    d = app.data;
    expect(d.categoryStatus(d.category('gas')!).remaining, 6000);
    expect(d.availableToSpend, free1);

    // the identity the dashboard prints always holds
    expect(d.totalMoney, d.totalSaved + d.reservedForBills + d.budgetedRemaining + d.availableToSpend);

    // ---------------- week 2 (next Friday)
    clock = DateTime(2026, 11, 27, 10);
    app.reload();
    d = app.data;
    expect(d.thisWeek.start, day(2026, 11, 27));
    expect(d.categoryStatus(d.category('food')!).remaining, 12000); // fresh week
    expect(d.categoryStatus(d.category('gas')!).remaining, 3000); // last week's extra $30 does not carry over
    expect(d.weekTotals.income, 0);
    final leftover = d.totalMoney - d.totalSaved; // unspent money from week 1 counts toward week 2
    final free2 = paycheck(29500);
    d = app.data;
    expect(d.availableToSpend, free2);
    expect(d.totalMoney, d.totalSaved + d.reservedForBills + d.budgetedRemaining + d.availableToSpend);
    expect(leftover, greaterThan(0));
    // insurance is being saved for, a little each paycheck
    expect(d.ledger.goalBalance(d.goals.firstWhere((g) => g.name == billSavingsName).id), greaterThan(0));
    await Future<void>.delayed(const Duration(seconds: 4));
  });
}
