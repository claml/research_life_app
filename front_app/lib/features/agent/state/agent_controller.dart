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
    required AiProfileRepository profiles,
    required AiCredentialStore credentials,
    required AgentChatRepository chats,
    required OpenAiCompatibleChatClient client,
  }) : _profiles = profiles,
       _credentials = credentials,
       _chats = chats,
       _client = client;

  static const _newSessionTitle = '新对话';
  static const _sessionTitleLength = 30;

  final AiProfileRepository _profiles;
  final AiCredentialStore _credentials;
  final AgentChatRepository _chats;
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

  int? _failedUserMessageId;
  CancelToken? _activeCancelToken;
  bool _disposed = false;

  bool get hasSession => currentSessionId != null;
  bool get isBusy => loadingSessions || loadingMessages || sending;
  bool get needsConfiguration {
    final activeProfile = profile;
    return activeProfile == null ||
        (activeProfile.requiresCredential && !hasCredential);
  }

  bool get canRetry => _failedUserMessageId != null && !sending;

  AgentChatSession? get currentSession {
    final sessionId = currentSessionId;
    if (sessionId == null) return null;
    for (final session in sessions) {
      if (session.id == sessionId) return session;
    }
    return null;
  }

  Future<void> bootstrap() async {
    loadingSessions = true;
    loadingMessages = true;
    error = null;
    _notify();
    try {
      final loadedProfile = await _profiles.loadActive();
      final credentialAvailable = loadedProfile != null &&
          await _credentials.has(loadedProfile.id);
      final loadedSessions = await _chats.listSessions();
      final firstSession = loadedSessions.firstOrNull;
      final loadedMessages = firstSession == null
          ? const <AgentChatMessage>[]
          : await _chats.listMessages(firstSession.id);

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
      error = '无法加载本地 AI 数据。';
    } finally {
      loadingSessions = false;
      loadingMessages = false;
      _notify();
    }
  }

  Future<void> refreshSessions() async {
    loadingSessions = true;
    error = null;
    _notify();
    try {
      final loaded = await _chats.listSessions();
      sessions
        ..clear()
        ..addAll(loaded);
    } on Object {
      error = '无法加载本地会话。';
    } finally {
      loadingSessions = false;
      _notify();
    }
  }

  Future<void> saveConfiguration({
    required AiProviderProfile profile,
    String credential = '',
  }) async {
    error = null;
    _notify();
    try {
      await _profiles.saveActive(profile);
      final trimmedCredential = credential.trim();
      if (trimmedCredential.isNotEmpty) {
        await _credentials.write(profile.id, trimmedCredential);
      }
      this.profile = profile;
      hasCredential = await _credentials.has(profile.id);
    } on Object {
      error = '无法保存 AI 配置。';
    }
    _notify();
  }

  Future<void> deleteCredential() async {
    final activeProfile = profile;
    if (activeProfile == null) return;
    error = null;
    _notify();
    try {
      await _credentials.delete(activeProfile.id);
      hasCredential = false;
    } on Object {
      error = '无法删除 AI 凭据。';
    }
    _notify();
  }

  Future<void> startNewSession() async {
    if (sending) return;
    currentSessionId = null;
    messages.clear();
    error = null;
    _clearTransientMessageState();
    _notify();
  }

  Future<void> openSession(int sessionId) async {
    if (sending) return;
    currentSessionId = sessionId;
    loadingMessages = true;
    error = null;
    messages.clear();
    _clearTransientMessageState();
    _notify();
    try {
      messages.addAll(await _chats.listMessages(sessionId));
    } on Object {
      error = '无法加载本地消息。';
    } finally {
      loadingMessages = false;
      _notify();
    }
  }

  Future<void> deleteSession(int sessionId) async {
    if (sending) return;
    error = null;
    try {
      await _chats.deleteSession(sessionId);
      sessions.removeWhere((session) => session.id == sessionId);
      if (currentSessionId == sessionId) {
        currentSessionId = null;
        messages.clear();
        _clearTransientMessageState();
        if (sessions.isNotEmpty) {
          final next = sessions.first;
          currentSessionId = next.id;
          messages.addAll(await _chats.listMessages(next.id));
        }
      }
    } on Object {
      error = '无法删除本地会话。';
    }
    _notify();
  }

  Future<void> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || sending) return;

    sending = true;
    error = null;
    volatileAssistantMessage = null;
    _failedUserMessageId = null;
    _notify();
    try {
      final request = await _prepareRequest();
      if (request == null) return;

      AgentChatMessage userMessage;
      List<AgentChatMessage> context;
      try {
        var sessionId = currentSessionId;
        if (sessionId == null) {
          final session = await _chats.createSession(
            profileId: request.profile.id,
            model: request.profile.model,
            title: _newSessionTitle,
          );
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
        context = await _chats.listMessages(sessionId);
      } on Object {
        error = '无法保存本地消息，未发送网络请求。';
        return;
      }

      await _completePersistedUserMessage(
        request: request,
        userMessage: userMessage,
        context: context,
      );
    } finally {
      sending = false;
      _activeCancelToken = null;
      _notify();
    }
  }

  Future<void> retryFailedMessage() async {
    final failedId = _failedUserMessageId;
    final sessionId = currentSessionId;
    if (sending || failedId == null || sessionId == null) return;

    sending = true;
    error = null;
    volatileAssistantMessage = null;
    _notify();
    try {
      final request = await _prepareRequest();
      if (request == null) return;

      List<AgentChatMessage> context;
      AgentChatMessage userMessage;
      try {
        context = await _chats.listMessages(sessionId);
        userMessage = context.singleWhere(
          (message) => message.id == failedId && message.isUser,
        );
      } on Object {
        error = '无法读取待重试的本地消息。';
        return;
      }

      await _completePersistedUserMessage(
        request: request,
        userMessage: userMessage,
        context: context,
      );
    } finally {
      sending = false;
      _activeCancelToken = null;
      _notify();
    }
  }

  void cancelActiveRequest() {
    _activeCancelToken?.cancel();
  }

  void setMode(AgentChatMode next) {
    mode = next;
    _notify();
  }

  void setDeepThinking(bool value) {
    deepThinking = value;
    _notify();
  }

  Future<_PreparedRequest?> _prepareRequest() async {
    final activeProfile = profile;
    if (activeProfile == null) {
      error = '请先配置 AI 服务。';
      return null;
    }

    try {
      final credential = await _credentials.read(activeProfile.id);
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
      error = '无法读取 AI 凭据。';
      return null;
    }
  }

  Future<void> _completePersistedUserMessage({
    required _PreparedRequest request,
    required AgentChatMessage userMessage,
    required List<AgentChatMessage> context,
  }) async {
    final token = CancelToken();
    _activeCancelToken = token;
    AiChatCompletion completion;
    try {
      completion = await _client.complete(
        profile: request.profile,
        credential: request.credential,
        messages: [
          for (final message in context)
            AiChatTurn(role: message.role, content: message.content),
        ],
        cancelToken: token,
      );
    } on AiChatClientException catch (failure) {
      _failedUserMessageId = userMessage.id;
      if (failure.kind != AiChatClientExceptionKind.cancelled) {
        error = failure.message;
      }
      return;
    } on Object {
      _failedUserMessageId = userMessage.id;
      error = 'AI 服务请求失败，请稍后重试。';
      return;
    } finally {
      if (identical(_activeCancelToken, token)) {
        _activeCancelToken = null;
      }
    }

    final sessionId = userMessage.sessionId;
    AgentChatMessage assistantMessage;
    try {
      assistantMessage = await _chats.appendMessage(
        sessionId: sessionId,
        role: 'assistant',
        content: completion.content,
        reasoningContent: completion.reasoningContent,
        model: completion.model ?? request.profile.model,
      );
    } on Object {
      final volatileMessage = AgentChatMessage(
        id: -1,
        sessionId: sessionId,
        role: 'assistant',
        content: completion.content,
        reasoningContent: completion.reasoningContent,
        model: completion.model ?? request.profile.model,
        createdAt: DateTime.now(),
      );
      volatileAssistantMessage = volatileMessage;
      messages.add(volatileMessage);
      _failedUserMessageId = null;
      error = '回答已生成，但未能写入本地历史。';
      return;
    }

    messages.add(assistantMessage);
    volatileAssistantMessage = null;
    _failedUserMessageId = null;
    try {
      final activeSession = currentSession;
      final updated = await _chats.updateSessionAfterReply(
        sessionId: sessionId,
        title: activeSession?.title == _newSessionTitle
            ? _titleFor(userMessage.content)
            : null,
        model: completion.model ?? request.profile.model,
      );
      _upsertSession(updated);
    } on Object {
      error = '回答已保存，但会话信息更新失败。';
    }
  }

  void _clearTransientMessageState() {
    _failedUserMessageId = null;
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
    _disposed = true;
    _activeCancelToken?.cancel();
    _activeCancelToken = null;
    super.dispose();
  }
}

final class _PreparedRequest {
  const _PreparedRequest({required this.profile, required this.credential});

  final AiProviderProfile profile;
  final String? credential;
}
