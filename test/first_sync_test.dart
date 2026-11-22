import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/data/defaults.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';

import 'helpers.dart';

void main() {
  test('a new device drops its never-synced default categories that duplicate synced ones', () {
    final db = LocalDb.memory();
    for (final c in defaultCategories()) {
      db.put(c); // created on the new device, never uploaded
    }
    // the same names arrive from the other device
    for (final c in defaultCategories().take(5)) {
      db.mergeRemote('categories', {...c.toRow(), 'updated_at': '2026-11-22T10:00:00Z', 'client_updated_at': '2026-11-22T10:00:00Z'});
    }
    final removed = db.dedupeNewCategories();
    expect(removed, 5);
    final names = db.all('categories').map((r) => r['name']).toList();
    expect(names.toSet().length, names.length); // no duplicate names left
    expect(names.length, 14);
  });

  test('a local category already used by a transaction is never dropped', () {
    final db = LocalDb.memory();
    final mine = Category(id: 'mine', name: 'Groceries', color: 1);
    db.put(mine);
    db.put(ev('expense', 500, acct: 'a', cat: 'mine'));
    db.mergeRemote('categories', {...Category(id: 'theirs', name: 'Groceries', color: 1).toRow(), 'updated_at': '2026-11-22T10:00:00Z'});
    expect(db.dedupeNewCategories(), 0);
  });

  test('a device with no synced data keeps all its own categories', () {
    final db = LocalDb.memory();
    for (final c in defaultCategories()) {
      db.put(c);
    }
    expect(db.dedupeNewCategories(), 0);
  });
}
