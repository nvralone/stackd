// Derives every balance from the immutable event list. Nothing here is cached UI state.
import '../data/models.dart';

class Ledger {
  final List<LedgerEvent> all;
  late final Set<String> reversedIds = {for (final e in all) if (e.kind == 'reversal' && e.reversesId != null) e.reversesId!};
  /// Events that currently count: not reversals themselves, not reversed.
  late final List<LedgerEvent> active = [for (final e in all) if (e.kind != 'reversal' && !reversedIds.contains(e.id)) e];

  Ledger(List<LedgerEvent> events) : all = List.unmodifiable(events);

  bool isReversed(String id) => reversedIds.contains(id);

  /// Signed effect of an event on a real money account.
  static int accountDelta(LedgerEvent e, String accountId) {
    switch (e.kind) {
      case 'opening':
      case 'adjustment':
        return e.accountId == accountId ? e.amountCents : 0;
      case 'income':
      case 'refund':
      case 'loan_in':
        return e.accountId == accountId ? e.amountCents : 0;
      case 'expense':
      case 'bill_payment':
      case 'loan_out':
        return e.accountId == accountId ? -e.amountCents : 0;
      case 'transfer':
        return (e.toAccountId == accountId ? e.amountCents : 0) - (e.accountId == accountId ? e.amountCents : 0);
      default: // goal_* are virtual allocations: no account change
        return 0;
    }
  }

  late final Map<String, int> _accountBalances = () {
    final m = <String, int>{};
    for (final e in active) {
      for (final id in [e.accountId, e.toAccountId]) {
        if (id != null && !m.containsKey(id)) m[id] = 0;
      }
      if (e.accountId != null) m[e.accountId!] = m[e.accountId!]! + accountDelta(e, e.accountId!);
      if (e.kind == 'transfer' && e.toAccountId != null) m[e.toAccountId!] = m[e.toAccountId!]! + e.amountCents;
    }
    return m;
  }();

  int accountBalance(String accountId) => _accountBalances[accountId] ?? 0;

  /// Sum of balances over the given accounts (transfers net to zero, so no double counting).
  int totalBalance(Iterable<String> accountIds) => accountIds.fold(0, (s, id) => s + accountBalance(id));

  int goalBalance(String goalId) {
    var s = 0;
    for (final e in active) {
      if (e.goalId != goalId) continue;
      if (e.kind == 'goal_deposit') s += e.amountCents;
      if (e.kind == 'goal_withdraw') s -= e.amountCents;
    }
    return s;
  }

  ({int deposits, int withdrawals, int emergency}) goalFlows(String goalId) {
    var d = 0, w = 0, em = 0;
    for (final e in active) {
      if (e.goalId != goalId) continue;
      if (e.kind == 'goal_deposit') d += e.amountCents;
      if (e.kind == 'goal_withdraw') {
        w += e.amountCents;
        if (e.reason == 'emergency') em += e.amountCents;
      }
    }
    return (deposits: d, withdrawals: w, emergency: em);
  }

  /// Net spending in a category over [start, end): expenses + bill payments - refunds.
  int categorySpent(String categoryId, DateTime start, DateTime end) {
    var s = 0;
    for (final e in active) {
      if (e.categoryId != categoryId || e.occurredOn.isBefore(start) || !e.occurredOn.isBefore(end)) continue;
      if (e.kind == 'expense' || e.kind == 'bill_payment') s += e.amountCents;
      if (e.kind == 'refund') s -= e.amountCents;
    }
    return s;
  }

  Iterable<LedgerEvent> between(DateTime start, DateTime end) =>
      active.where((e) => !e.occurredOn.isBefore(start) && e.occurredOn.isBefore(end));

  /// Totals for a date range. Income = earned income only (no refunds, no loans, no transfers).
  PeriodTotals totals(DateTime start, DateTime end) {
    var income = 0, spent = 0, refunds = 0, saved = 0, withdrawn = 0, borrowed = 0;
    for (final e in between(start, end)) {
      switch (e.kind) {
        case 'income':
          e.incomeSource == 'loan' ? borrowed += e.amountCents : income += e.amountCents;
        case 'expense':
        case 'bill_payment':
          spent += e.amountCents;
        case 'refund':
          refunds += e.amountCents;
        case 'goal_deposit':
          saved += e.amountCents;
        case 'goal_withdraw':
          withdrawn += e.amountCents;
      }
    }
    return PeriodTotals(income, spent - refunds, refunds, saved, withdrawn, borrowed);
  }

  /// Paid amount against a specific bill occurrence.
  int paidFor(String billId, int occurrence) => active
      .where((e) => e.billId == billId && e.billOccurrence == occurrence && (e.kind == 'bill_payment' || e.kind == 'loan_in'))
      .fold(0, (s, e) => s + e.amountCents);

  int paidForBill(String billId) => active
      .where((e) => e.billId == billId && (e.kind == 'bill_payment' || e.kind == 'loan_in'))
      .fold(0, (s, e) => s + e.amountCents);
}

class PeriodTotals {
  final int income, netSpent, refunds, saved, withdrawn, borrowed;
  const PeriodTotals(this.income, this.netSpent, this.refunds, this.saved, this.withdrawn, this.borrowed);
  int get netSaved => saved - withdrawn;
  /// Savings rate in whole percent of earned income.
  int get savingsRate => income <= 0 ? 0 : netSaved * 100 ~/ income;
}
