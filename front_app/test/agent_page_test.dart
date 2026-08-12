import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/local_services_scope.dart';
import 'package:research_life/app/research_life_scope.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/core/theme/app_tokens.dart';
import 'package:research_life/features/agent/agent_page.dart';
import 'package:research_life/services/agent/agent_models.dart';
import 'package:research_life/services/agent/ai_credential_store.dart';
import 'package:research_life/services/agent/ai_profile.dart';
import 'package:research_life/services/agent/ai_profile_repository.dart';
import 'package:research_life/services/agent/ai_runtime_services.dart';
import 'package:research_life/services/agent/openai_compatible_chat_client.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/database/repositories/agent_chat_repository.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/database/app_database.dart'
    show AppDatabase;
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/backup_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';
import 'package:research_life/state/local_backup_controller.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  testWidgets('Agent bootstraps locally and opens concise secure settings', (
    tester,
  ) async {
    final fixture = _AgentPageFixture();
    await fixture.pump(tester);

    expect(fixture.adapter.calls, 0);
    expect(find.text('配置 AI'), findsOneWidget);
    expect(find.byKey(const Key('agent-settings')), findsOneWidget);

    await tester.tap(find.byKey(const Key('agent-settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-provider')), findsOneWidget);
    expect(find.byKey(const Key('agent-base-url')), findsOneWidget);
    expect(find.byKey(const Key('agent-model')), findsOneWidget);
    expect(find.byKey(const Key('agent-api-key')), findsOneWidget);
    expect(find.byKey(const Key('agent-save-settings')), findsOneWidget);
    expect(find.byKey(const Key('agent-delete-credential')), findsOneWidget);
    expect(find.text('发送时，当前对话上下文会传给所选服务；本地历史与凭据分开保存。'), findsOneWidget);
  });

  testWidgets('saved key stays blank and blank save retains the credential', (
    tester,
  ) async {
    final fixture = _AgentPageFixture(configured: true);
    await fixture.pump(tester);

    await tester.tap(find.byKey(const Key('agent-settings')));
    await tester.pumpAndSettle();
    final keyField = tester.widget<TextField>(
      find.byKey(const Key('agent-api-key')),
    );
    expect(keyField.controller!.text, isEmpty);
    expect(keyField.obscureText, isTrue);

    await tester.tap(find.byKey(const Key('agent-save-settings')));
    await tester.pumpAndSettle();
    expect(
      await fixture.credentials.read(aiCredentialId(_profile)),
      'existing-secret',
    );

    await tester.tap(find.byKey(const Key('agent-settings')));
    await tester.pumpAndSettle();
    final reopened = tester.widget<TextField>(
      find.byKey(const Key('agent-api-key')),
    );
    expect(reopened.controller!.text, isEmpty);
    expect(reopened.obscureText, isTrue);
  });

  testWidgets(
    'provider preset remains editable and Ollama marks key optional',
    (tester) async {
      final fixture = _AgentPageFixture();
      await fixture.pump(tester);
      await tester.tap(find.byKey(const Key('agent-settings')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('agent-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ollama（本地）').last);
      await tester.pumpAndSettle();

      expect(find.text('API Key（可选）'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('agent-base-url')),
        'http://127.0.0.1:11434/v1',
      );
      await tester.enterText(find.byKey(const Key('agent-model')), 'qwen3:8b');
      await tester.tap(find.byKey(const Key('agent-save-settings')));
      await tester.pumpAndSettle();

      expect(fixture.profiles.active?.provider, 'ollama');
      expect(fixture.profiles.active?.baseUrl, 'http://127.0.0.1:11434/v1');
      expect(fixture.profiles.active?.model, 'qwen3:8b');
      expect(find.textContaining('qwen3:8b'), findsOneWidget);
    },
  );

  testWidgets('switching credential providers requires that provider key', (
    tester,
  ) async {
    final fixture = _AgentPageFixture(configured: true);
    await fixture.pump(tester);
    await tester.tap(find.byKey(const Key('agent-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('agent-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-save-settings')));
    await tester.pumpAndSettle();

    expect(find.text('请输入 API Key。'), findsOneWidget);
    expect(fixture.profiles.active?.provider, 'openai');
    expect(
      await fixture.credentials.read(aiCredentialId(_profile)),
      'existing-secret',
    );
  });

  testWidgets('credential delete is confirmed without deleting local history', (
    tester,
  ) async {
    final fixture = _AgentPageFixture(configured: true)
      ..seedSession(title: '保留的本地会话', user: '旧问题');
    await fixture.pump(tester);
    await tester.tap(find.byKey(const Key('agent-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-delete-credential')));
    await tester.pumpAndSettle();

    expect(find.text('删除 AI 凭据？'), findsOneWidget);
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(await fixture.credentials.read(aiCredentialId(_profile)), isNull);
    expect(fixture.chats.sessions, hasLength(1));
    expect(find.text('保留的本地会话'), findsOneWidget);
  });

  testWidgets('history opens and deletes locally and sidebar is 240 to 60', (
    tester,
  ) async {
    final fixture = _AgentPageFixture(configured: true)
      ..seedSession(title: '第一段历史', user: '第一问')
      ..seedSession(title: '第二段历史', user: '第二问');
    await fixture.pump(tester);

    expect(
      tester.getSize(find.byKey(const Key('agent-history-sidebar'))).width,
      240,
    );
    await tester.tap(find.byKey(const Key('agent-collapse-history')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('agent-history-sidebar'))).width,
      60,
    );
    await tester.tap(find.byKey(const Key('agent-expand-history')));
    await tester.pumpAndSettle();

    final secondId = fixture.chats.sessions[1].id;
    await tester.tap(find.byKey(ValueKey('agent-history-$secondId')));
    await tester.pumpAndSettle();
    expect(find.text('第二问'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('agent-delete-session-$secondId')));
    await tester.pumpAndSettle();
    expect(
      fixture.chats.sessions.map((session) => session.id),
      isNot(contains(secondId)),
    );
  });

  testWidgets('assistant answers render Markdown with a model chip', (
    tester,
  ) async {
    final fixture = _AgentPageFixture(configured: true)
      ..seedSession(
        title: 'Markdown 历史',
        user: '总结一下',
        assistant: '**结论**\n\n- 第一项',
      );
    await fixture.pump(tester);

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('结论'), findsOneWidget);
    expect(find.byKey(const Key('agent-model-chip')), findsOneWidget);
    expect(find.textContaining('model-a'), findsOneWidget);
  });

  testWidgets(
    'send failure offers retry without duplicating the user message',
    (tester) async {
      final fixture = _AgentPageFixture(configured: true);
      fixture.adapter.failNext();
      await fixture.pump(tester);

      await tester.enterText(
        find.byKey(const Key('agent-composer')),
        '需要重试的问题',
      );
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('agent-send')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('agent-send')));
      await tester.pumpAndSettle();

      expect(fixture.adapter.calls, 1);
      expect(fixture.chats.sessions, hasLength(1));
      expect(
        fixture.chats.messages.values.expand((messages) => messages),
        hasLength(1),
      );
      expect(find.byKey(const Key('agent-retry')), findsOneWidget);
      expect(find.text('需要重试的问题'), findsOneWidget);
      fixture.adapter.replyNext('重试后的 **答案**');
      await tester.tap(find.byKey(const Key('agent-retry')));
      await tester.pumpAndSettle();

      expect(fixture.adapter.calls, 2);
      expect(
        fixture.chats.messages.values
            .expand((messages) => messages)
            .where((message) => message.isUser),
        hasLength(1),
      );
      expect(
        fixture.chats.messages.values
            .expand((messages) => messages)
            .where((message) => message.isAssistant)
            .single
            .content,
        '重试后的 **答案**',
      );
      expect(find.byType(MarkdownBody), findsOneWidget);
    },
  );

  testWidgets('active send exposes cancel without showing a system error', (
    tester,
  ) async {
    final fixture = _AgentPageFixture(configured: true);
    fixture.adapter.blockNext();
    await fixture.pump(tester);

    await tester.enterText(find.byKey(const Key('agent-composer')), '取消这次请求');
    await tester.pump();
    expect(
      tester.widget<IconButton>(find.byKey(const Key('agent-send'))).onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('agent-send')));
    for (
      var frame = 0;
      frame < 30 && !fixture.adapter.requestStarted.isCompleted;
      frame += 1
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(fixture.adapter.requestStarted.isCompleted, isTrue);
    await tester.pump();
    expect(find.byTooltip('取消请求'), findsOneWidget);

    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pumpAndSettle();

    expect(find.text('请求已取消'), findsNothing);
    expect(find.byKey(const Key('agent-retry')), findsOneWidget);
  });

  testWidgets('narrow Agent workspace keeps primary controls reachable', (
    tester,
  ) async {
    final fixture = _AgentPageFixture(configured: true);
    await fixture.pump(tester, size: const Size(500, 700));

    expect(
      tester.getSize(find.byKey(const Key('agent-history-sidebar'))).width,
      60,
    );
    expect(find.byKey(const Key('agent-settings')), findsOneWidget);
    expect(find.byKey(const Key('agent-composer')), findsOneWidget);
    expect(find.byKey(const Key('agent-send')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Agent history open and delete persist through real Drift stores',
    (tester) async {
      final fixture = _DriftAgentPageFixture();
      await fixture.configure();
      final session = await fixture.chats.createSession(
        profileId: _profile.id,
        model: _profile.model,
        title: 'Drift history',
      );
      await fixture.chats.appendMessage(
        sessionId: session.id,
        role: 'user',
        content: 'Persisted question',
      );

      await fixture.pump(tester);
      await tester.tap(find.byKey(ValueKey('agent-history-${session.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Persisted question'), findsOneWidget);

      await tester.tap(
        find.byKey(ValueKey('agent-delete-session-${session.id}')),
      );
      await tester.pumpAndSettle();
      expect(await fixture.chats.listSessions(), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.close();
    },
  );
}

const _profile = AiProviderProfile(
  id: 'primary',
  provider: 'openai',
  displayName: 'OpenAI',
  baseUrl: 'https://example.invalid/v1',
  model: 'model-a',
  requiresCredential: true,
);

final class _AgentPageFixture {
  _AgentPageFixture({bool configured = false}) {
    if (configured) {
      profiles.active = _profile;
      credentials.values[aiCredentialId(_profile)] = 'existing-secret';
    }
    backupController = LocalBackupController(
      backupService: _UnusedBackupService(),
      migrationPreferences: _UnusedMigrationPreferences(),
      flushLocalWrites: () async {},
      restoreRuntime: (_) => Future<BackupRestoreResult>.error(
        StateError('restore is not used in AgentPage tests'),
      ),
    );
    lifeController = ResearchLifeController(
      importService: const ImportService(),
      analysisService: const AnalysisService(),
      reviewService: const ReviewService(),
      institutionCalendarService: const InstitutionCalendarService(),
      localWorkspaceService: const LocalWorkspaceService(),
    );
    services = AiRuntimeServices(
      profiles: profiles,
      credentials: credentials,
      chats: chats,
      client: OpenAiCompatibleChatClient(httpClientAdapter: adapter),
    );
  }

  final _MemoryProfileStore profiles = _MemoryProfileStore();
  final _MemoryCredentialStore credentials = _MemoryCredentialStore();
  final _MemoryChatStore chats = _MemoryChatStore();
  final _ScriptedAdapter adapter = _ScriptedAdapter();
  late final AiRuntimeServices services;
  late final LocalBackupController backupController;
  late final ResearchLifeController lifeController;

  void seedSession({
    required String title,
    required String user,
    String? assistant,
  }) {
    chats.seedSession(
      profile: _profile,
      title: title,
      user: user,
      assistant: assistant,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1100, 760),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(backupController.dispose);
    addTearDown(lifeController.dispose);
    await tester.pumpWidget(
      ResearchLifeScope(
        controller: lifeController,
        child: MaterialApp(
          theme: AppTheme.build(AppColorTheme.green),
          home: LocalServicesScope(
            backupController: backupController,
            aiServices: services,
            restoreAndRestart: (_) => Future<BackupRestoreResult>.error(
              StateError('restore is not used in AgentPage tests'),
            ),
            child: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: const AgentPage(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

final class _DriftAgentPageFixture {
  _DriftAgentPageFixture()
    : database = AppDatabase(NativeDatabase.memory()),
      credentials = _MemoryCredentialStore(),
      adapter = _ScriptedAdapter() {
    final preferences = PreferencesRepository(database);
    profiles = AiProfileRepository(preferences);
    chats = AgentChatRepository(
      database,
      operationCoordinator: LocalDataOperationCoordinator(),
    );
    backupController = LocalBackupController(
      backupService: _UnusedBackupService(),
      migrationPreferences: _UnusedMigrationPreferences(),
      flushLocalWrites: () async {},
      restoreRuntime: (_) => Future<BackupRestoreResult>.error(
        StateError('restore is not used in AgentPage tests'),
      ),
    );
    lifeController = ResearchLifeController(
      importService: const ImportService(),
      analysisService: const AnalysisService(),
      reviewService: const ReviewService(),
      institutionCalendarService: const InstitutionCalendarService(),
      localWorkspaceService: const LocalWorkspaceService(),
    );
    services = AiRuntimeServices(
      profiles: profiles,
      credentials: credentials,
      chats: chats,
      client: OpenAiCompatibleChatClient(httpClientAdapter: adapter),
    );
  }

  final AppDatabase database;
  final _MemoryCredentialStore credentials;
  final _ScriptedAdapter adapter;
  late final AiProfileRepository profiles;
  late final AgentChatRepository chats;
  late final LocalBackupController backupController;
  late final ResearchLifeController lifeController;
  late final AiRuntimeServices services;
  var _closed = false;

  Future<void> configure() async {
    await profiles.saveActive(_profile);
    await credentials.write(aiCredentialId(_profile), 'existing-secret');
  }

  Future<void> pump(WidgetTester tester) async {
    addTearDown(() async {
      if (!_closed) await close();
    });
    addTearDown(backupController.dispose);
    addTearDown(lifeController.dispose);
    await tester.pumpWidget(
      ResearchLifeScope(
        controller: lifeController,
        child: MaterialApp(
          theme: AppTheme.build(AppColorTheme.green),
          home: LocalServicesScope(
            backupController: backupController,
            aiServices: services,
            restoreAndRestart: (_) => Future<BackupRestoreResult>.error(
              StateError('restore is not used in AgentPage tests'),
            ),
            child: const Scaffold(body: AgentPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await database.close();
  }
}

final class _MemoryProfileStore implements AiProfileStore {
  AiProviderProfile? active;

  @override
  Future<void> clearActive() async => active = null;

  @override
  Future<AiProviderProfile?> loadActive() async => active;

  @override
  Future<void> saveActive(AiProviderProfile profile) async => active = profile;
}

final class _MemoryCredentialStore implements AiCredentialStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String profileId) async => values.remove(profileId);

  @override
  Future<bool> has(String profileId) async => values.containsKey(profileId);

  @override
  Future<String?> read(String profileId) async => values[profileId];

  @override
  Future<void> write(String profileId, String secret) async {
    values[profileId] = secret;
  }
}

final class _MemoryChatStore implements AgentChatStore {
  final List<AgentChatSession> sessions = <AgentChatSession>[];
  final Map<int, List<AgentChatMessage>> messages =
      <int, List<AgentChatMessage>>{};
  int _nextSessionId = 1;
  int _nextMessageId = 1;

  void seedSession({
    required AiProviderProfile profile,
    required String title,
    required String user,
    String? assistant,
  }) {
    final now = DateTime(2026, 8, 12, 9, _nextSessionId);
    final session = AgentChatSession(
      id: _nextSessionId++,
      title: title,
      profileId: profile.id,
      model: profile.model,
      createdAt: now,
      updatedAt: now,
    );
    sessions.add(session);
    messages[session.id] = [
      _message(session.id, 'user', user),
      if (assistant != null)
        _message(session.id, 'assistant', assistant, model: profile.model),
    ];
  }

  AgentChatMessage _message(
    int sessionId,
    String role,
    String content, {
    String? reasoningContent,
    String? model,
  }) {
    return AgentChatMessage(
      id: _nextMessageId++,
      sessionId: sessionId,
      role: role,
      content: content,
      reasoningContent: reasoningContent,
      model: model,
      createdAt: DateTime(2026, 8, 12, 10, _nextMessageId),
    );
  }

  @override
  Future<AgentChatMessage> appendMessage({
    required int sessionId,
    required String role,
    required String content,
    String? reasoningContent,
    String? model,
  }) async {
    final message = _message(
      sessionId,
      role,
      content,
      reasoningContent: reasoningContent,
      model: model,
    );
    messages.putIfAbsent(sessionId, () => <AgentChatMessage>[]).add(message);
    return message;
  }

  @override
  Future<AgentChatSession> createSession({
    required String profileId,
    required String model,
    required String title,
  }) async {
    final now = DateTime(2026, 8, 12, 11, _nextSessionId);
    final session = AgentChatSession(
      id: _nextSessionId++,
      title: title,
      profileId: profileId,
      model: model,
      createdAt: now,
      updatedAt: now,
    );
    sessions.insert(0, session);
    messages[session.id] = <AgentChatMessage>[];
    return session;
  }

  @override
  Future<void> deleteSession(int sessionId) async {
    sessions.removeWhere((session) => session.id == sessionId);
    messages.remove(sessionId);
  }

  @override
  Future<List<AgentChatMessage>> listMessages(int sessionId) async =>
      List<AgentChatMessage>.of(messages[sessionId] ?? const []);

  @override
  Future<List<AgentChatSession>> listSessions() async =>
      List<AgentChatSession>.of(sessions);

  @override
  Future<AgentChatSession> updateSessionAfterReply({
    required int sessionId,
    String? title,
    String? model,
  }) async {
    final index = sessions.indexWhere((session) => session.id == sessionId);
    final current = sessions[index];
    final updated = AgentChatSession(
      id: current.id,
      title: title ?? current.title,
      profileId: current.profileId,
      model: model ?? current.model,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt.add(const Duration(minutes: 1)),
    );
    sessions[index] = updated;
    return updated;
  }
}

final class _ScriptedAdapter implements HttpClientAdapter {
  final List<Future<ResponseBody> Function(RequestOptions, Future<void>?)>
  _actions = <Future<ResponseBody> Function(RequestOptions, Future<void>?)>[];
  int calls = 0;
  Completer<void> requestStarted = Completer<void>();

  void replyNext(String content) {
    _actions.add((_, _) async => _response(content));
  }

  void failNext() {
    _actions.add((options, _) {
      return Future<ResponseBody>.error(
        DioException.connectionError(
          reason: 'controlled failure',
          requestOptions: options,
        ),
      );
    });
  }

  void blockNext() {
    requestStarted = Completer<void>();
    _actions.add((options, cancelFuture) async {
      await cancelFuture;
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: 'controlled cancellation',
      );
    });
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    if (!requestStarted.isCompleted) requestStarted.complete();
    if (_actions.isEmpty) {
      throw StateError('No scripted HTTP response');
    }
    return _actions.removeAt(0)(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}

  ResponseBody _response(String content) {
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': content},
            'finish_reason': 'stop',
          },
        ],
        'model': 'model-a',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

final class _UnusedMigrationPreferences implements LocalMigrationPreferences {
  @override
  Future<void> invalidateLocalMigrationBackupRecord() async {}

  @override
  Future<bool> loadLocalMigrationBackupComplete() async => false;

  @override
  Future<String?> loadLocalMigrationBackupPath() async => null;

  @override
  Future<void> saveLocalMigrationBackupRecord(String path) async {}
}

final class _UnusedBackupService extends Fake implements BackupService {}
