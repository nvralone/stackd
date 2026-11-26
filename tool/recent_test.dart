// Read-only: prints recent transactions and the money breakdown from a COPY of the database.
//   $env:STACKD_DB='...copy.db'; flutter test tool/recent_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/money.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/state/app_state.dart';

void main() {
  final path = Platform.environment['STACKD_DB'];
  test('recent', () {
    final app = AppState(LocalDb.open(path!));
    final f = app.data;
    String n(String? id) => id == null ? '-' : (f.account(id)?.name ?? f.category(id)?.name ?? f.goal(id)?.name ?? f.bill(id)?.name ?? '?');
    final since = DateTime.now().subtract(const Duration(days: 4));
    final evs = f.ledger.all.where((e) => (e.createdAt ?? e.occurredOn).isAfter(since) || e.occurredOn.isAfter(since)).toList();
    final reversed = {for (final e in f.ledger.all) if (e.reversesId != null) e.reversesId};
    for (final e in evs) {
      // ignore: avoid_print
      print('EV ${e.occurredOn.toIso8601String().substring(0, 10)} ${e.kind.padRight(13)} ${formatCents(e.amountCents).padLeft(9)} '
          'acct=${n(e.accountId)} to=${n(e.toAccountId)} cat=${n(e.categoryId)} goal=${n(e.goalId)} bill=${n(e.billId)}#${e.billOccurrence} '
          'src=${e.incomeSource} ${reversed.contains(e.id) ? 'REVERSED ' : ''}note=${e.note}');
    }
    // ignore: avoid_print
    print('TOTALS money=${formatCents(f.totalMoney)} saved=${formatCents(f.totalSaved)} bills=${formatCents(f.reservedForBills)} '
        'budgets=${formatCents(f.budgetedRemaining)} spare=${formatCents(f.availableToSpend)}');
    for (final a in f.accounts) {
      // ignore: avoid_print
      print('ACCT ${a.name}: ${formatCents(f.ledger.accountBalance(a.id))}${a.archived ? ' (archived)' : ''}');
    }
    for (final s in f.categoryStatuses.where((s) => s.hasLimit)) {
      // ignore: avoid_print
      print('BUDGET ${s.category.name}: limit ${formatCents(s.limit)} extra ${formatCents(s.extra)} spent ${formatCents(s.spent)} left ${formatCents(s.remaining)}');
    }
    for (final o in f.upcomingBills(days: 10).where((o) => !o.bill.incoming)) {
      // ignore: avoid_print
      print('BILL ${o.bill.name} #${o.index} due ${o.due.toIso8601String().substring(0, 10)} ${formatCents(o.remainingCents)} paid ${formatCents(o.paidCents)}');
    }
    // ignore: avoid_print
    print('WEEK ${f.thisWeek.start.toIso8601String().substring(0, 10)} payday ${f.nextPayday}');
  }, skip: path == null);
}
