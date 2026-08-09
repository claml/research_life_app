class AgentChatSession {
  const AgentChatSession({
    required this.id,
    required this.title,
    required this.mode,
    this.contextType,
    this.documentId,
    this.annotationId,
    this.selectedText,
    this.createTime,
    this.updateTime,
  });

  final int id;
  final String title;
  final String mode;
  final String? contextType;
  final int? documentId;
  final int? annotationId;
  final String? selectedText;
  final DateTime? createTime;
  final DateTime? updateTime;

  factory AgentChatSession.fromJson(Map<String, dynamic> json) {
    return AgentChatSession(
      id: _asInt(json['id']),
      title: '${json['title'] ?? '新对话'}',
      mode: '${json['mode'] ?? 'fast'}',
      contextType: json['contextType'] as String?,
      documentId: _nullableInt(json['documentId']),
      annotationId: _nullableInt(json['annotationId']),
      selectedText: json['selectedText'] as String?,
      createTime: _parseDate(json['createTime']),
      updateTime: _parseDate(json['updateTime']),
    );
  }
}

class AgentChatMessage {
  const AgentChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.reasoningContent,
    this.model,
    this.createTime,
  });

  final int id;
  final String role;
  final String content;
  final String? reasoningContent;
  final String? model;
  final DateTime? createTime;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory AgentChatMessage.fromJson(Map<String, dynamic> json) {
    return AgentChatMessage(
      id: _asInt(json['id']),
      role: '${json['role'] ?? 'user'}',
      content: '${json['content'] ?? ''}',
      reasoningContent: json['reasoningContent'] as String?,
      model: json['model'] as String?,
      createTime: _parseDate(json['createTime']),
    );
  }
}

class AgentChatReply {
  const AgentChatReply({
    required this.userMessage,
    required this.assistantMessage,
    required this.session,
  });

  final AgentChatMessage userMessage;
  final AgentChatMessage assistantMessage;
  final AgentChatSession session;

  factory AgentChatReply.fromJson(Map<String, dynamic> json) {
    return AgentChatReply(
      userMessage: AgentChatMessage.fromJson(
        json['userMessage'] as Map<String, dynamic>,
      ),
      assistantMessage: AgentChatMessage.fromJson(
        json['assistantMessage'] as Map<String, dynamic>,
      ),
      session: AgentChatSession.fromJson(
        json['session'] as Map<String, dynamic>,
      ),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  return _asInt(value);
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse('$value');
}
