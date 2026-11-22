// Offline-first local store (SQLite). Every write is marked dirty and queued for sync.
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

/// Tables whose rows are never updated after insert. Inserts are idempotent (INSERT OR IGNORE).
const immutableTables = {'ledger_events', 'trip_entries', 'clover_events'};

/// Sync order respects foreign keys.
const syncTables = [
  'profiles', 'money_accounts', 'categories', 'income_schedules', 'trips', 'savings_goals', 'bills',
  'bill_overrides', 'budget_allocations', 'trip_budget_items', 'ledger_events', 'trip_entries',
];

class LocalDb {
  final Database db;
  LocalDb(this.db) {
    db.execute('''
      create table if not exists rows (
        tbl text not null, id text not null, json text not null,
        dirty integer not null default 1, client_updated_at text not null,
        primary key (tbl, id));
      create table if not exists kv (key text primary key, value text not null);
      create index if not exists rows_dirty on rows (dirty, tbl);
    ''');
  }

  factory LocalDb.open(String path) => LocalDb(sqlite3.open(path));
  factory LocalDb.memory() => LocalDb(sqlite3.openInMemory());

  /// Upsert a mutable entity, or insert-once an immutable one. Returns false for a duplicate immutable write.
  bool put(Entity e, {bool dirty = true, String? clientUpdatedAt}) {
    final now = clientUpdatedAt ?? DateTime.now().toUtc().toIso8601String();
    final row = {...e.toRow(), 'client_updated_at': now};
    if (immutableTables.contains(e.table)) {
      db.execute('insert or ignore into rows (tbl, id, json, dirty, client_updated_at) values (?, ?, ?, ?, ?)',
          [e.table, e.id, jsonEncode(row), dirty ? 1 : 0, now]);
      return db.updatedRows > 0;
    }
    db.execute('''insert into rows (tbl, id, json, dirty, client_updated_at) values (?, ?, ?, ?, ?)
        on conflict (tbl, id) do update set json = excluded.json, dirty = excluded.dirty,
        client_updated_at = excluded.client_updated_at''', [e.table, e.id, jsonEncode(row), dirty ? 1 : 0, now]);
    return true;
  }

  /// Raw upsert of a row pulled from the server (already clean).
  void putRaw(String table, DbRow row) {
    final id = row['id'] as String? ?? row['user_id'] as String;
    final cu = row['client_updated_at'] as String? ?? row['created_at'] as String? ?? DateTime.now().toUtc().toIso8601String();
    db.execute('''insert into rows (tbl, id, json, dirty, client_updated_at) values (?, ?, ?, 0, ?)
        on conflict (tbl, id) do update set json = excluded.json, dirty = 0, client_updated_at = excluded.client_updated_at''',
        [table, id, jsonEncode(row), cu]);
  }

  /// Applies a row pulled from the server. Immutable rows are kept as-is if already present.
  /// Mutable rows: a local unsynced edit wins unless the remote edit is newer (last writer wins).
  /// Returns true if the local copy changed.
  bool mergeRemote(String table, DbRow r) {
    final id = (r['id'] ?? r['user_id']) as String;
    final local = meta(table, id);
    if (local != null && immutableTables.contains(table)) return false;
    if (local != null && local.dirty) {
      final remote = DateTime.tryParse(r['client_updated_at'] as String? ?? '') ?? DateTime(1970);
      if (!remote.isAfter(DateTime.parse(local.clientUpdatedAt))) return false;
    }
    putRaw(table, r);
    return true;
  }

  /// Removes local categories that were never uploaded and duplicate (by name) a category
  /// that came from the server, as long as nothing references them. Prevents two devices
  /// each creating their own set of default categories.
  int dedupeNewCategories() {
    final rows = db.select("select id, json, dirty from rows where tbl = 'categories'");
    final synced = <String>{};
    for (final r in rows) {
      if (r['dirty'] == 0) synced.add(((jsonDecode(r['json'] as String) as Map)['name'] as String).toLowerCase());
    }
    var removed = 0;
    for (final r in rows) {
      if (r['dirty'] != 1) continue;
      final j = jsonDecode(r['json'] as String) as Map;
      if (j['updated_at'] != null) continue; // has been on the server: a real edit, keep
      if (!synced.contains((j['name'] as String).toLowerCase())) continue;
      final id = r['id'] as String;
      final used = db.select("select 1 from rows where tbl in ('ledger_events','bills','budget_allocations') and json like ? limit 1",
          ['%"$id"%']);
      if (used.isNotEmpty) continue;
      db.execute("delete from rows where tbl = 'categories' and id = ?", [id]);
      removed++;
    }
    return removed;
  }

  ({bool dirty, String clientUpdatedAt})? meta(String table, String id) {
    final r = db.select('select dirty, client_updated_at from rows where tbl = ? and id = ?', [table, id]);
    if (r.isEmpty) return null;
    return (dirty: r.first['dirty'] == 1, clientUpdatedAt: r.first['client_updated_at'] as String);
  }

  List<DbRow> all(String table) => [
        for (final r in db.select('select json from rows where tbl = ? order by rowid', [table]))
          Map<String, Object?>.from(jsonDecode(r['json'] as String) as Map)
      ];

  List<DbRow> dirtyRows(String table) => [
        for (final r in db.select('select json from rows where tbl = ? and dirty = 1 order by rowid', [table]))
          Map<String, Object?>.from(jsonDecode(r['json'] as String) as Map)
      ];

  int get dirtyCount => db.select('select count(*) c from rows where dirty = 1').first['c'] as int;

  void markClean(String table, Iterable<String> ids) {
    for (final id in ids) {
      db.execute('update rows set dirty = 0 where tbl = ? and id = ?', [table, id]);
    }
  }

  String? getKv(String key) {
    final r = db.select('select value from kv where key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  void setKv(String key, String value) =>
      db.execute('insert into kv (key, value) values (?, ?) on conflict (key) do update set value = excluded.value', [key, value]);

  /// Removes all financial data (used on sign-out and account deletion). Keeps the device id.
  void wipe() {
    db.execute('delete from rows');
    db.execute("delete from kv where key <> 'device_id'");
  }

  void transaction(void Function() body) {
    db.execute('begin');
    try {
      body();
      db.execute('commit');
    } catch (_) {
      db.execute('rollback');
      rethrow;
    }
  }

  /// Full JSON export of local data (user-owned backup).
  Map<String, Object?> export() => {
        'format': 'stackd-export-v1',
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        for (final t in [...syncTables, 'clover_events']) t: all(t),
      };
}
