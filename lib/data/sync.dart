// Supabase sync: push dirty rows (idempotent), pull changes since a cursor, retry with backoff.
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_db.dart';

enum SyncState { localOnly, signedOut, idle, syncing, error }

class SyncService {
  final LocalDb db;
  final SupabaseClient client;
  final void Function() onChanged;
  SyncState state = SyncState.idle;
  String? lastError;
  DateTime? lastSynced;
  int _failures = 0;
  Timer? _timer;
  Future<void>? _running;

  SyncService(this.db, this.client, this.onChanged);

  String? get uid => client.auth.currentUser?.id;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => sync());
    sync();
  }

  void stop() => _timer?.cancel();

  /// Coalesces concurrent calls; retries with exponential backoff on failure.
  Future<void> sync() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    if (uid == null) {
      state = SyncState.signedOut;
      return;
    }
    state = SyncState.syncing;
    onChanged();
    try {
      // Pull first so a new device sees existing data before uploading anything,
      // then drop never-synced default categories that duplicate synced ones.
      await pull();
      db.dedupeNewCategories();
      await push();
      await pull();
      db.setKv('first_sync_done', '1');
      state = SyncState.idle;
      lastError = null;
      lastSynced = DateTime.now();
      _failures = 0;
      onChanged();
    } catch (e) {
      state = SyncState.error;
      lastError = e.toString();
      _failures++;
      onChanged();
      final wait = Duration(seconds: (5 * (1 << _failures.clamp(0, 6))));
      Timer(wait, sync);
    }
  }

  Future<void> push() async {
    for (final t in syncTables) {
      final rows = db.dirtyRows(t);
      if (rows.isEmpty) continue;
      final payload = [
        for (final r in rows)
          {
            ...r,
            if (t == 'profiles') ...{'id': uid, 'user_id': uid},
          }..removeWhere((k, _) => immutableTables.contains(t) && k == 'client_updated_at')
      ];
      for (var i = 0; i < payload.length; i += 200) {
        final chunk = payload.sublist(i, (i + 200).clamp(0, payload.length));
        if (immutableTables.contains(t)) {
          // Same id twice = same event: ignored, so retries and double taps never duplicate money.
          await client.from(t).upsert(chunk, onConflict: 'id', ignoreDuplicates: true);
        } else {
          await client.from(t).upsert(chunk, onConflict: 'id');
        }
      }
      db.markClean(t, rows.map((r) => r['id'] as String));
    }
  }

  /// Pulls rows changed since the per-table cursor. Last-writer-wins on client_updated_at for mutable rows.
  Future<int> pull() async {
    var n = 0;
    for (final t in syncTables) {
      final col = t == 'trip_entries' ? 'created_at' : 'updated_at';
      final cursor = db.getKv('cursor:$t') ?? '1970-01-01T00:00:00Z';
      // Overlap by 2 minutes so rows committed late with earlier timestamps are not missed.
      var since = DateTime.parse(cursor).subtract(const Duration(minutes: 2)).toUtc().toIso8601String();
      var maxSeen = cursor;
      while (true) {
        final rows = await client.from(t).select().gte(col, since).order(col).limit(1000);
        for (final r in rows) {
          if (db.mergeRemote(t, r)) n++;
          final v = r[col] as String;
          if (DateTime.parse(v).isAfter(DateTime.parse(maxSeen))) maxSeen = v;
        }
        if (rows.length < 1000 || rows.last[col] == since) break;
        since = rows.last[col] as String; // next page (re-reading equal timestamps is harmless)
      }
      db.setKv('cursor:$t', maxSeen);
    }
    return n;
  }
}
