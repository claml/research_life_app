import '../../core/config/api_config.dart';
import '../../core/models/app_models.dart';
import '../../core/network/api_exception.dart';
import 'analysis_engine.dart';
import 'analysis_prompt_builder.dart';
import 'analysis_result_validator.dart';
import 'analysis_service.dart';
import 'llm_analysis_models.dart';
import 'llm_analysis_provider.dart';
import 'llm_provider_presets.dart';
import 'remote_llm_analysis_provider.dart';

typedef RemoteLlmAnalyzer =
    Future<AnalysisDraft> Function(
      AnalysisInput input,
      RemoteLlmAnalysisSettings settings, {
      String? historyPersonText,
      List<String>? clarificationAnswers,
    });

class AnalysisEngineCoordinator {
  AnalysisEngineCoordinator({
    required AnalysisService ruleBasedAnalysisService,
    LlmAnalysisProvider? remoteLlmProvider,
    RemoteLlmAnalyzer? remoteLlmAnalyzer,
    this.maxLlmInputCharacters = 20000,
  }) : _ruleBasedAnalysisService = ruleBasedAnalysisService,
       _remoteLlmAnalyzer =
           remoteLlmAnalyzer ??
           (remoteLlmProvider == null
               ? null
               : ((
                   input,
                   settings, {
                   String? historyPersonText,
                   List<String>? clarificationAnswers,
                 }) => _analyzeWithRemoteProvider(
                   remoteLlmProvider,
                   input,
                   settings,
                   historyPersonText: historyPersonText,
                   clarificationAnswers: clarificationAnswers,
                 )));

  final AnalysisService _ruleBasedAnalysisService;
  final RemoteLlmAnalyzer? _remoteLlmAnalyzer;
  final int maxLlmInputCharacters;

  Future<AnalysisDraft> analyze(
    AnalysisInput input,
    RemoteLlmAnalysisSettings settings, {
    String? historyPersonText,
    List<String>? clarificationAnswers,
  }) async {
    if (!settings.enableRemoteLlmAnalysis) {
      return _analyzeWithRules(input);
    }

    if (input.rawText.trim().length > maxLlmInputCharacters) {
      return _analyzeWithRules(
        input,
        warning: '周记文本超过 $maxLlmInputCharacters 字，已使用规则分析，未发送给远程模型。',
      );
    }

    final analyzer = _remoteLlmAnalyzer;
    if (analyzer == null) {
      final message = settings.fallbackToRules
          ? '远程模型服务未配置，已自动回退到规则分析。'
          : '远程模型服务未配置，未生成分析结果。';
      if (!settings.fallbackToRules) {
        throw AnalysisEngineCoordinatorException(message);
      }
      return _analyzeWithRules(input, warning: message);
    }

    try {
      return await analyzer(
        input,
        settings,
        historyPersonText: historyPersonText,
        clarificationAnswers: clarificationAnswers,
      );
    } catch (error) {
      final message = _failureMessage(
        error,
        settings,
        fallbackToRules: settings.fallbackToRules,
      );
      if (!settings.fallbackToRules) {
        throw AnalysisEngineCoordinatorException(message, cause: error);
      }
      return _analyzeWithRules(input, warning: message);
    }
  }

  AnalysisDraft _analyzeWithRules(AnalysisInput input, {String? warning}) {
    final draft = _ruleBasedAnalysisService.analyze(input);
    if (warning == null || warning.trim().isEmpty) {
      return draft;
    }
    return draft.copyWith(warnings: [warning, ...draft.warnings]);
  }

  static Future<AnalysisDraft> _analyzeWithRemoteProvider(
    LlmAnalysisProvider provider,
    AnalysisInput input,
    RemoteLlmAnalysisSettings settings, {
    String? historyPersonText,
    List<String>? clarificationAnswers,
  }) {
    final service = RemoteLlmAnalysisService(
      provider: provider,
      options: const {'temperature': 0},
      extraBody: _buildRemoteLlmExtraBody(settings),
      timeout: Duration(seconds: settings.remoteTimeoutSeconds),
      useJsonSchema: settings.strictJsonSchema,
    );
    return service.analyze(
      input,
      historyPersonText: historyPersonText,
      clarificationAnswers: clarificationAnswers,
    );
  }

