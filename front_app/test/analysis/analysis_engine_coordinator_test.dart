import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/analysis/analysis_engine_coordinator.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/analysis/remote_llm_analysis_provider.dart';

void main() {
  group('AnalysisEngineCoordinator', () {
    test('uses rule analysis when remote LLM is disabled', () async {
      var remoteCalled = false;
      final coordinator = AnalysisEngineCoordinator(
        ruleBasedAnalysisService: const AnalysisService(),
        remoteLlmAnalyzer: (_, _, {historyPersonText, clarificationAnswers}) {
          remoteCalled = true;
          return Future.value(_llmDraft());
        },
      );

      final draft = await coordinator.analyze(
        _input('这周完成论文整理。'),
        const RemoteLlmAnalysisSettings(enableRemoteLlmAnalysis: false),
      );

      expect(remoteCalled, isFalse);
      expect(draft.tasks.single.content, '这周完成论文整理');
    });

    test('uses remote LLM when enabled', () async {
      final coordinator = AnalysisEngineCoordinator(
        ruleBasedAnalysisService: const AnalysisService(),
        remoteLlmAnalyzer: (_, _, {historyPersonText, clarificationAnswers}) =>
            Future.value(_llmDraft()),
      );

      final draft = await coordinator.analyze(
        _input('这周完成论文整理。'),
        const RemoteLlmAnalysisSettings(enableRemoteLlmAnalysis: true),
      );

      expect(draft.id, 'llm_draft');
      expect(draft.tasks.single.id, 'llm_task');
    });

    test(
      'falls back to rules when remote LLM fails and fallback is enabled',
      () async {
        final coordinator = AnalysisEngineCoordinator(
          ruleBasedAnalysisService: const AnalysisService(),
          remoteLlmAnalyzer: (_, _, {historyPersonText, clarificationAnswers}) =>
              throw const RemoteLlmProviderException('down'),
        );

        final draft = await coordinator.analyze(
          _input('这周完成论文整理。'),
          const RemoteLlmAnalysisSettings(enableRemoteLlmAnalysis: true),
        );

        expect(draft.tasks.single.content, '这周完成论文整理');
        expect(draft.warnings.first, contains('远程模型服务调用失败'));
        expect(draft.warnings.first, contains('已自动回退到规则分析'));
      },
    );

    test('throws when remote LLM fails and fallback is disabled', () async {
      final coordinator = AnalysisEngineCoordinator(
        ruleBasedAnalysisService: const AnalysisService(),
        remoteLlmAnalyzer: (_, _, {historyPersonText, clarificationAnswers}) =>
            throw const RemoteLlmProviderException('slow'),
      );

      await expectLater(
        () => coordinator.analyze(
          _input('这周完成论文整理。'),
          const RemoteLlmAnalysisSettings(
            enableRemoteLlmAnalysis: true,
            fallbackToRules: false,
          ),
        ),
        throwsA(
          isA<AnalysisEngineCoordinatorException>().having(
            (error) => error.message,
            'message',
            contains('远程模型服务调用失败'),
          ),
        ),
      );
    });

    test('does not call remote LLM when input exceeds safety limit', () async {
      var remoteCalled = false;
      final coordinator = AnalysisEngineCoordinator(
        ruleBasedAnalysisService: const AnalysisService(),
        maxLlmInputCharacters: 5,
        remoteLlmAnalyzer: (_, _, {historyPersonText, clarificationAnswers}) {
          remoteCalled = true;
          return Future.value(_llmDraft());
        },
      );

      final draft = await coordinator.analyze(
        _input('这周完成论文整理。'),
        const RemoteLlmAnalysisSettings(enableRemoteLlmAnalysis: true),
      );

      expect(remoteCalled, isFalse);
      expect(draft.warnings.first, contains('未发送给远程模型'));
    });
  });
}

AnalysisInput _input(String text) {
  return AnalysisInput(rawText: text, sourceType: AnalysisSourceType.text);
}

AnalysisDraft _llmDraft() {
  return AnalysisDraft(
    id: 'llm_draft',
    tasks: [
      ExtractedTaskDraft(
        id: 'llm_task',
        content: '完成论文整理',
        category: ItemCategory.work,
        type: EventType.record,
        confidence: 0.9,
      ),
    ],
    persons: const [],
    summary: 'LLM summary',
    warnings: const [],
    createdAt: DateTime(2026, 5, 15),
  );
}
