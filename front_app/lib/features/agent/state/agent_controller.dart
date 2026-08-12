import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../services/agent/agent_models.dart';
import '../../../services/agent/ai_credential_store.dart';
import '../../../services/agent/ai_profile.dart';
import '../../../services/agent/ai_profile_repository.dart';
import '../../../services/agent/openai_compatible_chat_client.dart';
import '../../../services/database/repositories/agent_chat_repository.dart';

enum AgentChatMode { fast, expert }

class AgentController extends ChangeNotifier {
  AgentController({
    required AiProfileStore profiles,
    required AiCredentialStore credentials,
    required AgentChatStore chats,
    required OpenAiCompatibleChatClient client,
  }) : _profiles = profiles,
       _credentials = credentials,
       _chats = chats,
       _client = client;

  static const _newSessionTitle = '新对话';
  static const _sessionTitleLength = 30;

  final AiProfileStore _profiles;
  final AiCredentialStore _credentials;
  final AgentChatStore _chats;
  final OpenAiCompatibleChatClient _client;

  final List<AgentChatSession> sessions = <AgentChatSession>[];
  final List<AgentChatMessage> messages = <AgentChatMessage>[];

  AiProviderProfile? profile;
  bool hasCredential = false;
  AgentChatMode mode = AgentChatMode.fast;
  bool deepThinking = false;
  bool loadingSessions = false;
  bool loadingMessages = false;
  bool sending = false;
  String? error;
  int? currentSessionId;
  AgentChatMessage? volatileAssistantMessage;

  final Map<int, int> _failedUserMessageIds = <int, int>{};
  _PendingSessionUpdate? _pendingSessionUpdate;
  Future<bool>? _volatileRecoveryFuture;
  _AgentOperation? _activeOperation;
  int _nextOperationId = 0;
  int _messageLoadGeneration = 0;
  Future<void> _configurationQueue = Future<void>.value();
  bool _disposed = false;

  bool get hasSession => currentSessionId != null;
  bool get isBusy => loadingSessions || loadingMessages || sending;
  bool get needsConfiguration {
    final activeProfile = profile;
    return activeProfile == null ||
        (activeProfile.requiresCredential && !hasCredential);
  }

  bool get canRetry {
    final sessionId = currentSessionId;
    return sessionId != null &&
        _failedUserMessageIds.containsKey(sessionId) &&
        !sending;
  }

  AgentChatSession? get currentSession {
    final sessionId = currentSessionId;
    if (sessionId == null) return null;
    for (final session in sessions) {
      if (session.id == sessionId) return session;
    }
    return null;
  }

  Future<void> bootstrap() => _enqueueConfiguration(_bootstrap);

  Future<void> _bootstrap() async {
    final generation = ++_messageLoadGeneration;
    loadingSessions = true;
    loadingMessages = true;
    error = null;
    _notify();
    try {
      final loadedProfile = await _profiles.loadActive();
      final credentialAvailable =
          loadedProfile != null &&
          await _hasCredentialFor(loadedProfile, migrateLegacy: true);
      final loadedSessions = await _chats.listSessions();
      final firstSession = loadedSessions.firstOrNull;
      final loadedMessages = firstSession == null
          ? const <AgentChatMessage>[]
          : await _chats.listMessages(firstSession.id);
      if (_disposed || generation != _messageLoadGeneration) return;

      profile = loadedProfile;
      hasCredential = credentialAvailable;
      sessions
        ..clear()
        ..addAll(loadedSessions);
      currentSessionId = firstSession?.id;
      messages
        ..clear()
        ..addAll(loadedMessages);
      _clearTransientMessageState();
    } on Object {
      if (!_disposed && generation == _messageLoadGeneration) {
        error = '无法加载本地 AI 数据。';
      }
    } finally {
      if (!_disposed && generation == _messageLoadGeneration) {
        loadingSessions = false;
        loadingMessages = false;
        _notify();
      }
    }
  }

