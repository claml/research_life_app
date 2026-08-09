import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart' as db;

class SyncOutboxStats {
  const SyncOutboxStats({
    required this.pendingCount,
    required this.retryingCount,
    required this.cursorValue,
    this.cursorUpdatedAt,
  });

  final int pendingCount;
  final int retryingCount;
  final int cursorValue;
  final DateTime? cursorUpdatedAt;
}

class SyncOutboxRepository {
  const SyncOutboxRepository(this._database);

  final db.AppDatabase _database;

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
    required int syncVersion,
    required String deviceId,
  }) async {
    await _database
        .into(_database.syncOutbox)
        .insert(
          db.SyncOutboxCompanion.insert(
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payloadJson: jsonEncode(payload),
            syncVersion: Value(syncVersion),
            deviceId: deviceId,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<List<db.SyncOutboxData>> pending({int limit = 100}) {
    return (_database.select(_database.syncOutbox)
          ..orderBy([(row) => OrderingTerm(expression: row.id)])
          ..limit(limit))
        .get();
  }

  Future<SyncOutboxStats> loadStats({required String cursorScope}) async {
    final pendingCountExp = _database.syncOutbox.id.count();
    final pendingRow = await (_database.selectOnly(
      _database.syncOutbox,
    )..addColumns([pendingCountExp])).getSingle();
    final retryingCountExp = _database.syncOutbox.id.count();
    final retryingRow =
        await (_database.selectOnly(_database.syncOutbox)
              ..addColumns([retryingCountExp])
              ..where(_database.syncOutbox.retryCount.isBiggerThanValue(0)))
            .getSingle();
    final cursorRow = await (_database.select(
      _database.syncCursors,
    )..where((item) => item.scope.equals(cursorScope))).getSingleOrNull();

    return SyncOutboxStats(
      pendingCount: pendingRow.read(pendingCountExp) ?? 0,
      retryingCount: retryingRow.read(retryingCountExp) ?? 0,
      cursorValue: cursorRow?.cursorValue ?? 0,
      cursorUpdatedAt: cursorRow == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(cursorRow.updatedAt),
    );
  }

  Future<void> remove(int id) async {
    await (_database.delete(
      _database.syncOutbox,
    )..where((row) => row.id.equals(id))).go();
  }

  Future<void> incrementRetry(int id) async {
    final row = await (_database.select(
      _database.syncOutbox,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return;
    }
    await (_database.update(_database.syncOutbox)
          ..where((item) => item.id.equals(id)))
        .write(db.SyncOutboxCompanion(retryCount: Value(row.retryCount + 1)));
  }

  Future<int> readCursor(String scope) async {
    final row = await (_database.select(
      _database.syncCursors,
    )..where((item) => item.scope.equals(scope))).getSingleOrNull();
    return row?.cursorValue ?? 0;
  }

  Future<void> writeCursor(String scope, int cursorValue) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database
        .into(_database.syncCursors)
        .insertOnConflictUpdate(
          db.SyncCursorsCompanion.insert(
            scope: scope,
            cursorValue: Value(cursorValue),
            updatedAt: now,
          ),
        );
  }
}
