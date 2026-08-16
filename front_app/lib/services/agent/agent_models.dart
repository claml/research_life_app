import 'dart:convert';

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

enum AgentThinkingStatus { active, completed, failed, stopped }

final class AgentThinkingTrace {
  const AgentThinkingTrace({required this.status, required this.steps});

  static const _kind = 'research_life_thinking_trace';

  final AgentThinkingStatus status;
  final List<String> steps;

  String encode() => jsonEncode({
    'kind': _kind,
    'version': 1,
    'status': status.name,
    'steps': steps,
  });

  static AgentThinkingTrace? tryDecode(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?> ||
          decoded['kind'] != _kind ||
          decoded['version'] != 1) {
        return null;
      }
      final statusName = decoded['status'];
      final rawSteps = decoded['steps'];
      if (statusName is! String ||
          rawSteps is! List ||
          rawSteps.any((step) => step is! String)) {
        return null;
      }
      final status = AgentThinkingStatus.values
          .where((candidate) => candidate.name == statusName)
          .firstOrNull;
      if (status == null) return null;
      final steps = rawSteps.cast<String>();
      if (steps.isEmpty) return null;
      return AgentThinkingTrace(status: status, steps: steps);
    } on Object {
      return null;
    }
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
