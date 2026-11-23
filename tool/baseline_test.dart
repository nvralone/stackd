// Read-only snapshot of a STACKD database for before/after comparisons.
// Run against a COPY of the real database:
//   $env:STACKD_DB='C:\path\copy.db'; $env:STACKD_OUT='C:\path\snapshot.json'; flutter test tool/baseline_test.dart
// Skipped when STACKD_DB is not set, so it never runs in the normal test suite.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/domain/finance.dart';
import 'package:stackd/state/app_state.dart';

void main() {
  final path = Platform.environment['STACKD_DB'];
  test('baseline snapshot', () {
    final db = LocalDb.open(path!);
    // Content hash per table: every synced row exactly as stored (ignores the local dirty flag).
    final hashes = <String, Object>{};
    for (final t in syncTables) {
      final rows = db.db.select('select id, json from rows where tbl = ? order by id', [t]);
      final h = _fnv(rows.map((r) => '${r['id']}=${r['json']}').join('\n'));
      hashes[t] = {'rows': rows.length, 'fnv64': h};
    }
    final app = AppState(db, clock: () => DateTime(2026, 11, 23, 12));
    final FinanceData f = app.data;
    final snap = {
      'totals': {
        'totalMoney': f.totalMoney,
        'totalSaved': f.totalSaved,
        'reservedForBills': f.reservedForBills,
        'budgetedRemaining': f.budgetedRemaining,
        'availableToSpend': f.availableToSpend,
      },
      'accounts': {for (final a in f.accounts) a.name: f.ledger.accountBalance(a.id)},
      'goals': {for (final g in f.goals) g.name: {'saved': f.ledger.goalBalance(g.id), 'goal': g.goalCents}},
      'bills': [
        for (final b in f.bills) {'name': b.name, 'amount': b.amountCents, 'freq': b.frequency, 'firstDue': b.firstDue.toIso8601String()}
      ],
      'categories': {for (final c in f.categoryStatuses) c.category.name: {'limit': c.limit, 'budget': c.budget, 'spent': c.spent}},
      'events': f.ledger.all.length,
      'tables': hashes,
    };
    final out = const JsonEncoder.withIndent('  ').convert(snap);
    File(Platform.environment['STACKD_OUT'] ?? 'baseline.json').writeAsStringSync(out);
    // ignore: avoid_print
    print(out);
  }, skip: path == null ? 'set STACKD_DB to a copy of the database' : false);
}

/// FNV-1a 64-bit over UTF-8 bytes, as hex.
String _fnv(String s) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h *= 0x100000001b3;
  }
  return h.toUnsigned(64).toRadixString(16);
}