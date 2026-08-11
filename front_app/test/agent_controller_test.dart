import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/features/agent/state/agent_controller.dart';
import 'package:research_life/services/agent/ai_credential_store.dart';
import 'package:research_life/services/agent/ai_profile.dart';
import 'package:research_life/services/agent/ai_profile_repository.dart';
import 'package:research_life/services/agent/openai_compatible_chat_client.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/agent_chat_repository.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';

void main() {
  late _Fixture fixture;

  setUp(() {
    fixture = _Fixture();
  });

  tearDown(() async {
    fixture.controller.dispose();
    await fixture.closeDatabase();
  });

  test('bootstrap reads local state and never calls the HTTP client', () async {
    await fixture.storeConfiguration();
    final session = await fixture.chats.createSession(
      profileId: remoteProfile.id,
      model: remoteProfile.model,
      title: 'Existing chat',
    );
    await fixture.chats.appendMessage(
      sessionId: session.id,
      role: 'user',
      content: 'Earlier question',
    );

    await fixture.controller.bootstrap();

    expect(fixture.adapter.calls, 0);
    expect(fixture.controller.profile, remoteProfile);
    expect(fixture.controller.hasCredential, isTrue);
    expect(fixture.controller.sessions, hasLength(1));
    expect(fixture.controller.currentSessionId, session.id);
    expect(fixture.controller.messages.single.content, 'Earlier question');
  });

  test('missing profile never starts a request', () async {
    fixture.adapter.replyNext('unused');
    await fixture.controller.bootstrap();

    await fixture.controller.sendMessage('Question without a profile');

    expect(fixture.controller.needsConfiguration, isTrue);
    expect(fixture.adapter.calls, 0);
    expect(await fixture.chats.listSessions(), isEmpty);
  });

  test('missing credential never starts a request', () async {
    await fixture.profiles.saveActive(remoteProfile);
    fixture.adapter.replyNext('unused');
    await fixture.controller.bootstrap();

    await fixture.controller.sendMessage('Question without a credential');

    expect(fixture.controller.needsConfiguration, isTrue);
    expect(fixture.adapter.calls, 0);
    expect(await fixture.chats.listSessions(), isEmpty);
  });

  test('first send commits a local session and user message before HTTP', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    fixture.adapter.blockNext();

    final send = fixture.controller.sendMessage('Committed first');
    await fixture.adapter.requestStarted.future;

    final sessions = await fixture.chats.listSessions();
    expect(sessions, hasLength(1));
    final stored = await fixture.chats.listMessages(sessions.single.id);
    expect(stored.map((message) => message.content), ['Committed first']);
    expect(stored.single.isUser, isTrue);

    fixture.adapter.completeBlocked('Assistant answer');
    await send;
  });

  test('successful send persists assistant and truncates first title', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    fixture.adapter.replyNext('Assistant answer', model: 'served-model');
    const question = '12345678901234567890123456789012345';

    await fixture.controller.sendMessage(question);

    final session = (await fixture.chats.listSessions()).single;
    final stored = await fixture.chats.listMessages(session.id);
    expect(stored.map((message) => message.role), ['user', 'assistant']);
    expect(stored.last.content, 'Assistant answer');
    expect(stored.last.model, 'served-model');
    expect(session.title, '12345678901234567890123456789…');
    expect(session.model, 'served-model');
  });

  test('failed request keeps one user message and retry reuses it', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    fixture.adapter.failNext();

    await fixture.controller.sendMessage('Retry this question');

    expect(
      fixture.controller.messages.where((message) => message.isUser),
      hasLength(1),
    );
    expect(fixture.controller.canRetry, isTrue);

    fixture.adapter.replyNext('Recovered answer');
    await fixture.controller.retryFailedMessage();

    expect(
      fixture.controller.messages.where((message) => message.isUser),
      hasLength(1),
    );
    expect(
      fixture.controller.messages.where((message) => message.isAssistant),
      hasLength(1),
    );
    expect(
      await fixture.chats.listMessages(fixture.controller.currentSessionId!),
      hasLength(2),
    );
    expect(fixture.adapter.calls, 2);
    expect(fixture.controller.canRetry, isFalse);
  });

  test('only one send may be in flight', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    fixture.adapter.blockNext();

    final first = fixture.controller.sendMessage('First question');
    await fixture.adapter.requestStarted.future;
    await fixture.controller.sendMessage('Second question');

    expect(fixture.adapter.calls, 1);
    expect(
      fixture.controller.messages.where((message) => message.isUser),
      hasLength(1),
    );
    fixture.adapter.completeBlocked('First answer');
    await first;
  });

  test('local save failure stops before HTTP and does not leak input', () async {
    const content = 'private-content-marker';
    const key = 'private-key-marker';
    await fixture.storeConfiguration(credential: key);
    await fixture.controller.bootstrap();
    fixture.adapter.replyNext('unused');
    await fixture.closeDatabase();

    await fixture.controller.sendMessage(content);

    expect(fixture.adapter.calls, 0);
    expect(fixture.controller.error, isNotNull);
    expect(fixture.controller.error, isNot(contains(content)));
    expect(fixture.controller.error, isNot(contains(key)));
  });

  test('assistant save failure exposes the volatile answer', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    fixture.adapter.blockNext();

    final send = fixture.controller.sendMessage('Persist my answer');
    await fixture.adapter.requestStarted.future;
    await fixture.closeDatabase();
    fixture.adapter.completeBlocked('Visible but volatile');
    await send;

    expect(fixture.controller.messages.last.isAssistant, isTrue);
    expect(fixture.controller.messages.last.content, 'Visible but volatile');
    expect(
      fixture.controller.volatileAssistantMessage?.content,
      'Visible but volatile',
    );
    expect(fixture.controller.error, isNotNull);
    expect(fixture.controller.canRetry, isFalse);
  });

  test('open and delete sessions operate only on local history', () async {
    await fixture.storeConfiguration();
    final older = await fixture.chats.createSession(
      profileId: remoteProfile.id,
      model: remoteProfile.model,
      title: 'Older',
    );
    await fixture.chats.appendMessage(
      sessionId: older.id,
      role: 'user',
      content: 'Old question',
    );
    final newer = await fixture.chats.createSession(
      profileId: remoteProfile.id,
      model: remoteProfile.model,
      title: 'Newer',
    );
    await fixture.chats.appendMessage(
      sessionId: newer.id,
      role: 'user',
      content: 'New question',
    );
    await fixture.controller.bootstrap();

    await fixture.controller.openSession(older.id);
    expect(fixture.controller.messages.single.content, 'Old question');

    await fixture.controller.deleteSession(older.id);
    expect(fixture.controller.sessions.map((session) => session.id), [newer.id]);
    expect(fixture.controller.currentSessionId, newer.id);
    expect(fixture.controller.messages.single.content, 'New question');
    expect(fixture.adapter.calls, 0);
  });

  test('cancelling an active request is not a user-facing error', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    fixture.adapter.blockNext();

    final send = fixture.controller.sendMessage('Cancel this request');
    await fixture.adapter.requestStarted.future;
    fixture.controller.cancelActiveRequest();
    await send;

    expect(fixture.controller.error, isNull);
    expect(fixture.controller.sending, isFalse);
    expect(
      fixture.controller.messages.where((message) => message.isUser),
      hasLength(1),
    );
  });

  test('blank credential retains the existing credential', () async {
    await fixture.storeConfiguration(credential: 'existing-key');

    await fixture.controller.saveConfiguration(
      profile: replacementProfile,
      credential: '   ',
    );

    expect(await fixture.credentials.read(replacementProfile.id), 'existing-key');
    expect(await fixture.profiles.loadActive(), replacementProfile);
    expect(fixture.controller.hasCredential, isTrue);
  });

  test('replacement credential is written without being exposed', () async {
    await fixture.storeConfiguration(credential: 'existing-key');

    await fixture.controller.saveConfiguration(
      profile: replacementProfile,
      credential: ' replacement-key ',
    );

    expect(await fixture.credentials.read(replacementProfile.id), 'replacement-key');
    expect(fixture.controller.error, isNull);
  });

  test('deleteCredential removes only the active credential', () async {
    await fixture.storeConfiguration();
    final session = await fixture.chats.createSession(
      profileId: remoteProfile.id,
      model: remoteProfile.model,
      title: 'Keep history',
    );
    await fixture.controller.bootstrap();

    await fixture.controller.deleteCredential();

    expect(await fixture.credentials.read(remoteProfile.id), isNull);
    expect(fixture.controller.needsConfiguration, isTrue);
    expect((await fixture.chats.listSessions()).single.id, session.id);
  });
}

