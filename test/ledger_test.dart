import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/allocation.dart';
import 'package:stackd/domain/bills.dart';
import 'package:stackd/domain/finance.dart';
import 'package:stackd/domain/forecast.dart';

import 'helpers.dart';

final cash = MoneyAccount(id: 'cash', name: 'Cash');
final venmo = MoneyAccount(id: 'venmo', name: 'Venmo', kind: 'venmo');
final food = Category(id: 'ff', name: 'Fast Food', color: 0, tag: 'fast_food', limitCents: 3000);
final rent = Category(id: 'rent', name: 'Rent', color: 0, essential: true);
final beach = SavingsGoal(id: 'beach', name: 'Beach', goalCents: 50000);

FinanceData fin(List<LedgerEvent> events, {List<Bill> bills = const [], List<IncomeSchedule> schedules = const [],
        List<SavingsGoal>? goals, List<Category>? cats, List<BudgetAllocation> allocs = const [], List<BillOverride> ov = const [], Prefs? prefs}) =>
    FinanceData(accounts: [cash, venmo], categories: cats ?? [food, rent], goals: goals ?? [beach], bills: bills,
        schedules: schedules, events: events, budgetAllocations: allocs, overrides: ov, prefs: prefs, now: now);

void main() {
  group('transfers', () {
    test('move money without income, expense, or double counting', () {
      final f = fin([
        ev('opening', 10000, acct: 'cash'),
        ev('transfer', 2500, acct: 'cash', to: 'venmo'),
      ]);
      expect(f.ledger.accountBalance('cash'), 7500);
      expect(f.ledger.accountBalance('venmo'), 2500);
      expect(f.totalMoney, 10000);
      final t = f.weekTotals;
      expect(t.income, 0);
      expect(t.netSpent, 0);
    });
  });

  group('reversal (safe delete & edit)', () {
    test('reversed event no longer counts but stays in history', () {
      final spend = ev('expense', 1200, acct: 'cash', cat: 'ff');
      final f = fin([ev('opening', 5000, acct: 'cash'), spend, ev('reversal', 1200, reverses: spend.id)]);
      expect(f.ledger.accountBalance('cash'), 5000);
      expect(f.ledger.all.length, 3);
      expect(f.ledger.isReversed(spend.id), isTrue);
      expect(f.ledger.categorySpent('ff', t0, addDays(t0, 1)), 0);
    });
  });

  group('income classification', () {
    test('refunds and loans are not earned income', () {
      final f = fin([
        ev('income', 50000, acct: 'cash', src: 'paycheck'),
        ev('income', 6000, acct: 'cash', src: 'loan'),
        ev('expense', 2000, acct: 'cash', cat: 'ff'),
        ev('refund', 500, acct: 'cash', cat: 'ff'),
      ]);
      final t = f.weekTotals;
      expect(t.income, 50000);
      expect(t.borrowed, 6000);
      expect(t.netSpent, 1500);
      expect(f.ledger.categorySpent('ff', f.thisWeek.start, f.thisWeek.end), 1500);
      expect(f.totalMoney, 50000 + 6000 - 2000 + 500);
    });
  });

  group('savings', () {
    test('vault allocations are virtual and reduce available money', () {
      final f = fin([
        ev('opening', 20000, acct: 'cash'),
        ev('goal_deposit', 5000, goal: 'beach'),
        ev('goal_withdraw', 1000, goal: 'beach', reason: 'emergency'),
      ]);
      expect(f.totalMoney, 20000); // money did not leave accounts
      expect(f.totalSaved, 4000);
      expect(f.availableToSpend, 16000);
      final s = f.goalStatus(beach);
      expect(s.deposits, 5000);
      expect(s.withdrawals, 1000);
      expect(s.emergencyWithdrawals, 1000);
      expect(s.pct, 8);
    });
  });

  group('debt schedules', () {
    // Borrow $60, repay $10 every Friday for six weeks, no fees.
    final loan = Bill(id: 'cab', name: 'Cash App Borrow', kind: 'debt_owed', amountCents: 1000, frequency: 'weekly',
        firstDue: day(2026, 11, 20), principalCents: 6000);

    test('generates six weekly payments', () {
      expect(paymentCountOf(loan), 6);
      final occ = occurrences(loan, fin([]).ledger, const [], day(2027, 1, 1), now: now);
      expect(occ.length, 6);
      expect(occ.first.due, day(2026, 11, 20));
      expect(occ.last.due, day(2026, 12, 25));
      expect(occ.every((o) => o.amountCents == 1000), isTrue);
      expect(occ.every((o) => o.status != OccStatus.paid), isTrue); // nothing paid until confirmed
    });

    test('fees make the last payment the remainder', () {
      final b = Bill(id: 'x', name: 'Loan', kind: 'debt_owed', amountCents: 1000, frequency: 'weekly',
          firstDue: day(2026, 11, 20), principalCents: 6000, feeCents: 450);
      expect(paymentCountOf(b), 7);
      expect(scheduledAmount(b, 6), 450);
    });

    test('partial, missed, and paid payments', () {
      final f = fin([
        ev('bill_payment', 400, acct: 'cash', bill: 'cab', occ: 0),
      ], bills: [loan]);
      final later = DateTime(2026, 11, 28, 12); // after 1st and 2nd due dates
      final occ = occurrences(loan, f.ledger, const [], day(2027, 1, 1), now: later);
      expect(occ[0].status, OccStatus.overdue);
      expect(occ[0].remainingCents, 600);
      expect(occ[1].status, OccStatus.overdue);
      expect(remainingOwed(loan, f.ledger), 5600);

      final f2 = fin([ev('bill_payment', 1000, acct: 'cash', bill: 'cab', occ: 0)], bills: [loan]);
      expect(occurrences(loan, f2.ledger, const [], day(2027, 1, 1), now: now)[0].status, OccStatus.paid);
    });

    test('rescheduling moves a single occurrence', () {
      final ov = BillOverride(id: 'o', billId: 'cab', occurrence: 1, dueOn: day(2026, 12, 1));
      final occ = occurrences(loan, fin([]).ledger, [ov], day(2027, 1, 1), now: now);
      expect(occ[1].due, day(2026, 12, 1));
    });

    test('scheduled payments affect safe-to-spend, not balances', () {
      final f = fin([ev('opening', 10000, acct: 'cash')], bills: [loan]);
      expect(f.totalMoney, 10000);
      expect(f.reservedForBills, greaterThan(0));
      expect(f.availableToSpend, 10000 - f.reservedForBills);
    });
  });

  group('recurring bills', () {
    test('monthly rent and one-time bills', () {
      final r = Bill(id: 'r', name: 'Rent', amountCents: 90000, frequency: 'monthly', firstDue: day(2026, 12, 1));
      final once = Bill(id: 'o', name: 'Car fix', kind: 'one_time', amountCents: 20000, frequency: 'once', firstDue: day(2026, 11, 25));
      final f = fin([], bills: [r, once]);
      final up = f.upcomingBills(days: 60);
      expect(up.where((o) => o.bill.id == 'r').length, 2); // Dec 1 + Jan 1
      expect(up.where((o) => o.bill.id == 'o').length, 1);
      expect(totalOwed(r), isNull);
    });

    test('money lent to a friend is incoming, not an obligation', () {
      final lent = Bill(id: 'l', name: 'Jay owes me', kind: 'debt_lent', amountCents: 2000, frequency: 'weekly',
          firstDue: day(2026, 11, 19), principalCents: 4000);
      final f = fin([ev('opening', 1000, acct: 'cash')], bills: [lent]);
      expect(f.reservedForBills, 0);
    });
  });

  group('budget', () {
    test('category limit, extra allocation, rollover', () {
      final c = Category(id: 'sn', name: 'Snacks', color: 0, limitCents: 2000, rollover: true);
      final lastWeek = addDays(t0, -7);
      final f = fin([
        ev('expense', 500, acct: 'cash', cat: 'sn', on: lastWeek), // 1500 unused last week
        ev('expense', 3000, acct: 'cash', cat: 'sn'),
      ], cats: [c], allocs: [
        BudgetAllocation(id: 'a', categoryId: 'sn', periodStart: weekStartOf(t0, 1), amountCents: 400)
      ]);
      final s = f.categoryStatus(c);
      expect(s.rollover, 1500);
      expect(s.extra, 400);
      expect(s.budget, 3900);
      expect(s.remaining, 900);
      expect(s.over, isFalse);
    });
  });

  group('allocation proposals', () {
    final sched = IncomeSchedule(id: 'pay', name: 'Job', frequency: 'weekly', anchorDate: day(2026, 11, 20), expectedCents: 60000);

    test('paycheck proposal sums exactly and keeps bills covered', () {
      final g = SavingsGoal(id: 'g', name: 'Beach', goalCents: 50000, contributionCents: 5000);
      final rentBill = Bill(id: 'r', name: 'Rent', amountCents: 30000, frequency: 'monthly', firstDue: day(2026, 11, 19));
      final f = fin([ev('opening', 10000, acct: 'cash')], bills: [rentBill], schedules: [sched], goals: [g]);
      final p = suggestPaycheck(f, 60000);
      expect(p.allocated, 60000);
      expect(p.lines.firstWhere((l) => l.kind == TargetKind.bills).cents, 20000);
      expect(p.lines.firstWhere((l) => l.kind == TargetKind.goal).cents, 5000);
      expect(p.valid, isTrue);
    });

    test('extra money proposal never exceeds amount', () {
      final f = fin([ev('opening', 10000, acct: 'cash'), ev('expense', 4000, acct: 'cash', cat: 'ff')], schedules: [sched]);
      final p = suggestExtra(f, 7900);
      expect(p.allocated, 7900);
      expect(p.lines.any((l) => l.kind == TargetKind.category && l.targetId == 'ff'), isTrue);
      expect(p.lines.every((l) => l.cents >= 0), isTrue);
    });
  });

  group('forecast & what-if', () {
    final sched = IncomeSchedule(id: 'pay', name: 'Job', frequency: 'weekly', anchorDate: day(2026, 11, 20), expectedCents: 50000);

    test('deterministic and does not mutate data', () {
      final events = [ev('opening', 20000, acct: 'cash'), ev('expense', 2800, acct: 'cash', cat: 'ff', on: addDays(t0, -3))];
      final f = fin(events, schedules: [sched]);
      final a = buildForecast(f, weeks: 8);
      final b = buildForecast(f, weeks: 8);
      expect(a.weekly.map((p) => p.balance).toList(), b.weekly.map((p) => p.balance).toList());
      expect(a.weekly.length, 9);
      expect(f.ledger.all.length, 2);
      expect(a.payday, day(2026, 11, 20));
    });

    test('spending less raises projected balance; new bill lowers it', () {
      final f = fin([ev('opening', 20000, acct: 'cash'), ev('expense', 7000, acct: 'cash', cat: 'ff', on: addDays(t0, -2))], schedules: [sched]);
      final base = buildForecast(f, weeks: 4);
      final less = buildForecast(f, weeks: 4, s: const Scenario(weeklySpendDelta: -1000));
      final bill = buildForecast(f, weeks: 4, s: const Scenario(newMonthlyBill: 20000));
      expect(less.at(4).balance, greaterThan(base.at(4).balance));
      expect(bill.at(4).balance, lessThan(base.at(4).balance));
      final extra = buildForecast(f, weeks: 4, s: const Scenario(oneTimeIncome: 10000));
      expect(extra.at(4).balance - base.at(4).balance, 10000);
    });

    test('saving more each payday completes goals sooner', () {
      final g = SavingsGoal(id: 'g', name: 'Trip', goalCents: 100000, contributionCents: 5000);
      final f = fin([ev('opening', 20000, acct: 'cash')], schedules: [sched], goals: [g]);
      final base = buildForecast(f).goalCompletion['g']!;
      final more = buildForecast(f, s: const Scenario(extraSavingPerPayday: 5000)).goalCompletion['g']!;
      expect(more.isBefore(base), isTrue);
    });
  });
}
