import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../../../core/models/app_models.dart';
import '../../../services/analysis/analysis_commit_service.dart';
import '../../../services/analysis/analysis_engine_coordinator.dart';
import '../../../services/import/import_service.dart';
import '../../../services/review/review_service.dart';

typedef AnalysisSessionHistoryReader = List<SessionRecord> Function();
typedef AnalysisSessionFinder = SessionRecord? Function(String sessionId);
typedef AnalysisEditingSessionIdReader = String? Function();
typedef AnalysisSequenceProvider = int Function();
typedef RemoteLlmAnalysisSettingsLoader =
    Future<RemoteLlmAnalysisSettings> Function();
typedef AnalysisCommitHandler =
    void Function(AnalysisControllerCommitResult result);

/// 原文中人名的高亮底色（荧光笔语义，主题无关）。
const Color personHighlightColor = Color(0xFFFFF59D);

class AnalysisControllerCommitResult {
  const AnalysisControllerCommitResult({
    required this.session,
    required this.isNewSession,
  });

  final SessionRecord session;
  final bool isNewSession;
}

class PersonHighlightTextEditingController extends TextEditingController {
  final List<String> _highlightedPersonNames = [];

  void setHighlightedPersonNames(Iterable<String> names) {
    final normalized =
        names
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));

    if (_highlightedPersonNames.length == normalized.length &&
        _highlightedPersonNames.every(normalized.contains)) {
      return;
    }

    _highlightedPersonNames
      ..clear()
      ..addAll(normalized);
    notifyListeners();
  }

  void clearHighlightedPersonNames() {
    if (_highlightedPersonNames.isEmpty) {
      return;
    }
    _highlightedPersonNames.clear();
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final sourceText = text;
    if (_highlightedPersonNames.isEmpty || sourceText.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final ranges = <_PersonHighlightRange>[];
    for (final name in _highlightedPersonNames) {
      for (final match in RegExp(RegExp.escape(name)).allMatches(sourceText)) {
        ranges.add(_PersonHighlightRange(match.start, match.end));
      }
    }
    ranges.sort((a, b) {
      final startComparison = a.start.compareTo(b.start);
      if (startComparison != 0) {
        return startComparison;
      }
      return b.end.compareTo(a.end);
    });

    final baseStyle = style ?? const TextStyle();
    final highlightStyle = baseStyle.copyWith(
      backgroundColor: personHighlightColor,
      fontWeight: FontWeight.w600,
    );
    final spans = <TextSpan>[];
    var cursor = 0;

    for (final range in ranges) {
      if (range.start < cursor) {
        continue;
      }
      if (range.start > cursor) {
        spans.add(TextSpan(text: sourceText.substring(cursor, range.start)));
      }
      spans.add(
        TextSpan(
          text: sourceText.substring(range.start, range.end),
          style: highlightStyle,
        ),
      );
      cursor = range.end;
    }

    if (cursor < sourceText.length) {
      spans.add(TextSpan(text: sourceText.substring(cursor)));
    }

    return TextSpan(style: baseStyle, children: spans);
  }
}

class _PersonHighlightRange {
  const _PersonHighlightRange(this.start, this.end);

  final int start;
  final int end;
}

class AnalysisController extends ChangeNotifier {
  AnalysisController({
    required ImportService importService,
    required AnalysisEngineCoordinator analysisEngineCoordinator,
    required ReviewService reviewService,
    required AnalysisCommitService commitService,
    required RemoteLlmAnalysisSettingsLoader loadRemoteLlmAnalysisSettings,
    required AnalysisSessionHistoryReader sessionHistory,
    required AnalysisSessionFinder findSessionById,
    required AnalysisEditingSessionIdReader editingSessionId,
    required AnalysisSequenceProvider nextSessionSequence,
    required AnalysisCommitHandler onCommit,
  }) : _importService = importService,
       _analysisEngineCoordinator = analysisEngineCoordinator,
       _reviewService = reviewService,
       _commitService = commitService,
       _loadRemoteLlmAnalysisSettings = loadRemoteLlmAnalysisSettings,
       _sessionHistory = sessionHistory,
       _findSessionById = findSessionById,
       _editingSessionId = editingSessionId,
       _nextSessionSequence = nextSessionSequence,
       _onCommit = onCommit {
    inputController.addListener(_syncInputTextFromController);
  }

