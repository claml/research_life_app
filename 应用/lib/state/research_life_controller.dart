import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/models/app_models.dart';
import '../core/models/weather_models.dart';
import '../core/theme/app_tokens.dart';
import '../features/analysis/state/analysis_controller.dart';
import '../services/analysis/analysis_commit_service.dart';
import '../services/analysis/analysis_service.dart';
import '../services/analysis/ollama_client.dart';
import '../services/calendar/institution_calendar_service.dart';
import '../services/database/repositories/campus_places_repository.dart';
import '../services/database/repositories/manual_events_repository.dart';
import '../services/database/repositories/pdf_documents_repository.dart';
import '../services/database/repositories/preferences_repository.dart';
import '../services/database/repositories/sessions_repository.dart';
import '../services/import/import_service.dart';
import '../services/review/review_service.dart';
import '../services/storage/local_workspace_service.dart';
import '../services/vpet/vpet_companion_service.dart';
import '../services/weather/weather_service.dart';

enum HomeImageSlot { researchWall, lifeWall }

extension HomeImageSlotLabel on HomeImageSlot {
  String get label => switch (this) {
    HomeImageSlot.researchWall => '研究墙',
    HomeImageSlot.lifeWall => '生活墙',
  };

  String get fileBaseName => switch (this) {
    HomeImageSlot.researchWall => 'research_wall',
    HomeImageSlot.lifeWall => 'life_wall',
  };
}

class ResearchLifeController extends ChangeNotifier {
  ResearchLifeController({
    required ImportService importService,
    required AnalysisService analysisService,
    required ReviewService reviewService,
    required InstitutionCalendarService institutionCalendarService,
    required LocalWorkspaceService localWorkspaceService,
    WeatherService weatherService = const WeatherService(),
    VPetCompanionService? vPetCompanionService,
    PreferencesRepository? preferencesRepository,
    SessionsRepository? sessionsRepository,
    ManualEventsRepository? manualEventsRepository,
    CampusPlacesRepository? campusPlacesRepository,
    PdfDocumentsRepository? pdfDocumentsRepository,
  }) : _reviewService = reviewService,
       _institutionCalendarService = institutionCalendarService,
       _localWorkspaceService = localWorkspaceService,
       _weatherService = weatherService,
       _vPetCompanionService = vPetCompanionService ?? VPetCompanionService(),
       _preferencesRepository = preferencesRepository,
       _sessionsRepository = sessionsRepository,
       _manualEventsRepository = manualEventsRepository,
       _campusPlacesRepository = campusPlacesRepository,
       _pdfDocumentsRepository = pdfDocumentsRepository {
    _analysisCommitService = AnalysisCommitService(
      reviewService: reviewService,
      sessionsRepository: sessionsRepository,
    );
    analysisController = AnalysisController(
      importService: importService,
      analysisService: analysisService,
      reviewService: reviewService,
      commitService: _analysisCommitService,
      sessionHistory: () => _sessionHistory,
      findSessionById: _findSessionById,
      editingSessionId: () => _editingSessionId,
      nextSessionSequence: () => _sessionSequence++,
      onCommit: _handleAnalysisCommit,
    );
    analysisController.addListener(notifyListeners);
  }

  static const sampleText = '''
这周我完成了论文第二章的资料整理，周三和王老师同步了实验计划，
周四晚上和陈同学讨论数据清洗方案，周五跑了 4 公里。
下周二准备和导师开会确认论文框架，周末打算和朋友见面聊天。
''';

  static const _supportedImageExtensions = <String>[
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
  ];
  static const _vPetUpcomingTaskLimit = 3;
  static const _vPetUpcomingTaskLookAheadDays = 14;
  static const _defaultPdfCategory = '未分类';
  static const _minimumPdfReadingDuration = Duration(minutes: 5);

  static const defaultWeeklyPromptTemplate = '''
你是一名擅长中文周报润色的助手。请根据我提供的实际事项，整理成一段适合直接提交的周工作描述。
要求：
1. 只基于提供内容改写，不补充虚构信息。
2. 语气专业、自然、简洁，适度润色。
3. 优先写已完成工作，再带出后续计划。
4. 输出 1 到 2 段中文，不要使用标题，不要使用项目符号。
5. 如果涉及协作对象，只保留与工作推进相关的信息。

时间范围：
{{date_range}}

已完成事项（共 {{record_count}} 条）：
{{completed_items}}

计划事项（共 {{plan_count}} 条）：
{{planned_items}}

涉及人物（共 {{people_count}} 位）：
{{people}}

全部记录：
{{all_events}}
''';

  late final AnalysisController analysisController;
  late final AnalysisCommitService _analysisCommitService;
  final ReviewService _reviewService;
  final InstitutionCalendarService _institutionCalendarService;
  final LocalWorkspaceService _localWorkspaceService;
  final WeatherService _weatherService;
  final VPetCompanionService _vPetCompanionService;
  final PreferencesRepository? _preferencesRepository;
  final SessionsRepository? _sessionsRepository;
  final ManualEventsRepository? _manualEventsRepository;
  final CampusPlacesRepository? _campusPlacesRepository;
  final PdfDocumentsRepository? _pdfDocumentsRepository;

  SessionRecord? _latestSession;
  final List<SessionRecord> _sessionHistory = [];
  List<EventItem> _manualEvents = const [];
  List<EventItem> _institutionCalendarEvents = const [];
  String? _institutionCalendarTitle;
  final List<CampusPlace> _campusPlaces = _buildSampleCampusPlaces();
  final List<PdfLibraryDocument> _pdfDocuments = [];
  final Map<String, List<PdfTextAnnotation>> _pdfAnnotationsByDocumentId = {};
  List<WeatherLocation> _weatherSearchResults = const [];
  WeatherLocation? _weatherLocation;
  WeatherSnapshot? _weatherSnapshot;

  String? _editingSessionId;
  String? _editingInstitutionCalendarSessionId;

  String? _storageDirectoryPath;
  String? _homeImageFolderPath;
  String? _databaseFilePath;
  String? _researchWallImagePath;
  String? _lifeWallImagePath;
  bool _galleryInitialized = false;
  bool _galleryBusy = false;
  String _weeklyPromptTemplate = defaultWeeklyPromptTemplate;
  bool _weeklyPromptTemplateLoaded = false;
  bool _weeklyPromptTemplateBusy = false;
  AppColorTheme _colorTheme = AppColorTheme.green;
  bool _colorThemeLoaded = false;
  bool _colorThemeBusy = false;
  PdfReaderPreferences _pdfReaderPreferences = const PdfReaderPreferences();
  bool _pdfReaderPreferencesLoaded = false;
  bool _pdfReaderPreferencesBusy = false;
  LocalLlmAnalysisSettings _localLlmAnalysisSettings =
      const LocalLlmAnalysisSettings();
  bool _localLlmAnalysisSettingsLoaded = false;
  bool _localLlmAnalysisSettingsBusy = false;
  bool _ollamaConnectionTestBusy = false;
  bool _weatherLoaded = false;
  bool _weatherBusy = false;
  bool _weatherSearchBusy = false;
  String? _weatherError;
  Timer? _weatherRefreshTimer;
  bool _vPetCompanionLoaded = false;
  bool _vPetCompanionBusy = false;
  bool _vPetAutoStart = false;
  bool _vPetCloseWithApp = false;
  bool _vPetCloseWithAppConfigured = false;
  String? _vPetExecutablePath;
  bool _vPetUpcomingTaskReminderSent = false;
  bool _vPetUpcomingTaskReminderSending = false;
  bool _sessionHistoryLoaded = false;
  bool _sessionHistoryBusy = false;
  Future<void> _pendingSessionPersistence = Future<void>.value();
  Object? _sessionPersistenceError;
  bool _manualEventsLoaded = false;
  bool _manualEventsBusy = false;
  Future<void> _pendingManualEventPersistence = Future<void>.value();
  Object? _manualEventPersistenceError;
  bool _campusPlacesLoaded = false;
  bool _campusPlacesBusy = false;
  Future<void> _pendingCampusPlacePersistence = Future<void>.value();
  Object? _campusPlacePersistenceError;
  bool _pdfLibraryLoaded = false;
  bool _pdfLibraryBusy = false;
  Future<void> _pendingPdfPersistence = Future<void>.value();
  Object? _pdfPersistenceError;
  int _sessionSequence = 0;

  PersonHighlightTextEditingController get inputController =>
      analysisController.inputController;
  AnalysisInput? get currentInput => analysisController.currentInput;
  String get currentInputText => analysisController.currentInputText;
  AnalysisDraft? get currentDraft => analysisController.draft;
  ReviewPreview? get currentPreview => analysisController.preview;
  SessionRecord? get latestSession => _latestSession;
  List<SessionRecord> get sessionHistory => List.unmodifiable(_sessionHistory);
  List<EventItem> get manualEvents => List.unmodifiable(_manualEvents);
  List<PdfLibraryDocument> get pdfDocuments => List.unmodifiable(_pdfDocuments);
  List<EventItem> get institutionCalendarEvents => List.unmodifiable([
    for (final session in _institutionCalendarSessions) ...session.events,
    if (_institutionCalendarSessions.isEmpty) ..._institutionCalendarEvents,
  ]);
  List<CampusPlace> get campusPlaces => List.unmodifiable(_campusPlaces);
  List<EventItem> get calendarEvents => List.unmodifiable(
    _deduplicateCalendarEvents([
      for (final session in _sessionHistory) ...session.events,
      ..._manualEvents,
    ]),
  );
  String? get institutionCalendarTitle {
    final sessions = _institutionCalendarSessions;
    if (sessions.isEmpty) {
      return _institutionCalendarTitle;
    }
    return _institutionCalendarTitleFromSession(sessions.first);
  }

  String? get editingInstitutionCalendarSessionId =>
      _editingInstitutionCalendarSessionId;
  String? get editingInstitutionCalendarText {
    final sessionId = _editingInstitutionCalendarSessionId;
    if (sessionId == null) {
      return null;
    }
    return _findSessionById(sessionId)?.input.rawText;
  }

  String? get editingInstitutionCalendarTitle {
    final sessionId = _editingInstitutionCalendarSessionId;
    if (sessionId == null) {
      return null;
    }
    final session = _findSessionById(sessionId);
    return session == null
        ? null
        : _institutionCalendarTitleFromSession(session);
  }

  String get institutionCalendarPrompt =>
      InstitutionCalendarService.importPrompt;
  String get institutionCalendarTemplate =>
      InstitutionCalendarService.exampleTemplate;
  bool get isBusy => analysisController.isBusy;
  bool get lastImportSucceeded => analysisController.lastImportSucceeded;
  String? get sourceLabel => analysisController.sourceLabel;
  SessionRecord? get editingSession =>
      _editingSessionId == null ? null : _findSessionById(_editingSessionId!);
  String? get editingSessionLabel {
    final session = editingSession;
    if (session == null) {
      return null;
    }
    return _formatSessionPeriodLabel(session.confirmedAt);
  }

