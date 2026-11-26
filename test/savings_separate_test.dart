import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/finance.dart';

import 'helpers.dart';

void main() {
  test('accounts show only spendable money; savings are their own total', () {
    final money = MoneyAccount(id: 'm', name: 'Money');
    final cashApp = MoneyAccount(id: 'c', name: 'Cash App', sort: 1);
    final vault = SavingsGoal(id: 'v', name: 'Vault', goalCents: 100000);
    final f = FinanceData(accounts: [money, cashApp], goals: [vault], events: [
      ev('opening', 20300, acct: 'm'),
      ev('opening', 653, acct: 'c'),
      ev('goal_deposit', 13000, goal: 'v'),
    ], now: now);
    expect(f.savingsHome!.id, 'm');
    expect(f.accountSpendable('m'), 7300); // the real cash, not $203
    expect(f.savedIn('m'), 13000);
    expect(f.accountSpendable('c'), 653);
    expect(f.moneyInAccounts, 7953);
    expect(f.totalMoney, 7953 + 13000);
    expect(f.availableToSpend, 7953); // no bills or budgets here
  });
}
