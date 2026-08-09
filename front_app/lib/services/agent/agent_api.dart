import '../../core/network/api_client.dart';
import 'agent_models.dart';

class AgentApi {
  AgentApi(this._client);

  final ApiClient _client;

  Future<List<AgentChatSession>> listSessions() {
    return _client.getData<List<AgentChatSession>>(
      '/api/v1/agent/sessions',
      fromJson: (json) {
        final list = json as List<dynamic>;
        return list
            .map(
              (item) => AgentChatSession.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      },
    );
  }

  Future<AgentChatSession> createSession({
    String? title,
    String mode = 'fast',
    String? contextType,
    int? documentId,
    int? annotationId,
    String? selectedText,
  }) {
    return _client.postData<AgentChatSession>(
      '/api/v1/agent/sessions',
      data: {
        if (title != null && title.isNotEmpty) 'title': title,
        'mode': mode,
        if (contextType != null) 'contextType': contextType,
        if (documentId != null) 'documentId': documentId,
        if (annotationId != null) 'annotationId': annotationId,
        if (selectedText != null && selectedText.isNotEmpty)
          'selectedText': selectedText,
      },
      fromJson: (json) =>
          AgentChatSession.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<List<AgentChatMessage>> listMessages(int sessionId) {
    return _client.getData<List<AgentChatMessage>>(
      '/api/v1/agent/sessions/$sessionId/messages',
      fromJson: (json) {
        final list = json as List<dynamic>;
        return list
            .map(
              (item) => AgentChatMessage.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      },
    );
  }

  Future<AgentChatReply> sendMessage({
    required int sessionId,
    required String content,
    required String mode,
    bool deepThinking = false,
    String? provider,
    String? baseUrl,
    String? modelName,
    String? apiKey,
  }) {
    return _client.postData<AgentChatReply>(
      '/api/v1/agent/sessions/$sessionId/messages',
      data: {
        'content': content,
        'mode': mode,
        'deepThinking': deepThinking,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        if (baseUrl != null && baseUrl.isNotEmpty) 'baseUrl': baseUrl,
        if (modelName != null && modelName.isNotEmpty) 'modelName': modelName,
        if (apiKey != null && apiKey.isNotEmpty) 'apiKey': apiKey,
      },
      fromJson: (json) => AgentChatReply.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<void> deleteSession(int sessionId) {
    return _client.deleteVoid('/api/v1/agent/sessions/$sessionId');
  }
}