  String? get homeImageFolderPath => _homeImageFolderPath;
  String? get databaseFilePath => _databaseFilePath;
  String? get researchWallImagePath => _researchWallImagePath;
  String? get lifeWallImagePath => _lifeWallImagePath;
  String? get storageDirectoryPath => _storageDirectoryPath;
  bool get galleryBusy => _galleryBusy;
  String get weeklyPromptTemplate => _weeklyPromptTemplate;
  bool get weeklyPromptTemplateLoaded => _weeklyPromptTemplateLoaded;
  AppColorTheme get colorTheme => _colorTheme;
  bool get colorThemeLoaded => _colorThemeLoaded;
  PdfReaderPreferences get pdfReaderPreferences => _pdfReaderPreferences;
  bool get pdfReaderPreferencesLoaded => _pdfReaderPreferencesLoaded;
  LocalLlmAnalysisSettings get localLlmAnalysisSettings =>
      _localLlmAnalysisSettings;
  bool get localLlmAnalysisSettingsLoaded => _localLlmAnalysisSettingsLoaded;
  bool get localLlmAnalysisSettingsBusy => _localLlmAnalysisSettingsBusy;
  bool get ollamaConnectionTestBusy => _ollamaConnectionTestBusy;
  WeatherLocation? get weatherLocation => _weatherLocation;
  WeatherSnapshot? get weatherSnapshot => _weatherSnapshot;
  List<WeatherLocation> get weatherSearchResults =>
      List.unmodifiable(_weatherSearchResults);
  bool get weatherLoaded => _weatherLoaded;
  bool get weatherBusy => _weatherBusy;
  bool get weatherSearchBusy => _weatherSearchBusy;
  String? get weatherError => _weatherError;
  bool get vPetCompanionLoaded => _vPetCompanionLoaded;
  bool get vPetCompanionBusy => _vPetCompanionBusy;
  bool get vPetAutoStart => _vPetAutoStart;
  bool get vPetCloseWithApp => _vPetCloseWithApp;
  String? get vPetExecutablePath => _vPetExecutablePath;
  bool get vPetRunning => _vPetCompanionService.isRunning;
  int? get vPetProcessId => _vPetCompanionService.processId;
  bool get sessionHistoryLoaded => _sessionHistoryLoaded;
  bool get manualEventsLoaded => _manualEventsLoaded;
  bool get campusPlacesLoaded => _campusPlacesLoaded;
  bool get pdfLibraryLoaded => _pdfLibraryLoaded;
  bool get pdfLibraryBusy => _pdfLibraryBusy;

  List<PdfTextAnnotation> pdfAnnotationsFor(String documentId) =>
      List.unmodifiable(_pdfAnnotationsByDocumentId[documentId] ?? const []);

  Future<void> ensureSessionHistoryLoaded() async {
    final repository = _sessionsRepository;
    if (repository == null || _sessionHistoryLoaded || _sessionHistoryBusy) {
      return;
    }

    _sessionHistoryBusy = true;
    try {
      final loadedSessions = await repository.loadSessions();
      final mergedSessions =
          <String, SessionRecord>{
            for (final session in loadedSessions) session.id: session,
            for (final session in _sessionHistory) session.id: session,
          }.values.toList()..sort(
            (left, right) => right.confirmedAt.compareTo(left.confirmedAt),
          );

      _sessionHistory
        ..clear()
        ..addAll(mergedSessions);
      _latestSession = _latestAnalysisSession();
      _sessionHistoryLoaded = true;
      notifyListeners();
    } finally {
      _sessionHistoryBusy = false;
    }
  }

  Future<void> waitForPendingSessionPersistence() async {
    await _pendingSessionPersistence;
    final error = _sessionPersistenceError;
    if (error != null) {
      throw StateError('Session persistence failed: $error');
    }
  }

  Future<void> ensureManualEventsLoaded() async {
    final repository = _manualEventsRepository;
    if (repository == null || _manualEventsLoaded || _manualEventsBusy) {
      return;
    }

    _manualEventsBusy = true;
    try {
      final loadedEvents = await repository.loadManualEvents();
      final mergedEvents = <String, EventItem>{
        for (final event in loadedEvents) event.id: event,
        for (final event in _manualEvents) event.id: event,
      }.values.toList();
      _manualEvents = mergedEvents;
      _manualEventsLoaded = true;
      notifyListeners();
    } finally {
      _manualEventsBusy = false;
    }
  }

  Future<void> waitForPendingManualEventPersistence() async {
    await _pendingManualEventPersistence;
    final error = _manualEventPersistenceError;
    if (error != null) {
      throw StateError('Manual event persistence failed: $error');
    }
  }

  Future<void> waitForPendingPersistence() async {
    await waitForPendingSessionPersistence();
    await waitForPendingManualEventPersistence();
    await waitForPendingCampusPlacePersistence();
    await waitForPendingPdfPersistence();
  }

  Future<void> ensureCampusPlacesLoaded() async {
    final repository = _campusPlacesRepository;
    if (repository == null || _campusPlacesLoaded || _campusPlacesBusy) {
      return;
    }

    _campusPlacesBusy = true;
    try {
      final loadedPlaces = await repository.loadCampusPlaces();
      if (loadedPlaces.isNotEmpty) {
        _campusPlaces
          ..clear()
          ..addAll(loadedPlaces);
      } else if (await repository.hasSeededDefaults()) {
        _campusPlaces.clear();
      } else {
        await repository.saveCampusPlaces(_campusPlaces);
        await repository.markSeededDefaults();
      }
      _campusPlacesLoaded = true;
      notifyListeners();
    } finally {
      _campusPlacesBusy = false;
    }
  }

  Future<void> waitForPendingCampusPlacePersistence() async {
    await _pendingCampusPlacePersistence;
    final error = _campusPlacePersistenceError;
    if (error != null) {
      throw StateError('Campus place persistence failed: $error');
    }
  }

  Future<void> ensurePdfLibraryLoaded() async {
    final repository = _pdfDocumentsRepository;
    if (repository == null || _pdfLibraryLoaded || _pdfLibraryBusy) {
      return;
    }

    _setPdfLibraryBusy(true);
    try {
      final loadedDocuments = await repository.loadDocuments();
      _pdfDocuments
        ..clear()
        ..addAll(loadedDocuments);
      _pdfAnnotationsByDocumentId.clear();
      for (final document in loadedDocuments) {
        _pdfAnnotationsByDocumentId[document.id] = await repository
            .loadAnnotations(document.id);
      }
      _pdfLibraryLoaded = true;
      notifyListeners();
    } finally {
      _setPdfLibraryBusy(false);
    }
  }

  Future<void> waitForPendingPdfPersistence() async {
    await _pendingPdfPersistence;
    final error = _pdfPersistenceError;
    if (error != null) {
      throw StateError('PDF persistence failed: $error');
    }
  }

  Future<PdfLibraryDocument?> pickPdfDocument({
    String category = _defaultPdfCategory,
  }) async {
    const group = XTypeGroup(label: 'PDF 文献', extensions: ['pdf']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) {
      return null;
    }
    return addPdfDocumentFromPath(file.path, category: category);
  }

  Future<PdfLibraryDocument> addPdfDocumentFromPath(
    String path, {
    String category = _defaultPdfCategory,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('找不到这个 PDF 文件。');
    }
    if (_extensionOf(path) != 'pdf') {
      throw StateError('阅读模块目前只支持 PDF 文件。');
    }

    await ensurePdfLibraryLoaded();
    final now = DateTime.now();
    final archivedFile = await _localWorkspaceService.copyPdfIntoMaterials(
      file,
      category: category,
    );
    final normalizedCategory = category.trim().isEmpty
        ? _defaultPdfCategory
        : category.trim();
    final normalizedPath = _normalizeFilePath(archivedFile.path);
    final existingIndex = _pdfDocuments.indexWhere(
      (document) => _normalizeFilePath(document.path) == normalizedPath,
    );

    if (existingIndex != -1) {
      final updatedDocument = _pdfDocuments[existingIndex].copyWith(
        title: _fileTitleFromPath(archivedFile.path),
        category: normalizedCategory,
        lastOpenedAt: now,
        updatedAt: now,
      );
      _pdfDocuments
        ..removeAt(existingIndex)
        ..insert(0, updatedDocument);
      _queuePdfDocumentSave(updatedDocument);
      notifyListeners();
      return updatedDocument;
    }

    final document = PdfLibraryDocument(
      id: 'pdf_${now.microsecondsSinceEpoch}',
      title: _fileTitleFromPath(archivedFile.path),
      path: archivedFile.path,
      category: normalizedCategory,
      lastOpenedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    _pdfDocuments.insert(0, document);
    _pdfAnnotationsByDocumentId[document.id] = const [];
    _queuePdfDocumentSave(document);
    notifyListeners();
    return document;
  }

  String deletePdfDocument(String id) {
    final index = _pdfDocuments.indexWhere((document) => document.id == id);
    if (index == -1) {
      return '没有找到这份 PDF。';
    }

    final document = _pdfDocuments.removeAt(index);
    _pdfAnnotationsByDocumentId.remove(id);
    _queuePdfDocumentDelete(id);
    notifyListeners();
    return '已从阅读列表移除《${document.title}》。';
  }

  void markPdfDocumentOpened(String id) {
    _updatePdfDocument(id, (document) {
      final now = DateTime.now();
      return document.copyWith(lastOpenedAt: now, updatedAt: now);
    });
  }

  void updatePdfReadingPosition(String id, {int? pageNumber, int? pageCount}) {
    _updatePdfDocument(id, (document) {
      final resolvedPageCount = pageCount ?? document.pageCount;
      final resolvedPageNumber = pageNumber == null
          ? document.lastPage
          : _clampPdfPage(pageNumber, resolvedPageCount);
      if (resolvedPageNumber == document.lastPage &&
          resolvedPageCount == document.pageCount) {
        return document;
      }
      return document.copyWith(
        lastPage: resolvedPageNumber,
        pageCount: resolvedPageCount,
        updatedAt: DateTime.now(),
      );
    });
  }

  PdfLibraryDocument? pdfDocumentById(String id) {
    for (final document in _pdfDocuments) {
      if (document.id == id) {
        return document;
      }
    }
    return null;
  }

  Future<PdfTextAnnotation?> addPdfAnnotation({
    required String documentId,
    required int pageNumber,
    required PdfAnnotationKind kind,
    required String selectedText,
    required Iterable<PdfAnnotationRect> rects,
    required int colorValue,
    required double opacity,
    String? note,
  }) async {
    await ensurePdfLibraryLoaded();
    if (pdfDocumentById(documentId) == null) {
      return null;
    }

    final normalizedRects = rects
        .where((rect) => rect.width > 0 && rect.height > 0)
        .toList();
    if (normalizedRects.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final annotation = PdfTextAnnotation(
      id: 'pdf_note_${now.microsecondsSinceEpoch}',
      documentId: documentId,
      pageNumber: pageNumber,
      kind: kind,
      colorValue: colorValue,
      opacity: opacity.clamp(0.05, 1.0).toDouble(),
      selectedText: selectedText.trim(),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      rects: normalizedRects,
      createdAt: now,
      updatedAt: now,
    );

    final annotations = [
      ...(_pdfAnnotationsByDocumentId[documentId] ??
          const <PdfTextAnnotation>[]),
      annotation,
    ]..sort(_comparePdfAnnotations);
    _pdfAnnotationsByDocumentId[documentId] = annotations;
    _queuePdfAnnotationSave(annotation);
    notifyListeners();
    return annotation;
  }

  String deletePdfAnnotation(String documentId, String annotationId) {
    final annotations = _pdfAnnotationsByDocumentId[documentId];
    if (annotations == null) {
      return '没有找到这条标注。';
    }
    final nextAnnotations = annotations
        .where((annotation) => annotation.id != annotationId)
        .toList();
    if (nextAnnotations.length == annotations.length) {
      return '没有找到这条标注。';
    }

    _pdfAnnotationsByDocumentId[documentId] = nextAnnotations;
    _queuePdfAnnotationDelete(annotationId);
    notifyListeners();
    return '已删除标注。';
  }

  String updatePdfAnnotation(
    String documentId,
    String annotationId, {
    int? colorValue,
    double? opacity,
    String? note,
    bool clearNote = false,
  }) {
    final annotations = _pdfAnnotationsByDocumentId[documentId];
    if (annotations == null) {
      return '没有找到这条标注。';
    }
    final index = annotations.indexWhere(
      (annotation) => annotation.id == annotationId,
    );
    if (index == -1) {
      return '没有找到这条标注。';
    }

    final current = annotations[index];
    final normalizedNote = clearNote
        ? null
        : note == null
        ? current.note
        : note.trim().isEmpty
        ? null
        : note.trim();
    final updated = PdfTextAnnotation(
      id: current.id,
      documentId: current.documentId,
      pageNumber: current.pageNumber,
      kind: current.kind,
      colorValue: colorValue ?? current.colorValue,
      opacity: opacity == null
          ? current.opacity
          : opacity.clamp(0.05, 1.0).toDouble(),
      selectedText: current.selectedText,
      note: normalizedNote,
      rects: current.rects,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    final nextAnnotations = [...annotations]..[index] = updated;
    nextAnnotations.sort(_comparePdfAnnotations);
    _pdfAnnotationsByDocumentId[documentId] = nextAnnotations;
    _queuePdfAnnotationSave(updated);
    notifyListeners();
    return '已更新标注。';
  }

  bool pdfPageBookmarked(String documentId, int pageNumber) {
    return (_pdfAnnotationsByDocumentId[documentId] ?? const []).any(
      (annotation) =>
          annotation.kind == PdfAnnotationKind.bookmark &&
          annotation.pageNumber == pageNumber,
    );
  }

  Future<void> togglePdfPageBookmark({
    required String documentId,
    required int pageNumber,
  }) async {
    await ensurePdfLibraryLoaded();
    final annotations = _pdfAnnotationsByDocumentId[documentId] ?? const [];
    for (final annotation in annotations) {
      if (annotation.kind == PdfAnnotationKind.bookmark &&
          annotation.pageNumber == pageNumber) {
        deletePdfAnnotation(documentId, annotation.id);
        return;
      }
    }

    await addPdfAnnotation(
      documentId: documentId,
      pageNumber: pageNumber,
      kind: PdfAnnotationKind.bookmark,
      selectedText: '第 $pageNumber 页书签',
      rects: const [PdfAnnotationRect(left: 0, top: 30, right: 18, bottom: 0)],
      colorValue: 0xFFC29255,
      opacity: 0.92,
    );
  }

  Future<String?> recordPdfReadingSession({
    required String documentId,
    required DateTime startedAt,
    required DateTime endedAt,
    Duration minimumDuration = _minimumPdfReadingDuration,
  }) async {
    final document = pdfDocumentById(documentId);
    if (document == null) {
      return null;
    }
    final duration = endedAt.difference(startedAt);
    if (duration < minimumDuration) {
      return null;
    }

    await ensureManualEventsLoaded();
    final durationLabel = _formatReadingDuration(duration);
    final event = EventItem(
      id: 'reading_${endedAt.microsecondsSinceEpoch}',
      title: '阅读《${document.title}》$durationLabel',
      category: ItemCategory.study,
      type: EventType.record,
      startAt: startedAt,
      endAt: endedAt,
      origin: EventOrigin.manual,
      sourceLabel: '阅读',
    );
    _manualEvents = [..._manualEvents, event];
    _queueManualEventPersistence(event);
    notifyListeners();
    return '已记录阅读：${event.title}';
  }

  Future<String?> pickFileAndImport() async {
    return analysisController.importFile();
  }

  Future<String?> importFileFromPath(String path) async {
    return analysisController.importFileFromPath(path);
  }

  String? analyzeCurrentInput() {
    return analysisController.analyzeCurrentInput();
  }

  String? confirmDraft() {
    return analysisController.confirmDraft();
  }

  void _handleAnalysisCommit(AnalysisControllerCommitResult result) {
    final session = result.session;
    if (result.isNewSession) {
      _latestSession = session;
      _sessionHistory.insert(0, session);
      _sortSessionHistory();
      _queueSessionPersistence(session);
    } else {
      _replaceSessionRecord(session);
    }
    _editingSessionId = null;
    _editingInstitutionCalendarSessionId = null;
    notifyListeners();
  }

  String loadSessionForEditing(String sessionId) {
    final session = _findSessionById(sessionId);
    if (session == null || session.isInstitutionCalendar) {
      return '没有找到要编辑的周分析上传记录。';
    }

    _editingSessionId = session.id;
    _editingInstitutionCalendarSessionId = null;
    analysisController.loadSession(session);
    notifyListeners();
    return '已载入 ${_formatSessionPeriodLabel(session.confirmedAt)} 的周分析上传记录，可修改后重新分析并保存。';
  }

  String? cancelSessionEditing() {
    if (_editingSessionId == null) {
      return null;
    }

    _editingSessionId = null;
    notifyListeners();
    return '已退出编辑模式。';
  }

  String deleteSessionRecord(String sessionId) {
    final sessionIndex = _sessionHistory.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      return '没有找到要删除的历史记录。';
    }

    final removedSession = _sessionHistory.removeAt(sessionIndex);
    if (_latestSession?.id == removedSession.id) {
      _latestSession = _latestAnalysisSession();
    }
    if (_editingSessionId == removedSession.id) {
      _editingSessionId = null;
    }
    if (_editingInstitutionCalendarSessionId == removedSession.id) {
      _editingInstitutionCalendarSessionId = null;
    }
    analysisController.clearIfCurrentDraft(removedSession.draft.id);
    _queueSessionDelete(removedSession.id);
    notifyListeners();
    if (removedSession.isInstitutionCalendar) {
      return '已删除校历导入记录，并从主页日历移除相关校历事件。';
    }
    return '已删除历史记录，并移除相关人物、待办和规划事件。';
  }

  String fillSampleAndAnalyze() {
    _editingSessionId = null;
    _editingInstitutionCalendarSessionId = null;
    analysisController.loadTextInput(
      sampleText.trim(),
      sourceType: AnalysisSourceType.text,
    );
    return analyzeCurrentInput() ?? '已填入示例并完成分析。';
  }

  String addManualEvent({
    required DateTime date,
    required String title,
    required ItemCategory category,
    required EventType type,
  }) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return '标题不能为空。';
    }

    final day = DateTime(date.year, date.month, date.day);
    final event = EventItem(
      id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
      title: normalizedTitle,
      category: category,
      type: type,
      startAt: day,
      endAt: day,
      origin: EventOrigin.manual,
      sourceLabel: '手动添加',
    );
    _manualEvents = [..._manualEvents, event];
    _queueManualEventPersistence(event);
    notifyListeners();
    return '已添加记录。';
  }