  final ImportService _importService;
  final AnalysisEngineCoordinator _analysisEngineCoordinator;
  final ReviewService _reviewService;
  final AnalysisCommitService _commitService;
  final RemoteLlmAnalysisSettingsLoader _loadRemoteLlmAnalysisSettings;
  final AnalysisSessionHistoryReader _sessionHistory;
  final AnalysisSessionFinder _findSessionById;
  final AnalysisEditingSessionIdReader _editingSessionId;
  final AnalysisSequenceProvider _nextSessionSequence;
  final AnalysisCommitHandler _onCommit;

  final PersonHighlightTextEditingController inputController =
      PersonHighlightTextEditingController();

  String _currentInputText = '';
  AnalysisInput? _currentInput;
  AnalysisDraft? _draft;
  ReviewPreview? _preview;
  bool _lastImportSucceeded = false;
  String? _sourceLabel;
  bool _isImporting = false;
  bool _isAnalyzing = false;
  bool _isCommitting = false;
  bool _isGeneratingResult = false;
  String? _errorMessage;
  bool _syncingInputController = false;
  final Map<int, String> _clarificationAnswers = {};
  final Set<int> _skippedClarifications = {};

  String get currentInputText => _currentInputText;
  AnalysisInput? get currentInput => _currentInput;
  AnalysisDraft? get draft => _draft;
  ReviewPreview? get preview => _preview;
  bool get isAnalyzing => _isAnalyzing;
  bool get isCommitting => _isCommitting;
  bool get isImporting => _isImporting;
  bool get isGeneratingResult => _isGeneratingResult;
  bool get isBusy =>
      _isImporting || _isAnalyzing || _isCommitting || _isGeneratingResult;
  String? get errorMessage => _errorMessage;
  bool get lastImportSucceeded => _lastImportSucceeded;
  String? get sourceLabel => _sourceLabel;

  List<ClarificationItem> get clarifications =>
      _draft?.clarifications ?? const [];
  int get answeredClarificationCount =>
      _clarificationAnswers.length + _skippedClarifications.length;
  bool get allClarificationsResolved =>
      clarifications.isNotEmpty &&
      answeredClarificationCount >= clarifications.length;
  bool get hasPendingClarifications =>
      clarifications.isNotEmpty && !allClarificationsResolved;

  bool isClarificationAnswered(int index) =>
      _clarificationAnswers.containsKey(index) ||
      _skippedClarifications.contains(index);

  bool isClarificationSkipped(int index) =>
      _skippedClarifications.contains(index);

  String? clarificationAnswer(int index) => _clarificationAnswers[index];

  void answerClarification(int index, String answer) {
    if (index < 0 || index >= clarifications.length) {
      return;
    }
    final normalized = answer.trim();
    if (normalized.isEmpty) {
      _clarificationAnswers.remove(index);
    } else {
      _clarificationAnswers[index] = normalized;
    }
    _skippedClarifications.remove(index);
    notifyListeners();
  }

  void skipClarification(int index) {
    if (index < 0 || index >= clarifications.length) {
      return;
    }
    _clarificationAnswers.remove(index);
    _skippedClarifications.add(index);
    notifyListeners();
  }

  void skipAllClarifications() {
    for (var index = 0; index < clarifications.length; index++) {
      _clarificationAnswers.remove(index);
      _skippedClarifications.add(index);
    }
    notifyListeners();
  }

  void updateInputText(String text) {
    if (_currentInputText == text) {
      return;
    }

    _currentInputText = text;
    _clearClarificationState();
    if (inputController.text != text) {
      _setInputControllerText(text);
      return;
    }
    notifyListeners();
  }

