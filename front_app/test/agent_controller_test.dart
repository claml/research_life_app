import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/features/agent/state/agent_controller.dart';
import 'package:research_life/services/agent/agent_models.dart';
import 'package:research_life/services/agent/ai_credential_store.dart';
import 'package:research_life/services/agent/ai_profile.dart';
import 'package:research_life/services/agent/ai_profile_repository.dart';
import 'package:research_life/services/agent/openai_compatible_chat_client.dart';
import 'package:research_life/services/database/app_database.dart'
    hide AgentChatMessage, AgentChatSession;
import 'package:research_life/services/database/repositories/agent_chat_repository.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';

void main() {
  late _Fixture fixture;

  setUp(() {
    fixture = _Fixture();
  });

  tearDown(() async {
    fixture.disposeController();
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

  test(
    'first send commits a local session and user message before HTTP',
    () async {
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
      expect(
        AgentThinkingTrace.tryDecode(stored.single.reasoningContent)?.status,
        AgentThinkingStatus.active,
      );

      fixture.adapter.completeBlocked('Assistant answer');
      await send;
      final completed = await fixture.chats.listMessages(sessions.single.id);
      expect(
        AgentThinkingTrace.tryDecode(completed.first.reasoningContent)?.status,
        AgentThinkingStatus.completed,
      );
    },
  );

  test('failed request persists a failed thinking trace', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    fixture.adapter.failNext();

    await fixture.controller.sendMessage('Trace this failure');

    final stored = await fixture.chats.listMessages(
      fixture.controller.currentSessionId!,
    );
    final trace = AgentThinkingTrace.tryDecode(stored.first.reasoningContent);
    expect(trace?.status, AgentThinkingStatus.failed);
    expect(trace?.steps, contains('请求 AI 服务失败'));
  });

  test(
    'successful send persists assistant and truncates first title',
    () async {
      await fixture.storeConfiguration();
      await fixture.controller.bootstrap();
      fixture.adapter.replyNext(
        'Assistant answer',
        model: 'served-model',
        reasoningContent: 'INTERNAL_REASONING_MUST_NOT_PERSIST',
      );
      const question = '12345678901234567890123456789012345';

      await fixture.controller.sendMessage(question);

      final session = (await fixture.chats.listSessions()).single;
      final stored = await fixture.chats.listMessages(session.id);
      expect(stored.map((message) => message.role), ['user', 'assistant']);
      expect(stored.last.content, 'Assistant answer');
      expect(stored.last.model, 'served-model');
      expect(stored.last.reasoningContent, isNull);
      expect(session.title, '12345678901234567890123456789…');
      expect(session.model, 'served-model');
    },
  );

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

  test(
    'local save failure stops before HTTP and does not leak input',
    () async {
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
    },
  );

  test('assistant save failure exposes the volatile answer', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    fixture.chats.failNextAssistantAppend = true;
    fixture.adapter.replyNext('Visible but volatile');

    await fixture.controller.sendMessage('Persist my answer');

    expect(fixture.controller.messages.last.isAssistant, isTrue);
    expect(fixture.controller.messages.last.content, 'Visible but volatile');
    expect(
      fixture.controller.volatileAssistantMessage?.content,
      'Visible but volatile',
    );
    expect(
      AgentThinkingTrace.tryDecode(
        fixture.controller.messages.first.reasoningContent,
      )?.status,
      AgentThinkingStatus.active,
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
    expect(fixture.controller.sessions.map((session) => session.id), [
      newer.id,
    ]);
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
    final stored = await fixture.chats.listMessages(
      fixture.controller.currentSessionId!,
    );
    expect(
      AgentThinkingTrace.tryDecode(stored.first.reasoningContent)?.status,
      AgentThinkingStatus.stopped,
    );
  });

  test('cancel during credential read is sticky and starts no HTTP', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    final credentialRead = fixture.credentials.blockNextRead();
    fixture.adapter.replyNext('must not be used');

    final send = fixture.controller.sendMessage('Cancelled before local work');
    await credentialRead.started.future;
    fixture.controller.cancelActiveRequest();
    credentialRead.release.complete();
    await send;

    expect(fixture.adapter.calls, 0);
    expect(await fixture.chats.listSessions(), isEmpty);
    expect(fixture.controller.error, isNull);
  });

  test(
    'dispose during context load prevents HTTP and retains retry id',
    () async {
      await fixture.storeConfiguration();
      await fixture.controller.bootstrap();
      final contextLoad = fixture.chats.blockNextMessageLoad();
      fixture.adapter.replyNext('must not be used');

      final send = fixture.controller.sendMessage('Committed before dispose');
      await contextLoad.started.future;
      fixture.disposeController();
      contextLoad.release.complete();
      await send;

      expect(fixture.adapter.calls, 0);
      final session = (await fixture.chats.listSessions()).single;
      expect(
        (await fixture.chats.listMessages(session.id)).single.content,
        'Committed before dispose',
      );
      expect(fixture.controller.canRetry, isTrue);
    },
  );

  test(
    'context read failure leaves persisted user retryable without duplicate',
    () async {
      await fixture.storeConfiguration();
      await fixture.controller.bootstrap();
      fixture.chats.failNextMessageLoad = true;
      fixture.adapter.replyNext('Recovered after local read');

      await fixture.controller.sendMessage('One durable user');

      final session = (await fixture.chats.listSessions()).single;
      expect((await fixture.chats.listMessages(session.id)), hasLength(1));
      expect(fixture.controller.canRetry, isTrue);
      expect(fixture.adapter.calls, 0);

      await fixture.controller.retryFailedMessage();

      final stored = await fixture.chats.listMessages(session.id);
      expect(stored.map((message) => message.role), ['user', 'assistant']);
      expect(stored.where((message) => message.isUser), hasLength(1));
      expect(fixture.adapter.calls, 1);
    },
  );

  test(
    'pending user remains retryable after navigating away and back',
    () async {
      await fixture.storeConfiguration();
      final other = await fixture.chats.createSession(
        profileId: remoteProfile.id,
        model: remoteProfile.model,
        title: 'Other session',
      );
      await fixture.chats.appendMessage(
        sessionId: other.id,
        role: 'user',
        content: 'Other question',
      );
      await fixture.chats.appendMessage(
        sessionId: other.id,
        role: 'assistant',
        content: 'Other answer',
      );
      await fixture.controller.bootstrap();
      await fixture.controller.startNewSession();
      fixture.chats.failNextMessageLoad = true;
      fixture.adapter.replyNext('Recovered after navigation');

      await fixture.controller.sendMessage('Pending in session A');

      final pendingSessionId = fixture.controller.currentSessionId!;
      final pendingBefore = await fixture.chats.listMessages(pendingSessionId);
      final pendingUserId = pendingBefore.single.id;
      await fixture.controller.openSession(other.id);
      await fixture.controller.openSession(pendingSessionId);

      expect(fixture.controller.canRetry, isTrue);
      await fixture.controller.retryFailedMessage();

      final stored = await fixture.chats.listMessages(pendingSessionId);
      expect(stored.map((message) => message.role), ['user', 'assistant']);
      expect(
        stored.where((message) => message.isUser).map((message) => message.id),
        [pendingUserId],
      );
      expect(fixture.adapter.calls, 1);
      expect(fixture.adapter.jsonBodies.single['messages'], [
        {'role': 'user', 'content': 'Pending in session A'},
      ]);
    },
  );

  test(
    'pending user blocks a new send after navigating away and back',
    () async {
      await fixture.storeConfiguration();
      await fixture.controller.bootstrap();
      fixture.chats.failNextMessageLoad = true;

      await fixture.controller.sendMessage('Pending in session A');

      final pendingSessionId = fixture.controller.currentSessionId!;
      final pendingUser = (await fixture.chats.listMessages(
        pendingSessionId,
      )).single;
      await fixture.controller.startNewSession();
      expect(fixture.controller.currentSessionId, isNull);
      await fixture.controller.openSession(pendingSessionId);
      fixture.adapter.replyNext('must not be used');

      await fixture.controller.sendMessage('Do not append a second user');

      final stored = await fixture.chats.listMessages(pendingSessionId);
      expect(fixture.controller.canRetry, isTrue);
      expect(fixture.controller.error, isNotNull);
      expect(fixture.adapter.calls, 0);
      expect(stored, hasLength(1));
      expect(stored.single.id, pendingUser.id);
      expect(stored.single.content, 'Pending in session A');
    },
  );

  test(
    'profile save failure preserves durable and in-memory configuration',
    () async {
      await fixture.storeConfiguration(credential: 'old-key');
      await fixture.controller.bootstrap();
      fixture.profiles.failNextSave = true;

      await fixture.controller.saveConfiguration(
        profile: replacementProfile,
        credential: 'new-key',
      );

      expect(await fixture.profiles.loadActive(), remoteProfile);
      expect(
        await fixture.credentials.read(aiCredentialId(remoteProfile)),
        'old-key',
      );
      expect(fixture.controller.profile, remoteProfile);
      expect(fixture.controller.hasCredential, isTrue);
      expect(fixture.controller.error, isNotNull);
    },
  );

  test(
    'credential write failure rolls profile back without losing old key',
    () async {
      await fixture.storeConfiguration(credential: 'old-key');
      await fixture.controller.bootstrap();
      fixture.credentials.failNextWrite = true;

      await fixture.controller.saveConfiguration(
        profile: replacementProfile,
        credential: 'new-key',
      );

      expect(await fixture.profiles.loadActive(), remoteProfile);
      expect(
        await fixture.credentials.read(aiCredentialId(remoteProfile)),
        'old-key',
      );
      expect(fixture.controller.profile, remoteProfile);
      expect(fixture.controller.hasCredential, isTrue);
      expect(fixture.controller.error, isNotNull);
    },
  );

  test('post-write status failure rolls profile and credential back', () async {
    await fixture.storeConfiguration(credential: 'old-key');
    await fixture.controller.bootstrap();
    fixture.credentials.failNextHas = true;

    await fixture.controller.saveConfiguration(
      profile: replacementProfile,
      credential: 'new-key',
    );

    expect(await fixture.profiles.loadActive(), remoteProfile);
    expect(
      await fixture.credentials.read(aiCredentialId(remoteProfile)),
      'old-key',
    );
    expect(fixture.controller.profile, remoteProfile);
    expect(fixture.controller.hasCredential, isTrue);
    expect(fixture.controller.error, isNotNull);
  });

  test(
    'latest openSession wins when message loads complete out of order',
    () async {
      await fixture.storeConfiguration();
      final older = await fixture.chats.createSession(
        profileId: remoteProfile.id,
        model: remoteProfile.model,
        title: 'Older',
      );
      await fixture.chats.appendMessage(
        sessionId: older.id,
        role: 'user',
        content: 'Older history',
      );
      final newer = await fixture.chats.createSession(
        profileId: remoteProfile.id,
        model: remoteProfile.model,
        title: 'Newer',
      );
      await fixture.chats.appendMessage(
        sessionId: newer.id,
        role: 'user',
        content: 'Newer history',
      );
      await fixture.controller.bootstrap();
      final oldLoad = fixture.chats.blockNextMessageLoad(sessionId: older.id);
      final newLoad = fixture.chats.blockNextMessageLoad(sessionId: newer.id);

      final openOlder = fixture.controller.openSession(older.id);
      await oldLoad.started.future;
      final openNewer = fixture.controller.openSession(newer.id);
      await newLoad.started.future;
      newLoad.release.complete();
      await openNewer;
      oldLoad.release.complete();
      await openOlder;

      expect(fixture.controller.currentSessionId, newer.id);
      expect(fixture.controller.messages.map((message) => message.content), [
        'Newer history',
      ]);
      expect(fixture.controller.loadingMessages, isFalse);
      expect(fixture.controller.error, isNull);
    },
  );

  test(
    'next send persists volatile assistant before building context',
    () async {
      await fixture.storeConfiguration();
      await fixture.controller.bootstrap();
      fixture.chats.failNextAssistantAppend = true;
      fixture.adapter.replyNext('First volatile answer');
      await fixture.controller.sendMessage('First user');
      fixture.adapter.replyNext('Second answer');

      await fixture.controller.sendMessage('Second user');

      final session = (await fixture.chats.listSessions()).single;
      final stored = await fixture.chats.listMessages(session.id);
      expect(stored.map((message) => message.content), [
        'First user',
        'First volatile answer',
        'Second user',
        'Second answer',
      ]);
      expect(fixture.controller.volatileAssistantMessage, isNull);
      expect(
        fixture.controller.messages.where((message) => message.id < 0),
        isEmpty,
      );
      expect(fixture.adapter.jsonBodies[1]['messages'], [
        {'role': 'user', 'content': 'First user'},
        {'role': 'assistant', 'content': 'First volatile answer'},
        {'role': 'user', 'content': 'Second user'},
      ]);
    },
  );

  test('failed volatile persistence blocks another user and HTTP', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    fixture.chats.failNextAssistantAppend = true;
    fixture.adapter.replyNext('Still volatile');
    await fixture.controller.sendMessage('First user');
    fixture.chats.failNextAssistantAppend = true;
    fixture.adapter.replyNext('must not be used');

    await fixture.controller.sendMessage('Must not append');

    final session = (await fixture.chats.listSessions()).single;
    expect(
      (await fixture.chats.listMessages(session.id)).map((m) => m.content),
      ['First user'],
    );
    expect(fixture.adapter.calls, 1);
    expect(
      fixture.controller.volatileAssistantMessage?.content,
      'Still volatile',
    );
  });

  test('failed volatile recovery blocks opening another session', () async {
    await fixture.storeConfiguration();
    final other = await fixture.chats.createSession(
      profileId: remoteProfile.id,
      model: remoteProfile.model,
      title: 'Other',
    );
    await fixture.controller.bootstrap();
    await fixture.controller.startNewSession();
    fixture.chats.failNextAssistantAppend = true;
    fixture.adapter.replyNext('Stay visible');
    await fixture.controller.sendMessage('Current user');
    final currentId = fixture.controller.currentSessionId;
    fixture.chats.failNextAssistantAppend = true;

    await fixture.controller.openSession(other.id);

    expect(fixture.controller.currentSessionId, currentId);
    expect(
      fixture.controller.volatileAssistantMessage?.content,
      'Stay visible',
    );
    expect(fixture.controller.messages.last.content, 'Stay visible');
  });

  test(
    'concurrent volatile recovery appends once and latest navigation wins',
    () async {
      await fixture.storeConfiguration();
      final other = await fixture.chats.createSession(
        profileId: remoteProfile.id,
        model: remoteProfile.model,
        title: 'Other session',
      );
      await fixture.controller.bootstrap();
      await fixture.controller.startNewSession();
      fixture.chats.failNextAssistantAppend = true;
      fixture.adapter.replyNext('Recover exactly once');
      await fixture.controller.sendMessage('Session A user');
      final volatileSessionId = fixture.controller.currentSessionId!;
      final assistantAppend = fixture.chats.blockNextAssistantAppend();

      final openOther = fixture.controller.openSession(other.id);
      await assistantAppend.started.future;
      final startNew = fixture.controller.startNewSession();
      await Future<void>.delayed(Duration.zero);
      assistantAppend.release.complete();
      await Future.wait([openOther, startNew]);

      final stored = await fixture.chats.listMessages(volatileSessionId);
      expect(stored.map((message) => message.role), ['user', 'assistant']);
      expect(
        stored.where((message) => message.isAssistant).single.content,
        'Recover exactly once',
      );
      expect(fixture.controller.currentSessionId, isNull);
      expect(fixture.controller.messages, isEmpty);
      expect(fixture.controller.volatileAssistantMessage, isNull);
    },
  );

  test('blank credential retains the existing credential', () async {
    await fixture.storeConfiguration(credential: 'existing-key');

    await fixture.controller.saveConfiguration(
      profile: replacementProfile,
      credential: '   ',
    );

    expect(
      await fixture.credentials.read(aiCredentialId(replacementProfile)),
      'existing-key',
    );
    expect(await fixture.profiles.loadActive(), replacementProfile);
    expect(fixture.controller.hasCredential, isTrue);
  });

  test(
    'provider credentials are isolated and restored when switching back',
    () async {
      await fixture.storeConfiguration(credential: 'openai-only-key');
      await fixture.controller.bootstrap();
      const deepSeek = AiProviderProfile(
        id: 'primary',
        provider: 'deepseek',
        displayName: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-chat',
        requiresCredential: true,
      );

      await fixture.controller.saveConfiguration(
        profile: deepSeek,
        credential: '',
      );

      expect(fixture.controller.hasCredential, isFalse);
      expect(fixture.controller.needsConfiguration, isTrue);
      fixture.adapter.replyNext('must not be requested');
      await fixture.controller.sendMessage('do not leak the old key');
      expect(fixture.adapter.calls, 0);

      await fixture.controller.saveConfiguration(
        profile: deepSeek,
        credential: 'deepseek-only-key',
      );
      await fixture.controller.sendMessage('use the new provider key');
      expect(
        fixture.adapter.authorizationHeaders.single,
        'Bearer deepseek-only-key',
      );
      expect(
        fixture.adapter.authorizationHeaders.single,
        isNot(contains('openai-only-key')),
      );

      await fixture.controller.deleteCredential();
      expect(await fixture.credentials.read(aiCredentialId(deepSeek)), isNull);
      expect(
        await fixture.credentials.read(aiCredentialId(remoteProfile)),
        'openai-only-key',
      );

      await fixture.controller.saveConfiguration(
        profile: remoteProfile,
        credential: '',
      );
      expect(fixture.controller.hasCredential, isTrue);
      expect(fixture.controller.needsConfiguration, isFalse);
      fixture.adapter.replyNext('openai answer');
      await fixture.controller.sendMessage('use restored OpenAI key');
      expect(
        fixture.adapter.authorizationHeaders.last,
        'Bearer openai-only-key',
      );
      expect(
        fixture.adapter.authorizationHeaders.last,
        isNot(contains('deepseek-only-key')),
      );
    },
  );

  test(
    'bootstrap migrates the legacy slot only for the persisted provider',
    () async {
      await fixture.profiles.saveActive(remoteProfile);
      await fixture.credentials.write(remoteProfile.id, 'legacy-openai-key');

      await fixture.controller.bootstrap();

      expect(await fixture.credentials.read(remoteProfile.id), isNull);
      expect(
        await fixture.credentials.read(aiCredentialId(remoteProfile)),
        'legacy-openai-key',
      );
      expect(fixture.controller.hasCredential, isTrue);
    },
  );

  test('replacement credential is written without being exposed', () async {
    await fixture.storeConfiguration(credential: 'existing-key');

    await fixture.controller.saveConfiguration(
      profile: replacementProfile,
      credential: ' replacement-key ',
    );

    expect(
      await fixture.credentials.read(aiCredentialId(replacementProfile)),
      'replacement-key',
    );
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

    expect(
      await fixture.credentials.read(aiCredentialId(remoteProfile)),
      isNull,
    );
    expect(fixture.controller.needsConfiguration, isTrue);
    expect((await fixture.chats.listSessions()).single.id, session.id);
  });

  test(
    'concurrent configuration saves finish with latest invocation',
    () async {
      final firstSave = fixture.profiles.blockNextSave();
      final saveA = fixture.controller.saveConfiguration(
        profile: remoteProfile,
        credential: 'openai-key',
      );
      await firstSave.started.future;
      const deepSeek = AiProviderProfile(
        id: 'primary',
        provider: 'deepseek',
        displayName: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-chat',
        requiresCredential: true,
      );
      final saveB = fixture.controller.saveConfiguration(
        profile: deepSeek,
        credential: 'deepseek-key',
      );
      await Future<void>.delayed(Duration.zero);
      firstSave.release.complete();
      await Future.wait([saveA, saveB]);

      expect(await fixture.profiles.loadActive(), deepSeek);
      expect(fixture.controller.profile, deepSeek);
      expect(fixture.controller.hasCredential, isTrue);
    },
  );

  test('late bootstrap cannot overwrite a newer save', () async {
    await fixture.storeConfiguration();
    final oldLoad = fixture.profiles.blockNextLoad();
    final bootstrap = fixture.controller.bootstrap();
    await oldLoad.started.future;
    final save = fixture.controller.saveConfiguration(
      profile: replacementProfile,
      credential: 'replacement-key',
    );
    oldLoad.release.complete();
    await Future.wait([bootstrap, save]);

    expect(await fixture.profiles.loadActive(), replacementProfile);
    expect(fixture.controller.profile, replacementProfile);
    expect(fixture.controller.hasCredential, isTrue);
  });

  test('delete then save is serialized without memory durable split', () async {
    await fixture.storeConfiguration();
    await fixture.controller.bootstrap();
    final blockedDelete = fixture.credentials.blockNextDelete();
    final deletion = fixture.controller.deleteCredential();
    await blockedDelete.started.future;
    final save = fixture.controller.saveConfiguration(
      profile: replacementProfile,
      credential: 'new-key',
    );
    blockedDelete.release.complete();
    await Future.wait([deletion, save]);

    expect(await fixture.profiles.loadActive(), replacementProfile);
    expect(fixture.controller.profile, replacementProfile);
    expect(fixture.controller.hasCredential, isTrue);
    expect(
      await fixture.credentials.read(aiCredentialId(replacementProfile)),
      'new-key',
    );
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
    profiles = _ControlledProfileStore(AiProfileRepository(preferences));
    chats = _ControlledChatStore(
      AgentChatRepository(database, operationCoordinator: coordinator),
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
  late final _ControlledProfileStore profiles;
  late final _ControlledChatStore chats;
  late final OpenAiCompatibleChatClient client;
  late final AgentController controller;
  bool _databaseClosed = false;
  bool _controllerDisposed = false;

  Future<void> storeConfiguration({String credential = 'test-key'}) async {
    await profiles.saveActive(remoteProfile);
    await credentials.write(aiCredentialId(remoteProfile), credential);
  }

  Future<void> closeDatabase() async {
    if (_databaseClosed) return;
    _databaseClosed = true;
    await database.close();
  }

  void disposeController() {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    controller.dispose();
  }
}

final class _MemoryCredentialStore implements AiCredentialStore {
  final Map<String, String> _values = <String, String>{};
  _AsyncGate? _blockedRead;
  _AsyncGate? _blockedDelete;
  bool failNextWrite = false;
  bool failNextHas = false;

  _AsyncGate blockNextRead() {
    final gate = _AsyncGate();
    _blockedRead = gate;
    return gate;
  }

  _AsyncGate blockNextDelete() => _blockedDelete = _AsyncGate();

  @override
  Future<void> delete(String profileId) async {
    final gate = _blockedDelete;
    if (gate != null) {
      _blockedDelete = null;
      gate.started.complete();
      await gate.release.future;
    }
    _values.remove(profileId);
  }

  @override
  Future<bool> has(String profileId) async {
    if (failNextHas) {
      failNextHas = false;
      throw const AiCredentialException();
    }
    return _values.containsKey(profileId);
  }

  @override
  Future<String?> read(String profileId) async {
    final gate = _blockedRead;
    if (gate != null) {
      _blockedRead = null;
      gate.started.complete();
      await gate.release.future;
    }
    return _values[profileId];
  }

  @override
  Future<void> write(String profileId, String secret) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const AiCredentialException();
    }
    _values[profileId] = secret;
  }
}

