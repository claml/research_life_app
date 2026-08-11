class AgentChatSession {
  const AgentChatSession({
    required this.id,
    required this.title,
    required this.profileId,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String profileId;
  final String model;
  final DateTime createdAt;
  final DateTime updatedAt;
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
