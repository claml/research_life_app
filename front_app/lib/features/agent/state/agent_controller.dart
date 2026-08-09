import 'package:flutter/foundation.dart';

import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../services/agent/agent_api.dart';
import '../../../services/agent/agent_models.dart';
import '../../../services/analysis/llm_provider_presets.dart';

enum AgentChatMode { fast, expert }

class AgentController extends ChangeNotifier {
  AgentController({required AgentApi api}) : _api = api;

  final AgentApi _api;

  final List<AgentChatSession> sessions = <AgentChatSession>[];
  final List<AgentChatMessage> messages = <AgentChatMessage>[];

  AgentChatMode mode = AgentChatMode.fast;
  bool deepThinking = false;
  bool loadingSessions = false;
  bool loadingMessages = false;
  bool sending = false;
  String? error;
  int? currentSessionId;

  bool get hasSession => currentSessionId != null;
  bool get isBusy => loadingSessions || loadingMessages || sending;

  AgentChatSession? get currentSession {
    if (currentSessionId == null) return null;
    for (final session in sessions) {
      if (session.id == currentSessionId) return session;
    }
    return null;
  }

  Future<void> bootstrap() async {
    await refreshSessions();
    if (sessions.isNotEmpty && currentSessionId == null) {
      await openSession(sessions.first.id);
    }
  }

  Future<void> refreshSessions() async {
    loadingSessions = true;
    error = null;
    notifyListeners();
    try {
      final loaded = await _api.listSessions();
      sessions
        ..clear()
        ..addAll(loaded);
    } on ApiException catch (ex) {
      error = ex.message;
    } catch (ex) {
      error = '加载对话列表失败：$ex';
    } finally {
      loadingSessions = false;
      notifyListeners();
    }
  }

  Future<void> startNewSession({String? selectedText}) async {
    sending = true;
    error = null;
    notifyListeners();
    try {
      final session = await _api.createSession(
        mode: _modeValue(mode),
        contextType: selectedText != null ? 'reading' : 'general',
        selectedText: selectedText,
      );
      sessions.insert(0, session);
      await openSession(session.id);
    } on ApiException catch (ex) {
      error = ex.message;
    } catch (ex) {
      error = '创建对话失败：$ex';
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> openSession(int sessionId) async {
    currentSessionId = sessionId;
    loadingMessages = true;
    error = null;
    messages.clear();
    notifyListeners();
    try {
      final loaded = await _api.listMessages(sessionId);
      messages.addAll(loaded);
      final session = currentSession;
      if (session != null) {
        mode = session.mode == 'expert'
            ? AgentChatMode.expert
            : AgentChatMode.fast;
      }
    } on ApiException catch (ex) {
      error = ex.message;
    } catch (ex) {
      error = '加载消息失败：$ex';
    } finally {
      loadingMessages = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(
    String content, {
    AgentLlmSettings? llmSettings,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || sending) return;

    sending = true;
    error = null;
    notifyListeners();

    try {
      int? sessionId = currentSessionId;
      if (sessionId == null) {
        final session = await _api.createSession(mode: _modeValue(mode));
        sessions.insert(0, session);
        sessionId = session.id;
        currentSessionId = sessionId;
      }

      final reply = await _api.sendMessage(
        sessionId: sessionId,
        content: trimmed,
        mode: _modeValue(mode),
        deepThinking: deepThinking,
        provider: llmSettings?.provider,
        baseUrl: llmSettings == null
            ? null
            : llmResolveBaseUrl(
                provider: llmSettings.provider,
                baseUrl: llmSettings.baseUrl,
              ),
        modelName: llmSettings == null
            ? null
            : llmResolveModelName(
                provider: llmSettings.provider,
                modelName: llmSettings.modelName,
              ),
        apiKey: llmSettings?.hasApiKey == true
            ? llmSettings!.apiKey!.trim()
            : null,
      );

      _upsertSession(reply.session);
      messages.add(reply.userMessage);
      messages.add(reply.assistantMessage);
    } on ApiException catch (ex) {
      error = ex.message;
    } catch (ex) {
      error = '发送失败：$ex';
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> deleteSession(int sessionId) async {
    try {
      await _api.deleteSession(sessionId);
      sessions.removeWhere((item) => item.id == sessionId);
      if (currentSessionId == sessionId) {
        currentSessionId = null;
        messages.clear();
        if (sessions.isNotEmpty) {
          await openSession(sessions.first.id);
        }
      }
    } on ApiException catch (ex) {
      error = ex.message;
    } catch (ex) {
      error = '删除失败：$ex';
    }
    notifyListeners();
  }

  void setMode(AgentChatMode next) {
    mode = next;
    notifyListeners();
  }

  void setDeepThinking(bool value) {
    deepThinking = value;
    notifyListeners();
  }

  void _upsertSession(AgentChatSession session) {
    final index = sessions.indexWhere((item) => item.id == session.id);
    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.insert(0, session);
    }
    sessions.sort((a, b) {
      final aTime =
          a.updateTime ??
          a.createTime ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          b.updateTime ??
          b.createTime ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }

  String _modeValue(AgentChatMode value) {
    return value == AgentChatMode.expert ? 'expert' : 'fast';
  }
}