final class _ControlledProfileStore implements AiProfileStore {
  _ControlledProfileStore(this._delegate);

  final AiProfileRepository _delegate;
  bool failNextSave = false;
  _AsyncGate? _blockedSave;
  _AsyncGate? _blockedLoad;

  _AsyncGate blockNextSave() => _blockedSave = _AsyncGate();
  _AsyncGate blockNextLoad() => _blockedLoad = _AsyncGate();

  @override
  Future<void> clearActive() => _delegate.clearActive();

  @override
  Future<AiProviderProfile?> loadActive() async {
    final snapshot = await _delegate.loadActive();
    final gate = _blockedLoad;
    if (gate != null) {
      _blockedLoad = null;
      gate.started.complete();
      await gate.release.future;
    }
    return snapshot;
  }

  @override
  Future<void> saveActive(AiProviderProfile profile) {
    if (failNextSave) {
      failNextSave = false;
      return Future<void>.error(StateError('controlled profile save failure'));
    }
    final gate = _blockedSave;
    if (gate == null) return _delegate.saveActive(profile);
    _blockedSave = null;
    return () async {
      gate.started.complete();
      await gate.release.future;
      await _delegate.saveActive(profile);
    }();
  }
}

final class _ControlledChatStore implements AgentChatStore {
  _ControlledChatStore(this._delegate);