  Future<void> refreshSessions() async {
    loadingSessions = true;
    error = null;
    _notify();
    try {
      final loaded = await _chats.listSessions();
      if (_disposed) return;
      sessions
        ..clear()
        ..addAll(loaded);
    } on Object {
      if (!_disposed) error = '无法加载本地会话。';
    } finally {
      if (!_disposed) {
        loadingSessions = false;
        _notify();
      }
    }
  }

  Future<void> saveConfiguration({
    required AiProviderProfile profile,
    String credential = '',
  }) => _enqueueConfiguration(
    () => _saveConfiguration(profile: profile, credential: credential),
  );

  Future<void> _saveConfiguration({
    required AiProviderProfile profile,
    required String credential,
  }) async {
    final previousMemoryProfile = this.profile;
    final previousMemoryHasCredential = hasCredential;
    AiProviderProfile? previousProfile;
    String? previousTargetCredential;
    error = null;
    _notify();

    try {
      previousProfile = await _profiles.loadActive();
      previousTargetCredential = await _credentials.read(
        aiCredentialId(profile),
      );
    } on Object {
      await _reloadConfiguration(
        fallbackProfile: previousMemoryProfile,
        fallbackHasCredential: previousMemoryHasCredential,
      );
      error = '无法保存 AI 配置。';
      _notify();
      return;
    }

    var profileMayHaveChanged = false;
    var credentialMayHaveChanged = false;
    try {
      profileMayHaveChanged = true;
      await _profiles.saveActive(profile);
      final trimmedCredential = credential.trim();
      if (trimmedCredential.isNotEmpty) {
        credentialMayHaveChanged = true;
        await _credentials.write(aiCredentialId(profile), trimmedCredential);
      }
      final credentialAvailable = await _credentials.has(
        aiCredentialId(profile),
      );
      this.profile = profile;
      hasCredential = credentialAvailable;
    } on Object {
      if (credentialMayHaveChanged) {
        await _restoreCredential(
          aiCredentialId(profile),
          previousTargetCredential,
        );
      }
      if (profileMayHaveChanged) {
        await _restoreProfile(previousProfile);
      }
      await _reloadConfiguration(
        fallbackProfile: previousMemoryProfile,
        fallbackHasCredential: previousMemoryHasCredential,
      );
      error = '无法保存 AI 配置。';
    }
    _notify();
  }

  Future<void> deleteCredential() => _enqueueConfiguration(_deleteCredential);

  Future<void> _deleteCredential() async {
    final activeProfile = profile;
    if (activeProfile == null) return;
    error = null;
    _notify();
    try {
      final identity = aiCredentialId(activeProfile);
      final legacyOwner = await _credentials.read(
        _legacyCredentialOwnerId(activeProfile),
      );
      if (legacyOwner == identity) {
        await _credentials.delete(activeProfile.id);
      }
      await _credentials.delete(identity);
      if (legacyOwner == identity) {
        await _credentials.delete(_legacyCredentialOwnerId(activeProfile));
      }
      hasCredential = false;
    } on Object {
      error = '无法删除 AI 凭据。';
    }
    _notify();
  }

