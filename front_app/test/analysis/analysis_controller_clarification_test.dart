import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/features/analysis/state/analysis_controller.dart';
import 'package:research_life/services/analysis/analysis_commit_service.dart';
import 'package:research_life/services/analysis/analysis_engine_coordinator.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';

void main() {
  group('AnalysisController clarification flow', () {
    test('exposes clarifications from first round and generates final result',
        () async {
      var callCount = 0;
      String? capturedHistory;
      List<String>? capturedAnswers;
      final controller = _createController(
        sessionHistory: [_historySession()],
        onAnalyze: (
          input,
          settings, {
          historyPersonText,
          clarificationAnswers,
        }) {
          callCount++;
          capturedHistory = historyPersonText;
          capturedAnswers = clarificationAnswers;
          return Future.value(
            callCount == 1 ? _draftWithClarifications() : _finalDraft(),
          );
        },
      );

      controller.updateInputText('这周和王老师开会。');
      await controller.analyzeCurrentInput();

      expect(controller.clarifications, hasLength(1));
      expect(controller.hasPendingClarifications, isTrue);
      expect(controller.allClarificationsResolved, isFalse);
      expect(capturedHistory, contains('王丽'));
      expect(capturedHistory, contains('王老师'));

      controller.answerClarification(0, '是，就是王丽老师');
      expect(controller.hasPendingClarifications, isFalse);
      expect(controller.allClarificationsResolved, isTrue);

      await controller.generateFinalResult();

      expect(callCount, 2);
      expect(capturedAnswers, hasLength(1));
      expect(
        capturedAnswers!.single,
        contains('问题：周记里的王老师与历史人物王丽是同一人吗？'),
      );
      expect(capturedAnswers!.single, contains('回答：是，就是王丽老师'));
      expect(controller.clarifications, isEmpty);
      expect(controller.hasPendingClarifications, isFalse);
      expect(controller.preview!.summary, '最终结果');
    });

    test('skip all clarifications then generate keeps first round judgment',
        () async {
      var callCount = 0;
      List<String>? capturedAnswers;
      final controller = _createController(
        onAnalyze: (
          input,
          settings, {
          historyPersonText,
          clarificationAnswers,
        }) {
          callCount++;
          capturedAnswers = clarificationAnswers;
          return Future.value(
            callCount == 1 ? _draftWithClarifications() : _finalDraft(),
          );
        },
      );

      controller.updateInputText('这周和王老师开会。');
      await controller.analyzeCurrentInput();

      controller.skipAllClarifications();
      expect(controller.allClarificationsResolved, isTrue);
      expect(controller.answeredClarificationCount, 1);

      await controller.generateFinalResult();

      expect(callCount, 2);
      expect(capturedAnswers!.single, contains('跳过（保持第一轮判断）'));
    });

    test('generating without answers returns a message', () async {
      final controller = _createController(
        onAnalyze: (input, settings, {historyPersonText, clarificationAnswers}) =>
            Future.value(_draftWithClarifications()),
      );

      controller.updateInputText('这周和王老师开会。');
      await controller.analyzeCurrentInput();

      final message = await controller.generateFinalResult();

      expect(message, '还有未回答的疑问，请先回答或全部跳过。');
      expect(controller.isGeneratingResult, isFalse);
    });

    test('generating without clarifications returns a message', () async {
      final controller = _createController();

      controller.updateInputText('这周完成论文整理。');
      await controller.analyzeCurrentInput();

      final message = await controller.generateFinalResult();

      expect(message, '没有待澄清的疑问，可直接确认结果。');
    });

    test('input change clears clarification answers', () async {
      final controller = _createController(
        onAnalyze: (input, settings, {historyPersonText, clarificationAnswers}) =>
            Future.value(_draftWithClarifications()),
      );

      controller.updateInputText('这周和王老师开会。');
      await controller.analyzeCurrentInput();
      controller.answerClarification(0, '是，就是王丽老师');
      expect(controller.allClarificationsResolved, isTrue);

      controller.updateInputText('这周和导师开会。');

      expect(controller.allClarificationsResolved, isFalse);
      expect(controller.hasPendingClarifications, isTrue);
    });

    test('confirmDraft strips clarifications from committed session', () async {
      SessionRecord? committed;
      final controller = _createController(
        onAnalyze: (input, settings, {historyPersonText, clarificationAnswers}) =>
            Future.value(_draftWithClarifications()),
        onCommit: (result) => committed = result.session,
      );

      controller.updateInputText('这周和王老师开会。');
      await controller.analyzeCurrentInput();
      expect(controller.draft!.clarifications, hasLength(1));

      final message = controller.confirmDraft();

      expect(message, '分析结果已确认，已同步到主页、人物关系和历史记录。');
      expect(committed, isNotNull);
      expect(committed!.draft.clarifications, isEmpty);
      expect(controller.draft!.clarifications, isEmpty);
    });

    test('clearDraft resets clarification state', () async {
      final controller = _createController(
        onAnalyze: (input, settings, {historyPersonText, clarificationAnswers}) =>
            Future.value(_draftWithClarifications()),
      );

      controller.updateInputText('这周和王老师开会。');
      await controller.analyzeCurrentInput();
      controller.answerClarification(0, '是');

      controller.clearDraft();

      expect(controller.clarifications, isEmpty);
      expect(controller.hasPendingClarifications, isFalse);
      expect(controller.allClarificationsResolved, isFalse);
    });
  });
}

