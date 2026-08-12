import 'package:drift/drift.dart';

import '../../../core/models/app_models.dart';
import '../app_database.dart';
import '../../storage/local_data_operation_coordinator.dart';

/// 独立 Markdown 笔记的数据访问（本地优先，同步由 Outbox/引擎负责）。
class NotesRepository {
  const NotesRepository(
    this._database, {
    LocalDataOperationCoordinator? operationCoordinator,
  }) : _operationCoordinator = operationCoordinator;

  final AppDatabase _database;
  final LocalDataOperationCoordinator? _operationCoordinator;

  Future<T> _write<T>(Future<T> Function() operation) {
    final coordinator = _operationCoordinator;
    return coordinator == null
        ? operation()
        : coordinator.runExclusive(operation);
  }

  Future<List<UserNote>> loadNotes() async {
    final rows =
        await (_database.select(_database.notes)..orderBy([
              (note) => OrderingTerm(
                expression: note.updatedAt,
                mode: OrderingMode.desc,
              ),
            ]))
            .get();
    return rows
        .where((row) => row.isDeleted == false)
        .map(_noteFromRow)
        .toList();
  }

  Future<UserNote?> findById(String id) async {
    final row = await (_database.select(
      _database.notes,
    )..where((note) => note.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _noteFromRow(row);
  }

  Future<void> saveNote(UserNote note) async {
    await _write(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _database
          .into(_database.notes)
          .insertOnConflictUpdate(
            NotesCompanion.insert(
              id: note.id,
              title: note.title,
              contentMarkdown: Value(note.contentMarkdown),
              createdAt: now,
              updatedAt: now,
              syncVersion: const Value(1),
              syncState: const Value('local'),
              deviceId: const Value(null),
              isDeleted: const Value(false),
            ),
          );
    });
  }

  Future<void> deleteById(String id) async {
    await _write(() async {
      await (_database.delete(
        _database.notes,
      )..where((note) => note.id.equals(id))).go();
    });
  }

  UserNote _noteFromRow(Note row) {
    return UserNote(
      id: row.id,
      title: row.title,
      contentMarkdown: row.contentMarkdown ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
    );
  }
}