  Future<T> _enqueueConfiguration<T>(Future<T> Function() operation) {
    final result = _configurationQueue.then((_) => operation());
    _configurationQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<bool> hasCredentialFor(AiProviderProfile candidate) =>
      _credentials.has(aiCredentialId(candidate));

  Future<void> startNewSession() async {
    if (sending || _disposed) return;
    final generation = ++_messageLoadGeneration;
    if (!await _persistVolatileAssistant()) return;
    if (_disposed || generation != _messageLoadGeneration) return;
    currentSessionId = null;
    messages.clear();
    error = null;
    _clearTransientMessageState();
    _notify();
  }

  Future<void> openSession(int sessionId) async {
    if (sending || _disposed) return;
    final generation = ++_messageLoadGeneration;
    if (!await _persistVolatileAssistant()) return;
    if (_disposed || generation != _messageLoadGeneration) return;
    currentSessionId = sessionId;
    loadingMessages = true;
    error = null;
    messages.clear();
    _clearTransientMessageState();
    _notify();
    try {
      final loaded = await _chats.listMessages(sessionId);
      if (_disposed ||
          generation != _messageLoadGeneration ||
          currentSessionId != sessionId) {
        return;
      }
      messages
        ..clear()
        ..addAll(loaded);
    } on Object {
      if (!_disposed &&
          generation == _messageLoadGeneration &&
          currentSessionId == sessionId) {
        error = '无法加载本地消息。';
      }
    } finally {
      if (!_disposed &&
          generation == _messageLoadGeneration &&
          currentSessionId == sessionId) {
        loadingMessages = false;
        _notify();
      }
    }
  }

  Future<void> deleteSession(int sessionId) async {
    if (sending) return;
    if (currentSessionId == sessionId && !await _persistVolatileAssistant()) {
      return;
    }
    final generation = ++_messageLoadGeneration;
    error = null;
    try {
      await _chats.deleteSession(sessionId);
      _failedUserMessageIds.remove(sessionId);
      sessions.removeWhere((session) => session.id == sessionId);
      if (_disposed || generation != _messageLoadGeneration) return;
      if (currentSessionId == sessionId) {
        currentSessionId = null;
        messages.clear();
        _clearTransientMessageState();
        if (sessions.isNotEmpty) {
          final next = sessions.first;
          final loaded = await _chats.listMessages(next.id);
          if (_disposed || generation != _messageLoadGeneration) return;
          currentSessionId = next.id;
          messages
            ..clear()
            ..addAll(loaded);
        }
      }
    } on Object {
      if (!_disposed && generation == _messageLoadGeneration) {
        error = '无法删除本地会话。';
      }
    }
    if (!_disposed && generation == _messageLoadGeneration) _notify();
  }

  Future<void> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || sending || _disposed) return;
    final activeSessionId = currentSessionId;
    if (activeSessionId != null &&
        _failedUserMessageIds.containsKey(activeSessionId)) {
      error = '请先重试上一条消息。';
      _notify();
      return;
    }

