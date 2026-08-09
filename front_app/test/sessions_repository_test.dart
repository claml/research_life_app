import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/sessions_repository.dart';

void main() {
  late AppDatabase database;
  late SessionsRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = SessionsRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('saves and loads a confirmed session snapshot', () async {
    final session = _buildSessionRecord();

    await repository.saveSession(session);
    final loaded = await repository.loadSessions();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, session.id);
    expect(loaded.single.title, session.title);
    expect(loaded.single.input.rawText, session.input.rawText);
    expect(loaded.single.events.single.title, session.events.single.title);
    expect(loaded.single.people.single.name, session.people.single.name);
    expect(loaded.single.draft.tasks.single.relatedPersonNames, ['Alice']);
  });

  test('loads legacy snapshot without snapshotVersion', () async {
    final session = _buildSessionRecord();
    await _insertSnapshotRow(
      database,
      session: session,
      snapshotJson: jsonEncode(_legacySessionJson(session)),
    );

    final loaded = await repository.loadSessions();

    expect(repository.snapshotWarnings, isEmpty);
    expect(loaded, hasLength(1));
    expect(loaded.single.id, session.id);
    expect(loaded.single.events.single.title, session.events.single.title);
    expect(loaded.single.people.single.name, session.people.single.name);
  });

  test('writes new snapshots with v1 envelope', () async {
    final session = _buildSessionRecord();

    await repository.saveSession(session);

    final rows = await database.select(database.sessions).get();
    final snapshot = jsonDecode(rows.single.snapshotJson!);

    expect(snapshot, isA<Map<String, dynamic>>());
    expect(snapshot['snapshotVersion'], 1);
    expect(snapshot['createdByAppVersion'], isNotEmpty);
    expect(DateTime.tryParse('${snapshot['createdAt']}'), isNotNull);
    expect(snapshot['payload'], isA<Map<String, dynamic>>());
    expect(snapshot['payload']['id'], session.id);
  });

  test('records warnings for damaged snapshots without failing load', () async {
    final validSession = _buildSessionRecord();
    final damagedSession = validSession.copyWith(id: 'session_damaged');
    final invalidPayloadSession = validSession.copyWith(
      id: 'session_invalid_payload',
    );
    await repository.saveSession(validSession);
    await _insertSnapshotRow(
      database,
      session: damagedSession,
      snapshotJson: '{not valid json',
    );
    await _insertSnapshotRow(
      database,
      session: invalidPayloadSession,
      snapshotJson: jsonEncode({
        'snapshotVersion': 1,
        'createdByAppVersion': 'test',
        'createdAt': DateTime.now().toIso8601String(),
        'payload': {'id': invalidPayloadSession.id},
      }),
    );

    final loaded = await repository.loadSessions();

    expect(loaded.map((session) => session.id), contains(validSession.id));
    expect(
      loaded.map((session) => session.id),
      isNot(contains(damagedSession.id)),
    );
    expect(
      loaded.map((session) => session.id),
      isNot(contains(invalidPayloadSession.id)),
    );
    expect(repository.snapshotWarnings, hasLength(2));
    expect(
      repository.snapshotWarnings.map((warning) => warning.sessionId),
      containsAll([damagedSession.id, invalidPayloadSession.id]),
    );
    expect(
      repository.snapshotWarnings.map((warning) => warning.message),
      contains('Session snapshot JSON is malformed.'),
    );
  });

  test('deletes a session with related rows', () async {
    final session = _buildSessionRecord();
    await repository.saveSession(session);

    await repository.deleteSession(session.id);

    final sessionRows = await database.select(database.sessions).get();
    final eventRows = await database.select(database.events).get();
    final personRows = await database.select(database.persons).get();
    final relationRows = await database.select(database.eventPersons).get();
    final loaded = await repository.loadSessions();

    expect(sessionRows, isEmpty);
    expect(eventRows, isEmpty);
    expect(personRows, isEmpty);
    expect(relationRows, isEmpty);
    expect(loaded, isEmpty);
  });
  test('rewrites relational rows when saving an updated session', () async {
    final session = _buildSessionRecord();
    await repository.saveSession(session);

    final updatedSession = session.copyWith(
      draft: session.draft.copyWith(
        persons: [session.draft.persons.single.copyWith(name: 'Alicia')],
        tasks: [
          session.draft.tasks.single.copyWith(relatedPersonNames: ['Alicia']),
        ],
      ),
      events: [
        session.events.single.copyWith(personNames: ['Alicia']),
      ],
      people: [session.people.single.copyWith(name: 'Alicia')],
    );

    await repository.saveSession(updatedSession);

    final eventRows = await database.select(database.events).get();
    final personRows = await database.select(database.persons).get();
    final relationRows = await database.select(database.eventPersons).get();
    final loaded = await repository.loadSessions();

    expect(eventRows, hasLength(1));
    expect(personRows, hasLength(1));
    expect(relationRows, hasLength(1));
    expect(personRows.single.name, 'Alicia');
    expect(loaded.single.people.single.name, 'Alicia');
  });
}

