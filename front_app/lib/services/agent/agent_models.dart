class AgentChatSession {
  const AgentChatSession({
    required this.id,
    required this.title,
    required this.profileId,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
    @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
    this.mode = 'fast',
    @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
    this.contextType,
    @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
    this.documentId,
    @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
    this.annotationId,
    @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
    this.selectedText,
  });

  final int id;
  final String title;
  final String profileId;
  final String model;
  final DateTime createdAt;
  final DateTime updatedAt;

  @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
  final String mode;

  @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
  final String? contextType;

  @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
  final int? documentId;

  @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
  final int? annotationId;

  @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
  final String? selectedText;

  @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
  DateTime? get createTime => createdAt;

  @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
  DateTime? get updateTime => updatedAt;

  @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
  factory AgentChatSession.fromJson(Map<String, dynamic> json) {
    final createdAt = _parseDate(json['createTime']) ?? _legacyEpoch;
    return AgentChatSession(
      id: _asInt(json['id']),
      title: '${json['title'] ?? 'New chat'}',
      profileId: '${json['profileId'] ?? 'legacy-remote'}',
      model: '${json['model'] ?? ''}',
      createdAt: createdAt,
      updatedAt: _parseDate(json['updateTime']) ?? createdAt,
      mode: '${json['mode'] ?? 'fast'}',
      contextType: json['contextType'] as String?,
      documentId: _nullableInt(json['documentId']),
      annotationId: _nullableInt(json['annotationId']),
      selectedText: json['selectedText'] as String?,
    );
  }
}

class AgentChatMessage {
  const AgentChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.reasoningContent,
    this.model,
  });

  final int id;
  final int sessionId;
  final String role;
  final String content;
  final String? reasoningContent;
  final String? model;
  final DateTime createdAt;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
  DateTime? get createTime => createdAt;

  @Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
  factory AgentChatMessage.fromJson(
    Map<String, dynamic> json, {
    int? fallbackSessionId,
  }) {
    return AgentChatMessage(
      id: _asInt(json['id']),
      sessionId: _nullableInt(json['sessionId']) ?? fallbackSessionId ?? 0,
      role: '${json['role'] ?? 'user'}',
      content: '${json['content'] ?? ''}',
      reasoningContent: json['reasoningContent'] as String?,
      model: json['model'] as String?,
      createdAt: _parseDate(json['createTime']) ?? _legacyEpoch,
    );
  }
}

final class AiChatTurn {
  const AiChatTurn({required this.role, required this.content});

  final String role;
  final String content;
}

final class AiChatCompletion {
  const AiChatCompletion({
    required this.content,
    this.reasoningContent,
    this.model,
    this.finishReason,
  });

  final String content;
  final String? reasoningContent;
  final String? model;
  final String? finishReason;
}

@Deprecated('Temporary AgentApi compatibility; remove in Task 5.')
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
    final session = AgentChatSession.fromJson(
      json['session'] as Map<String, dynamic>,
    );
    return AgentChatReply(
      userMessage: AgentChatMessage.fromJson(
        json['userMessage'] as Map<String, dynamic>,
        fallbackSessionId: session.id,
      ),
      assistantMessage: AgentChatMessage.fromJson(
        json['assistantMessage'] as Map<String, dynamic>,
        fallbackSessionId: session.id,
      ),
      session: session,
    );
  }
}

final DateTime _legacyEpoch = DateTime.fromMillisecondsSinceEpoch(
  0,
  isUtc: true,
);

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
