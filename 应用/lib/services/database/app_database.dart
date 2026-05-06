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

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Preferences,
    Sessions,
    Events,
    Persons,
    EventPersons,
    CampusPlaces,
    PdfLibraryDocuments,
    PdfLibraryAnnotations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 4;

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
      },
    );
  }
}