  final AgentChatRepository _delegate;
  final List<_MessageLoadGate> _messageLoadGates = <_MessageLoadGate>[];
  _AsyncGate? _blockedAssistantAppend;
  bool failNextMessageLoad = false;
  bool failNextAssistantAppend = false;

  _AsyncGate blockNextMessageLoad({int? sessionId}) {
    final gate = _AsyncGate();
    _messageLoadGates.add(_MessageLoadGate(sessionId: sessionId, gate: gate));
    return gate;
  }

  _AsyncGate blockNextAssistantAppend() {
    final gate = _AsyncGate();
    _blockedAssistantAppend = gate;
    return gate;
  }

  @override
  Future<AgentChatMessage> appendMessage({
    required int sessionId,
    required String role,
    required String content,
    String? reasoningContent,
    String? model,
  }) async {
    if (role == 'assistant' && failNextAssistantAppend) {
      failNextAssistantAppend = false;
      throw StateError('controlled assistant append failure');
    }
    if (role == 'assistant') {
      final gate = _blockedAssistantAppend;
      if (gate != null) {
        _blockedAssistantAppend = null;
        gate.started.complete();
        await gate.release.future;
      }
    }
    return _delegate.appendMessage(
      sessionId: sessionId,
      role: role,
      content: content,
      reasoningContent: reasoningContent,
      model: model,
    );
  }

