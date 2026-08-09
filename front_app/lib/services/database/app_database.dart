import 'package:drift/drift.dart';

part 'app_database.g.dart';

class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get summary => text()();
  IntColumn get confirmedAt => integer()();
  TextColumn get sourceType => text()();
  TextColumn get sourcePath => text().nullable()();
  TextColumn get rawText => text()();
  TextColumn get snapshotJson => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Events extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
  TextColumn get title => text()();
  TextColumn get category => text()();
  TextColumn get type => text()();
  TextColumn get origin => text()();
  IntColumn get startAt => integer()();
  IntColumn get endAt => integer().nullable()();
  TextColumn get sourceLabel => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get syncVersion => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  TextColumn get deviceId => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Persons extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
  TextColumn get name => text()();
  TextColumn get role => text()();
  TextColumn get aliasesJson => text()();
  IntColumn get relatedTaskCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class EventPersons extends Table {
  TextColumn get eventId => text().references(Events, #id)();
  TextColumn get personId => text().references(Persons, #id)();

  @override
  Set<Column<Object>> get primaryKey => {eventId, personId};
}

/// 独立 Markdown 笔记（与 PDF 批注 note 分离存储）。
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get contentMarkdown => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get syncVersion => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  TextColumn get deviceId => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 待办状态：与事件分离存储，事件可来自周分析会话或手动创建，
/// 完成态 / 优先级按 eventId 独立记录，避免改动会话快照结构。
class TodoStatus extends Table {
  TextColumn get eventId => text()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  TextColumn get priority => text().withDefault(const Constant('none'))();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {eventId};
}

class CampusPlaces extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  TextColumn get note => text()();
  RealColumn get normalizedDx => real()();
  RealColumn get normalizedDy => real()();
  TextColumn get iconKey => text()();
  TextColumn get colorKey => text()();
  IntColumn get zoneId => integer().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isMine => boolean().withDefault(const Constant(true))();
  IntColumn get lastVisitedAt => integer().nullable()();
  IntColumn get logCount => integer().withDefault(const Constant(0))();
  IntColumn get heatScore => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PdfLibraryDocuments extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get path => text()();
  TextColumn get category => text().withDefault(const Constant('未分类'))();
  IntColumn get lastPage => integer().withDefault(const Constant(1))();
  IntColumn get pageCount => integer().nullable()();
  IntColumn get lastOpenedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get serverId => integer().nullable()();
  IntColumn get syncVersion => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  TextColumn get deviceId => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get storageKey => text().nullable()();
  TextColumn get contentHash => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PdfLibraryAnnotations extends Table {
  TextColumn get id => text()();
  TextColumn get documentId => text().references(PdfLibraryDocuments, #id)();
  IntColumn get pageNumber => integer()();
  TextColumn get type => text()();
  IntColumn get colorValue => integer()();
  RealColumn get opacity => real()();
  TextColumn get selectedText => text()();
  TextColumn get note => text().nullable()();
  TextColumn get rectsJson => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get serverId => integer().nullable()();
  IntColumn get syncVersion => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  TextColumn get deviceId => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  IntColumn get syncVersion => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  IntColumn get createdAt => integer()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
}

class SyncCursors extends Table {
  TextColumn get scope => text()();
  IntColumn get cursorValue => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {scope};
}

@DriftDatabase(
  tables: [
    Preferences,
    Sessions,
    Events,
    Persons,
    EventPersons,
    TodoStatus,
    Notes,
    CampusPlaces,
    PdfLibraryDocuments,
    PdfLibraryAnnotations,
    SyncOutbox,
    SyncCursors,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static const currentSchemaVersion = 8;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.addColumn(sessions, sessions.snapshotJson);
        }
        if (from < 3) {
          await migrator.createTable(pdfLibraryDocuments);
          await migrator.createTable(pdfLibraryAnnotations);
        }
        if (from >= 3 && from < 4) {
          await migrator.addColumn(
            pdfLibraryDocuments,
            pdfLibraryDocuments.category,
          );
          await migrator.addColumn(
            pdfLibraryAnnotations,
            pdfLibraryAnnotations.note,
          );
        }
        if (from < 5) {
          await migrator.addColumn(
            pdfLibraryDocuments,
            pdfLibraryDocuments.serverId,
          );
          await migrator.addColumn(
            pdfLibraryDocuments,
            pdfLibraryDocuments.syncVersion,
          );
          await migrator.addColumn(
            pdfLibraryDocuments,
            pdfLibraryDocuments.syncState,
          );
          await migrator.addColumn(
            pdfLibraryDocuments,
            pdfLibraryDocuments.deviceId,
          );
          await migrator.addColumn(
            pdfLibraryDocuments,
            pdfLibraryDocuments.isDeleted,
          );
          await migrator.addColumn(
            pdfLibraryDocuments,
            pdfLibraryDocuments.storageKey,
          );
          await migrator.addColumn(
            pdfLibraryDocuments,
            pdfLibraryDocuments.contentHash,
          );
          await migrator.addColumn(
            pdfLibraryAnnotations,
            pdfLibraryAnnotations.serverId,
          );
          await migrator.addColumn(
            pdfLibraryAnnotations,
            pdfLibraryAnnotations.syncVersion,
          );
          await migrator.addColumn(
            pdfLibraryAnnotations,
            pdfLibraryAnnotations.syncState,
          );
          await migrator.addColumn(
            pdfLibraryAnnotations,
            pdfLibraryAnnotations.deviceId,
          );
          await migrator.addColumn(
            pdfLibraryAnnotations,
            pdfLibraryAnnotations.isDeleted,
          );
          await migrator.createTable(syncOutbox);
          await migrator.createTable(syncCursors);
        }
        if (from < 6) {
          await migrator.createTable(todoStatus);
        }
        if (from < 7) {
          await migrator.addColumn(events, events.syncVersion);
          await migrator.addColumn(events, events.syncState);
          await migrator.addColumn(events, events.deviceId);
          await migrator.addColumn(events, events.isDeleted);
        }
        if (from < 8) {
          await migrator.createTable(notes);
        }
      },
    );
  }
}
