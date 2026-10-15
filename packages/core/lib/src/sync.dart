import 'db.dart';
import 'store.dart';

/// The server side of sync. Rows are plain column maps; the remote adds a
/// `server_at` stamp that only ever increases and serves as the pull cursor.
abstract interface class Remote {
  /// Upserts [rows]. The remote must ignore a row older than what it holds.
  Future<void> push(String table, List<Map<String, Object?>> rows);

  /// Rows with `server_at` after [since] (all rows if null), oldest first.
  Future<List<Map<String, Object?>>> pull(String table, String? since);
}

/// Thrown by a [Remote] whose server has no such table yet, which happens
/// when the app is newer than the schema installed on the server.
class MissingTable implements Exception {
  MissingTable(this.table);
  final String table;
  @override
  String toString() => 'The sync server has no "$table" table; run the latest supabase/schema.sql';
}

/// A [Remote] that can tell which columns its server lacks, having left them
/// out of what it pushed.
abstract interface class ReportsMissingColumns {
  /// Column names by table.
  Map<String, Set<String>> get missingColumns;
}

class SyncResult {
  SyncResult(this.pulled, this.pushed, [this.missing = const [], this.missingColumns = const {}]);
  final int pulled;
  final int pushed;

  /// Tables the server does not have yet; their rows wait locally.
  final List<String> missing;

  /// Columns the server does not have yet, by table. Those rows stay marked
  /// for pushing, so the values arrive once the server is updated.
  final Map<String, List<String>> missingColumns;

  Map<String, Object?> toJson() => {
        'pulled': pulled,
        'pushed': pushed,
        if (missing.isNotEmpty) 'missing_tables': missing,
        if (missingColumns.isNotEmpty) 'missing_columns': missingColumns,
      };
}

/// Pull then push. Conflicts resolve per row by the newer `updated_at`.
class SyncEngine {
  SyncEngine(this.store, this.remote);

  final Store store;
  final Remote remote;

  Future<SyncResult> sync() async {
    final db = store.db;
    var pulled = 0, pushed = 0;
    // An older server must not stop the tables it does have from syncing.
    final missing = <String>[];

    for (final table in syncedTables) {
      final List<Map<String, Object?>> rows;
      try {
        rows = await remote.pull(table, store.getMeta('pulled:$table'));
      } on MissingTable {
        missing.add(table);
        continue;
      }
      if (rows.isEmpty) continue;
      db.execute('BEGIN');
      try {
        for (final row in rows) {
          if (_apply(table, row)) pulled++;
        }
        store.setMeta('pulled:$table', rows.last['server_at'] as String);
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }

    for (final table in syncedTables) {
      if (missing.contains(table)) continue;
      final rows = [
        for (final r in db.select('SELECT * FROM $table WHERE dirty = 1')) {...r}..remove('dirty'),
      ];
      if (rows.isEmpty) continue;
      await remote.push(table, rows);
      // Left dirty while the server lacks columns, so nothing is lost.
      if (_lacks(table).isNotEmpty) {
        pushed += rows.length;
        continue;
      }
      for (final r in rows) {
        // A row edited again while the push was in flight stays dirty.
        db.execute(
          'UPDATE $table SET dirty = 0 WHERE id = ? AND updated_at = ?',
          [r['id'], r['updated_at']],
        );
      }
      pushed += rows.length;
    }
    return SyncResult(pulled, pushed, missing, {
      for (final t in syncedTables)
        if (_lacks(t).isNotEmpty) t: _lacks(t).toList()..sort(),
    });
  }

  Set<String> _lacks(String table) => switch (remote) {
        final ReportsMissingColumns r => r.missingColumns[table] ?? const {},
        _ => const {},
      };

  bool _apply(String table, Map<String, Object?> remoteRow) {
    final db = store.db;
    final local = db.select('SELECT updated_at FROM $table WHERE id = ?', [remoteRow['id']]);
    if (local.isNotEmpty &&
        (local.first['updated_at'] as String).compareTo(remoteRow['updated_at'] as String) >= 0) {
      return false;
    }
    final columns = [
      for (final c in db.select('PRAGMA table_info($table)'))
        if (c['name'] != 'dirty') c['name'] as String,
    ];
    // A server older than this app lacks some columns. Keep what this device
    // has for those instead of blanking them.
    final mine = local.isEmpty ? const <String, Object?>{} : db.select('SELECT * FROM $table WHERE id = ?', [remoteRow['id']]).first;
    db.execute(
      'INSERT OR REPLACE INTO $table (${columns.join(', ')}, dirty) '
      'VALUES (${List.filled(columns.length, '?').join(', ')}, 0)',
      [for (final c in columns) remoteRow.containsKey(c) ? remoteRow[c] : mine[c]],
    );
    return true;
  }

  /// Forget pull cursors and mark everything for pushing; used after signing
  /// in, since the server may be a different or empty project.
  static void reset(Store store) {
    for (final table in syncedTables) {
      store.setMeta('pulled:$table', null);
      store.db.execute('UPDATE $table SET dirty = 1');
    }
  }
}
