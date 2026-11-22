import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/state/app_state.dart';

import 'helpers.dart';

void main() {
  group('duplicate transactions', () {
    test('same event id twice is stored once', () {
      final db = LocalDb.memory();
      final e = ev('expense', 500, acct: 'a');
      expect(db.put(e), isTrue);
      expect(db.put(e), isFalse);
      expect(db.all('ledger_events').length, 1);
    });

    test('AppState.record ignores a double-tap with the same id', () async {
      final app = AppState(LocalDb.memory(), clock: () => now);
      final acct = MoneyAccount(id: 'a', name: 'Cash');
      app.createAccount(acct, 10000);
      final e = app.event(id: 'fixed-id-0000', kind: 'expense', amountCents: 1500, accountId: 'a');
      app.record([e]);
      app.record([e]);
      expect(app.data.ledger.accountBalance('a'), 8500);
      await Future<void>.delayed(const Duration(seconds: 4)); // let debounce timers finish
    });
  });

  group('offline queue', () {
    test('writes stay queued (dirty) across restarts until synced', () {
      final dir = Directory.systemTemp.createTempSync('stackd');
      final path = '${dir.path}/t.db';
      var db = LocalDb.open(path);
      db.put(MoneyAccount(id: 'a', name: 'Cash'));
      db.put(ev('income', 1000, acct: 'a'));
      expect(db.dirtyCount, 2);
      db.db.close();
      db = LocalDb.open(path); // app restarted while offline
      expect(db.dirtyCount, 2);
      expect(db.dirtyRows('ledger_events').length, 1);
      db.markClean('ledger_events', db.dirtyRows('ledger_events').map((r) => r['id'] as String));
      expect(db.dirtyCount, 1);
      db.db.close();
      dir.deleteSync(recursive: true);
    });
  });

  group('sync conflict resolution', () {
    test('remote immutable row never overwrites a local copy', () {
      final db = LocalDb.memory();
      final e = ev('expense', 500, acct: 'a');
      db.put(e);
      expect(db.mergeRemote('ledger_events', {...e.toRow(), 'amount_cents': 999}), isFalse);
      expect(LedgerEvent.fromRow(db.all('ledger_events').single).amountCents, 500);
    });

    test('newer local edit beats older remote edit; newer remote wins otherwise', () {
      final db = LocalDb.memory();
      final c = Category(id: 'c', name: 'Local name', color: 1);
      db.put(c, clientUpdatedAt: '2026-11-18T12:00:00.000Z');
      final older = {...c.toRow(), 'name': 'Old remote', 'client_updated_at': '2026-11-18T11:00:00.000Z'};
      expect(db.mergeRemote('categories', older), isFalse);
      expect(db.all('categories').single['name'], 'Local name');
      final newer = {...c.toRow(), 'name': 'New remote', 'client_updated_at': '2026-11-18T13:00:00.000+00:00'};
      expect(db.mergeRemote('categories', newer), isTrue);
      expect(db.all('categories').single['name'], 'New remote');
      expect(db.dirtyCount, 0);
    });

    test('clean local rows accept remote changes', () {
      final db = LocalDb.memory();
      db.put(MoneyAccount(id: 'a', name: 'Cash'), dirty: false);
      expect(db.mergeRemote('money_accounts', {...MoneyAccount(id: 'a', name: 'Wallet').toRow()}), isTrue);
      expect(db.all('money_accounts').single['name'], 'Wallet');
    });
  });

  group('sign-out / account deletion', () {
    test('wipe removes all financial data but keeps device id', () async {
      final app = AppState(LocalDb.memory(), clock: () => now);
      app.createAccount(MoneyAccount(id: 'a', name: 'Cash'), 5000);
      app.ensureDefaults();
      final device = app.deviceId;
      await app.signOut();
      expect(app.db.all('money_accounts'), isEmpty);
      expect(app.db.all('ledger_events'), isEmpty);
      expect(app.db.all('categories'), isEmpty);
      expect(app.data.totalMoney, 0);
      expect(app.db.getKv('device_id'), device);
      await Future<void>.delayed(const Duration(seconds: 4));
    });

    test('export contains every table', () {
      final db = LocalDb.memory();
      db.put(MoneyAccount(id: 'a', name: 'Cash'));
      final x = db.export();
      expect(x['format'], 'stackd-export-v1');
      expect((x['money_accounts'] as List).length, 1);
      expect(x.containsKey('ledger_events'), isTrue);
    });
  });

  group('edit & reverse through AppState', () {
    test('edit keeps audit trail and updates balance', () async {
      final app = AppState(LocalDb.memory(), clock: () => now);
      app.createAccount(MoneyAccount(id: 'a', name: 'Cash'), 10000);
      final e = app.event(kind: 'expense', amountCents: 2000, accountId: 'a');
      app.record([e]);
      app.edit(e, e.replacement(newId: 'r1', amountCents: 2500));
      expect(app.data.ledger.accountBalance('a'), 7500);
      expect(app.data.ledger.all.length, 4); // opening, original, reversal, replacement
      app.reverse(app.data.ledger.active.firstWhere((x) => x.id == 'r1'));
      expect(app.data.ledger.accountBalance('a'), 10000);
      await Future<void>.delayed(const Duration(seconds: 4));
    });

    test('undo group reverses income + split together', () async {
      final app = AppState(LocalDb.memory(), clock: () => now);
      app.createAccount(MoneyAccount(id: 'a', name: 'Cash'), 0);
      app.save(SavingsGoal(id: 'g', name: 'Trip', goalCents: 10000));
      app.record([
        app.event(kind: 'income', amountCents: 7900, accountId: 'a', incomeSource: 'sale', groupId: 'grp'),
        app.event(kind: 'goal_deposit', amountCents: 3000, goalId: 'g', groupId: 'grp'),
      ]);
      expect(app.data.totalSaved, 3000);
      app.reverseGroup('grp');
      expect(app.data.totalSaved, 0);
      expect(app.data.totalMoney, 0);
      await Future<void>.delayed(const Duration(seconds: 4));
    });
  });
}