  @override
  Future<AgentChatSession> createSession({
    required String profileId,
    required String model,
    required String title,
  }) {
    return _delegate.createSession(
      profileId: profileId,
      model: model,
      title: title,
    );
  }

  @override
  Future<void> deleteSession(int sessionId) =>
      _delegate.deleteSession(sessionId);

  @override
  Future<List<AgentChatMessage>> listMessages(int sessionId) async {
    if (failNextMessageLoad) {
      failNextMessageLoad = false;
      throw StateError('controlled message load failure');
    }
    final gateIndex = _messageLoadGates.indexWhere(
      (candidate) =>
          candidate.sessionId == null || candidate.sessionId == sessionId,
    );
    if (gateIndex >= 0) {
      final blocked = _messageLoadGates.removeAt(gateIndex).gate;
      blocked.started.complete();
      await blocked.release.future;
    }
    return _delegate.listMessages(sessionId);
  }

  @override
  Future<List<AgentChatSession>> listSessions() => _delegate.listSessions();

  @override
  Future<AgentChatMessage> updateMessageReasoningContent({
    required int messageId,
    required String? reasoningContent,
  }) => _delegate.updateMessageReasoningContent(
    messageId: messageId,
    reasoningContent: reasoningContent,
  );

  @override
  Future<AgentChatSession> updateSessionAfterReply({
    required int sessionId,
    String? title,
    String? model,
  }) {
    return _delegate.updateSessionAfterReply(
      sessionId: sessionId,
      title: title,
      model: model,
    );
  }
}