const remoteProfile = AiProviderProfile(
  id: 'primary',
  provider: 'openai',
  displayName: 'OpenAI',
  baseUrl: 'https://example.invalid/v1',
  model: 'model-a',
  requiresCredential: true,
);

const replacementProfile = AiProviderProfile(
  id: 'primary',
  provider: 'openai',
  displayName: 'OpenAI replacement',
  baseUrl: 'https://example.invalid/v1',
  model: 'model-b',
  requiresCredential: true,
);

final class _Fixture {
  _Fixture()
    : database = AppDatabase(NativeDatabase.memory()),
      coordinator = LocalDataOperationCoordinator(),
      credentials = _MemoryCredentialStore(),
      adapter = _ScriptedAdapter() {
    final preferences = PreferencesRepository(
      database,
      operationCoordinator: coordinator,
    );
    profiles = AiProfileRepository(preferences);
    chats = AgentChatRepository(
      database,
      operationCoordinator: coordinator,
    );
    client = OpenAiCompatibleChatClient(httpClientAdapter: adapter);
    controller = AgentController(
      profiles: profiles,
      credentials: credentials,
      chats: chats,
      client: client,
    );
  }

  final AppDatabase database;
  final LocalDataOperationCoordinator coordinator;
  final _MemoryCredentialStore credentials;
  final _ScriptedAdapter adapter;
  late final AiProfileRepository profiles;
  late final AgentChatRepository chats;
  late final OpenAiCompatibleChatClient client;
  late final AgentController controller;
  bool _databaseClosed = false;

