import '../../core/models/app_models.dart';

class LocalLlmAnalysisResult {
  const LocalLlmAnalysisResult({
    required this.summary,
    required this.tasks,
    required this.persons,
    required this.warnings,
  });

  final String summary;
  final List<LocalLlmTaskResult> tasks;
  final List<LocalLlmPersonResult> persons;
  final List<String> warnings;
}

class LocalLlmTaskResult {
  const LocalLlmTaskResult({
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

class LocalLlmPersonResult {
  const LocalLlmPersonResult({
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
