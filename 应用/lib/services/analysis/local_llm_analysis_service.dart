import 'dart:async';

import '../../core/models/app_models.dart';
import 'analysis_prompt_builder.dart';
import 'analysis_result_validator.dart';
import 'local_llm_analysis_models.dart';
import 'ollama_client.dart';

abstract class AnalysisEngine {
  Future<AnalysisDraft> analyze(AnalysisInput input);
}

class LocalLlmAnalysisService implements AnalysisEngine {
  const LocalLlmAnalysisService({
    required OllamaClient client,
    required this.model,
    AnalysisPromptBuilder promptBuilder = const AnalysisPromptBuilder(),
    AnalysisResultValidator validator = const AnalysisResultValidator(),
    this.options = const <String, Object?>{},
    this.timeout,
  }) : _client = client,
       _promptBuilder = promptBuilder,
       _validator = validator;

  final OllamaClient _client;
  final String model;
  final AnalysisPromptBuilder _promptBuilder;
  final AnalysisResultValidator _validator;
  final Map<String, Object?> options;
  final Duration? timeout;

  @override
  Future<AnalysisDraft> analyze(AnalysisInput input) async {
    final startedAt = DateTime.now();
    final response = await _client.generate(
      model: model,
      prompt: _promptBuilder.buildPrompt(input),
      format: _promptBuilder.buildJsonSchema(),
      options: options.isEmpty ? null : options,
      timeout: timeout,
    );
    final result = _validator.validate(response.response);
    return _toDraft(result, createdAt: startedAt);
  }

  AnalysisDraft _toDraft(
    LocalLlmAnalysisResult result, {
    required DateTime createdAt,
  }) {
    final tasks = [
      for (var index = 0; index < result.tasks.length; index++)
        ExtractedTaskDraft(
          id: 'llm_task_$index',
          content: result.tasks[index].title,
          category: result.tasks[index].category,
          type: result.tasks[index].type,
          confidence: result.tasks[index].confidence,
          relatedPersonNames: result.tasks[index].people,
          timeHint: result.tasks[index].timeHint,
        ),
    ];
    final persons = [
      for (var index = 0; index < result.persons.length; index++)
        ExtractedPersonDraft(
          id: 'llm_person_$index',
          name: result.persons[index].name,
          role: result.persons[index].role,
          aliases: result.persons[index].aliases,
          relatedTaskIndexes: result.persons[index].relatedTaskIndexes,
        ),
    ];

    return AnalysisDraft(
      id: 'draft_llm_${createdAt.microsecondsSinceEpoch}',
      tasks: tasks,
      persons: persons,
      summary: result.summary,
      warnings: result.warnings,
      createdAt: createdAt,
    );
  }
}