  String updateEditableEvent({
    required String eventId,
    required String title,
    required ItemCategory category,
    required EventType type,
  }) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return '标题不能为空。';
    }

    final manualIndex = _manualEvents.indexWhere(
      (event) => event.id == eventId,
    );
    if (manualIndex != -1) {
      final target = _manualEvents[manualIndex];
      if (!target.isEditable) {
        return '该记录不允许修改。';
      }

      final nextManualEvents = [..._manualEvents];
      final updatedEvent = target.copyWith(
        title: normalizedTitle,
        category: category,
        type: type,
      );
      nextManualEvents[manualIndex] = updatedEvent;
      _manualEvents = nextManualEvents;
      _queueManualEventPersistence(updatedEvent);
      notifyListeners();
      return '已更新记录。';
    }

    final session = _findSessionByEventId(eventId);
    if (session == null) {
      return '当前没有可修改的记录。';
    }

    final sessionIndex = session.events.indexWhere(
      (event) => event.id == eventId,
    );
    if (sessionIndex == -1) {
      return '没有找到要修改的记录。';
    }

    final target = session.events[sessionIndex];
    if (!target.isEditable) {
      return '节假日和校历内容不允许修改。';
    }

    final updatedEvents = [...session.events];
    updatedEvents[sessionIndex] = target.copyWith(
      title: normalizedTitle,
      category: category,
      type: type,
    );
    if (sessionIndex >= session.draft.tasks.length) {
      return '记录与分析草稿不同步，暂时无法修改。';
    }

    final updatedTasks = [...session.draft.tasks];
    updatedTasks[sessionIndex] = updatedTasks[sessionIndex].copyWith(
      content: normalizedTitle,
      category: category,
      type: type,
    );
    final updatedDraft = session.draft.copyWith(
      tasks: updatedTasks,
      summary: _buildDraftSummary(updatedTasks, session.draft.persons),
    );
    final updatedPreview = _reviewService.buildPreview(updatedDraft);
    final updatedSession = session.copyWith(
      draft: updatedDraft,
      preview: updatedPreview,
      events: updatedEvents,
      people: _buildPeopleFromDraft(updatedDraft),
    );
    _replaceSessionRecord(updatedSession);
    notifyListeners();
    return '已更新记录。';
  }

  String mergePersons({
    required String primaryPersonId,
    required String secondaryPersonId,
  }) {
    if (primaryPersonId == secondaryPersonId) {
      return '请选择两个不同的人物。';
    }

    final primarySession = _findSessionByPersonId(primaryPersonId);
    final secondarySession = _findSessionByPersonId(secondaryPersonId);
    if (primarySession == null || secondarySession == null) {
      return '当前没有可合并的人物数据。';
    }
    if (primarySession.id != secondarySession.id) {
      return '暂不支持跨分析会话合并人物。';
    }
    final session = primarySession;

    final primaryProfile = _findPersonProfileById(
      session.people,
      primaryPersonId,
    );
    final secondaryProfile = _findPersonProfileById(
      session.people,
      secondaryPersonId,
    );
    if (primaryProfile == null || secondaryProfile == null) {
      return '未找到要合并的人物。';
    }

    final primaryDraft = _findPersonDraftById(
      session.draft.persons,
      primaryPersonId,
    );
    final secondaryDraft = _findPersonDraftById(
      session.draft.persons,
      secondaryPersonId,
    );
    if (primaryDraft == null || secondaryDraft == null) {
      return '人物草稿数据不完整，暂时无法合并。';
    }

    final primaryKnownNames = _collectKnownPersonNames(
      profile: primaryProfile,
      draft: primaryDraft,
    );
    final secondaryKnownNames = _collectKnownPersonNames(
      profile: secondaryProfile,
      draft: secondaryDraft,
    );
    final mergedKnownNames = <String>{
      ...primaryKnownNames,
      ...secondaryKnownNames,
    };
    final updatedTasks = session.draft.tasks
        .map(
          (task) => task.copyWith(
            relatedPersonNames: _mergePersonNames(
              task.relatedPersonNames,
              mergedKnownNames: mergedKnownNames,
              primaryName: primaryProfile.name,
            ),
          ),
        )
        .toList();
    final updatedDraftPersons = session.draft.persons
        .where((person) => person.id != secondaryPersonId)
        .map((person) {
          if (person.id != primaryPersonId) {
            return person;
          }

          return person.copyWith(
            name: primaryProfile.name,
            role: _resolveMergedPersonRole(
              primaryProfile.role,
              secondaryProfile.role,
            ),
            aliases: _buildMergedAliases(
              primaryName: primaryProfile.name,
              primaryKnownNames: primaryKnownNames,
              secondaryKnownNames: secondaryKnownNames,
            ),
            relatedTaskIndexes: _collectTaskIndexesForPerson(
              updatedTasks,
              primaryProfile.name,
            ),
          );
        })
        .toList();
    final updatedDraft = session.draft.copyWith(
      tasks: updatedTasks,
      persons: updatedDraftPersons,
      summary: _buildDraftSummary(updatedTasks, updatedDraftPersons),
    );
    final updatedPreview = _reviewService.buildPreview(updatedDraft);
    final updatedEvents = session.events
        .map(
          (event) => event.copyWith(
            personNames: _mergePersonNames(
              event.personNames,
              mergedKnownNames: mergedKnownNames,
              primaryName: primaryProfile.name,
            ),
          ),
        )
        .toList();
    final updatedSession = session.copyWith(
      draft: updatedDraft,
      preview: updatedPreview,
      events: updatedEvents,
      people: _buildPeopleFromDraft(updatedDraft),
    );

    _replaceSessionRecord(updatedSession);
    notifyListeners();
    return '已将“${secondaryProfile.name}”合并到“${primaryProfile.name}”。';
  }

  String renamePerson({
    required String personId,
    required String nextName,
    bool keepOriginalNameAsAlias = true,
  }) {
    final normalizedName = nextName.trim();
    if (normalizedName.isEmpty) {
      return '称谓不能为空。';
    }

    final session = _findSessionByPersonId(personId);
    if (session == null) {
      return '当前没有可编辑的人物数据。';
    }

    final profile = _findPersonProfileById(session.people, personId);
    final draftPerson = _findPersonDraftById(session.draft.persons, personId);
    if (profile == null || draftPerson == null) {
      return '未找到要编辑的人物。';
    }
    if (normalizedName == profile.name) {
      return '称谓未发生变化。';
    }
    if (_hasPersonNameConflict(
      people: session.people,
      personId: personId,
      candidateName: normalizedName,
    )) {
      return '已存在同名人物，请直接使用“合并人物”。';
    }

    final knownNames = _collectKnownPersonNames(
      profile: profile,
      draft: draftPerson,
    );
    final updatedTasks = session.draft.tasks
        .map(
          (task) => task.copyWith(
            relatedPersonNames: _mergePersonNames(
              task.relatedPersonNames,
              mergedKnownNames: knownNames,
              primaryName: normalizedName,
            ),
          ),
        )
        .toList();
    final updatedDraftPersons = session.draft.persons.map((person) {
      if (person.id != personId) {
        return person;
      }

      return person.copyWith(
        name: normalizedName,
        aliases: _buildRenamedAliases(
          nextName: normalizedName,
          knownNames: knownNames,
          originalNames: {profile.name, draftPerson.name},
          keepOriginalNameAsAlias: keepOriginalNameAsAlias,
        ),
        relatedTaskIndexes: _collectTaskIndexesForPerson(
          updatedTasks,
          normalizedName,
        ),
      );
    }).toList();
    final updatedDraft = session.draft.copyWith(
      tasks: updatedTasks,
      persons: updatedDraftPersons,
      summary: _buildDraftSummary(updatedTasks, updatedDraftPersons),
    );
    final updatedPreview = _reviewService.buildPreview(updatedDraft);
    final updatedEvents = session.events
        .map(
          (event) => event.copyWith(
            personNames: _mergePersonNames(
              event.personNames,
              mergedKnownNames: knownNames,
              primaryName: normalizedName,
            ),
          ),
        )
        .toList();
    final updatedSession = session.copyWith(
      draft: updatedDraft,
      preview: updatedPreview,
      events: updatedEvents,
      people: _buildPeopleFromDraft(updatedDraft),
    );

    _replaceSessionRecord(updatedSession);
    notifyListeners();
    return '已将人物称谓更新为“$normalizedName”。';
  }

  String importInstitutionCalendar(String rawText) {
    final result = _institutionCalendarService.parse(rawText);
    final now = DateTime.now();
    final targetSession = _editingInstitutionCalendarSessionId == null
        ? _findDuplicateInstitutionCalendarSession(rawText)
        : _findSessionById(_editingInstitutionCalendarSessionId!);
    final sessionKey = targetSession == null
        ? 'calendar_${now.microsecondsSinceEpoch}_${_sessionSequence++}'
        : _sessionKeyFromId(targetSession.id);
    final session = _buildInstitutionCalendarSession(
      rawText: rawText.trim(),
      result: result,
      sessionKey: sessionKey,
      confirmedAt: targetSession?.confirmedAt ?? now,
      createdAt: targetSession?.draft.createdAt ?? now,
    );

    if (targetSession == null) {
      _sessionHistory.insert(0, session);
      _sortSessionHistory();
      _queueSessionPersistence(session);
    } else {
      _replaceSessionRecord(session);
    }

    _editingInstitutionCalendarSessionId = null;
    _institutionCalendarEvents = const [];
    _institutionCalendarTitle = result.title;
    notifyListeners();

    final actionLabel = targetSession == null ? '已保存到历史记录。' : '已更新校历导入记录。';
    if (result.warnings.isEmpty) {
      return '${result.summary}$actionLabel';
    }
    return '${result.summary}$actionLabel\n${result.warnings.join('\n')}';
  }

  String clearInstitutionCalendar() {
    final calendarSessions = _institutionCalendarSessions;
    if (calendarSessions.isEmpty && _institutionCalendarEvents.isEmpty) {
      return '当前没有已导入的校历。';
    }

    final removedIds = calendarSessions.map((session) => session.id).toList();
    _sessionHistory.removeWhere((session) => session.isInstitutionCalendar);
    for (final sessionId in removedIds) {
      _queueSessionDelete(sessionId);
    }
    _latestSession = _latestAnalysisSession();
    _editingInstitutionCalendarSessionId = null;
    _institutionCalendarEvents = const [];
    _institutionCalendarTitle = null;
    notifyListeners();
    return '已清空校历导入内容。';
  }

  String loadInstitutionCalendarForEditing(String sessionId) {
    final session = _findSessionById(sessionId);
    if (session == null || !session.isInstitutionCalendar) {
      return '没有找到要编辑的校历导入记录。';
    }

    _editingInstitutionCalendarSessionId = session.id;
    _editingSessionId = null;
    notifyListeners();
    return '已载入“${session.title}”，可在设置页修改固定格式文本后保存。';
  }

  String? cancelInstitutionCalendarEditing() {
    if (_editingInstitutionCalendarSessionId == null) {
      return null;
    }

    _editingInstitutionCalendarSessionId = null;
    notifyListeners();
    return '已退出校历编辑模式。';
  }

  void clearComposer() {
    _editingSessionId = null;
    _editingInstitutionCalendarSessionId = null;
    analysisController.clearComposer();
    notifyListeners();
  }

  void clearDraftOnly() {
    analysisController.clearDraft();
  }

  Future<void> ensureWeeklyPromptTemplateLoaded() async {
    if (_weeklyPromptTemplateLoaded || _weeklyPromptTemplateBusy) {
      return;
    }

    _weeklyPromptTemplateBusy = true;
    try {
      final storedTemplate = await _loadStoredWeeklyPromptTemplate();
      if (storedTemplate != null && storedTemplate.trim().isNotEmpty) {
        _weeklyPromptTemplate = storedTemplate;
      }
      _weeklyPromptTemplateLoaded = true;
      notifyListeners();
    } finally {
      _weeklyPromptTemplateBusy = false;
    }
  }

  Future<void> ensureColorThemeLoaded() async {
    if (_colorThemeLoaded || _colorThemeBusy) {
      return;
    }

    _colorThemeBusy = true;
    try {
      final storedTheme = await _preferencesRepository?.loadColorTheme();
      _colorTheme = AppColorThemeDetails.fromStorageValue(storedTheme);
      _colorThemeLoaded = true;
      notifyListeners();
    } finally {
      _colorThemeBusy = false;
    }
  }

  Future<String> setColorTheme(AppColorTheme theme) async {
    if (_colorTheme == theme && _colorThemeLoaded) {
      return '已切换到${theme.label}主题。';
    }

    await _preferencesRepository?.saveColorTheme(theme.storageValue);
    _colorTheme = theme;
    _colorThemeLoaded = true;
    notifyListeners();
    return '已切换到${theme.label}主题。';
  }

  Future<void> ensurePdfReaderPreferencesLoaded() async {
    if (_pdfReaderPreferencesLoaded || _pdfReaderPreferencesBusy) {
      return;
    }

    _pdfReaderPreferencesBusy = true;
    try {
      _pdfReaderPreferences = await _loadStoredPdfReaderPreferences();
      _pdfReaderPreferencesLoaded = true;
      notifyListeners();
    } finally {
      _pdfReaderPreferencesBusy = false;
    }
  }

  Future<void> savePdfReaderPreferences(
    PdfReaderPreferences preferences,
  ) async {
    _pdfReaderPreferences = preferences;
    _pdfReaderPreferencesLoaded = true;
    notifyListeners();
    await _saveStoredPdfReaderPreferences(preferences);
  }

  Future<void> ensureLocalLlmAnalysisSettingsLoaded() async {
    if (_localLlmAnalysisSettingsLoaded || _localLlmAnalysisSettingsBusy) {
      return;
    }

    _setLocalLlmAnalysisSettingsBusy(true);
    try {
      _localLlmAnalysisSettings = await _loadStoredLocalLlmAnalysisSettings();
      _localLlmAnalysisSettingsLoaded = true;
      notifyListeners();
    } finally {
      _setLocalLlmAnalysisSettingsBusy(false);
    }
  }

  Future<String> saveLocalLlmAnalysisSettings(
    LocalLlmAnalysisSettings settings,
  ) async {
    final normalizedSettings = settings.copyWith();
    _setLocalLlmAnalysisSettingsBusy(true);
    try {
      _localLlmAnalysisSettings = normalizedSettings;
      _localLlmAnalysisSettingsLoaded = true;
      await _saveStoredLocalLlmAnalysisSettings(normalizedSettings);
      notifyListeners();
      return '本地 LLM 周分析设置已保存。';
    } finally {
      _setLocalLlmAnalysisSettingsBusy(false);
    }
  }

  Future<String> testOllamaConnection() async {
    await ensureLocalLlmAnalysisSettingsLoaded();
    if (_ollamaConnectionTestBusy) {
      return 'Ollama 连接测试正在进行。';
    }

    final settings = _localLlmAnalysisSettings;
    _setOllamaConnectionTestBusy(true);
    OllamaClient? client;
    try {
      client = OllamaClient(
        baseUri: Uri.parse(settings.ollamaBaseUrl),
        timeout: Duration(seconds: settings.ollamaTimeoutSeconds),
      );
      await client.checkHealth();
      final models = await client.listModels();
      final modelName = settings.ollamaModel.trim();
      final hasModel = models.any(
        (model) => model.name == modelName || model.model == modelName,
      );
      if (!hasModel) {
        return 'Ollama 已连接，但未找到模型 $modelName。请执行：ollama pull $modelName';
      }
      return 'Ollama 连接正常，已找到模型 $modelName。';
    } on FormatException {
      return 'Ollama 地址格式无效，请检查 ${settings.ollamaBaseUrl}。';
    } on OllamaTimeoutException catch (error) {
      return 'Ollama 连接测试超时：${error.message}';
    } on OllamaHttpStatusException catch (error) {
      return 'Ollama 返回 HTTP ${error.statusCode}，请确认服务可用。';
    } on OllamaInvalidJsonException catch (error) {
      return 'Ollama 返回内容不是有效 JSON：${error.message}';
    } on OllamaConnectionException catch (error) {
      return '无法连接 Ollama：${error.message}';
    } on OllamaClientException catch (error) {
      return 'Ollama 连接测试失败：${error.message}';
    } catch (error) {
      return 'Ollama 连接测试失败：$error';
    } finally {
      client?.close(force: true);
      _setOllamaConnectionTestBusy(false);
    }
  }

  Future<void> ensureVPetCompanionLoaded({bool autoStart = false}) async {
    if (_vPetCompanionBusy) {
      return;
    }
    if (_vPetCompanionLoaded) {
      if (autoStart && _vPetAutoStart && !vPetRunning) {
        await startVPetCompanion();
      }
      return;
    }

    _setVPetCompanionBusy(true);
    try {
      final settings = await _loadStoredVPetCompanionSettings();
      _vPetExecutablePath = settings.executablePath;
      _vPetAutoStart = settings.autoStart;
      _vPetCloseWithApp = settings.closeWithApp;
      _vPetCloseWithAppConfigured = settings.closeWithAppConfigured;
      _vPetExecutablePath ??= await _vPetCompanionService
          .findDefaultExecutablePath();
      _vPetCompanionLoaded = true;
      notifyListeners();

      if (autoStart && _vPetAutoStart && !vPetRunning) {
        await startVPetCompanion();
      }
    } finally {
      _setVPetCompanionBusy(false);
    }
  }

  Future<String> chooseVPetExecutable() async {
    await ensureVPetCompanionLoaded();
    final selectedFile = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Windows 可执行文件', extensions: ['exe']),
      ],
    );
    if (selectedFile == null) {
      return '已取消选择 VPet 程序。';
    }

    final selectedPath = selectedFile.path;
    if (!selectedPath.toLowerCase().endsWith('.exe')) {
      return '请选择 VPet-Simulator.Windows.exe。';
    }

    _vPetExecutablePath = selectedPath;
    await _saveStoredVPetCompanionSettings();
    notifyListeners();
    return '已选择 VPet 程序：$selectedPath';
  }

  Future<String> setVPetAutoStart(bool value) async {
    await ensureVPetCompanionLoaded();
    _vPetAutoStart = value;
    await _saveStoredVPetCompanionSettings();
    notifyListeners();
    return value ? '已开启随研究生活启动 VPet。' : '已关闭随研究生活启动 VPet。';
  }

  Future<String> setVPetCloseWithApp(bool value) async {
    await ensureVPetCompanionLoaded();
    _vPetCloseWithApp = value;
    _vPetCloseWithAppConfigured = true;
    await _saveStoredVPetCompanionSettings();
    notifyListeners();
    return value ? '退出研究生活时会尝试关闭 VPet。' : '退出研究生活时会保留 VPet。';
  }

  Future<String> startVPetCompanion() async {
    await ensureVPetCompanionLoaded();
    if (vPetRunning) {
      return 'VPet 已在运行。';
    }

    final executablePath = _vPetExecutablePath;
    if (executablePath == null || executablePath.trim().isEmpty) {
      return '请先选择 VPet-Simulator.Windows.exe。';
    }

    _setVPetCompanionBusy(true);
    try {
      await _vPetCompanionService.launch(
        executablePath: executablePath,
        onExit: () {
          if (!hasListeners) {
            return;
          }
          notifyListeners();
        },
      );
      notifyListeners();
      unawaited(_sendVPetUpcomingTaskReminderOnce());
      return '已启动 VPet 桌宠。';
    } on FileSystemException catch (error) {
      return '启动 VPet 失败：${error.message}';
    } catch (error) {
      return '启动 VPet 失败：$error';
    } finally {
      _setVPetCompanionBusy(false);
    }
  }

  Future<String> stopVPetCompanion() async {
    if (!vPetRunning) {
      return 'VPet 当前没有由研究生活启动。';
    }

    _setVPetCompanionBusy(true);
    try {
      final stopped = await _vPetCompanionService.stop();
      notifyListeners();
      return stopped ? '已关闭 VPet 桌宠。' : '未能关闭 VPet 桌宠。';
    } finally {
      _setVPetCompanionBusy(false);
    }
  }

  Future<String> sendVPetTestMessage() async {
    await ensureVPetCompanionLoaded();
    if (!vPetRunning) {
      return '请先启动 VPet 桌宠。';
    }

    _setVPetCompanionBusy(true);
    try {
      await _vPetCompanionService.say('研究生活已经连接到 VPet。', force: true);
      return '已发送测试消息给 VPet。';
    } on SocketException catch (error) {
      return 'VPet IPC 连接失败：${error.message}';
    } on HttpException catch (error) {
      return 'VPet IPC 请求失败：${error.message}';
    } catch (error) {
      return 'VPet IPC 通信失败：$error';
    } finally {
      _setVPetCompanionBusy(false);
    }
  }

  Future<void> _sendVPetUpcomingTaskReminderOnce() async {
    if (_vPetUpcomingTaskReminderSent ||
        _vPetUpcomingTaskReminderSending ||
        !vPetRunning) {
      return;
    }

    _vPetUpcomingTaskReminderSending = true;
    try {
      await ensureSessionHistoryLoaded();
      await ensureManualEventsLoaded();

      final upcomingTasks = _collectUpcomingTaskReminders(
        now: DateTime.now(),
        limit: _vPetUpcomingTaskLimit,
      );
      if (upcomingTasks.isEmpty) {
        _vPetUpcomingTaskReminderSent = true;
        return;
      }

      final ready = await _vPetCompanionService.waitUntilReady();
      if (!ready || !vPetRunning) {
        return;
      }

      await _vPetCompanionService.say(
        _buildVPetUpcomingTaskReminder(upcomingTasks, DateTime.now()),
        force: true,
      );
      _vPetUpcomingTaskReminderSent = true;
    } catch (_) {
      // Startup reminders should never interrupt opening the app.
    } finally {
      _vPetUpcomingTaskReminderSending = false;
    }
  }

  Future<void> ensureWeatherLoaded({bool force = false}) async {
    if (_weatherBusy) {
      return;
    }
    if (_weatherLoaded && !force) {
      _ensureWeatherRefreshTimer();
      return;
    }

    _setWeatherBusy(true);
    try {
      WeatherLocation? location = _weatherLocation;
      location ??= await _loadStoredWeatherLocation();
      location ??= await _weatherService.detectLocalLocation();

      final snapshot = await _weatherService.fetchCurrentWeather(location);
      _weatherLocation = snapshot.location;
      _weatherSnapshot = snapshot;
      _weatherLoaded = true;
      _weatherError = null;
      _ensureWeatherRefreshTimer();
      notifyListeners();
    } on WeatherServiceException catch (error) {
      _weatherLoaded = true;
      _weatherError = error.message;
      notifyListeners();
    } catch (error) {
      _weatherLoaded = true;
      _weatherError = '天气更新失败：$error';
      notifyListeners();
    } finally {
      _setWeatherBusy(false);
    }
  }

  Future<String> refreshWeather() async {
    await ensureWeatherLoaded(force: true);
    return _weatherError == null ? '天气已更新。' : _weatherError!;
  }

  Future<List<WeatherLocation>> searchWeatherLocations(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      _weatherSearchResults = const [];
      _weatherError = null;
      notifyListeners();
      return const [];
    }

    _setWeatherSearchBusy(true);
    try {
      final results = await _weatherService.searchLocations(normalizedQuery);
      _weatherSearchResults = results;
      _weatherError = null;
      notifyListeners();
      return results;
    } on WeatherServiceException catch (error) {
      _weatherSearchResults = const [];
      _weatherError = error.message;
      notifyListeners();
      return const [];
    } catch (error) {
      _weatherSearchResults = const [];
      _weatherError = '城市搜索失败：$error';
      notifyListeners();
      return const [];
    } finally {
      _setWeatherSearchBusy(false);
    }
  }

  Future<String> useWeatherLocation(WeatherLocation location) async {
    final selectedLocation = location.copyWith(
      source: WeatherLocationSource.selected,
    );

    await _saveStoredWeatherLocation(selectedLocation);
    _weatherLocation = selectedLocation;
    _weatherSnapshot = null;
    _weatherLoaded = false;
    await ensureWeatherLoaded(force: true);

    if (_weatherError != null) {
      return '已保存${selectedLocation.city}，但天气暂不可用：$_weatherError';
    }
    return '已切换到${selectedLocation.city}天气。';
  }

  Future<String> useAutomaticWeatherLocation() async {
    await _clearStoredWeatherLocation();
    _weatherLocation = null;
    _weatherSnapshot = null;
    _weatherLoaded = false;
    await ensureWeatherLoaded(force: true);

    if (_weatherError != null) {
      return '自动定位失败：$_weatherError';
    }
    return '已切换到当前位置天气。';
  }

  Future<String> saveWeeklyPromptTemplate(String template) async {
    final normalizedTemplate = template.trim();
    if (normalizedTemplate.isEmpty) {
      return '常用提示词模板不能为空。';
    }

    await _saveStoredWeeklyPromptTemplate(normalizedTemplate);
    _weeklyPromptTemplate = normalizedTemplate;
    _weeklyPromptTemplateLoaded = true;
    notifyListeners();
    return '已设为常用提示词模板。';
  }

  Future<String> resetWeeklyPromptTemplate() async {
    await _saveStoredWeeklyPromptTemplate(defaultWeeklyPromptTemplate);
    _weeklyPromptTemplate = defaultWeeklyPromptTemplate;
    _weeklyPromptTemplateLoaded = true;
    notifyListeners();
    return '已恢复默认提示词模板。';
  }

  Future<String?> _loadStoredWeeklyPromptTemplate() async {
    final repository = _preferencesRepository;
    if (repository == null) {
      return _localWorkspaceService.loadWeeklyPromptTemplate();
    }

    final storedTemplate = await repository.loadWeeklyPromptTemplate();
    if (storedTemplate != null && storedTemplate.trim().isNotEmpty) {
      return storedTemplate;
    }

    final legacyTemplate = await _localWorkspaceService
        .loadWeeklyPromptTemplate();
    if (legacyTemplate != null && legacyTemplate.trim().isNotEmpty) {
      await repository.saveWeeklyPromptTemplate(legacyTemplate);
      return legacyTemplate;
    }

    return null;
  }

  Future<void> _saveStoredWeeklyPromptTemplate(String template) {
    final repository = _preferencesRepository;
    if (repository == null) {
      return _localWorkspaceService.saveWeeklyPromptTemplate(template);
    }
    return repository.saveWeeklyPromptTemplate(template);
  }

  Future<PdfReaderPreferences> _loadStoredPdfReaderPreferences() async {
    final rawPreferences = await _preferencesRepository
        ?.loadPdfReaderPreferences();
    if (rawPreferences == null || rawPreferences.trim().isEmpty) {
      return const PdfReaderPreferences();
    }

    try {
      final decoded = jsonDecode(rawPreferences);
      if (decoded is Map) {
        return PdfReaderPreferences.fromJson(decoded.cast<String, Object?>());
      }
    } on FormatException {
      return const PdfReaderPreferences();
    }
    return const PdfReaderPreferences();
  }

  Future<void> _saveStoredPdfReaderPreferences(
    PdfReaderPreferences preferences,
  ) async {
    await _preferencesRepository?.savePdfReaderPreferences(
      jsonEncode(preferences.toJson()),
    );
  }

  Future<LocalLlmAnalysisSettings> _loadStoredLocalLlmAnalysisSettings() async {
    final rawSettings = await _preferencesRepository
        ?.loadLocalLlmAnalysisSettings();
    if (rawSettings == null || rawSettings.trim().isEmpty) {
      return const LocalLlmAnalysisSettings();
    }

    try {
      final decoded = jsonDecode(rawSettings);
      if (decoded is Map) {
        return LocalLlmAnalysisSettings.fromJson(
          decoded.cast<String, Object?>(),
        );
      }
    } on FormatException {
      return const LocalLlmAnalysisSettings();
    }
    return const LocalLlmAnalysisSettings();
  }

  Future<void> _saveStoredLocalLlmAnalysisSettings(
    LocalLlmAnalysisSettings settings,
  ) async {
    await _preferencesRepository?.saveLocalLlmAnalysisSettings(
      jsonEncode(settings.toJson()),
    );
  }

  Future<WeatherLocation?> _loadStoredWeatherLocation() async {
    final rawLocation = await _preferencesRepository?.loadWeatherLocation();
    if (rawLocation == null || rawLocation.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawLocation);
      if (decoded is Map) {
        return WeatherLocation.fromJson(decoded.cast<String, Object?>());
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> _saveStoredWeatherLocation(WeatherLocation location) async {
    await _preferencesRepository?.saveWeatherLocation(
      jsonEncode(location.toJson()),
    );
  }

  Future<void> _clearStoredWeatherLocation() async {
    await _preferencesRepository?.clearWeatherLocation();
  }

  Future<_VPetCompanionSettings> _loadStoredVPetCompanionSettings() async {
    final rawSettings = await _preferencesRepository
        ?.loadVPetCompanionSettings();
    if (rawSettings == null || rawSettings.trim().isEmpty) {
      return const _VPetCompanionSettings();
    }

    try {
      final decoded = jsonDecode(rawSettings);
      if (decoded is Map) {
        return _VPetCompanionSettings.fromJson(decoded.cast<String, Object?>());
      }
    } on FormatException {
      return const _VPetCompanionSettings();
    }
    return const _VPetCompanionSettings();
  }

  Future<void> _saveStoredVPetCompanionSettings() async {
    await _preferencesRepository?.saveVPetCompanionSettings(
      jsonEncode(
        _VPetCompanionSettings(
          executablePath: _vPetExecutablePath,
          autoStart: _vPetAutoStart,
          closeWithApp: _vPetCloseWithApp,
          closeWithAppConfigured: _vPetCloseWithAppConfigured,
        ).toJson(),
      ),
    );
  }

  String buildWeeklyReportPrompt({
    required DateTime start,
    required DateTime end,
    required List<EventItem> rangeEvents,
    String? templateOverride,
  }) {
    final effectiveTemplate = (templateOverride ?? '').trim().isEmpty
        ? _weeklyPromptTemplate
        : templateOverride!.trim();
    final sortedEvents = [...rangeEvents]
      ..sort((left, right) => left.startAt.compareTo(right.startAt));
    final records = sortedEvents
        .where((event) => event.type == EventType.record)
        .toList();
    final plans = sortedEvents
        .where((event) => event.type == EventType.plan)
        .toList();
    final people = _collectUniquePeople(sortedEvents);

    final replacements = <String, String>{
      '{{date_range}}': '${_formatMonthDay(start)} - ${_formatMonthDay(end)}',
      '{{record_count}}': '${records.length}',
      '{{plan_count}}': '${plans.length}',
      '{{people_count}}': '${people.length}',
      '{{completed_items}}': _formatPromptEventList(records),
      '{{planned_items}}': _formatPromptEventList(plans),
      '{{people}}': _formatPeopleList(people),
      '{{all_events}}': _formatPromptEventList(sortedEvents, includeMeta: true),
    };

    var prompt = effectiveTemplate;
    for (final entry in replacements.entries) {
      prompt = prompt.replaceAll(entry.key, entry.value);
    }
    return prompt.trim();
  }

  Future<void> ensureHomeGalleryReady() async {
    if (_galleryInitialized || _galleryBusy) {
      return;
    }

    _setGalleryBusy(true);
    try {
      final storageDirectory = await _localWorkspaceService
          .resolveStorageDirectory();
      final databaseFile = await _localWorkspaceService.resolveDatabaseFile();
      final folder = Directory(
        '${storageDirectory.parent.path}${Platform.pathSeparator}home_images',
      );
      await _migrateLegacyHomeImageFolderIfNeeded(storageDirectory, folder);
      await folder.create(recursive: true);
      await _ensureReadme(folder);

      _storageDirectoryPath = storageDirectory.path;
      _databaseFilePath = databaseFile.path;
      _homeImageFolderPath = folder.path;
      await refreshHomeImages(notify: false);
      _galleryInitialized = true;
      notifyListeners();
    } finally {
      _setGalleryBusy(false);
    }
  }

  Future<String?> refreshHomeImages({bool notify = true}) async {
    if (_homeImageFolderPath == null) {
      return null;
    }

    _researchWallImagePath = await _findImageForSlot(
      HomeImageSlot.researchWall,
    );
    _lifeWallImagePath = await _findImageForSlot(HomeImageSlot.lifeWall);

    if (_researchWallImagePath != null) {
      await FileImage(File(_researchWallImagePath!)).evict();
    }
    if (_lifeWallImagePath != null) {
      await FileImage(File(_lifeWallImagePath!)).evict();
    }

    if (notify) {
      notifyListeners();
      return '图片已刷新。';
    }
    return null;
  }

  Future<String?> replaceHomeImage(HomeImageSlot slot) async {
    await ensureHomeGalleryReady();
    const group = XTypeGroup(
      label: '主页图片',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) {
      return null;
    }

    return replaceHomeImageFromPath(slot, file.path);
  }

  Future<String?> replaceHomeImageFromPath(
    HomeImageSlot slot,
    String sourcePath,
  ) async {
    await ensureHomeGalleryReady();
    final folderPath = _homeImageFolderPath;
    if (folderPath == null) {
      return '图片文件夹初始化失败。';
    }

    _setGalleryBusy(true);
    final backupSuffix = '.bak_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final extension = _extensionOf(sourcePath);
      final targetPath =
          '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.$extension';
      final tempPath =
          '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.incoming.$extension';
      final backupPaths = <String>[];
      await File(sourcePath).copy(tempPath);

      for (final existingFile in await _existingSlotFiles(slot)) {
        final backupPath = '${existingFile.path}$backupSuffix';
        await existingFile.rename(backupPath);
        backupPaths.add(backupPath);
      }

      await File(tempPath).rename(targetPath);
      await FileImage(File(targetPath)).evict();
      for (final backupPath in backupPaths) {
        final backupFile = File(backupPath);
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
      }
      await refreshHomeImages(notify: false);
      notifyListeners();
      return '已更新${slot.label}图片。';
    } on FileSystemException catch (error) {
      await _restoreSlotReplacement(slot, backupSuffix);
      return '替换图片失败：${error.message}';
    } finally {
      _setGalleryBusy(false);
    }
  }

  Future<String?> openHomeImageFolder() async {
    await ensureHomeGalleryReady();
    final folderPath = _homeImageFolderPath;
    if (folderPath == null) {
      return '图片文件夹初始化失败。';
    }

    return _openFolder(folderPath, '图片文件夹');
  }

  Future<String?> openStorageFolder() async {
    await ensureHomeGalleryReady();
    final storagePath = _storageDirectoryPath;
    if (storagePath == null) {
      return '应用数据目录初始化失败。';
    }

    return _openFolder(storagePath, '应用数据目录');
  }

  Future<String?> openDatabaseFolder() async {
    await ensureHomeGalleryReady();
    final databasePath = _databaseFilePath;
    if (databasePath == null) {
      return '数据库文件路径初始化失败。';
    }

    return _openFolder(File(databasePath).parent.path, '数据库所在文件夹');
  }

  Future<String?> backupDatabase() async {
    await ensureHomeGalleryReady();
    await waitForPendingPersistence();

    try {
      final copiedFiles = await _localWorkspaceService.backupDatabaseFiles();
      if (copiedFiles.isEmpty) {
        return '数据库文件还没有创建，暂无可备份内容。';
      }

      final backupFolder = copiedFiles.first.parent.path;
      return '数据库已备份到：$backupFolder';
    } on FileSystemException catch (error) {
      return '备份数据库失败：${error.message}';
    }
  }

  CampusPlace createCampusPlace({
    required String name,
    required PlaceCategory category,
    required String note,
    required double normalizedDx,
    required double normalizedDy,
    required String iconKey,
    required String colorKey,
    int? zoneId,
    bool isMine = true,
  }) {
    final now = DateTime.now();
    final place = CampusPlace(
      id: 'place_${now.microsecondsSinceEpoch}',
      name: name.trim(),
      category: category,
      note: note.trim(),
      normalizedDx: _normalizeFraction(normalizedDx),
      normalizedDy: _normalizeFraction(normalizedDy),
      iconKey: iconKey,
      colorKey: colorKey,
      zoneId: zoneId,
      createdAt: now,
      updatedAt: now,
      isMine: isMine,
    );
    _campusPlaces.insert(0, place);
    _queueCampusPlaceSave(place);
    notifyListeners();
    return place;
  }

  bool updateCampusPlace({
    required String id,
    required String name,
    required PlaceCategory category,
    required String note,
    required double normalizedDx,
    required double normalizedDy,
    required String iconKey,
    required String colorKey,
    required bool isMine,
    int? zoneId,
  }) {
    final index = _campusPlaces.indexWhere((place) => place.id == id);
    if (index == -1) {
      return false;
    }

    final current = _campusPlaces[index];
    final updatedPlace = current.copyWith(
      name: name.trim(),
      category: category,
      note: note.trim(),
      normalizedDx: _normalizeFraction(normalizedDx),
      normalizedDy: _normalizeFraction(normalizedDy),
      iconKey: iconKey,
      colorKey: colorKey,
      zoneId: zoneId ?? current.zoneId,
      isMine: isMine,
      updatedAt: DateTime.now(),
    );
    _campusPlaces[index] = updatedPlace;
    _queueCampusPlaceSave(updatedPlace);
    notifyListeners();
    return true;
  }

  bool deleteCampusPlace(String id) {
    final index = _campusPlaces.indexWhere((place) => place.id == id);
    if (index == -1) {
      return false;
    }

    final removedPlace = _campusPlaces.removeAt(index);
    _queueCampusPlaceDelete(removedPlace.id);
    notifyListeners();
    return true;
  }

  bool toggleCampusPlaceFavorite(String id) {
    final index = _campusPlaces.indexWhere((place) => place.id == id);
    if (index == -1) {
      return false;
    }

    final current = _campusPlaces[index];
    final updatedPlace = current.copyWith(
      isFavorite: !current.isFavorite,
      updatedAt: DateTime.now(),
    );
    _campusPlaces[index] = updatedPlace;
    _queueCampusPlaceSave(updatedPlace);
    notifyListeners();
    return true;
  }

  bool markCampusPlaceVisited(String id) {
    final index = _campusPlaces.indexWhere((place) => place.id == id);
    if (index == -1) {
      return false;
    }

    final current = _campusPlaces[index];
    final now = DateTime.now();
    final updatedPlace = current.copyWith(
      lastVisitedAt: now,
      updatedAt: now,
      heatScore: current.heatScore + 1,
    );
    _campusPlaces[index] = updatedPlace;
    _queueCampusPlaceSave(updatedPlace);
    notifyListeners();
    return true;
  }

  CampusPlace? campusPlaceById(String id) {
    for (final place in _campusPlaces) {
      if (place.id == id) {
        return place;
      }
    }
    return null;
  }

  Future<void> prepareForAppExit() async {
    _weatherRefreshTimer?.cancel();
    if (_vPetCloseWithApp) {
      await _vPetCompanionService.stop();
    }
  }

  @override
  void dispose() {
    _weatherRefreshTimer?.cancel();
    if (_vPetCloseWithApp && vPetRunning) {
      unawaited(_vPetCompanionService.stop());
    }
    analysisController.removeListener(notifyListeners);
    analysisController.dispose();
    super.dispose();
  }

  void _setGalleryBusy(bool value) {
    if (_galleryBusy == value) {
      return;
    }
    _galleryBusy = value;
    notifyListeners();
  }

  void _setWeatherBusy(bool value) {
    if (_weatherBusy == value) {
      return;
    }
    _weatherBusy = value;
    notifyListeners();
  }

  void _setWeatherSearchBusy(bool value) {
    if (_weatherSearchBusy == value) {
      return;
    }
    _weatherSearchBusy = value;
    notifyListeners();
  }

  void _setVPetCompanionBusy(bool value) {
    if (_vPetCompanionBusy == value) {
      return;
    }
    _vPetCompanionBusy = value;
    notifyListeners();
  }

  void _setLocalLlmAnalysisSettingsBusy(bool value) {
    if (_localLlmAnalysisSettingsBusy == value) {
      return;
    }
    _localLlmAnalysisSettingsBusy = value;
    notifyListeners();
  }

  void _setOllamaConnectionTestBusy(bool value) {
    if (_ollamaConnectionTestBusy == value) {
      return;
    }
    _ollamaConnectionTestBusy = value;
    notifyListeners();
  }

  void _setPdfLibraryBusy(bool value) {
    if (_pdfLibraryBusy == value) {
      return;
    }
    _pdfLibraryBusy = value;
    notifyListeners();
  }

  void _ensureWeatherRefreshTimer() {
    if (_weatherRefreshTimer != null) {
      return;
    }

    _weatherRefreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      unawaited(ensureWeatherLoaded(force: true));
    });
  }

  List<EventItem> _collectUpcomingTaskReminders({
    required DateTime now,
    required int limit,
  }) {
    final today = _startOfDay(now);
    final latestDay = today.add(
      const Duration(days: _vPetUpcomingTaskLookAheadDays),
    );
    final candidates =
        calendarEvents.where((event) {
          if (event.type != EventType.plan ||
              event.origin == EventOrigin.holiday) {
            return false;
          }

          final dueDay = _startOfDay(event.startAt);
          return !dueDay.isBefore(today) && !dueDay.isAfter(latestDay);
        }).toList()..sort((left, right) {
          final dateComparison = left.startAt.compareTo(right.startAt);
          if (dateComparison != 0) {
            return dateComparison;
          }
          return left.title.compareTo(right.title);
        });

    return candidates.take(limit).toList();
  }

  String _buildVPetUpcomingTaskReminder(List<EventItem> tasks, DateTime now) {
    final lines = <String>[
      tasks.length == 1 ? '我在这里轻轻提醒你：这件任务快到时间啦。' : '我陪你看了一下，最近这些任务离截止时间比较近：',
      for (var index = 0; index < tasks.length; index++)
        '${index + 1}. ${_formatVPetDueLabel(tasks[index].startAt, now)}：${tasks[index].title}',
      '先从第一件开始就好。一步一步来，你能稳稳推进。',
    ];
    return lines.join('\n');
  }

  String _formatVPetDueLabel(DateTime dueAt, DateTime now) {
    final today = _startOfDay(now);
    final dueDay = _startOfDay(dueAt);
    final dayOffset = dueDay.difference(today).inDays;

    if (dayOffset == 0) {
      return '今天';
    }
    if (dayOffset == 1) {
      return '明天';
    }
    if (dayOffset == 2) {
      return '后天';
    }
    if (dayOffset < 7) {
      return '${_weekdayLabel(dueDay)}（${_formatMonthDay(dueDay)}）';
    }
    return _formatMonthDay(dueDay);
  }

  String _weekdayLabel(DateTime date) {
    return switch (date.weekday) {
      DateTime.monday => '周一',
      DateTime.tuesday => '周二',
      DateTime.wednesday => '周三',
      DateTime.thursday => '周四',
      DateTime.friday => '周五',
      DateTime.saturday => '周六',
      DateTime.sunday => '周日',
      _ => '',
    };
  }

  List<SessionRecord> get _institutionCalendarSessions => _sessionHistory
      .where((session) => session.isInstitutionCalendar)
      .toList(growable: false);

  SessionRecord _buildInstitutionCalendarSession({
    required String rawText,
    required InstitutionCalendarImportResult result,
    required String sessionKey,
    required DateTime confirmedAt,
    required DateTime createdAt,
  }) {
    final title = result.title == null || result.title!.isEmpty
        ? '校历导入'
        : '校历导入：${result.title}';
    final sourceLabel = result.title == null || result.title!.isEmpty
        ? '校历导入'
        : '校历导入 · ${result.title}';
    final draft = AnalysisDraft(
      id: 'draft_$sessionKey',
      tasks: [
        for (var index = 0; index < result.events.length; index++)
          ExtractedTaskDraft(
            id: 'task_${sessionKey}_$index',
            content: result.events[index].title,
            category: result.events[index].category,
            type: result.events[index].type,
            confidence: 1,
            timeHint: _formatEventDateRange(result.events[index]),
          ),
      ],
      persons: const [],
      summary: result.summary,
      warnings: result.warnings,
      createdAt: createdAt,
    );
    final preview = _reviewService.buildPreview(draft);
    final events = [
      for (var index = 0; index < result.events.length; index++)
        result.events[index].copyWith(
          id: 'event_${draft.id}_$index',
          origin: EventOrigin.institutionCalendar,
          sourceLabel: sourceLabel,
        ),
    ];

    return SessionRecord(
      id: 'session_$sessionKey',
      title: title,
      input: AnalysisInput(
        rawText: rawText,
        sourceType: AnalysisSourceType.institutionCalendar,
      ),
      draft: draft,
      preview: preview,
      events: events,
      people: const [],
      confirmedAt: confirmedAt,
    );
  }

  List<PersonProfile> _buildPeopleFromDraft(AnalysisDraft draft) {
    return draft.persons.map((person) {
      final relatedPlans = person.relatedTaskIndexes
          .where((index) => index < draft.tasks.length)
          .map((index) => draft.tasks[index])
          .where((task) => task.type == EventType.plan)
          .map((task) => task.content)
          .toList();

      return PersonProfile(
        id: person.id,
        name: person.name,
        role: person.role,
        aliases: person.aliases,
        relatedTaskCount: person.relatedTaskIndexes.length,
        relatedPlanTitles: relatedPlans,
      );
    }).toList();
  }

  SessionRecord? _findSessionById(String sessionId) {
    for (final session in _sessionHistory) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }

  SessionRecord? _findDuplicateInstitutionCalendarSession(String rawText) {
    final normalizedInput = _normalizeSessionInput(rawText);
    if (normalizedInput.isEmpty) {
      return null;
    }

    for (final session in _institutionCalendarSessions) {
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

  SessionRecord? _latestAnalysisSession() {
    for (final session in _sessionHistory) {
      if (!session.isInstitutionCalendar) {
        return session;
      }
    }
    return null;
  }

  void _sortSessionHistory() {
    _sessionHistory.sort(
      (left, right) => right.confirmedAt.compareTo(left.confirmedAt),
    );
  }

  String? _institutionCalendarTitleFromSession(SessionRecord session) {
    for (final line in session.input.rawText.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.toUpperCase().startsWith('TITLE:')) {
        final title = trimmed.substring(6).trim();
        return title.isEmpty ? null : title;
      }
    }

    const titlePrefix = '校历导入：';
    if (session.title.startsWith(titlePrefix)) {
      final title = session.title.substring(titlePrefix.length).trim();
      return title.isEmpty ? null : title;
    }
    return null;
  }

  String _normalizeSessionInput(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  SessionRecord? _findSessionByEventId(String eventId) {
    for (final session in _sessionHistory) {
      if (session.events.any((event) => event.id == eventId)) {
        return session;
      }
    }
    return null;
  }

  SessionRecord? _findSessionByPersonId(String personId) {
    for (final session in _sessionHistory) {
      if (session.people.any((person) => person.id == personId)) {
        return session;
      }
    }
    return null;
  }

  PersonProfile? _findPersonProfileById(
    List<PersonProfile> people,
    String personId,
  ) {
    for (final person in people) {
      if (person.id == personId) {
        return person;
      }
    }
    return null;
  }

  ExtractedPersonDraft? _findPersonDraftById(
    List<ExtractedPersonDraft> people,
    String personId,
  ) {
    for (final person in people) {
      if (person.id == personId) {
        return person;
      }
    }
    return null;
  }

  Set<String> _collectKnownPersonNames({
    required PersonProfile profile,
    required ExtractedPersonDraft draft,
  }) {
    return <String>{
      profile.name,
      draft.name,
      ...profile.aliases,
      ...draft.aliases,
    }..removeWhere((name) => name.trim().isEmpty);
  }

  List<String> _buildMergedAliases({
    required String primaryName,
    required Set<String> primaryKnownNames,
    required Set<String> secondaryKnownNames,
  }) {
    final aliases = <String>[];
    final seen = <String>{};

    for (final name in [...primaryKnownNames, ...secondaryKnownNames]) {
      final normalized = name.trim();
      if (normalized.isEmpty || normalized == primaryName) {
        continue;
      }
      if (seen.add(normalized)) {
        aliases.add(normalized);
      }
    }

    return aliases;
  }

  List<String> _buildRenamedAliases({
    required String nextName,
    required Set<String> knownNames,
    required Set<String> originalNames,
    required bool keepOriginalNameAsAlias,
  }) {
    final aliases = <String>[];
    final seen = <String>{};

    for (final name in knownNames) {
      final normalized = name.trim();
      if (normalized.isEmpty || normalized == nextName) {
        continue;
      }
      if (!keepOriginalNameAsAlias && originalNames.contains(normalized)) {
        continue;
      }
      if (seen.add(normalized)) {
        aliases.add(normalized);
      }
    }

    return aliases;
  }

  List<String> _mergePersonNames(
    List<String> personNames, {
    required Set<String> mergedKnownNames,
    required String primaryName,
  }) {
    if (personNames.isEmpty) {
      return const [];
    }

    final nextNames = <String>[];
    final seen = <String>{};

    for (final name in personNames) {
      final normalized = name.trim();
      final mappedName = mergedKnownNames.contains(normalized)
          ? primaryName
          : normalized;
      if (mappedName.isEmpty) {
        continue;
      }
      if (seen.add(mappedName)) {
        nextNames.add(mappedName);
      }
    }

    return nextNames;
  }

  List<int> _collectTaskIndexesForPerson(
    List<ExtractedTaskDraft> tasks,
    String personName,
  ) {
    final indexes = <int>[];

    for (var index = 0; index < tasks.length; index++) {
      if (tasks[index].relatedPersonNames.contains(personName)) {
        indexes.add(index);
      }
    }

    return indexes;
  }

  bool _hasPersonNameConflict({
    required List<PersonProfile> people,
    required String personId,
    required String candidateName,
  }) {
    for (final person in people) {
      if (person.id == personId) {
        continue;
      }
      if (person.name == candidateName ||
          person.aliases.contains(candidateName)) {
        return true;
      }
    }
    return false;
  }

  PersonRole _resolveMergedPersonRole(
    PersonRole primaryRole,
    PersonRole secondaryRole,
  ) {
    if (primaryRole != PersonRole.other) {
      return primaryRole;
    }
    return secondaryRole;
  }

  String _buildDraftSummary(
    List<ExtractedTaskDraft> tasks,
    List<ExtractedPersonDraft> people,
  ) {
    if (tasks.isEmpty) {
      return '当前描述信息较少，暂时无法总结出稳定的本周进展。';
    }

    final categories = tasks
        .map((task) => task.category.label)
        .toSet()
        .toList();
    final categoryText = categories.isEmpty
        ? ''
        : '，覆盖 ${categories.join('、')}';
    final peopleText = people.isEmpty ? '未识别到明确人物' : '涉及 ${people.length} 位人物';
    return '本次分析共识别出 ${tasks.length} 条事项，$peopleText$categoryText。';
  }

  DateTime _weekStart(DateTime date) {
    return _dateOnly(
      date,
    ).subtract(Duration(days: date.weekday - DateTime.monday));
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  List<String> _collectUniquePeople(List<EventItem> events) {
    final people = <String>[];
    final seen = <String>{};

    for (final event in events) {
      for (final person in event.personNames) {
        if (seen.add(person)) {
          people.add(person);
        }
      }
    }

    return people;
  }

  String _formatPromptEventList(
    List<EventItem> events, {
    bool includeMeta = false,
  }) {
    if (events.isEmpty) {
      return '无';
    }

    return events
        .map((event) {
          final collaboratorSuffix = event.personNames.isEmpty
              ? ''
              : '（协作：${event.personNames.join('、')}）';

          if (!includeMeta) {
            return '- ${_formatEventDateRange(event)}：${event.title}$collaboratorSuffix';
          }

          return '- ${_formatEventDateRange(event)}｜${event.type.label}｜'
              '${event.category.label}｜${event.title}$collaboratorSuffix';
        })
        .join('\n');
  }

  String _formatPeopleList(List<String> people) {
    if (people.isEmpty) {
      return '无';
    }

    return people.map((person) => '- $person').join('\n');
  }

  String _formatMonthDay(DateTime date) {
    return '${date.month}/${date.day}';
  }

  String _formatSessionPeriodLabel(DateTime date) {
    final start = _weekStart(date);
    final end = start.add(const Duration(days: 6));
    return '${_formatMonthDay(start)} - ${_formatMonthDay(end)}';
  }

  List<EventItem> _deduplicateCalendarEvents(List<EventItem> events) {
    final dedupedEvents = <EventItem>[];
    final analysisEventKeys = <String>{};

    for (final event in events) {
      if (event.origin != EventOrigin.analysis) {
        dedupedEvents.add(event);
        continue;
      }

      final key = _calendarDuplicateKey(event);
      if (analysisEventKeys.add(key)) {
        dedupedEvents.add(event);
      }
    }

    return dedupedEvents;
  }

  String _calendarDuplicateKey(EventItem event) {
    final people =
        event.personNames
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toList()
          ..sort();
    final parts = <String>[
      _normalizeCalendarTitle(event.title),
      event.category.name,
      event.type.name,
      _dateKey(event.startAt),
      event.endAt == null ? '' : _dateKey(event.endAt!),
      people.join('|'),
    ];
    return parts.map((part) => '${part.length}:$part').join('|');
  }

  String _normalizeCalendarTitle(String title) {
    return title.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();
  }

  String _dateKey(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return '${normalized.year}-${normalized.month}-${normalized.day}';
  }

  String _formatEventDateRange(EventItem event) {
    final end = event.endAt;
    if (end == null || _sameDay(event.startAt, end)) {
      return _formatMonthDay(event.startAt);
    }
    return '${_formatMonthDay(event.startAt)} - ${_formatMonthDay(end)}';
  }

  bool _sameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Future<void> _ensureReadme(Directory folder) async {
    final readme = File('${folder.path}${Platform.pathSeparator}README.txt');
    if (await readme.exists()) {
      return;
    }

    await readme.writeAsString('''
研究生活主页图片文件夹
这个文件夹位于应用数据目录下。
支持的命名方式：
- research_wall.png / .jpg / .jpeg / .webp / .bmp
- life_wall.png / .jpg / .jpeg / .webp / .bmp
''');
  }

  Future<void> _migrateLegacyHomeImageFolderIfNeeded(
    Directory storageDirectory,
    Directory targetFolder,
  ) async {
    if (await targetFolder.exists()) {
      return;
    }

    final legacyFolder = Directory(
      '${storageDirectory.path}${Platform.pathSeparator}home_images',
    );
    if (!await legacyFolder.exists()) {
      return;
    }

    try {
      await legacyFolder.rename(targetFolder.path);
    } on FileSystemException {
      await _copyDirectory(legacyFolder, targetFolder);
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);

    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
      if (name.isEmpty) {
        continue;
      }

      final targetPath = '${target.path}${Platform.pathSeparator}$name';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  Future<List<File>> _existingSlotFiles(HomeImageSlot slot) async {
    final folderPath = _homeImageFolderPath;
    if (folderPath == null) {
      return const [];
    }

    final files = <File>[];
    for (final extension in _supportedImageExtensions) {
      final file = File(
        '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.$extension',
      );
      if (await file.exists()) {
        files.add(file);
      }
    }
    return files;
  }

  Future<void> _restoreSlotReplacement(
    HomeImageSlot slot,
    String backupSuffix,
  ) async {
    final folderPath = _homeImageFolderPath;
    if (folderPath == null) {
      return;
    }

    for (final extension in _supportedImageExtensions) {
      final incoming = File(
        '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.incoming.$extension',
      );
      if (await incoming.exists()) {
        await incoming.delete();
      }

      final target = File(
        '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.$extension',
      );
      final backupFile = File('${target.path}$backupSuffix');
      if (await backupFile.exists()) {
        if (await target.exists()) {
          await target.delete();
        }
        await backupFile.rename(target.path);
      }
    }
  }

  Future<String?> _findImageForSlot(HomeImageSlot slot) async {
    final folderPath = _homeImageFolderPath;
    if (folderPath == null) {
      return null;
    }

    for (final extension in _supportedImageExtensions) {
      final file = File(
        '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.$extension',
      );
      if (await file.exists()) {
        return file.path;
      }
    }

    return null;
  }

  String _extensionOf(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) {
      return 'png';
    }
    return path.substring(dotIndex + 1).toLowerCase();
  }

  String _fileTitleFromPath(String path) {
    final normalized = path.replaceAll('/', '\\');
    final separatorIndex = normalized.lastIndexOf('\\');
    final fileName = separatorIndex == -1
        ? normalized
        : normalized.substring(separatorIndex + 1);
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }

  String _formatReadingDuration(Duration duration) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes < 60) {
      return '$totalMinutes 分钟';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) {
      return '$hours 小时';
    }
    return '$hours 小时 $minutes 分钟';
  }

  String _normalizeFilePath(String path) {
    return path
        .replaceAll('/', '\\')
        .replaceAll(RegExp(r'\\+$'), '')
        .toLowerCase();
  }

  Future<String?> _openFolder(String path, String label) async {
    try {
      await Process.start('explorer.exe', [path]);
      return '已打开$label。';
    } on ProcessException catch (error) {
      return '打开$label失败：${error.message}';
    }
  }

  void _replaceSessionRecord(SessionRecord updatedSession) {
    final index = _sessionHistory.indexWhere(
      (item) => item.id == updatedSession.id,
    );
    if (index != -1) {
      _sessionHistory[index] = updatedSession;
      _sortSessionHistory();
    }

    if (updatedSession.isInstitutionCalendar) {
      if (_latestSession?.id == updatedSession.id) {
        _latestSession = _latestAnalysisSession();
      }
    } else if (_latestSession?.id == updatedSession.id) {
      _latestSession = updatedSession;
    } else {
      _latestSession ??= _latestAnalysisSession();
    }
    analysisController.replaceDraftIfCurrent(updatedSession);
    _queueSessionPersistence(updatedSession);
  }

  void _queueSessionPersistence(SessionRecord session) {
    _sessionPersistenceError = null;
    _pendingSessionPersistence = _pendingSessionPersistence
        .then((_) => _analysisCommitService.saveSession(session))
        .catchError((Object error) {
          _sessionPersistenceError = error;
        });
    unawaited(_pendingSessionPersistence);
  }

  void _queueSessionDelete(String sessionId) {
    _sessionPersistenceError = null;
    _pendingSessionPersistence = _pendingSessionPersistence
        .then((_) => _analysisCommitService.deleteSession(sessionId))
        .catchError((Object error) {
          _sessionPersistenceError = error;
        });
    unawaited(_pendingSessionPersistence);
  }

  void _queueManualEventPersistence(EventItem event) {
    final repository = _manualEventsRepository;
    if (repository == null) {
      return;
    }

    _manualEventPersistenceError = null;
    _pendingManualEventPersistence = _pendingManualEventPersistence
        .then((_) => repository.saveManualEvent(event))
        .catchError((Object error) {
          _manualEventPersistenceError = error;
        });
    unawaited(_pendingManualEventPersistence);
  }

  void _queueCampusPlaceSave(CampusPlace place) {
    final repository = _campusPlacesRepository;
    if (repository == null) {
      return;
    }

    _campusPlacePersistenceError = null;
    _pendingCampusPlacePersistence = _pendingCampusPlacePersistence
        .then((_) => repository.saveCampusPlace(place))
        .catchError((Object error) {
          _campusPlacePersistenceError = error;
        });
    unawaited(_pendingCampusPlacePersistence);
  }

  void _queueCampusPlaceDelete(String placeId) {
    final repository = _campusPlacesRepository;
    if (repository == null) {
      return;
    }

    _campusPlacePersistenceError = null;
    _pendingCampusPlacePersistence = _pendingCampusPlacePersistence
        .then((_) => repository.deleteCampusPlace(placeId))
        .catchError((Object error) {
          _campusPlacePersistenceError = error;
        });
    unawaited(_pendingCampusPlacePersistence);
  }

  void _queuePdfDocumentSave(PdfLibraryDocument document) {
    final repository = _pdfDocumentsRepository;
    if (repository == null) {
      return;
    }

    _pdfPersistenceError = null;
    _pendingPdfPersistence = _pendingPdfPersistence
        .then((_) => repository.saveDocument(document))
        .catchError((Object error) {
          _pdfPersistenceError = error;
        });
    unawaited(_pendingPdfPersistence);
  }

  void _queuePdfDocumentDelete(String documentId) {
    final repository = _pdfDocumentsRepository;
    if (repository == null) {
      return;
    }

    _pdfPersistenceError = null;
    _pendingPdfPersistence = _pendingPdfPersistence
        .then((_) => repository.deleteDocument(documentId))
        .catchError((Object error) {
          _pdfPersistenceError = error;
        });
    unawaited(_pendingPdfPersistence);
  }

  void _queuePdfAnnotationSave(PdfTextAnnotation annotation) {
    final repository = _pdfDocumentsRepository;
    if (repository == null) {
      return;
    }

    _pdfPersistenceError = null;
    _pendingPdfPersistence = _pendingPdfPersistence
        .then((_) => repository.saveAnnotation(annotation))
        .catchError((Object error) {
          _pdfPersistenceError = error;
        });
    unawaited(_pendingPdfPersistence);
  }

  void _queuePdfAnnotationDelete(String annotationId) {
    final repository = _pdfDocumentsRepository;
    if (repository == null) {
      return;
    }

    _pdfPersistenceError = null;
    _pendingPdfPersistence = _pendingPdfPersistence
        .then((_) => repository.deleteAnnotation(annotationId))
        .catchError((Object error) {
          _pdfPersistenceError = error;
        });
    unawaited(_pendingPdfPersistence);
  }

  void _updatePdfDocument(
    String id,
    PdfLibraryDocument Function(PdfLibraryDocument document) update,
  ) {
    final index = _pdfDocuments.indexWhere((document) => document.id == id);
    if (index == -1) {
      return;
    }

    final current = _pdfDocuments[index];
    final updated = update(current);
    if (identical(current, updated)) {
      return;
    }
    _pdfDocuments[index] = updated;
    _queuePdfDocumentSave(updated);
    notifyListeners();
  }

  int _comparePdfAnnotations(PdfTextAnnotation left, PdfTextAnnotation right) {
    final pageComparison = left.pageNumber.compareTo(right.pageNumber);
    if (pageComparison != 0) {
      return pageComparison;
    }
    return right.createdAt.compareTo(left.createdAt);
  }

  int _clampPdfPage(int pageNumber, int? pageCount) {
    final lower = pageNumber < 1 ? 1 : pageNumber;
    final upper = pageCount == null || pageCount < 1 ? lower : pageCount;
    return lower > upper ? upper : lower;
  }

  double _normalizeFraction(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }

  static List<CampusPlace> _buildSampleCampusPlaces() {
    final now = DateTime.now();
    return [
      CampusPlace(
        id: 'place_library',
        name: '主图书馆',
        category: PlaceCategory.study,
        note: '适合安静自习，二层靠窗的位置采光最好。',
        normalizedDx: 0.34,
        normalizedDy: 0.28,
        iconKey: 'book',
        colorKey: 'forest',
        isFavorite: true,
        createdAt: now.subtract(const Duration(days: 18)),
        updatedAt: now.subtract(const Duration(days: 2)),
        lastVisitedAt: now.subtract(const Duration(hours: 6)),
        heatScore: 12,
      ),
      CampusPlace(
        id: 'place_canteen',
        name: '一食堂',
        category: PlaceCategory.dining,
        note: '中午排队较快，靠北侧窗口常有盖饭。',
        normalizedDx: 0.67,
        normalizedDy: 0.33,
        iconKey: 'food',
        colorKey: 'amber',
        isFavorite: true,
        createdAt: now.subtract(const Duration(days: 12)),
        updatedAt: now.subtract(const Duration(days: 1)),
        lastVisitedAt: now.subtract(const Duration(hours: 20)),
        heatScore: 8,
      ),
      CampusPlace(
        id: 'place_dorm',
        name: '南宿舍 A 栋',
        category: PlaceCategory.dormitory,
        note: '快递柜和洗衣房都在楼下，晚上回宿舍路线最顺。',
        normalizedDx: 0.21,
        normalizedDy: 0.76,
        iconKey: 'bed',
        colorKey: 'slate',
        createdAt: now.subtract(const Duration(days: 24)),
        updatedAt: now.subtract(const Duration(days: 4)),
        lastVisitedAt: now.subtract(const Duration(hours: 10)),
        heatScore: 15,
      ),
      CampusPlace(
        id: 'place_lab',
        name: '材料实验楼',
        category: PlaceCategory.lab,
        note: '三层东侧实验室需要提前登记，晚上刷卡后可进入。',
        normalizedDx: 0.53,
        normalizedDy: 0.58,
        iconKey: 'flask',
        colorKey: 'berry',
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 1)),
        lastVisitedAt: now.subtract(const Duration(days: 1, hours: 3)),
        heatScore: 9,
      ),
      CampusPlace(
        id: 'place_gym',
        name: '体育馆',
        category: PlaceCategory.sports,
        note: '羽毛球场需要提前预约，晚间照明稳定。',
        normalizedDx: 0.8,
        normalizedDy: 0.74,
        iconKey: 'run',
        colorKey: 'teal',
        createdAt: now.subtract(const Duration(days: 14)),
        updatedAt: now.subtract(const Duration(days: 3)),
        heatScore: 5,
      ),
      CampusPlace(
        id: 'place_service',
        name: '行政服务中心',
        category: PlaceCategory.errands,
        note: '补办校园卡、打印证明都在这里，工作日人流较多。',
        normalizedDx: 0.48,
        normalizedDy: 0.18,
        iconKey: 'office',
        colorKey: 'blue',
        isMine: false,
        createdAt: now.subtract(const Duration(days: 7)),
        updatedAt: now.subtract(const Duration(days: 2)),
        heatScore: 3,
      ),
    ];
  }
}

class _VPetCompanionSettings {
  const _VPetCompanionSettings({
    this.executablePath,
    this.autoStart = false,
    this.closeWithApp = true,
    this.closeWithAppConfigured = false,
  });

  factory _VPetCompanionSettings.fromJson(Map<String, Object?> json) {
    final executablePath = json['executablePath'];
    final closeWithAppConfigured = json['closeWithAppConfigured'] == true;
    return _VPetCompanionSettings(
      executablePath:
          executablePath is String && executablePath.trim().isNotEmpty
          ? executablePath
          : null,
      autoStart: json['autoStart'] == true,
      closeWithApp: closeWithAppConfigured
          ? json['closeWithApp'] == true
          : true,
      closeWithAppConfigured: closeWithAppConfigured,
    );
  }

  final String? executablePath;
  final bool autoStart;
  final bool closeWithApp;
  final bool closeWithAppConfigured;

  Map<String, Object?> toJson() {
    return {
      'executablePath': executablePath,
      'autoStart': autoStart,
      'closeWithApp': closeWithApp,
      'closeWithAppConfigured': closeWithAppConfigured,
    };
  }
}