  Future<String?> importFile() async {
    const group = XTypeGroup(
      label: '研究生活导入',
      extensions: ['txt', 'md', 'docx', 'doc'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) {
      return null;
    }
    return importFileFromPath(file.path);
  }

  Future<String?> importFileFromPath(String path) async {
    _setImporting(true);
    try {
      final result = await _importService.importFile(path);
      if (!result.success || result.input == null) {
        _lastImportSucceeded = false;
        _errorMessage = result.message;
        notifyListeners();
        return result.message;
      }

      final input = result.input!;
      _lastImportSucceeded = true;
      _currentInput = input;
      _sourceLabel = _formatSourceLabel(input);
      inputController.clearHighlightedPersonNames();
      _setInputControllerText(input.rawText);
      _draft = null;
      _preview = null;
      _errorMessage = null;
      _clearClarificationState();
      notifyListeners();
      return result.message;
    } catch (error) {
      _lastImportSucceeded = false;
      _errorMessage = '$error';
      notifyListeners();
      rethrow;
    } finally {
      _setImporting(false);
    }
  }

  Future<String?> analyzeCurrentInput() async {
    final rawText = inputController.text.trim();
    if (rawText.isEmpty) {
      const message = '请先输入一段周描述，或导入 TXT / MD / DOCX 文件。';
      _errorMessage = message;
      notifyListeners();
      return message;
    }

    _setAnalyzing(true);
    try {
      final input = AnalysisInput(
        rawText: rawText,
        sourceType: _currentInput?.sourceType ?? AnalysisSourceType.text,
        sourcePath: _currentInput?.sourcePath,
      );

      _currentInput = input;
      _currentInputText = inputController.text;
      _sourceLabel = _formatSourceLabel(input);
      final settings = await _loadRemoteLlmAnalysisSettings();
      _draft = await _analysisEngineCoordinator.analyze(
        input,
        settings,
        historyPersonText: _buildHistoryPersonText(),
      );
      _preview = _reviewService.buildPreview(_draft!);
      _clearClarificationState();
      inputController.setHighlightedPersonNames(
        _personNamesFromPreview(_preview!),
      );
      _lastImportSucceeded = false;
      _errorMessage = _preview!.warnings.isEmpty
          ? null
          : _preview!.warnings.first;
      notifyListeners();
      return _errorMessage;
    } catch (error) {
      _errorMessage = '$error';
      notifyListeners();
      rethrow;
    } finally {
      _setAnalyzing(false);
    }
  }

  Future<String?> generateFinalResult() async {
    final input = _currentInput;
    final draft = _draft;
    if (input == null || draft == null) {
      const message = '当前没有可生成的分析结果。';
      _errorMessage = message;
      notifyListeners();
      return message;
    }
    final clarifications = nullSafeList(draft.clarifications);
    if (clarifications.isEmpty) {
      const message = '没有待澄清的疑问，可直接确认结果。';
      _errorMessage = message;
      notifyListeners();
      return message;
    }
    if (!allClarificationsResolved) {
      const message = '还有未回答的疑问，请先回答或全部跳过。';
      _errorMessage = message;
      notifyListeners();
      return message;
    }
    if (_isGeneratingResult) {
      return null;
    }

    _setGeneratingResult(true);
    try {
      final settings = await _loadRemoteLlmAnalysisSettings();
      final answerLines = <String>[
        for (var index = 0; index < clarifications.length; index++)
          _formatClarificationAnswer(index, clarifications[index]),
      ];
      final result = await _analysisEngineCoordinator.analyze(
        input,
        settings,
        historyPersonText: _buildHistoryPersonText(),
        clarificationAnswers: answerLines,
      );
      _draft = result;
      _preview = _reviewService.buildPreview(result);
      _clearClarificationState();
      inputController.setHighlightedPersonNames(
        _personNamesFromPreview(_preview!),
      );
      _lastImportSucceeded = false;
      _errorMessage = result.warnings.isEmpty ? null : result.warnings.first;
      notifyListeners();
      return _errorMessage;
    } catch (error) {
      _errorMessage = '$error';
      notifyListeners();
      rethrow;
    } finally {
      _setGeneratingResult(false);
    }
  }

  String? confirmDraft() {
    final draft = _draft;
    final input = _currentInput;
    final preview = _preview;
    if (draft == null || input == null || preview == null) {
      const message = '当前还没有可以确认的分析结果。';
      _errorMessage = message;
      notifyListeners();
      return message;
    }

    _setCommitting(true);
    try {
      final now = DateTime.now();
      final editingSessionId = _editingSessionId();
      final targetSession = editingSessionId == null
          ? _findDuplicateSessionForInput(now, input.rawText)
          : _findSessionById(editingSessionId);
      final sessionKey = targetSession == null
          ? '${now.microsecondsSinceEpoch}_${_nextSessionSequence()}'
          : _sessionKeyFromId(targetSession.id);
      final draftForSession = targetSession == null
          ? draft.copyWith(clarifications: const [])
          : draft.copyWith(
              createdAt: targetSession.draft.createdAt,
              clarifications: const [],
            );
      final session = _commitService.buildSession(
        id: targetSession?.id ?? 'session_$sessionKey',
        title: targetSession?.title ?? '第 ${_sessionHistory().length + 1} 次分析',
        input: input,
        draft: draftForSession,
        preview: preview,
        sessionKey: sessionKey,
        confirmedAt: targetSession?.confirmedAt ?? now,
        sourceLabel: _sourceLabel,
      );

      _draft = session.draft;
      _preview = session.preview;
      _clearClarificationState();
      inputController.setHighlightedPersonNames(
        _personNamesFromPreview(session.preview),
      );
      _lastImportSucceeded = false;
      _errorMessage = null;
      _onCommit(
        AnalysisControllerCommitResult(
          session: session,
          isNewSession: targetSession == null,
        ),
      );
      notifyListeners();
      return targetSession == null
          ? '分析结果已确认，已同步到主页、人物关系和历史记录。'
          : '已更新同一天或本周已有的周分析上传记录。';
    } catch (error) {
      _errorMessage = '$error';
      notifyListeners();
      rethrow;
    } finally {
      _setCommitting(false);
    }
  }

  void clearDraft() {
    _draft = null;
    _preview = null;
    _lastImportSucceeded = false;
    inputController.clearHighlightedPersonNames();
    _clearClarificationState();
    notifyListeners();
  }

  void clearComposer() {
    _currentInput = null;
    _draft = null;
    _preview = null;
    _lastImportSucceeded = false;
    _sourceLabel = null;
    _errorMessage = null;
    inputController.clearHighlightedPersonNames();
    _setInputControllerText('');
    _clearClarificationState();
    notifyListeners();
  }

  void loadTextInput(String text, {AnalysisSourceType? sourceType}) {
    _currentInput = null;
    _sourceLabel = (sourceType ?? AnalysisSourceType.text).label;
    _lastImportSucceeded = false;
    _errorMessage = null;
    _setInputControllerText(text);
    _clearClarificationState();
    notifyListeners();
  }

  void loadSession(SessionRecord session) {
    _currentInput = session.input;
    _draft = session.draft;
    _preview = session.preview;
    _sourceLabel = _formatSourceLabel(session.input);
    _lastImportSucceeded = false;
    _errorMessage = null;
    _setInputControllerText(session.input.rawText);
    inputController.setHighlightedPersonNames(
      _personNamesFromPreview(session.preview),
    );
    _clearClarificationState();
    notifyListeners();
  }

  void clearIfCurrentDraft(String draftId) {
    if (_draft?.id != draftId) {
      return;
    }
    clearComposer();
  }

  void replaceDraftIfCurrent(SessionRecord session) {
    if (_draft?.id != session.draft.id) {
      return;
    }
    _draft = session.draft;
    _preview = session.preview;
    notifyListeners();
  }

  void _syncInputTextFromController() {
    if (_syncingInputController) {
      return;
    }
    final text = inputController.text;
    if (_currentInputText == text) {
      return;
    }
    _currentInputText = text;
    _clearClarificationState();
    notifyListeners();
  }

  void _setInputControllerText(String text) {
    if (inputController.text == text) {
      _currentInputText = text;
      return;
    }

    _syncingInputController = true;
    inputController.text = text;
    _syncingInputController = false;
    _currentInputText = text;
  }

  void _setImporting(bool value) {
    if (_isImporting == value) {
      return;
    }
    _isImporting = value;
    notifyListeners();
  }

  void _setAnalyzing(bool value) {
    if (_isAnalyzing == value) {
      return;
    }
    _isAnalyzing = value;
    notifyListeners();
  }

  void _setCommitting(bool value) {
    if (_isCommitting == value) {
      return;
    }
    _isCommitting = value;
    notifyListeners();
  }

  void _setGeneratingResult(bool value) {
    if (_isGeneratingResult == value) {
      return;
    }
    _isGeneratingResult = value;
    notifyListeners();
  }

  void _clearClarificationState() {
    _clarificationAnswers.clear();
    _skippedClarifications.clear();
  }

  String _formatClarificationAnswer(int index, ClarificationItem item) {
    final answer = _skippedClarifications.contains(index)
        ? '跳过（保持第一轮判断）'
        : (_clarificationAnswers[index] ?? '跳过（保持第一轮判断）');
    final personHint = item.personIndex != null
        ? '（第 ${item.personIndex! + 1} 个识别人物）'
        : '';
    return '问题：${item.question}$personHint\n回答：$answer';
  }

  String _buildHistoryPersonText() {
    final entries =
        <
          ({
            String name,
            String roleLabel,
            DateTime lastSeen,
            List<String> aliases,
          })
        >[];
    for (final session in _sessionHistory()) {
      if (session.isInstitutionCalendar) {
        continue;
      }
      for (final person in session.people) {
        entries.add((
          name: person.name,
          roleLabel: person.role.label,
          lastSeen: session.confirmedAt,
          aliases: person.aliases
              .map((alias) => alias.trim())
              .where(
                (alias) =>
                    alias.isNotEmpty &&
                    alias != person.name &&
                    alias != person.name.trim(),
              )
              .toSet()
              .toList(),
        ));
      }
    }
    if (entries.isEmpty) {
      return '';
    }

    entries.sort((left, right) => right.lastSeen.compareTo(left.lastSeen));
    const limit = 20;
    final lines = <String>[];
    for (final entry in entries.take(limit)) {
      final aliasText = entry.aliases.isEmpty
          ? ''
          : '称呼：${entry.aliases.join('、')} | ';
      lines.add(
        '- ${entry.name} | $aliasText角色：${entry.roleLabel} | 最近出现：${_formatHistoryDate(entry.lastSeen)}',
      );
    }
    return lines.join('\n');
  }

  String _formatHistoryDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatSourceLabel(AnalysisInput input) {
    final sourcePath = input.sourcePath;
    if (sourcePath == null || sourcePath.isEmpty) {
      return input.sourceType.label;
    }

    final segments = sourcePath.replaceAll('\\', '/').split('/');
    return '${input.sourceType.label} · ${segments.last}';
  }

  List<String> _personNamesFromPreview(ReviewPreview preview) {
    return preview.persons
        .expand((person) => <String>[person.name, ...person.aliases])
        .where((name) => name.trim().isNotEmpty)
        .toSet()
        .toList();
  }

  SessionRecord? _findDuplicateSessionForInput(DateTime date, String rawText) {
    final normalizedInput = _normalizeSessionInput(rawText);
    if (normalizedInput.isEmpty) {
      return null;
    }

    for (final session in _sessionHistory()) {
      if (session.isInstitutionCalendar) {
        continue;
      }
      if (!_sameWeek(session.confirmedAt, date)) {
        continue;
      }
      if (_normalizeSessionInput(session.input.rawText) == normalizedInput) {
        return session;
      }
    }
    return null;
  }

  String _sessionKeyFromId(String sessionId) {
    const prefix = 'session_';
    return sessionId.startsWith(prefix)
        ? sessionId.substring(prefix.length)
        : sessionId;
  }

  String _normalizeSessionInput(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _sameWeek(DateTime left, DateTime right) {
    return _weekStart(left) == _weekStart(right);
  }

  DateTime _weekStart(DateTime date) {
    return _dateOnly(
      date,
    ).subtract(Duration(days: date.weekday - DateTime.monday));
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  @override
  void dispose() {
    inputController.removeListener(_syncInputTextFromController);
    inputController.dispose();
    super.dispose();
  }
}