  static Map<String, Object?>? _buildRemoteLlmExtraBody(
    RemoteLlmAnalysisSettings settings,
  ) {
    final baseUrl = llmResolveBaseUrl(
      provider: settings.provider,
      baseUrl: settings.baseUrl,
    );
    final modelName = llmResolveModelName(
      provider: settings.provider,
      modelName: settings.modelName,
    );
    final apiKey = settings.apiKey?.trim();
    final body = <String, Object?>{
      'provider': ?settings.provider,
      'baseUrl': ?baseUrl,
      'modelName': ?modelName,
      if (apiKey != null && apiKey.isNotEmpty) 'apiKey': apiKey,
    };
    return body.isEmpty ? null : body;
  }

  String _failureMessage(
    Object error,
    RemoteLlmAnalysisSettings settings, {
    required bool fallbackToRules,
  }) {
    final suffix = fallbackToRules ? '已自动回退到规则分析。' : '未生成分析结果。';
    if (error is RemoteLlmProviderException) {
      if (_isUnauthorized(error.cause)) {
        return '远程模型服务需要登录云端账号或登录已过期，$suffix';
      }
      if (error.cause is ApiException) {
        final apiError = error.cause as ApiException;
        if (apiError.code == 408) {
          return '远程模型响应超时（超过 ${settings.remoteTimeoutSeconds} 秒），$suffix'
              '如需更长等待，可在设置页「远程 LLM 周分析」中调大超时时间。';
        }
        if (apiError.code == 503) {
          return '无法连接后端服务器（${ApiConfig.baseUrl}），请确认 Spring Boot 后端已启动，$suffix';
        }
        if (apiError.code >= 400 && apiError.code < 500) {
          return '远程模型服务请求被拒绝（${apiError.code}：${apiError.message}），$suffix';
        }
        return '远程模型服务调用失败（${apiError.code}：${apiError.message}），$suffix';
      }
      return '远程模型服务调用失败，$suffix';
    }
    if (error is AnalysisResultValidationException) {
      return '远程模型返回格式无效，$suffix';
    }
    return '远程模型分析失败，$suffix';
  }

  static bool _isUnauthorized(Object? cause) {
    return cause is ApiException && cause.code == 401;
  }
}

class RemoteLlmAnalysisService implements AnalysisEngine {
  const RemoteLlmAnalysisService({
    required LlmAnalysisProvider provider,
    this.promptBuilder = const AnalysisPromptBuilder(),
    this.validator = const AnalysisResultValidator(),
    this.options = const <String, Object?>{},
    this.extraBody,
    this.timeout,
    this.useJsonSchema = true,
  }) : _provider = provider;

  final LlmAnalysisProvider _provider;
  final AnalysisPromptBuilder promptBuilder;
  final AnalysisResultValidator validator;
  final Map<String, Object?> options;
  final Map<String, Object?>? extraBody;
  final Duration? timeout;
  final bool useJsonSchema;

  @override
  Future<AnalysisDraft> analyze(
    AnalysisInput input, {
    String? historyPersonText,
    List<String>? clarificationAnswers,
  }) async {
    final startedAt = DateTime.now();
    final rawResponse = await _provider.generateAnalysisJson(
      prompt: promptBuilder.buildPrompt(
        input,
        historyPersonText: historyPersonText,
        clarificationAnswers: clarificationAnswers,
      ),
      format: useJsonSchema ? promptBuilder.buildJsonSchema() : 'json',
      options: options.isEmpty ? null : options,
      extraBody: extraBody,
      timeout: timeout,
    );
    final result = validator.validate(rawResponse);
    return _toDraft(result, createdAt: startedAt);
  }

  AnalysisDraft _toDraft(
    LlmAnalysisResult result, {
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
      clarifications: nullSafeList(result.clarifications),
      createdAt: createdAt,
    );
  }
}

class AnalysisEngineCoordinatorException implements Exception {
  const AnalysisEngineCoordinatorException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
