import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/agent/agent_models.dart';
import 'package:research_life/services/database/app_database.dart'
    hide AgentChatMessage, AgentChatSession;
import 'package:research_life/services/database/repositories/agent_chat_repository.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';

import 'generated/app_database_schema/schema.dart';

void main() {
  late AppDatabase database;
  late LocalDataOperationCoordinator coordinator;
  late AgentChatRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    coordinator = LocalDataOperationCoordinator();
    repository = AgentChatRepository(
      database,
      operationCoordinator: coordinator,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('creates a session and returns messages in insertion order', () async {
    final session = await repository.createSession(
      profileId: 'primary',
      model: 'model-a',
      title: '新对话',
    );
    await repository.appendMessage(
      sessionId: session.id,
      role: 'user',
      content: '问题',
    );
    await repository.appendMessage(
      sessionId: session.id,
      role: 'assistant',
      content: '回答',
      reasoningContent: '思考',
      model: 'model-a',
    );

    final messages = await repository.listMessages(session.id);
    expect(messages.map((message) => message.role), ['user', 'assistant']);
    expect(messages.map((message) => message.content), ['问题', '回答']);
    expect(messages.last.reasoningContent, '思考');
    expect(
      messages.every((message) => message.sessionId == session.id),
      isTrue,
    );
  });

  test(
    'update after reply changes metadata and promotes the session',
    () async {
      final first = await repository.createSession(
        profileId: 'primary',
        model: 'model-a',
        title: 'first',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final second = await repository.createSession(
        profileId: 'secondary',
        model: 'model-b',
        title: 'second',
      );

      await Future<void>.delayed(const Duration(milliseconds: 2));
      final updated = await repository.updateSessionAfterReply(
        sessionId: first.id,
        title: 'renamed',
        model: 'model-c',
      );

      expect(updated.id, first.id);
      expect(updated.title, 'renamed');
      expect(updated.profileId, 'primary');
      expect(updated.model, 'model-c');
      expect(updated.createdAt, first.createdAt);
      expect(updated.updatedAt.isAfter(first.updatedAt), isTrue);
      expect((await repository.listSessions()).map((session) => session.id), [
        first.id,
        second.id,
      ]);
    },
  );

  test('delete session removes its messages transactionally', () async {
    final session = await _seededSession(repository);

    await repository.deleteSession(session.id);

    expect(await repository.listMessages(session.id), isEmpty);
    expect(await repository.listSessions(), isEmpty);
  });

  test(
    'delete transaction waits for the local data coordinator lease',
    () async {
      final session = await _seededSession(repository);
      final leaseStarted = Completer<void>();
      final releaseLease = Completer<void>();
      var deleteCompleted = false;
      final lease = coordinator.runExclusive(() async {
        leaseStarted.complete();
        await releaseLease.future;
      });
      await leaseStarted.future;

      final delete = repository
          .deleteSession(session.id)
          .then((_) => deleteCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(deleteCompleted, isFalse);
      expect(await repository.listMessages(session.id), hasLength(1));
      expect(await repository.listSessions(), hasLength(1));

      releaseLease.complete();
      await Future.wait([lease, delete]);

      expect(await repository.listMessages(session.id), isEmpty);
      expect(await repository.listSessions(), isEmpty);
    },
  );

  test('legacy remote model decoding remains available until task 5', () {
    final reply = AgentChatReply.fromJson({
      'session': {
        'id': 7,
        'title': 'legacy',
        'mode': 'expert',
        'updateTime': '2026-08-11T12:00:00.000Z',
      },
      'userMessage': {'id': 8, 'role': 'user', 'content': 'question'},
      'assistantMessage': {'id': 9, 'role': 'assistant', 'content': 'answer'},
    });

    expect(reply.session.id, 7);
    expect(reply.session.mode, 'expert');
    expect(reply.session.updateTime, DateTime.utc(2026, 8, 11, 12));
    expect(reply.userMessage.id, 8);
    expect(reply.userMessage.sessionId, 7);
    expect(reply.assistantMessage.id, 9);
    expect(reply.assistantMessage.sessionId, 7);
  });

  test('schema fixtures and generated helper cannot silently go stale', () async {
    expect(GeneratedHelper.versions, orderedEquals([8, 9]));
    final verifier = SchemaVerifier(GeneratedHelper());

    for (final version in [8, 9]) {
      final authoritative = await File(
        'drift_schemas/schema_v$version.json',
      ).readAsBytes();
      final driftAlias = await File(
        'drift_schemas/drift_schema_v$version.json',
      ).readAsBytes();

      final generatedSchema = await verifier.schemaAt(version);
      try {
        final generatedTables = <String, String>{
          for (final row in generatedSchema.rawDatabase.select(
            "SELECT name, sql FROM sqlite_schema "
            "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
            'ORDER BY name',
          ))
            row['name'] as String: _normalizeCreateTableSql(
              row['sql'] as String,
            ),
        };
        expect(
          generatedTables,
          equals(_fixedSqlTables(authoritative)),
          reason:
              'generated schema v$version must match its authoritative fixture',
        );
      } finally {
        generatedSchema.close();
      }

      expect(
        driftAlias,
        orderedEquals(authoritative),
        reason: 'schema v$version fixture aliases must be byte-identical',
      );
    }
  });

  test(
    'schema 8 migrates to schema 9 without changing existing rows',
    () async {
      await database.close();
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(8);
      addTearDown(schema.close);
      schema.rawDatabase.execute(
        'INSERT INTO preferences (key, value, updated_at) VALUES (?, ?, ?)',
        ['existing', 'preserved', 42],
      );
      final db = AppDatabase(schema.newConnection().executor);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, 9);

      final existing = await (db.select(
        db.preferences,
      )..where((row) => row.key.equals('existing'))).getSingle();
      expect(existing.value, 'preserved');
      expect(existing.updatedAt, 42);
    },
  );
}

Future<AgentChatSession> _seededSession(AgentChatRepository repository) async {
  final session = await repository.createSession(
    profileId: 'primary',
    model: 'model-a',
    title: '新对话',
  );
  await repository.appendMessage(
    sessionId: session.id,
    role: 'user',
    content: '问题',
  );
  return session;
}

Map<String, String> _fixedSqlTables(List<int> fixtureBytes) {
  final fixture = jsonDecode(utf8.decode(fixtureBytes)) as Map<String, dynamic>;
  final fixedSql = fixture['fixed_sql'] as List<dynamic>;
  return <String, String>{
    for (final entry in fixedSql.cast<Map<String, dynamic>>())
      entry['name'] as String: _normalizeCreateTableSql(
        ((entry['sql'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .singleWhere(
                  (statement) => statement['dialect'] == 'sqlite',
                ))['sql']
            as String,
      ),
  };
}

String _normalizeCreateTableSql(String sql) {
  return sql
      .replaceFirst(
        RegExp(r'^CREATE TABLE IF NOT EXISTS\s+', caseSensitive: false),
        'CREATE TABLE ',
      )
      .replaceAllMapped(
        RegExp(r'"([A-Za-z_][A-Za-z0-9_]*)"'),
        (match) => match.group(1)!,
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*\(\s*'), '(')
      .replaceAll(RegExp(r'\s*\)\s*'), ')')
      .replaceAll(RegExp(r'\s*,\s*'), ',')
      .replaceFirst(RegExp(r';$'), '')
      .trim();
}