typedef _FakeAnalyzer =
    Future<AnalysisDraft> Function(
      AnalysisInput input,
      RemoteLlmAnalysisSettings settings, {
      String? historyPersonText,
      List<String>? clarificationAnswers,
    });

AnalysisController _createController({
  _FakeAnalyzer? onAnalyze,
  List<SessionRecord>? sessionHistory,
  AnalysisCommitHandler? onCommit,
}) {
  final coordinator = AnalysisEngineCoordinator(
    ruleBasedAnalysisService: const AnalysisService(),
    remoteLlmAnalyzer:
        onAnalyze ??
        ((input, settings, {historyPersonText, clarificationAnswers}) =>
            Future.value(_finalDraft())),
  );
  final history = sessionHistory ?? const <SessionRecord>[];
  return AnalysisController(
    importService: const ImportService(),
    analysisEngineCoordinator: coordinator,
    reviewService: const ReviewService(),
    commitService: const AnalysisCommitService(),
    loadRemoteLlmAnalysisSettings: () async =>
        const RemoteLlmAnalysisSettings(enableRemoteLlmAnalysis: true),
    sessionHistory: () => history,
    findSessionById: (_) => null,
    editingSessionId: () => null,
    nextSessionSequence: () => 1,
    onCommit: onCommit ?? (_) {},
  );
}

AnalysisDraft _draftWithClarifications() {
  return AnalysisDraft(
    id: 'draft_round1',
    tasks: const [],
    persons: const [],
    summary: '第一轮结果',
    warnings: const [],
    clarifications: const [
      ClarificationItem(
        type: ClarificationType.identity,
        personIndex: 0,
        question: '周记里的王老师与历史人物王丽是同一人吗？',
        context: '周三和王老师开会',
        options: ['是，就是王丽', '不是'],
      ),
    ],
    createdAt: DateTime(2026, 7, 20),
  );
}

AnalysisDraft _finalDraft() {
  return AnalysisDraft(
    id: 'draft_round2',
    tasks: const [],
    persons: const [
      ExtractedPersonDraft(
        id: 'p1',
        name: '王丽',
        role: PersonRole.teacher,
        aliases: ['王老师'],
      ),
    ],
    summary: '最终结果',
    warnings: const [],
    createdAt: DateTime(2026, 7, 20),
  );
}

SessionRecord _historySession() {
  final draft = AnalysisDraft(
    id: 'draft_hist',
    tasks: const [],
    persons: const [],
    summary: '',
    warnings: const [],
    createdAt: DateTime(2026, 7, 13),
  );
  return SessionRecord(
    id: 'session_hist',
    title: '历史周记',
    input: const AnalysisInput(
      rawText: '上周和老师开会。',
      sourceType: AnalysisSourceType.text,
    ),
    draft: draft,
    preview: const ReviewService().buildPreview(draft),
    events: const [],
    people: const [
      PersonProfile(
        id: 'p_hist',
        name: '王丽',
        role: PersonRole.teacher,
        aliases: ['王老师'],
        relatedTaskCount: 1,
        relatedPlanTitles: [],
      ),
    ],
    confirmedAt: DateTime(2026, 7, 13),
  );
}
