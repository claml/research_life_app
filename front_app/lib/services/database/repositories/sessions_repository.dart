import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/models/app_models.dart';
import '../app_database.dart';
import '../snapshots/session_snapshot.dart';
import '../snapshots/session_snapshot_migrator.dart';
import '../../storage/local_data_operation_coordinator.dart';

class SessionsRepository {
  SessionsRepository(
    this._database, {
    String createdByAppVersion = SessionSnapshot.defaultCreatedByAppVersion,
    SessionSnapshotMigrator snapshotMigrator = const SessionSnapshotMigrator(),
    LocalDataOperationCoordinator? operationCoordinator,
  }) : _createdByAppVersion = createdByAppVersion,
       _snapshotMigrator = snapshotMigrator,
       _operationCoordinator = operationCoordinator;

  final AppDatabase _database;
  final String _createdByAppVersion;
  final SessionSnapshotMigrator _snapshotMigrator;
  final LocalDataOperationCoordinator? _operationCoordinator;
  final List<SessionSnapshotWarning> _snapshotWarnings = [];

  List<SessionSnapshotWarning> get snapshotWarnings =>
      List.unmodifiable(_snapshotWarnings);

  Future<T> _write<T>(Future<T> Function() operation) {
    final coordinator = _operationCoordinator;
    return coordinator == null
        ? operation()
        : coordinator.runExclusive(operation);
  }

  Future<List<SessionRecord>> loadSessions() async {
    _snapshotWarnings.clear();
    final rows =
        await (_database.select(_database.sessions)..orderBy([
              (session) => OrderingTerm(
                expression: session.confirmedAt,
                mode: OrderingMode.desc,
              ),
            ]))
            .get();

    final sessions = <SessionRecord>[];
    for (final row in rows) {
      final snapshotJson = row.snapshotJson;
      if (snapshotJson == null || snapshotJson.trim().isEmpty) {
        continue;
      }

      try {
        final decoded = jsonDecode(snapshotJson);
        final snapshotJsonMap = _mapSnapshotJson(decoded);
        if (snapshotJsonMap == null) {
          _snapshotWarnings.add(
            SessionSnapshotWarning(
              sessionId: row.id,
              message: 'Session snapshot root is not a JSON object.',
            ),
          );
          continue;
        }

        final migrated = _snapshotMigrator.migrate(
          snapshotJsonMap,
          createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
          createdByAppVersion: _createdByAppVersion,
        );
        _validateSessionPayload(migrated.snapshot.payload);
        sessions.add(_sessionFromJson(migrated.snapshot.payload));
      } on FormatException catch (error) {
        _snapshotWarnings.add(
          SessionSnapshotWarning(
            sessionId: row.id,
            message: 'Session snapshot JSON is malformed.',
            details: error,
          ),
        );
      } on SessionSnapshotMigrationException catch (error) {
        _snapshotWarnings.add(
          SessionSnapshotWarning(
            sessionId: row.id,
            message: 'Session snapshot migration failed.',
            details: error,
          ),
        );
      } on TypeError catch (error) {
        _snapshotWarnings.add(
          SessionSnapshotWarning(
            sessionId: row.id,
            message: 'Session snapshot payload has an incompatible shape.',
            details: error,
          ),
        );
      } on RangeError catch (error) {
        _snapshotWarnings.add(
          SessionSnapshotWarning(
            sessionId: row.id,
            message: 'Session snapshot payload contains an out-of-range value.',
            details: error,
          ),
        );
      }
    }
    return sessions;
  }

  Future<void> saveSession(SessionRecord session) {
    return _write(() => _saveSession(session));
  }