    final operation = _beginOperation();
    sending = true;
    error = null;
    _notify();
    try {
      if (!await _persistVolatileAssistant(operation: operation)) return;
      if (_operationStopped(operation)) return;

      final request = await _prepareRequest(operation);
      if (request == null || _operationStopped(operation)) return;

      AgentChatMessage? userMessage;
      try {
        var sessionId = currentSessionId;
        if (sessionId == null) {
          final session = await _chats.createSession(
            profileId: request.profile.id,
            model: request.profile.model,
            title: _newSessionTitle,
          );
          if (_operationStopped(operation)) return;
          _upsertSession(session);
          sessionId = session.id;
          currentSessionId = session.id;
        }
        userMessage = await _chats.appendMessage(
          sessionId: sessionId,
          role: 'user',
          content: trimmed,
        );
        messages.add(userMessage);
        _failedUserMessageIds[sessionId] = userMessage.id;
        if (_operationStopped(operation)) return;

        final context = await _chats.listMessages(sessionId);
        if (_operationStopped(operation)) return;
        await _completePersistedUserMessage(
          operation: operation,
          request: request,
          userMessage: userMessage,
          context: context,
        );
      } on Object {
        if (!_operationStopped(operation)) {
          error = userMessage == null
              ? '无法保存本地消息，未发送网络请求。'
              : '无法读取本地消息，未发送网络请求。';
        }
      }
    } finally {
      _finishOperation(operation);
    }
  }

  Future<void> retryFailedMessage() async {
    final sessionId = currentSessionId;
    final failedId = sessionId == null
        ? null
        : _failedUserMessageIds[sessionId];
    if (sending || _disposed) return;
    if (failedId == null && volatileAssistantMessage == null) return;

    final operation = _beginOperation();
    sending = true;
    error = null;
    _notify();
    try {
      if (!await _persistVolatileAssistant(operation: operation)) return;
      if (_operationStopped(operation) ||
          failedId == null ||
          sessionId == null) {
        return;
      }

      final request = await _prepareRequest(operation);
      if (request == null || _operationStopped(operation)) return;

      try {
        final context = await _chats.listMessages(sessionId);
        if (_operationStopped(operation)) return;
        final userMessage = context.singleWhere(
          (message) => message.id == failedId && message.isUser,
        );
        await _completePersistedUserMessage(
          operation: operation,
          request: request,
          userMessage: userMessage,
          context: context,
        );
      } on Object {
        if (!_operationStopped(operation)) {
          error = '无法读取待重试的本地消息。';
        }
      }
    } finally {
      _finishOperation(operation);
    }
  }

  void cancelActiveRequest() {
    _activeOperation?.cancel();
  }

  void setMode(AgentChatMode next) {
    mode = next;
    _notify();
  }

  void setDeepThinking(bool value) {
    deepThinking = value;
    _notify();
  }

  Future<_PreparedRequest?> _prepareRequest(_AgentOperation operation) async {
    if (_operationStopped(operation)) return null;
    final activeProfile = profile;
    if (activeProfile == null) {
      error = '请先配置 AI 服务。';
      return null;
    }

    try {
      final credential = await _credentials.read(aiCredentialId(activeProfile));
      if (_operationStopped(operation)) return null;
      final trimmedCredential = credential?.trim();
      hasCredential = trimmedCredential != null && trimmedCredential.isNotEmpty;
      if (activeProfile.requiresCredential && !hasCredential) {
        error = '请重新输入 AI 凭据。';
        return null;
      }
      return _PreparedRequest(
        profile: activeProfile,
        credential: hasCredential ? trimmedCredential : null,
      );
    } on Object {
      if (!_operationStopped(operation)) error = '无法读取 AI 凭据。';
      return null;
    }
  }

  Future<void> _completePersistedUserMessage({
    required _AgentOperation operation,
    required _PreparedRequest request,
    required AgentChatMessage userMessage,
    required List<AgentChatMessage> context,
  }) async {
    if (_operationStopped(operation)) return;
    AiChatCompletion completion;
    try {
      completion = await _client.complete(
        profile: request.profile,
        credential: request.credential,
        messages: [
          for (final message in context)
            AiChatTurn(role: message.role, content: message.content),
        ],
        cancelToken: operation.cancelToken,
      );
    } on AiChatClientException catch (failure) {
      if (failure.kind != AiChatClientExceptionKind.cancelled &&
          !_operationStopped(operation)) {
        error = failure.message;
      }
      return;
    } on Object {
      if (!_operationStopped(operation)) {
        error = 'AI 服务请求失败，请稍后重试。';
      }
      return;
    }
    if (_operationStopped(operation)) return;

    final sessionId = userMessage.sessionId;
    AgentChatMessage assistantMessage;
    try {
      assistantMessage = await _chats.appendMessage(
        sessionId: sessionId,
        role: 'assistant',
        content: completion.content,
        reasoningContent: null,
        model: completion.model ?? request.profile.model,
      );
    } on Object {
      final volatileMessage = AgentChatMessage(
        id: -1,
        sessionId: sessionId,
        role: 'assistant',
        content: completion.content,
        reasoningContent: null,
        model: completion.model ?? request.profile.model,
        createdAt: DateTime.now(),
      );
      volatileAssistantMessage = volatileMessage;
      messages.add(volatileMessage);
      _failedUserMessageIds.remove(sessionId);
      if (!_operationStopped(operation)) {
        error = '回答已生成，但未能写入本地历史。';
      }
      return;
    }

    messages.add(assistantMessage);
    volatileAssistantMessage = null;
    _failedUserMessageIds.remove(sessionId);
    final pendingUpdate = _PendingSessionUpdate(
      sessionId: sessionId,
      userContent: userMessage.content,
      model: completion.model ?? request.profile.model,
    );
    if (_operationStopped(operation)) {
      _pendingSessionUpdate = pendingUpdate;
      return;
    }
    if (!await _updateSessionAfterAssistant(pendingUpdate)) {
      _pendingSessionUpdate = pendingUpdate;
    }
  }

  Future<bool> _persistVolatileAssistant({_AgentOperation? operation}) {
    final activeRecovery = _volatileRecoveryFuture;
    if (activeRecovery != null) return activeRecovery;

    late final Future<bool> recovery;
    recovery = _persistVolatileAssistantOnce(operation: operation).whenComplete(
      () {
        if (identical(_volatileRecoveryFuture, recovery)) {
          _volatileRecoveryFuture = null;
        }
      },
    );
    _volatileRecoveryFuture = recovery;
    return recovery;
  }

  Future<bool> _persistVolatileAssistantOnce({
    _AgentOperation? operation,
  }) async {
    final pendingUpdate = _pendingSessionUpdate;
    if (pendingUpdate != null) {
      if (!await _updateSessionAfterAssistant(pendingUpdate)) {
        if (operation != null && _operationStopped(operation)) error = null;
        return false;
      }
      _pendingSessionUpdate = null;
      error = null;
    }

    final volatileMessage = volatileAssistantMessage;
    if (volatileMessage == null) return true;
    if (currentSessionId != volatileMessage.sessionId) {
      error = '请先恢复当前会话的本地回答。';
      return false;
    }
    if (operation != null && _operationStopped(operation)) return false;

    AgentChatMessage persisted;
    try {
      persisted = await _chats.appendMessage(
        sessionId: volatileMessage.sessionId,
        role: 'assistant',
        content: volatileMessage.content,
        reasoningContent: null,
        model: volatileMessage.model,
      );
    } on Object {
      if (operation == null || !_operationStopped(operation)) {
        error = '回答尚未写入本地历史，请重试。';
      }
      return false;
    }

    final volatileIndex = messages.indexWhere(
      (message) =>
          message.id == volatileMessage.id &&
          message.sessionId == volatileMessage.sessionId,
    );
    if (volatileIndex >= 0) {
      messages[volatileIndex] = persisted;
    } else if (currentSessionId == persisted.sessionId) {
      messages.add(persisted);
    }
    volatileAssistantMessage = null;
    _failedUserMessageIds.remove(persisted.sessionId);

    AgentChatMessage? firstUser;
    for (final message in messages) {
      if (message.sessionId == persisted.sessionId && message.isUser) {
        firstUser = message;
        break;
      }
    }
    final recoveredUpdate = _PendingSessionUpdate(
      sessionId: persisted.sessionId,
      userContent: firstUser?.content ?? _newSessionTitle,
      model: persisted.model,
    );
    if (operation != null && _operationStopped(operation)) {
      _pendingSessionUpdate = recoveredUpdate;
      return false;
    }
    if (!await _updateSessionAfterAssistant(recoveredUpdate)) {
      _pendingSessionUpdate = recoveredUpdate;
      return false;
    }
    error = null;
    return true;
  }

  Future<bool> _updateSessionAfterAssistant(
    _PendingSessionUpdate pending,
  ) async {
    try {
      final activeSession = currentSession;
      final updated = await _chats.updateSessionAfterReply(
        sessionId: pending.sessionId,
        title: activeSession?.title == _newSessionTitle
            ? _titleFor(pending.userContent)
            : null,
        model: pending.model,
      );
      _upsertSession(updated);
      return true;
    } on Object {
      error = '回答已保存，但会话信息更新失败。';
      return false;
    }
  }

  Future<void> _restoreCredential(String profileId, String? credential) async {
    try {
      if (credential == null) {
        await _credentials.delete(profileId);
      } else {
        await _credentials.write(profileId, credential);
      }
    } on Object {
      // Best-effort compensation. Reload below remains the source of truth.
    }
  }

  Future<void> _restoreProfile(AiProviderProfile? previousProfile) async {
    try {
      if (previousProfile == null) {
        await _profiles.clearActive();
      } else {
        await _profiles.saveActive(previousProfile);
      }
    } on Object {
      // Best-effort compensation. Reload below remains the source of truth.
    }
  }

  Future<void> _reloadConfiguration({
    required AiProviderProfile? fallbackProfile,
    required bool fallbackHasCredential,
  }) async {
    try {
      final loaded = await _profiles.loadActive();
      final available = loaded != null && await _hasCredentialFor(loaded);
      profile = loaded;
      hasCredential = available;
    } on Object {
      profile = fallbackProfile;
      hasCredential = fallbackHasCredential;
    }
  }

  Future<bool> _hasCredentialFor(
    AiProviderProfile activeProfile, {
    bool migrateLegacy = false,
  }) async {
    final identity = aiCredentialId(activeProfile);
    final identityAvailable = await _credentials.has(identity);
    if (!migrateLegacy) return identityAvailable;

    // Legacy releases used the profile id (normally `primary`) as one shared
    // slot. It is only interpreted for the profile currently persisted at
    // migration time. A non-secret owner marker is written first, making a
    // partial migration fail closed even if a later Windows operation fails.
    final ownerId = _legacyCredentialOwnerId(activeProfile);
    final owner = await _credentials.read(ownerId);
    if (owner != null && owner != identity) return identityAvailable;
    final legacy = await _credentials.read(activeProfile.id);
    final trimmed = legacy?.trim();
    if (trimmed == null || trimmed.isEmpty) return identityAvailable;
    if (owner == null) await _credentials.write(ownerId, identity);
    if (!identityAvailable) await _credentials.write(identity, trimmed);
    await _credentials.delete(activeProfile.id);
    return true;
  }

  String _legacyCredentialOwnerId(AiProviderProfile activeProfile) =>
      '${activeProfile.id}--legacy-owner';

  _AgentOperation _beginOperation() {
    final operation = _AgentOperation(++_nextOperationId);
    _activeOperation = operation;
    return operation;
  }

  bool _operationStopped(_AgentOperation operation) {
    return _disposed ||
        operation.cancelled ||
        !identical(_activeOperation, operation);
  }

  void _finishOperation(_AgentOperation operation) {
    if (identical(_activeOperation, operation)) {
      _activeOperation = null;
    }
    sending = false;
    _notify();
  }

  void _clearTransientMessageState() {
    _pendingSessionUpdate = null;
    volatileAssistantMessage = null;
  }

  void _upsertSession(AgentChatSession session) {
    final index = sessions.indexWhere((item) => item.id == session.id);
    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.add(session);
    }
    sessions.sort((a, b) {
      final byTime = b.updatedAt.compareTo(a.updatedAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
  }

  String _titleFor(String content) {
    final characters = content.runes.toList(growable: false);
    if (characters.length <= _sessionTitleLength) return content;
    return '${String.fromCharCodes(characters.take(_sessionTitleLength - 1))}…';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_messageLoadGeneration;
    _activeOperation?.cancel();
    _activeOperation = null;
    super.dispose();
  }
}

final class _AgentOperation {
  _AgentOperation(this.id);

  final int id;
  final CancelToken cancelToken = CancelToken();

  bool get cancelled => cancelToken.isCancelled;

  void cancel() {
    if (!cancelToken.isCancelled) cancelToken.cancel();
  }
}

final class _PreparedRequest {
  const _PreparedRequest({required this.profile, required this.credential});

  final AiProviderProfile profile;
  final String? credential;
}

final class _PendingSessionUpdate {
  const _PendingSessionUpdate({
    required this.sessionId,
    required this.userContent,
    required this.model,
  });

  final int sessionId;
  final String userContent;
  final String? model;
}