final class _AsyncGate {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
}

final class _MessageLoadGate {
  const _MessageLoadGate({required this.sessionId, required this.gate});

  final int? sessionId;
  final _AsyncGate gate;
}

typedef _AdapterAction =
    Future<ResponseBody> Function(
      RequestOptions options,
      Future<void>? cancelFuture,
    );

final class _ScriptedAdapter implements HttpClientAdapter {
  final List<_AdapterAction> _actions = <_AdapterAction>[];
  final List<Map<String, Object?>> jsonBodies = <Map<String, Object?>>[];
  final List<Object?> authorizationHeaders = <Object?>[];
  int calls = 0;
  Completer<void> requestStarted = Completer<void>();
  Completer<ResponseBody>? _blocked;

  void replyNext(
    String content, {
    String model = 'model-a',
    String? reasoningContent,
  }) {
    _actions.add((options, cancelFuture) async {
      return _response(
        content,
        model: model,
        reasoningContent: reasoningContent,
      );
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
    authorizationHeaders.add(options.headers['authorization']);
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      if (bytes.isNotEmpty) {
        jsonBodies.add(
          Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map),
        );
      }
    }
    if (!requestStarted.isCompleted) requestStarted.complete();
    if (_actions.isEmpty) {
      throw StateError('No scripted HTTP response');
    }
    return _actions.removeAt(0)(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}

  ResponseBody _response(
    String content, {
    required String model,
    String? reasoningContent,
  }) {
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': content,
              'reasoning_content': ?reasoningContent,
            },
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