  Future<void> _saveSession(SessionRecord session) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final confirmedAt = _dateTimeToInt(session.confirmedAt);
    await _database.transaction(() async {
      final existingEvents = await (_database.select(
        _database.events,
      )..where((event) => event.sessionId.equals(session.id))).get();
      final existingPeople = await (_database.select(
        _database.persons,
      )..where((person) => person.sessionId.equals(session.id))).get();
      final existingEventIds = existingEvents.map((event) => event.id).toList();
      final existingPersonIds = existingPeople
          .map((person) => person.id)
          .toList();

      if (existingEventIds.isNotEmpty) {
        await (_database.delete(
          _database.eventPersons,
        )..where((link) => link.eventId.isIn(existingEventIds))).go();
      }
      if (existingPersonIds.isNotEmpty) {
        await (_database.delete(
          _database.eventPersons,
        )..where((link) => link.personId.isIn(existingPersonIds))).go();
      }
      await (_database.delete(
        _database.events,
      )..where((event) => event.sessionId.equals(session.id))).go();
      await (_database.delete(
        _database.persons,
      )..where((person) => person.sessionId.equals(session.id))).go();

      await _database
          .into(_database.sessions)
          .insertOnConflictUpdate(
            SessionsCompanion.insert(
              id: session.id,
              title: session.title,
              summary: session.preview.summary,
              confirmedAt: confirmedAt,
              sourceType: session.input.sourceType.name,
              sourcePath: Value(session.input.sourcePath),
              rawText: session.input.rawText,
              snapshotJson: Value(jsonEncode(_sessionSnapshotToJson(session))),
              createdAt: _dateTimeToInt(session.draft.createdAt),
              updatedAt: now,
            ),
          );

      for (var index = 0; index < session.events.length; index++) {
        final event = session.events[index];
        await _database
            .into(_database.events)
            .insert(
              EventsCompanion.insert(
                id: event.id,
                sessionId: Value(session.id),
                title: event.title,
                category: event.category.name,
                type: event.type.name,
                origin: event.origin.name,
                startAt: _dateTimeToInt(event.startAt),
                endAt: Value(_nullableDateTimeToInt(event.endAt)),
                sourceLabel: Value(event.sourceLabel),
                createdAt: confirmedAt,
                updatedAt: now,
              ),
            );
      }

      for (final person in session.people) {
        await _database
            .into(_database.persons)
            .insert(
              PersonsCompanion.insert(
                id: person.id,
                sessionId: Value(session.id),
                name: person.name,
                role: person.role.name,
                aliasesJson: jsonEncode(person.aliases),
                relatedTaskCount: Value(person.relatedTaskCount),
                createdAt: confirmedAt,
                updatedAt: now,
              ),
            );
      }

      final peopleByKnownName = <String, String>{};
      for (final person in session.people) {
        peopleByKnownName[person.name] = person.id;
        for (final alias in person.aliases) {
          peopleByKnownName[alias] = person.id;
        }
      }

      for (final event in session.events) {
        final linkedPersonIds = <String>{};
        for (final personName in event.personNames) {
          final personId = peopleByKnownName[personName];
          if (personId != null) {
            linkedPersonIds.add(personId);
          }
        }

        for (final personId in linkedPersonIds) {
          await _database
              .into(_database.eventPersons)
              .insert(
                EventPersonsCompanion.insert(
                  eventId: event.id,
                  personId: personId,
                ),
              );
        }
      }
    });
  }

  Future<void> deleteSession(String sessionId) {
    return _write(() => _deleteSession(sessionId));
  }

  Future<void> _deleteSession(String sessionId) async {
    await _database.transaction(() async {
      final existingEvents = await (_database.select(
        _database.events,
      )..where((event) => event.sessionId.equals(sessionId))).get();
      final existingPeople = await (_database.select(
        _database.persons,
      )..where((person) => person.sessionId.equals(sessionId))).get();
      final existingEventIds = existingEvents.map((event) => event.id).toList();
      final existingPersonIds = existingPeople
          .map((person) => person.id)
          .toList();

      if (existingEventIds.isNotEmpty) {
        await (_database.delete(
          _database.eventPersons,
        )..where((link) => link.eventId.isIn(existingEventIds))).go();
      }
      if (existingPersonIds.isNotEmpty) {
        await (_database.delete(
          _database.eventPersons,
        )..where((link) => link.personId.isIn(existingPersonIds))).go();
      }
      await (_database.delete(
        _database.events,
      )..where((event) => event.sessionId.equals(sessionId))).go();
      await (_database.delete(
        _database.persons,
      )..where((person) => person.sessionId.equals(sessionId))).go();
      await (_database.delete(
        _database.sessions,
      )..where((session) => session.id.equals(sessionId))).go();
    });
  }

  Map<String, dynamic>? _mapSnapshotJson(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }

  Map<String, dynamic> _sessionSnapshotToJson(SessionRecord session) {
    return SessionSnapshot.v1(
      payload: _sessionToJson(session),
      createdByAppVersion: _createdByAppVersion,
    ).toJson();
  }

  /// 生成用于云端同步的会话快照 JSON（供 Outbox 推送）。
  Future<String> snapshotJsonFor(SessionRecord session) async {
    return jsonEncode(_sessionSnapshotToJson(session));
  }

  /// 从云端拉取的快照 JSON 恢复并保存会话（幂等覆盖）。
  Future<void> saveSessionFromSnapshotJson(String snapshotJson) {
    return _write(() => _saveSessionFromSnapshotJson(snapshotJson));
  }

  Future<void> _saveSessionFromSnapshotJson(String snapshotJson) async {
    final session = await _sessionFromSnapshotJson(snapshotJson);
    if (session == null) {
      return;
    }
    await saveSession(session);
  }

  /// 解析快照 JSON 为 SessionRecord（与 loadSessions 同一套迁移/校验）。
  Future<SessionRecord?> _sessionFromSnapshotJson(String snapshotJson) async {
    try {
      final decoded = jsonDecode(snapshotJson);
      final snapshotJsonMap = _mapSnapshotJson(decoded);
      if (snapshotJsonMap == null) {
        return null;
      }
      final migrated = _snapshotMigrator.migrate(
        snapshotJsonMap,
        createdAt: DateTime.now(),
        createdByAppVersion: _createdByAppVersion,
      );
      _validateSessionPayload(migrated.snapshot.payload);
      return _sessionFromJson(migrated.snapshot.payload);
    } catch (_) {
      return null;
    }
  }

  void _validateSessionPayload(Map<String, dynamic> payload) {
    const requiredKeys = <String>[
      'id',
      'title',
      'input',
      'draft',
      'events',
      'people',
      'confirmedAt',
    ];

    for (final key in requiredKeys) {
      if (!payload.containsKey(key)) {
        throw SessionSnapshotMigrationException(
          'Session snapshot payload is missing required field "$key".',
        );
      }
    }
  }

  Map<String, dynamic> _sessionToJson(SessionRecord session) {
    return {
      'id': session.id,
      'title': session.title,
      'input': _analysisInputToJson(session.input),
      'draft': _analysisDraftToJson(session.draft),
      'events': session.events.map(_eventItemToJson).toList(),
      'people': session.people.map(_personProfileToJson).toList(),
      'confirmedAt': _dateTimeToInt(session.confirmedAt),
    };
  }

  SessionRecord _sessionFromJson(Map<String, dynamic> json) {
    final draft = _analysisDraftFromJson(_mapValue(json['draft']));
    final events = _listValue(json['events']).map(_eventItemFromJson).toList();
    final people = _listValue(
      json['people'],
    ).map(_personProfileFromJson).toList();
    final preview = _buildPreviewFromDraft(draft);
    return SessionRecord(
      id: _stringValue(json['id']),
      title: _stringValue(json['title']),
      input: _analysisInputFromJson(_mapValue(json['input'])),
      draft: draft,
      preview: preview,
      events: events,
      people: people,
      confirmedAt: _dateTimeValue(json['confirmedAt']),
    );
  }

  Map<String, dynamic> _analysisInputToJson(AnalysisInput input) {
    return {
      'rawText': input.rawText,
      'sourceType': input.sourceType.name,
      'sourcePath': input.sourcePath,
    };
  }

  AnalysisInput _analysisInputFromJson(Map<String, dynamic> json) {
    return AnalysisInput(
      rawText: _stringValue(json['rawText']),
      sourceType: _enumValue(
        AnalysisSourceType.values,
        json['sourceType'],
        AnalysisSourceType.text,
      ),
      sourcePath: _nullableStringValue(json['sourcePath']),
    );
  }

  Map<String, dynamic> _analysisDraftToJson(AnalysisDraft draft) {
    return {
      'id': draft.id,
      'tasks': draft.tasks.map(_taskDraftToJson).toList(),
      'persons': draft.persons.map(_personDraftToJson).toList(),
      'summary': draft.summary,
      'warnings': draft.warnings,
      'clarifications': nullSafeList(
        draft.clarifications,
      ).map(_clarificationToJson).toList(),
      'createdAt': _dateTimeToInt(draft.createdAt),
    };
  }

  AnalysisDraft _analysisDraftFromJson(Map<String, dynamic> json) {
    return AnalysisDraft(
      id: _stringValue(json['id']),
      tasks: _listValue(json['tasks']).map(_taskDraftFromJson).toList(),
      persons: _listValue(json['persons']).map(_personDraftFromJson).toList(),
      summary: _stringValue(json['summary']),
      warnings: _stringListValue(json['warnings']),
      clarifications: _clarificationsFromJson(json['clarifications']),
      createdAt: _dateTimeValue(json['createdAt']),
    );
  }

  Map<String, dynamic> _clarificationToJson(ClarificationItem item) {
    return {
      'type': item.type.wireValue,
      'personIndex': item.personIndex,
      'question': item.question,
      'context': item.context,
      'options': item.options,
      'historyMatch': item.historyMatch,
    };
  }

  List<ClarificationItem> _clarificationsFromJson(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final rawItem in raw)
        if (rawItem is Map<String, dynamic>)
          ClarificationItem(
            type: _clarificationTypeValue(rawItem['type']),
            personIndex: rawItem['personIndex'] is int
                ? rawItem['personIndex'] as int
                : null,
            question: _stringValue(rawItem['question']),
            context: _nullableStringValue(rawItem['context']),
            options: _stringListValue(rawItem['options']),
            historyMatch: _nullableStringValue(rawItem['historyMatch']),
          ),
    ];
  }

  ClarificationType _clarificationTypeValue(Object? value) {
    final text = value is String ? value : '';
    for (final type in ClarificationType.values) {
      if (type.wireValue == text) {
        return type;
      }
    }
    return ClarificationType.other;
  }

  Map<String, dynamic> _taskDraftToJson(ExtractedTaskDraft task) {
    return {
      'id': task.id,
      'content': task.content,
      'category': task.category.name,
      'type': task.type.name,
      'confidence': task.confidence,
      'relatedPersonNames': task.relatedPersonNames,
      'timeHint': task.timeHint,
    };
  }

  ExtractedTaskDraft _taskDraftFromJson(Map<String, dynamic> json) {
    return ExtractedTaskDraft(
      id: _stringValue(json['id']),
      content: _stringValue(json['content']),
      category: _enumValue(
        ItemCategory.values,
        json['category'],
        ItemCategory.other,
      ),
      type: _enumValue(EventType.values, json['type'], EventType.record),
      confidence: _doubleValue(json['confidence'], fallback: 0.0),
      relatedPersonNames: _stringListValue(json['relatedPersonNames']),
      timeHint: _nullableStringValue(json['timeHint']),
    );
  }

  Map<String, dynamic> _personDraftToJson(ExtractedPersonDraft person) {
    return {
      'id': person.id,
      'name': person.name,
      'role': person.role.name,
      'aliases': person.aliases,
      'relatedTaskIndexes': person.relatedTaskIndexes,
    };
  }

  ExtractedPersonDraft _personDraftFromJson(Map<String, dynamic> json) {
    return ExtractedPersonDraft(
      id: _stringValue(json['id']),
      name: _stringValue(json['name']),
      role: _enumValue(PersonRole.values, json['role'], PersonRole.other),
      aliases: _stringListValue(json['aliases']),
      relatedTaskIndexes: _intListValue(json['relatedTaskIndexes']),
    );
  }

  Map<String, dynamic> _eventItemToJson(EventItem event) {
    return {
      'id': event.id,
      'title': event.title,
      'category': event.category.name,
      'type': event.type.name,
      'startAt': _dateTimeToInt(event.startAt),
      'endAt': _nullableDateTimeToInt(event.endAt),
      'origin': event.origin.name,
      'personNames': event.personNames,
      'sourceLabel': event.sourceLabel,
    };
  }

  EventItem _eventItemFromJson(Map<String, dynamic> json) {
    return EventItem(
      id: _stringValue(json['id']),
      title: _stringValue(json['title']),
      category: _enumValue(
        ItemCategory.values,
        json['category'],
        ItemCategory.other,
      ),
      type: _enumValue(EventType.values, json['type'], EventType.record),
      startAt: _dateTimeValue(json['startAt']),
      endAt: _nullableDateTimeValue(json['endAt']),
      origin: _enumValue(
        EventOrigin.values,
        json['origin'],
        EventOrigin.analysis,
      ),
      personNames: _stringListValue(json['personNames']),
      sourceLabel: _nullableStringValue(json['sourceLabel']),
    );
  }

  Map<String, dynamic> _personProfileToJson(PersonProfile person) {
    return {
      'id': person.id,
      'name': person.name,
      'role': person.role.name,
      'aliases': person.aliases,
      'relatedTaskCount': person.relatedTaskCount,
      'relatedPlanTitles': person.relatedPlanTitles,
    };
  }

  PersonProfile _personProfileFromJson(Map<String, dynamic> json) {
    return PersonProfile(
      id: _stringValue(json['id']),
      name: _stringValue(json['name']),
      role: _enumValue(PersonRole.values, json['role'], PersonRole.other),
      aliases: _stringListValue(json['aliases']),
      relatedTaskCount: _intValue(json['relatedTaskCount']),
      relatedPlanTitles: _stringListValue(json['relatedPlanTitles']),
    );
  }

  ReviewPreview _buildPreviewFromDraft(AnalysisDraft draft) {
    final completedTasks = draft.tasks
        .where((task) => task.type == EventType.record)
        .toList();
    final plannedTasks = draft.tasks
        .where((task) => task.type == EventType.plan)
        .toList();
    final relationLabels = draft.persons
        .map((person) => person.role.label)
        .toSet()
        .toList();

    return ReviewPreview(
      id: 'preview_${draft.id}',
      completedTasks: completedTasks,
      plannedTasks: plannedTasks,
      persons: draft.persons,
      summary: draft.summary,
      warnings: draft.warnings,
      relationLabels: relationLabels,
    );
  }

  Map<String, dynamic> _mapValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', value));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _listValue(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.map(_mapValue).toList();
  }

  List<String> _stringListValue(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => '$item')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<int> _intListValue(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.map(_intValue).toList();
  }

  T _enumValue<T extends Enum>(List<T> values, Object? value, T fallback) {
    final name = '$value';
    for (final enumValue in values) {
      if (enumValue.name == name) {
        return enumValue;
      }
    }
    return fallback;
  }

  String _stringValue(Object? value) {
    return value == null ? '' : '$value';
  }

  String? _nullableStringValue(Object? value) {
    if (value == null) {
      return null;
    }
    final text = '$value';
    return text.isEmpty ? null : text;
  }

  int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value') ?? 0;
  }

  double _doubleValue(Object? value, {required double fallback}) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? fallback;
  }

  int _dateTimeToInt(DateTime value) {
    return value.millisecondsSinceEpoch;
  }

  int? _nullableDateTimeToInt(DateTime? value) {
    return value?.millisecondsSinceEpoch;
  }

  DateTime _dateTimeValue(Object? value) {
    return DateTime.fromMillisecondsSinceEpoch(_intValue(value));
  }

  DateTime? _nullableDateTimeValue(Object? value) {
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(_intValue(value));
  }
}