  Future<void> storeConfiguration({String credential = 'test-key'}) async {
    await profiles.saveActive(remoteProfile);
    await credentials.write(remoteProfile.id, credential);
  }

  Future<void> closeDatabase() async {
    if (_databaseClosed) return;
    _databaseClosed = true;
    await database.close();
  }
}

final class _MemoryCredentialStore implements AiCredentialStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String profileId) async {
    _values.remove(profileId);
  }

  @override
  Future<bool> has(String profileId) async => _values.containsKey(profileId);

  @override
  Future<String?> read(String profileId) async => _values[profileId];

  @override
  Future<void> write(String profileId, String secret) async {
    _values[profileId] = secret;
  }
}

typedef _AdapterAction = Future<ResponseBody> Function(
  RequestOptions options,
  Future<void>? cancelFuture,
);

final class _ScriptedAdapter implements HttpClientAdapter {
  final List<_AdapterAction> _actions = <_AdapterAction>[];
  int calls = 0;
  Completer<void> requestStarted = Completer<void>();
  Completer<ResponseBody>? _blocked;

  void replyNext(String content, {String model = 'model-a'}) {
    _actions.add((options, cancelFuture) async {
      return _response(content, model: model);
    });
  }

  void failNext() {
    _actions.add((options, cancelFuture) {
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
    final blocked = Completer<ResponseBody>();
    _blocked = blocked;
    _actions.add((options, cancelFuture) {
      final cancelled = cancelFuture?.then<ResponseBody>((_) {
        throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'controlled cancellation',
        );
      });
      if (cancelled == null) return blocked.future;
      return Future.any<ResponseBody>([blocked.future, cancelled]);
    });
  }

  void completeBlocked(String content) {
    _blocked!.complete(_response(content, model: 'model-a'));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    if (!requestStarted.isCompleted) requestStarted.complete();
    if (_actions.isEmpty) {
      throw StateError('No scripted HTTP response');
    }
    return _actions.removeAt(0)(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}

  ResponseBody _response(String content, {required String model}) {
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': content},
            'finish_reason': 'stop',
          },
        ],
        'model': model,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}