Future<void> _insertSnapshotRow(
  AppDatabase database, {
  required SessionRecord session,
  required String snapshotJson,
}) async {
  await database
      .into(database.sessions)
      .insert(
        SessionsCompanion.insert(
          id: session.id,
          title: session.title,
          summary: session.preview.summary,
          confirmedAt: session.confirmedAt.millisecondsSinceEpoch,
          sourceType: session.input.sourceType.name,
          sourcePath: Value(session.input.sourcePath),
          rawText: session.input.rawText,
          snapshotJson: Value(snapshotJson),
          createdAt: session.draft.createdAt.millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

Map<String, dynamic> _legacySessionJson(SessionRecord session) {
  return {
    'id': session.id,
    'title': session.title,
    'input': {
      'rawText': session.input.rawText,
      'sourceType': session.input.sourceType.name,
      'sourcePath': session.input.sourcePath,
    },
    'draft': {
      'id': session.draft.id,
      'tasks': [
        for (final task in session.draft.tasks)
          {
            'id': task.id,
            'content': task.content,
            'category': task.category.name,
            'type': task.type.name,
            'confidence': task.confidence,
            'relatedPersonNames': task.relatedPersonNames,
            'timeHint': task.timeHint,
          },
      ],
      'persons': [
        for (final person in session.draft.persons)
          {
            'id': person.id,
            'name': person.name,
            'role': person.role.name,
            'aliases': person.aliases,
            'relatedTaskIndexes': person.relatedTaskIndexes,
          },
      ],
      'summary': session.draft.summary,
      'warnings': session.draft.warnings,
      'createdAt': session.draft.createdAt.millisecondsSinceEpoch,
    },
    'events': [
      for (final event in session.events)
        {
          'id': event.id,
          'title': event.title,
          'category': event.category.name,
          'type': event.type.name,
          'startAt': event.startAt.millisecondsSinceEpoch,
          'endAt': event.endAt?.millisecondsSinceEpoch,
          'origin': event.origin.name,
          'personNames': event.personNames,
          'sourceLabel': event.sourceLabel,
        },
    ],
    'people': [
      for (final person in session.people)
        {
          'id': person.id,
          'name': person.name,
          'role': person.role.name,
          'aliases': person.aliases,
          'relatedTaskCount': person.relatedTaskCount,
          'relatedPlanTitles': person.relatedPlanTitles,
        },
    ],
    'confirmedAt': session.confirmedAt.millisecondsSinceEpoch,
  };
}

SessionRecord _buildSessionRecord() {
  final createdAt = DateTime(2026, 4, 26, 10);
  final task = ExtractedTaskDraft(
    id: 'task_1',
    content: 'Prepare paper',
    category: ItemCategory.work,
    type: EventType.plan,
    confidence: 0.9,
    relatedPersonNames: const ['Alice'],
    timeHint: 'tomorrow',
  );
  final personDraft = ExtractedPersonDraft(
    id: 'person_1',
    name: 'Alice',
    role: PersonRole.friend,
    relatedTaskIndexes: const [0],
  );
  final draft = AnalysisDraft(
    id: 'draft_1',
    tasks: [task],
    persons: [personDraft],
    summary: 'One planned task',
    warnings: const [],
    createdAt: createdAt,
  );
  final preview = ReviewPreview(
    id: 'preview_draft_1',
    completedTasks: const [],
    plannedTasks: [task],
    persons: [personDraft],
    summary: draft.summary,
    warnings: const [],
    relationLabels: const ['朋友'],
  );
  final event = EventItem(
    id: 'event_1',
    title: task.content,
    category: task.category,
    type: task.type,
    startAt: DateTime(2026, 4, 27),
    endAt: DateTime(2026, 4, 27),
    personNames: task.relatedPersonNames,
  );
  final person = PersonProfile(
    id: personDraft.id,
    name: personDraft.name,
    role: personDraft.role,
    aliases: const [],
    relatedTaskCount: 1,
    relatedPlanTitles: [task.content],
  );

  return SessionRecord(
    id: 'session_1',
    title: 'First session',
    input: const AnalysisInput(
      rawText: 'Prepare paper with Alice',
      sourceType: AnalysisSourceType.text,
    ),
    draft: draft,
    preview: preview,
    events: [event],
    people: [person],
    confirmedAt: createdAt,
  );
}
