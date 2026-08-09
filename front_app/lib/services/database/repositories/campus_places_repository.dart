import 'package:drift/drift.dart';

import '../../../core/models/app_models.dart';
import '../app_database.dart' as db;

class CampusPlacesRepository {
  const CampusPlacesRepository(this._database);

  static const _seededDefaultsKey = 'campusPlacesSeeded';

  final db.AppDatabase _database;

  Future<bool> hasSeededDefaults() async {
    final row =
        await (_database.select(
              _database.preferences,
            )..where((preference) => preference.key.equals(_seededDefaultsKey)))
            .getSingleOrNull();
    return row?.value == 'true';
  }

  Future<void> markSeededDefaults() async {
    await _database
        .into(_database.preferences)
        .insertOnConflictUpdate(
          db.PreferencesCompanion.insert(
            key: _seededDefaultsKey,
            value: 'true',
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<List<CampusPlace>> loadCampusPlaces() async {
    final rows =
        await (_database.select(_database.campusPlaces)..orderBy([
              (place) => OrderingTerm(
                expression: place.updatedAt,
                mode: OrderingMode.desc,
              ),
            ]))
            .get();
    return rows.map(_placeFromRow).toList();
  }

  Future<void> saveCampusPlace(CampusPlace place) async {
    await _database
        .into(_database.campusPlaces)
        .insertOnConflictUpdate(
          db.CampusPlacesCompanion.insert(
            id: place.id,
            name: place.name,
            category: place.category.name,
            note: place.note,
            normalizedDx: place.normalizedDx,
            normalizedDy: place.normalizedDy,
            iconKey: place.iconKey,
            colorKey: place.colorKey,
            zoneId: Value(place.zoneId),
            isFavorite: Value(place.isFavorite),
            isMine: Value(place.isMine),
            lastVisitedAt: Value(_nullableDateTimeToInt(place.lastVisitedAt)),
            logCount: Value(place.logCount),
            heatScore: Value(place.heatScore),
            createdAt: _dateTimeToInt(place.createdAt),
            updatedAt: _dateTimeToInt(place.updatedAt),
          ),
        );
  }

  Future<void> saveCampusPlaces(Iterable<CampusPlace> places) async {
    await _database.transaction(() async {
      for (final place in places) {
        await saveCampusPlace(place);
      }
    });
  }

  Future<void> deleteCampusPlace(String id) async {
    await (_database.delete(
      _database.campusPlaces,
    )..where((place) => place.id.equals(id))).go();
  }

  CampusPlace _placeFromRow(db.CampusPlace row) {
    return CampusPlace(
      id: row.id,
      name: row.name,
      category: _enumValue(
        PlaceCategory.values,
        row.category,
        PlaceCategory.other,
      ),
      note: row.note,
      normalizedDx: row.normalizedDx,
      normalizedDy: row.normalizedDy,
      iconKey: row.iconKey,
      colorKey: row.colorKey,
      zoneId: row.zoneId,
      isFavorite: row.isFavorite,
      isMine: row.isMine,
      createdAt: _dateTimeValue(row.createdAt),
      updatedAt: _dateTimeValue(row.updatedAt),
      lastVisitedAt: _nullableDateTimeValue(row.lastVisitedAt),
      logCount: row.logCount,
      heatScore: row.heatScore,
    );
  }

  T _enumValue<T extends Enum>(List<T> values, String value, T fallback) {
    for (final enumValue in values) {
      if (enumValue.name == value) {
        return enumValue;
      }
    }
    return fallback;
  }

  int _dateTimeToInt(DateTime value) {
    return value.millisecondsSinceEpoch;
  }

  int? _nullableDateTimeToInt(DateTime? value) {
    return value?.millisecondsSinceEpoch;
  }

  DateTime _dateTimeValue(int value) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  DateTime? _nullableDateTimeValue(int? value) {
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}
