import '../../core/models/app_models.dart';

class LlmAnalysisResult {
  const LlmAnalysisResult({
    required this.summary,
    required this.tasks,
    required this.persons,
    required this.warnings,
    this.clarifications = const [],
  });

  final String summary;
  final List<LlmTaskResult> tasks;
  final List<LlmPersonResult> persons;
  final List<String> warnings;
  final List<ClarificationItem> clarifications;
}

class LlmTaskResult {
  const LlmTaskResult({
    required this.title,
    required this.description,
    required this.category,
    required this.type,
    required this.confidence,
    required this.people,
    this.timeHint,
    required this.evidence,
  });

  final String title;
  final String description;
  final ItemCategory category;
  final EventType type;
  final double confidence;
  final List<String> people;
  final String? timeHint;
  final String evidence;
}

class LlmPersonResult {
  const LlmPersonResult({
    required this.name,
    required this.role,
    required this.aliases,
    required this.relationshipNote,
    required this.relatedTaskIndexes,
    required this.confidence,
  });

  final String name;
  final PersonRole role;
  final List<String> aliases;
  final String relationshipNote;
  final List<int> relatedTaskIndexes;
  final double confidence;
}
