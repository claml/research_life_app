import 'package:drift/drift.dart';

import '../../../core/models/app_models.dart';
import '../app_database.dart';

class ManualEventsRepository {
  const ManualEventsRepository(this._database);

  final AppDatabase _database;

  Future<List<EventItem>> loadManualEvents() async {
    final rows =
        await (_database.select(_database.events)
              ..where(
                (event) =>
                    event.origin.equals(EventOrigin.manual.name) &
                    event.sessionId.isNull(),
              )
              ..orderBy([
                (event) => OrderingTerm(
                  expression: event.startAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();

    return rows.map(_eventFromRow).toList();
  }

  Future<void> saveManualEvent(EventItem event) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database
        .into(_database.events)
        .insertOnConflictUpdate(
          EventsCompanion.insert(
            id: event.id,
            sessionId: const Value(null),
            title: event.title,
            category: event.category.name,
            type: event.type.name,
            origin: EventOrigin.manual.name,
            startAt: _dateTimeToInt(event.startAt),
            endAt: Value(_nullableDateTimeToInt(event.endAt)),
            sourceLabel: Value(event.sourceLabel),
            createdAt: now,
            updatedAt: now,
            syncVersion: const Value(1),
            syncState: const Value('local'),
            deviceId: const Value(null),
            isDeleted: const Value(false),
          ),
        );
  }

  Future<void> deleteById(String id) async {
    await (_database.delete(
      _database.events,
    )..where((event) => event.id.equals(id))).go();
  }

  EventItem _eventFromRow(Event row) {
    return EventItem(
      id: row.id,
      title: row.title,
      category: _enumValue(
        ItemCategory.values,
        row.category,
        ItemCategory.other,
      ),
      type: _enumValue(EventType.values, row.type, EventType.record),
      startAt: _dateTimeValue(row.startAt),
      endAt: _nullableDateTimeValue(row.endAt),
      origin: EventOrigin.manual,
      sourceLabel: row.sourceLabel,
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
