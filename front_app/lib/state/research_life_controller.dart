import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/models/app_models.dart';
import '../core/models/weather_models.dart';
import '../core/theme/app_tokens.dart';
import '../features/analysis/state/analysis_controller.dart';
import '../services/analysis/analysis_commit_service.dart';
import '../services/analysis/analysis_engine_coordinator.dart';
import '../services/analysis/analysis_service.dart';
import '../services/calendar/institution_calendar_service.dart';
import '../services/database/repositories/campus_places_repository.dart';
import '../services/database/repositories/manual_events_repository.dart';
import '../services/database/repositories/notes_repository.dart';
import '../services/database/repositories/pdf_documents_repository.dart';
import '../services/database/repositories/preferences_repository.dart';
import '../services/database/repositories/sessions_repository.dart';
import '../services/database/repositories/todo_status_repository.dart';
import '../services/export/consulting_package_service.dart';
import '../services/import/import_service.dart';
import '../services/pet/pet_companion_service.dart';
import '../services/review/review_service.dart';
import '../core/network/api_exception.dart';
import '../services/storage/backup_service.dart';
import '../services/storage/local_data_operation_coordinator.dart';
import '../services/storage/local_folder_service.dart';
import '../services/storage/local_workspace_service.dart';
import '../core/network/api_client.dart';
import '../core/utils/workspace_file_kind.dart';
import '../services/pdf/pdf_operation_api.dart';
import '../services/reminder/reminder_scheduler.dart';
import '../services/sync/cloud_file_service.dart';
import '../services/sync/file_sync_engine.dart';
import '../services/sync/sync_models.dart';
import 'auth_controller.dart';
import '../services/weather/weather_service.dart';

enum HomeImageSlot { researchWall, lifeWall }

class ReadingOpenRequest {
  const ReadingOpenRequest({
    this.documentId,
    this.cloudServerId,
    this.pageNumber,
    this.annotationId,
    this.openFullscreen = false,
  });

  final String? documentId;
  final int? cloudServerId;
  final int? pageNumber;
  final String? annotationId;
  final bool openFullscreen;

  bool get isEmpty => documentId == null && cloudServerId == null;
}

class DocumentViewOpenRequest {
  const DocumentViewOpenRequest({this.documentId, this.cloudServerId});

  final String? documentId;
  final int? cloudServerId;

  bool get isEmpty => documentId == null && cloudServerId == null;
}

class PdfToolsOpenRequest {
  const PdfToolsOpenRequest({this.documentId, this.cloudServerId});

  final String? documentId;
  final int? cloudServerId;

  bool get isEmpty => documentId == null && cloudServerId == null;
}

extension HomeImageSlotLabel on HomeImageSlot {
  String get label => switch (this) {
    HomeImageSlot.researchWall => '照片 1',
    HomeImageSlot.lifeWall => '照片 2',
  };

  String get fileBaseName => switch (this) {
    HomeImageSlot.researchWall => 'research_wall',
    HomeImageSlot.lifeWall => 'life_wall',
  };
}

class ResearchLifeController extends ChangeNotifier {
  /// 仅随配色主题变化，用于避免把整棵 `MaterialApp` 绑到本控制器的全部通知上。
  final ValueNotifier<AppColorTheme> colorThemeListenable =
      ValueNotifier<AppColorTheme>(AppColorTheme.green);

  ResearchLifeController({
    required ImportService importService,
    required AnalysisService analysisService,
    required ReviewService reviewService,
    required InstitutionCalendarService institutionCalendarService,
    required LocalWorkspaceService localWorkspaceService,
    WeatherService? weatherService,
    PetCompanionService? petCompanionService,
    PreferencesRepository? preferencesRepository,
    SessionsRepository? sessionsRepository,
    ManualEventsRepository? manualEventsRepository,
    TodoStatusRepository? todoStatusRepository,
    NotesRepository? notesRepository,
    CampusPlacesRepository? campusPlacesRepository,
    PdfDocumentsRepository? pdfDocumentsRepository,
    LocalFolderService? localFolderService,
    FileSyncEngine? fileSyncEngine,
    CloudFileService? cloudFileService,
    bool Function()? isCloudSyncEnabled,
    AnalysisEngineCoordinator? analysisEngineCoordinator,
    LocalDataOperationCoordinator? localDataOperationCoordinator,
  }) : _reviewService = reviewService,
       _institutionCalendarService = institutionCalendarService,
       _localWorkspaceService = localWorkspaceService,
       _weatherService = weatherService ?? WeatherService(),
       _petCompanionService =
           petCompanionService ??
           PetCompanionService(localWorkspaceService: localWorkspaceService),
       _preferencesRepository = preferencesRepository,
       _sessionsRepository = sessionsRepository,
       _manualEventsRepository = manualEventsRepository,
       _todoStatusRepository = todoStatusRepository,
       _notesRepository = notesRepository,
       _campusPlacesRepository = campusPlacesRepository,
       _pdfDocumentsRepository = pdfDocumentsRepository,
       _localFolderService = localFolderService,
       _fileSyncEngine = fileSyncEngine,
       _cloudFileServiceOverride = cloudFileService,
       _isCloudSyncEnabled = isCloudSyncEnabled,
       _analysisEngineCoordinator =
           analysisEngineCoordinator ??
           AnalysisEngineCoordinator(ruleBasedAnalysisService: analysisService),
       _localDataOperationCoordinator =
           localDataOperationCoordinator ?? LocalDataOperationCoordinator() {
    _analysisCommitService = AnalysisCommitService(
      reviewService: reviewService,
      sessionsRepository: sessionsRepository,
    );
    analysisController = AnalysisController(
      importService: importService,
      analysisEngineCoordinator: _analysisEngineCoordinator,
      reviewService: reviewService,
      commitService: _analysisCommitService,
      loadRemoteLlmAnalysisSettings: _remoteLlmSettingsForAnalysis,
      sessionHistory: () => _sessionHistory,
      findSessionById: _findSessionById,
      editingSessionId: () => _editingSessionId,
      nextSessionSequence: () => _sessionSequence++,
      onCommit: _handleAnalysisCommit,
    );
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
  static const _petTodayTaskLimit = 3;
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
  final AnalysisEngineCoordinator _analysisEngineCoordinator;
  final LocalWorkspaceService _localWorkspaceService;
  final LocalDataOperationCoordinator _localDataOperationCoordinator;
  final WeatherService _weatherService;
  final PetCompanionService _petCompanionService;
  final PreferencesRepository? _preferencesRepository;
  final SessionsRepository? _sessionsRepository;
  final ManualEventsRepository? _manualEventsRepository;
  final TodoStatusRepository? _todoStatusRepository;
  final NotesRepository? _notesRepository;
  final CampusPlacesRepository? _campusPlacesRepository;
  final PdfDocumentsRepository? _pdfDocumentsRepository;
  final LocalFolderService? _localFolderService;
  final FileSyncEngine? _fileSyncEngine;
  final CloudFileService? _cloudFileServiceOverride;
  final bool Function()? _isCloudSyncEnabled;

  SessionRecord? _latestSession;
  final List<SessionRecord> _sessionHistory = [];
  List<EventItem> _manualEvents = const [];
  Map<String, EventTodoState> _todoStatus = const {};
  bool _todoStatusLoaded = false;
  bool _todoStatusBusy = false;
  Future<void> _pendingTodoStatusPersistence = Future.value();
  Object? _todoStatusPersistenceError;
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
  GlassSettings _glassSettings = const GlassSettings();
  bool _glassSettingsLoaded = false;
  bool _glassSettingsBusy = false;
  RemoteLlmAnalysisSettings _remoteLlmAnalysisSettings =
      const RemoteLlmAnalysisSettings();
  bool _remoteLlmAnalysisSettingsLoaded = false;
  bool _remoteLlmAnalysisSettingsBusy = false;
  bool _weatherLoaded = false;
  bool _weatherBusy = false;
  bool _weatherSearchBusy = false;
  String? _weatherError;
  Timer? _weatherRefreshTimer;
  String _weatherApiKey = '';
  String _weatherApiHost = '';
  bool _weatherApiLoaded = false;
  bool _weatherAnimationEnabled = true;
  bool _weatherAnimationPreferenceLoaded = false;
  bool _petCompanionLoaded = false;
  bool _petCompanionBusy = false;

  /// 合并并发 `ensurePetCompanionLoaded`，避免设置页与启动流程抢 `_petCompanionBusy` 时丢掉 `autoStart`。
  Future<void>? _petCompanionLoadFuture;
  bool _petAutoStart = true;
  bool _petCloseWithApp = true;
  bool _petCloseWithAppConfigured = false;
  bool _petRunning = false;
  String? _selectedPetId;
  PetDefinition? _activePet = PetCompanionService.bundledSiam;
  List<PetDefinition> _availablePets = const [PetCompanionService.bundledSiam];
  String _petAnimationState = 'idle';
  String? _petBubbleText;
  Timer? _petBubbleTimer;
  bool _petTodayTaskReminderSent = false;
  bool _petTodayTaskReminderSending = false;
  bool _homeTodoHintDismissed = false;
  bool _calendarRemindersEnabled = true;
  bool _calendarRemindersEnabledLoaded = false;
  bool _calendarRemindersEnabledBusy = false;
  final Set<String> _remindedEventIds = {};
  List<DueReminder> _pendingReminders = const [];
  Timer? _reminderTimer;
  List<UserNote> _notes = const [];
  bool _notesLoaded = false;
  bool _notesBusy = false;
  String? _pinLockHash;
  String? _pinLockSalt;
  bool _pinLockEnabled = false;
  bool _pinLockLoaded = false;
  bool _pinLockBusy = false;
  bool _isLocked = false;
  Timer? _idleLockTimer;
  static const idleLockTimeout = Duration(minutes: 5);
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
  bool _cloudSyncBusy = false;
  String? _cloudSyncMessage;
  bool _cloudSyncIsError = false;
  CloudSyncStatus _cloudSyncStatus = const CloudSyncStatus.empty();
  bool _cloudSyncStatusBusy = false;
  String? _cloudSyncStatusMessage;
  List<CloudFileEntry> _cloudFileEntries = const [];
  bool _cloudFilesBusy = false;
  String? _cloudFilesMessage;
  ReadingOpenRequest? _pendingReadingOpen;
  DocumentViewOpenRequest? _pendingDocumentViewOpen;
  PdfToolsOpenRequest? _pendingPdfToolsOpen;
  bool _pendingPdfToolsNavigation = false;
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

  /// 阅读页左侧列表：仅包含仍在阅读列表中的文献。
  List<PdfLibraryDocument> get pdfReadingDocuments => [
    for (final document in _pdfDocuments)
      if (!document.isDeleted && document.inReadingList) document,
  ];

  /// 已「移到本地」、可在「我的文件」本机栏展示的文件。
  List<PdfLibraryDocument> get localMaterializedDocuments => [
    for (final document in _pdfDocuments)
      if (!document.cloudOnly &&
          document.path.isNotEmpty &&
          File(document.path).existsSync())
        document,
  ];

  /// 本机 PDF，供文献阅读与 PDF 操作使用。
  List<PdfLibraryDocument> get localPdfDocuments => [
    for (final document in localMaterializedDocuments)
      if (document.fileKind.isPdf) document,
  ];

  /// 本机可查阅的文本 / PPT。
  List<PdfLibraryDocument> get localViewableDocuments => [
    for (final document in localMaterializedDocuments)
      if (document.fileKind.isViewable) document,
  ];

  bool get hasPendingReadingOpen =>
      _pendingReadingOpen != null && !_pendingReadingOpen!.isEmpty;

  bool get hasPendingDocumentViewOpen =>
      _pendingDocumentViewOpen != null && !_pendingDocumentViewOpen!.isEmpty;

  bool get hasPendingPdfToolsOpen => _pendingPdfToolsNavigation;

  bool get hasPendingPdfToolsSelection => _pendingPdfToolsOpen != null;

  /// Compatibility for the pre-existing shell; Agent settings are page-local.
  bool consumeAiSettingsNavigationRequest() => false;

  void requestOpenPdfTools({String? documentId, int? cloudServerId}) {
    if (documentId != null) {
      final doc = pdfDocumentById(documentId);
      if (doc != null && !doc.fileKind.isPdf) {
        throw StateError('PDF 操作仅支持 PDF 文件。');
      }
    }
    _pendingPdfToolsOpen = PdfToolsOpenRequest(
      documentId: documentId,
      cloudServerId: cloudServerId,
    );
    _pendingPdfToolsNavigation = true;
    notifyListeners();
  }

  bool consumePdfToolsNavigationRequest() {
    final pending = _pendingPdfToolsNavigation;
    _pendingPdfToolsNavigation = false;
    return pending;
  }

  PdfToolsOpenRequest? consumePdfToolsOpenRequest() {
    final request = _pendingPdfToolsOpen;
    _pendingPdfToolsOpen = null;
    return request;
  }

  List<EventItem> get institutionCalendarEvents => List.unmodifiable([
    for (final session in _institutionCalendarSessions) ...session.events,
    if (_institutionCalendarSessions.isEmpty) ..._institutionCalendarEvents,
  ]);
  List<CampusPlace> get campusPlaces => List.unmodifiable(_campusPlaces);
  List<EventItem> get calendarEvents => List.unmodifiable(
    _applyTodoStatusToEvents(
      _deduplicateCalendarEvents([
        for (final session in _sessionHistory) ...session.events,
        ..._manualEvents,
      ]),
    ),
  );

  /// 待办列表：分析/手动产生的「计划」类事件，排除校历与节假日等非个人安排。
  List<EventItem> get todoEvents => List.unmodifiable([
    for (final event in calendarEvents)
      if (event.type == EventType.plan &&
          event.origin != EventOrigin.institutionCalendar &&
          event.origin != EventOrigin.holiday)
        event,
  ]);

  /// 今日未完成待办。
  List<EventItem> get todayTodoEvents {
    final today = _startOfDay(DateTime.now());
    return List.unmodifiable([
      for (final event in todoEvents)
        if (!event.isDone && _sameDay(event.startAt, today)) event,
    ]);
  }

  /// 全部未完成待办。
  List<EventItem> get pendingTodoEvents => List.unmodifiable([
    for (final event in todoEvents)
      if (!event.isDone) event,
  ]);

  /// 已完成待办（按完成时间倒序）。
  List<EventItem> get completedTodoEvents {
    final completed =
        [
          for (final event in todoEvents)
            if (event.isDone) event,
        ]..sort((left, right) {
          final leftAt = left.completedAt ?? left.startAt;
          final rightAt = right.completedAt ?? right.startAt;
          return rightAt.compareTo(leftAt);
        });
    return List.unmodifiable(completed);
  }

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
  GlassSettings get glassSettings => _glassSettings;
  bool get glassSettingsLoaded => _glassSettingsLoaded;
  bool get pdfReaderPreferencesLoaded => _pdfReaderPreferencesLoaded;
  RemoteLlmAnalysisSettings get remoteLlmAnalysisSettings =>
      _remoteLlmAnalysisSettings;
  bool get remoteLlmAnalysisSettingsLoaded => _remoteLlmAnalysisSettingsLoaded;
  bool get remoteLlmAnalysisSettingsBusy => _remoteLlmAnalysisSettingsBusy;
  WeatherLocation? get weatherLocation => _weatherLocation;
  WeatherSnapshot? get weatherSnapshot => _weatherSnapshot;
  List<WeatherLocation> get weatherSearchResults =>
      List.unmodifiable(_weatherSearchResults);
  bool get weatherLoaded => _weatherLoaded;
  bool get weatherBusy => _weatherBusy;
  bool get weatherSearchBusy => _weatherSearchBusy;
  String? get weatherError => _weatherError;
  String get weatherApiKey => _weatherApiKey;
  String get weatherApiHost => _weatherApiHost;
  bool get weatherApiLoaded => _weatherApiLoaded;
  bool get weatherAnimationEnabled => _weatherAnimationEnabled;
  bool get petCompanionLoaded => _petCompanionLoaded;
  bool get petCompanionBusy => _petCompanionBusy;
  bool get petAutoStart => _petAutoStart;
  bool get petCloseWithApp => _petCloseWithApp;
  bool get petRunning => _petRunning;

  /// 首页天气区是否显示今日待办提示：仅当桌宠未运行时弹出。
  bool get showHomeTodoHint =>
      !petRunning && !_homeTodoHintDismissed && todayTodoEvents.isNotEmpty;

  /// 关闭首页今日待办提示（本次启动内不再显示，不持久化）。
  void dismissHomeTodoHint() {
    if (_homeTodoHintDismissed) {
      return;
    }
    _homeTodoHintDismissed = true;
    notifyListeners();
  }

  /// 日历事件桌面提醒是否启用。
  bool get calendarRemindersEnabled => _calendarRemindersEnabled;

  /// 待展示的到期提醒（浮层按此渲染，可逐条关闭）。
  List<DueReminder> get pendingReminders =>
      List.unmodifiable(_pendingReminders);

  Future<void> ensureCalendarRemindersLoaded() async {
    if (_calendarRemindersEnabledLoaded || _calendarRemindersEnabledBusy) {
      return;
    }

    _calendarRemindersEnabledBusy = true;
    try {
      _calendarRemindersEnabled =
          await _preferencesRepository?.loadCalendarReminderEnabled() ?? true;
      _calendarRemindersEnabledLoaded = true;
      _startReminderTimer();
      notifyListeners();
    } finally {
      _calendarRemindersEnabledBusy = false;
    }
  }

  Future<void> setCalendarRemindersEnabled(bool enabled) async {
    _calendarRemindersEnabled = enabled;
    notifyListeners();
    await _preferencesRepository?.saveCalendarReminderEnabled(enabled);
  }

  /// 关闭某条到期提醒。
  void dismissReminder(String eventId) {
    final next = [..._pendingReminders]
      ..removeWhere((reminder) => reminder.eventId == eventId);
    if (next.length == _pendingReminders.length) {
      return;
    }
    _pendingReminders = next;
    notifyListeners();
  }

  void _startReminderTimer() {
    _reminderTimer ??= Timer.periodic(const Duration(hours: 1), (_) {
      unawaited(checkCalendarRemindersNow());
    });
    unawaited(checkCalendarRemindersNow());
  }

  /// 立即检查并投递到期提醒（供定时器、设置页和测试调用）。
  Future<void> checkCalendarRemindersNow() async {
    if (!_calendarRemindersEnabled) {
      return;
    }
    await ensureSessionHistoryLoaded();
    await ensureManualEventsLoaded();

    final due = ReminderScheduler.dueReminders(
      events: calendarEvents,
      now: DateTime.now(),
      alreadyReminded: _remindedEventIds,
    );
    if (due.isEmpty) {
      return;
    }

    for (final reminder in due) {
      _remindedEventIds.add(reminder.eventId);
    }
    _pendingReminders = [..._pendingReminders, ...due];
    for (final reminder in due) {
      _scheduleReminderAutoDismiss(reminder.eventId);
    }
    notifyListeners();
  }

  void _scheduleReminderAutoDismiss(String eventId) {
    Timer(const Duration(seconds: 15), () {
      dismissReminder(eventId);
    });
  }

  /// 独立 Markdown 笔记列表（按更新时间倒序）。
  List<UserNote> get notes => List.unmodifiable(_notes);

  Future<void> ensureNotesLoaded() async {
    final repository = _notesRepository;
    if (repository == null || _notesLoaded || _notesBusy) {
      return;
    }

    _notesBusy = true;
    try {
      _notes = await repository.loadNotes();
      _notesLoaded = true;
      notifyListeners();
    } finally {
      _notesBusy = false;
    }
  }

  Future<String> createNote({
    required String title,
    String contentMarkdown = '',
  }) async {
    await ensureNotesLoaded();
    final now = DateTime.now();
    final note = UserNote(
      id: 'note_${now.millisecondsSinceEpoch}',
      title: title.trim().isEmpty ? '未命名笔记' : title.trim(),
      contentMarkdown: contentMarkdown,
      createdAt: now,
      updatedAt: now,
    );
    _notes = [note, ..._notes];
    await _saveNoteLocal(note);
    notifyListeners();
    return '已创建笔记。';
  }

  Future<String> updateNote(
    String id, {
    required String title,
    String? contentMarkdown,
  }) async {
    await ensureNotesLoaded();
    final index = _notes.indexWhere((note) => note.id == id);
    if (index == -1) {
      return '笔记不存在。';
    }

    final current = _notes[index];
    final updated = current.copyWith(
      title: title.trim().isEmpty ? current.title : title.trim(),
      contentMarkdown: contentMarkdown ?? current.contentMarkdown,
      updatedAt: DateTime.now(),
    );
    _notes = [..._notes]..[index] = updated;
    await _saveNoteLocal(updated);
    notifyListeners();
    return '已保存笔记。';
  }

  Future<void> deleteNote(String id) async {
    await ensureNotesLoaded();
    _notes = [..._notes]..removeWhere((note) => note.id == id);
    final repository = _notesRepository;
    if (repository != null) {
      await repository.deleteById(id);
    }
    _enqueueNoteDelete(id);
    notifyListeners();
  }

  Future<void> _saveNoteLocal(UserNote note) async {
    final repository = _notesRepository;
    if (repository == null) {
      return;
    }
    await repository.saveNote(note);
    _enqueueNoteSync(note);
  }

  void _enqueueNoteSync(UserNote note) {
    if (!cloudSyncEnabled) {
      return;
    }
    final engine = _fileSyncEngine;
    if (engine == null) {
      return;
    }
    unawaited(engine.enqueueNote(note));
  }

  void _enqueueNoteDelete(String id) {
    if (!cloudSyncEnabled) {
      return;
    }
    final engine = _fileSyncEngine;
    if (engine == null) {
      return;
    }
    unawaited(engine.enqueueNoteDelete(id));
  }

  /// 是否启用了锁屏 PIN。
  bool get pinLockEnabled => _pinLockEnabled;

  /// 是否处于锁定状态（需要输入 PIN 解锁）。
  bool get isLocked => _isLocked;

  /// 关闭窗口时是否最小化到系统托盘（而非直接退出）。
  bool _closeToTray = true;
  bool _closeToTrayLoaded = false;

  bool get closeToTray => _closeToTray;

  /// 今日待办对话框请求（托盘菜单等外部入口触发）。
  final ValueNotifier<int> todayTodoDialogRequests = ValueNotifier<int>(0);

  Future<void> ensureCloseToTrayLoaded() async {
    if (_closeToTrayLoaded) {
      return;
    }
    final repository = _preferencesRepository;
    if (repository != null) {
      _closeToTray = await repository.loadCloseToTray();
    }
    _closeToTrayLoaded = true;
  }

  Future<void> setCloseToTray(bool value) async {
    if (_closeToTray == value) {
      return;
    }
    _closeToTray = value;
    final repository = _preferencesRepository;
    if (repository != null) {
      await repository.saveCloseToTray(value);
    }
    notifyListeners();
  }

  /// 请求界面弹出今日待办对话框（供系统托盘菜单调用）。
  void requestTodayTodoDialog() {
    todayTodoDialogRequests.value += 1;
  }

  Future<void> ensurePinLockLoaded() async {
    if (_pinLockLoaded || _pinLockBusy) {
      return;
    }

    _pinLockBusy = true;
    try {
      final raw = await _preferencesRepository?.loadPinLock();
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _pinLockHash = decoded['hash'] as String?;
          _pinLockSalt = decoded['salt'] as String?;
          _pinLockEnabled = _pinLockHash != null && _pinLockHash!.isNotEmpty;
        }
      }
      _pinLockLoaded = true;
      if (_pinLockEnabled) {
        // 重启后需要输入 PIN 才能进入。
        _isLocked = true;
        _startIdleLockTimer();
        notifyListeners();
      }
    } finally {
      _pinLockBusy = false;
    }
  }

  /// 设置或修改 PIN（6 位数字）。已设置时需提供正确的旧 PIN。
  Future<String> enablePinLock(String pin, {String? oldPin}) async {
    await ensurePinLockLoaded();
    final normalized = pin.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalized)) {
      return 'PIN 需为 6 位数字。';
    }
    if (_pinLockEnabled) {
      if (oldPin == null || !_verifyPinHash(oldPin)) {
        return '旧 PIN 不正确。';
      }
    }

    final salt = _generateSalt();
    final hash = _hashPin(normalized, salt);
    final payload = jsonEncode({'hash': hash, 'salt': salt});
    await _preferencesRepository?.savePinLock(payload);
    _pinLockHash = hash;
    _pinLockSalt = salt;
    _pinLockEnabled = true;
    _startIdleLockTimer();
    notifyListeners();
    return '已设置锁屏 PIN。';
  }

  /// 关闭 PIN（需输入正确 PIN 验证）。
  Future<String> disablePinLock(String pin) async {
    await ensurePinLockLoaded();
    if (!_pinLockEnabled) {
      return '当前未启用锁屏 PIN。';
    }
    if (!_verifyPinHash(pin)) {
      return 'PIN 不正确。';
    }
    await _preferencesRepository?.deletePinLock();
    _pinLockHash = null;
    _pinLockSalt = null;
    _pinLockEnabled = false;
    _stopIdleLockTimer();
    _isLocked = false;
    notifyListeners();
    return '已关闭锁屏 PIN。';
  }

  /// 校验 PIN 是否正确；正确则解锁。
  bool verifyPin(String pin) {
    final ok = _verifyPinHash(pin);
    if (ok) {
      unlock();
    }
    return ok;
  }

  void lock() {
    if (!_pinLockEnabled || _isLocked) {
      return;
    }
    _isLocked = true;
    notifyListeners();
  }

  void unlock() {
    if (!_isLocked) {
      return;
    }
    _isLocked = false;
    notifyListeners();
  }

  /// 用户活动（鼠标/键盘）时调用，重置闲置计时器。
  void notifyUserActivity() {
    if (!_pinLockEnabled) {
      return;
    }
    _startIdleLockTimer();
  }

  bool _verifyPinHash(String pin) {
    if (_pinLockHash == null || _pinLockSalt == null) {
      return false;
    }
    return _hashPin(pin.trim(), _pinLockSalt!) == _pinLockHash;
  }

  String _hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  String _generateSalt() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _startIdleLockTimer() {
    _stopIdleLockTimer();
    if (!_pinLockEnabled) {
      return;
    }
    _idleLockTimer = Timer(idleLockTimeout, lock);
  }

  void _stopIdleLockTimer() {
    _idleLockTimer?.cancel();
    _idleLockTimer = null;
  }

  void _enqueueSessionSync(SessionRecord session) {
    if (!cloudSyncEnabled) {
      return;
    }
    final engine = _fileSyncEngine;
    if (engine == null) {
      return;
    }
    unawaited(engine.enqueueSession(session));
  }

  void _enqueueSessionDelete(String id) {
    if (!cloudSyncEnabled) {
      return;
    }
    final engine = _fileSyncEngine;
    if (engine == null) {
      return;
    }
    unawaited(engine.enqueueSessionDelete(id));
  }

  /// 从数据库重载会话历史（云端拉取后调用，让新拉取的会话进入内存）。
  Future<void> _reloadSessionHistory() async {
    final repository = _sessionsRepository;
    if (repository == null) {
      return;
    }
    final loaded = await repository.loadSessions();
    _sessionHistory
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  PetDefinition? get activePet => _activePet;
  List<PetDefinition> get availablePets => List.unmodifiable(_availablePets);
  String get petAnimationState => _petAnimationState;
  String? get petBubbleText => _petBubbleText;
  bool get sessionHistoryLoaded => _sessionHistoryLoaded;
  bool get manualEventsLoaded => _manualEventsLoaded;
  bool get campusPlacesLoaded => _campusPlacesLoaded;
  bool get pdfLibraryLoaded => _pdfLibraryLoaded;
  bool get pdfLibraryBusy => _pdfLibraryBusy;
  bool get cloudSyncBusy => _cloudSyncBusy;
  String? get cloudSyncMessage => _cloudSyncMessage;
  bool get cloudSyncIsError => _cloudSyncIsError;
  CloudSyncStatus get cloudSyncStatus => _cloudSyncStatus;
  bool get cloudSyncStatusBusy => _cloudSyncStatusBusy;
  String? get cloudSyncStatusMessage => _cloudSyncStatusMessage;
  bool get cloudSyncEnabled => _isCloudSyncEnabled?.call() ?? false;
  bool get isGuestMode => !cloudSyncEnabled;
  List<CloudFileEntry> get cloudFileEntries =>
      List.unmodifiable(_cloudFileEntries);
  bool get cloudFilesBusy => _cloudFilesBusy;
  String? get cloudFilesMessage => _cloudFilesMessage;

  int get pendingCloudSyncCount => _pdfDocuments
      .where(
        (document) =>
            !document.isDeleted &&
            (document.syncState == 'pending' || document.serverId == null),
      )
      .length;

  List<PdfTextAnnotation> pdfAnnotationsFor(String documentId) =>
      List.unmodifiable(_pdfAnnotationsByDocumentId[documentId] ?? const []);

  List<PdfTextAnnotation> pdfNotesFor(String documentId) =>
      pdfAnnotationsFor(documentId)
          .where(
            (annotation) =>
                annotation.kind == PdfAnnotationKind.note &&
                !annotation.isDeleted &&
                (annotation.note?.trim().isNotEmpty ?? false),
          )
          .toList();

  List<PdfNoteDocumentGroup> pdfNoteDocumentGroups() {
    final groups = <PdfNoteDocumentGroup>[];
    final seenDocumentIds = <String>{};

    for (final document in _pdfDocuments) {
      if (document.isDeleted) {
        continue;
      }
      final notes = pdfNotesFor(document.id);
      if (notes.isEmpty) {
        continue;
      }
      seenDocumentIds.add(document.id);
      groups.add(PdfNoteDocumentGroup(document: document, notes: notes));
    }

    for (final documentId in _pdfAnnotationsByDocumentId.keys) {
      if (seenDocumentIds.contains(documentId)) {
        continue;
      }
      final notes = pdfNotesFor(documentId);
      if (notes.isEmpty) {
        continue;
      }
      final document = pdfDocumentById(documentId);
      if (document == null || document.isDeleted) {
        continue;
      }
      groups.add(PdfNoteDocumentGroup(document: document, notes: notes));
    }

    groups.sort(
      (left, right) => right.latestUpdated.compareTo(left.latestUpdated),
    );
    return groups;
  }

  PdfTextAnnotation? pdfAnnotationById(String documentId, String annotationId) {
    for (final annotation in pdfAnnotationsFor(documentId)) {
      if (annotation.id == annotationId) {
        return annotation;
      }
    }
    return null;
  }

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

  Future<void> ensureTodoStatusLoaded() async {
    final repository = _todoStatusRepository;
    if (repository == null || _todoStatusLoaded || _todoStatusBusy) {
      return;
    }

    _todoStatusBusy = true;
    try {
      _todoStatus = await repository.loadAll();
      _todoStatusLoaded = true;
      notifyListeners();
    } finally {
      _todoStatusBusy = false;
    }
  }

  Future<void> waitForPendingTodoStatusPersistence() async {
    await _pendingTodoStatusPersistence;
    final error = _todoStatusPersistenceError;
    if (error != null) {
      throw StateError('Todo status persistence failed: $error');
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
    await waitForPendingTodoStatusPersistence();
    await waitForPendingCampusPlacePersistence();
    await waitForPendingPdfPersistence();
  }

  Future<void> flushLocalPersistence() async {
    await waitForPendingManualEventPersistence();
    await waitForPendingPersistence();
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

  Future<void> ensurePdfLibraryLoaded({bool force = false}) async {
    final repository = _pdfDocumentsRepository;
    if (repository == null || _pdfLibraryBusy) {
      return;
    }
    if (_pdfLibraryLoaded && !force) {
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

  Future<void> reloadPdfLibrary() => ensurePdfLibraryLoaded(force: true);

  Future<String> renameLocalFolder(String folderPath, String newName) async {
    final service = _localFolderService;
    if (service == null) {
      return '当前无法重命名文件夹。';
    }
    await waitForPendingPdfPersistence();
    await ensurePdfLibraryLoaded();
    await service.renameFolder(folder: Directory(folderPath), newName: newName);
    await reloadPdfLibrary();
    return '已重命名文件夹。';
  }

  void clearCloudFileCache() {
    _cloudFileEntries = const [];
    _cloudFilesMessage = null;
    notifyListeners();
  }

  void requestOpenReading({
    String? documentId,
    int? cloudServerId,
    int? pageNumber,
    String? annotationId,
    bool openFullscreen = false,
  }) {
    if (documentId != null) {
      final doc = pdfDocumentById(documentId);
      if (doc != null && !doc.fileKind.isPdf) {
        throw StateError('科研文献仅支持 PDF，请使用「文档查阅」打开该文件。');
      }
      ensureInReadingList(documentId);
    }
    _pendingReadingOpen = ReadingOpenRequest(
      documentId: documentId,
      cloudServerId: cloudServerId,
      pageNumber: pageNumber,
      annotationId: annotationId,
      openFullscreen: openFullscreen,
    );
    notifyListeners();
  }

  void requestOpenDocumentView({String? documentId, int? cloudServerId}) {
    if (documentId != null) {
      final doc = pdfDocumentById(documentId);
      if (doc != null && !doc.fileKind.isViewable) {
        throw StateError('文档查阅仅支持文本或 PPT 文件。');
      }
    }
    _pendingDocumentViewOpen = DocumentViewOpenRequest(
      documentId: documentId,
      cloudServerId: cloudServerId,
    );
    notifyListeners();
  }

  DocumentViewOpenRequest? consumeDocumentViewOpenRequest() {
    final request = _pendingDocumentViewOpen;
    _pendingDocumentViewOpen = null;
    return request;
  }

  PdfOperationApi get pdfOperationApi => PdfOperationApi(client: ApiClient());

  Future<void> refreshCloudUserNotes() async {
    final syncEngine = _fileSyncEngine;
    if (syncEngine == null || !cloudSyncEnabled) {
      return;
    }
    await ensurePdfLibraryLoaded();
    try {
      final remoteNotes = await syncEngine.fetchUserNotes();
      for (final note in remoteNotes) {
        final existing =
            _pdfAnnotationsByDocumentId[note.documentId] ??
            const <PdfTextAnnotation>[];
        final index = existing.indexWhere((item) => item.id == note.id);
        final next = [...existing];
        if (index == -1) {
          next.add(note);
        } else if (note.updatedAt.isAfter(existing[index].updatedAt)) {
          next[index] = note;
        }
        next.sort(_comparePdfAnnotations);
        _pdfAnnotationsByDocumentId[note.documentId] = next;
        await _pdfDocumentsRepository?.saveAnnotation(
          note,
          operation: 'sync_meta',
        );
      }
      notifyListeners();
    } on ApiException {
      // 离线或后端未升级时保留本地笔记列表。
    }
  }

  ReadingOpenRequest? consumeReadingOpenRequest() {
    final request = _pendingReadingOpen;
    _pendingReadingOpen = null;
    return request;
  }

  /// 用户通过侧栏手动切换页面时丢弃未消费的跨页打开请求，避免刷新等操作误触发跳转。
  void discardUnconsumedOpenRequests() {
    _pendingReadingOpen = null;
    _pendingDocumentViewOpen = null;
    _pendingPdfToolsOpen = null;
    _pendingPdfToolsNavigation = false;
  }

  CloudFileEntry? cloudFileEntryByServerId(int serverId) {
    for (final entry in _cloudFileEntries) {
      if (entry.serverId == serverId) {
        return entry;
      }
    }
    return null;
  }

  Future<void> refreshCloudFiles({bool reconcile = true}) async {
    final syncEngine = _fileSyncEngine;
    if (syncEngine == null || !cloudSyncEnabled) {
      _cloudFileEntries = const [];
      _cloudFilesMessage = isGuestMode ? '本地模式：文件仅保存在本机' : null;
      notifyListeners();
      return;
    }
    if (_cloudFilesBusy) {
      return;
    }
    _cloudFilesBusy = true;
    _cloudFilesMessage = null;
    notifyListeners();
    try {
      _cloudFileEntries = await syncEngine.fetchCloudFileTree(
        reconcile: reconcile,
      );
      final fileCount = _cloudFileEntries
          .where((entry) => !entry.systemRoot && !entry.isFolder)
          .length;
      final folderCount = _cloudFileEntries
          .where((entry) => !entry.systemRoot && entry.isFolder)
          .length;
      _cloudFilesMessage = '已同步云端：$folderCount 个文件夹，$fileCount 个文件';
    } on ApiException catch (error) {
      _cloudFilesMessage = error.message;
    } catch (error) {
      _cloudFilesMessage = '刷新云端文件失败：$error';
    } finally {
      _cloudFilesBusy = false;
      notifyListeners();
    }
  }

  Future<String?> refreshCloudSyncStatus() async {
    final syncEngine = _fileSyncEngine;
    if (syncEngine == null || !cloudSyncEnabled) {
      _cloudSyncStatus = const CloudSyncStatus.empty();
      _cloudSyncStatusMessage = isGuestMode ? '当前为本地模式，登录后可查看云同步状态。' : null;
      notifyListeners();
      return _cloudSyncStatusMessage;
    }
    if (_cloudSyncStatusBusy) {
      return null;
    }
    _cloudSyncStatusBusy = true;
    _cloudSyncStatusMessage = null;
    notifyListeners();
    try {
      _cloudSyncStatus = await syncEngine.loadStatus();
      _cloudSyncStatusMessage = null;
      return '同步状态已刷新。';
    } on ApiException catch (error) {
      _cloudSyncStatusMessage = error.message;
      return error.message;
    } catch (error) {
      _cloudSyncStatusMessage = '刷新同步状态失败：$error';
      return _cloudSyncStatusMessage;
    } finally {
      _cloudSyncStatusBusy = false;
      notifyListeners();
    }
  }

  Future<String?> syncCloudNow() async {
    final syncEngine = _fileSyncEngine;
    if (syncEngine == null || !cloudSyncEnabled) {
      return '请先登录后再同步云端数据。';
    }
    if (_cloudSyncBusy) {
      return null;
    }
    _cloudSyncBusy = true;
    _cloudSyncMessage = null;
    _cloudSyncIsError = false;
    notifyListeners();
    try {
      final report = await syncEngine.syncAll();
      await ensurePdfLibraryLoaded(force: true);
      await refreshCloudFiles(reconcile: true);
      await _reloadSessionHistory();
      await refreshCloudSyncStatus();
      _cloudSyncMessage =
          '同步完成：上传 ${report.uploadedFileCount} 个文件，待处理 ${_cloudSyncStatus.totalPendingCount} 项。';
      _cloudSyncIsError = false;
      return _cloudSyncMessage;
    } on ApiException catch (error) {
      _cloudSyncMessage = error.message;
      _cloudSyncIsError = true;
      return error.message;
    } catch (error) {
      _cloudSyncMessage = '同步失败：$error';
      _cloudSyncIsError = true;
      return _cloudSyncMessage;
    } finally {
      _cloudSyncBusy = false;
      notifyListeners();
    }
  }

  Future<String?> saveDocumentToCloud(
    String documentId, {
    String? newTitle,
  }) async {
    if (!cloudSyncEnabled) {
      return '请先登录后再保存到云端';
    }
    final syncEngine = _fileSyncEngine;
    if (syncEngine == null) {
      return '同步引擎未初始化';
    }
    await waitForPendingPdfPersistence();
    await _flushDocumentAnnotations(documentId);

    var document = pdfDocumentById(documentId);
    if (document == null) {
      return '未找到该文件';
    }
    if (document.path.isEmpty || !File(document.path).existsSync()) {
      return '本地文件不存在，无法上传';
    }
    if (document.cloudOnly) {
      _upsertPdfDocument(document, persist: true);
      document = pdfDocumentById(documentId) ?? document;
    }

    final trimmedTitle = newTitle?.trim();
    final saveAsNew =
        trimmedTitle != null &&
        trimmedTitle.isNotEmpty &&
        trimmedTitle != document.title;
    final annotations = List<PdfTextAnnotation>.from(
      _pdfAnnotationsByDocumentId[documentId] ?? const [],
    );

    _cloudSyncBusy = true;
    notifyListeners();
    try {
      var activeDocument = document;
      var activeDocumentId = documentId;
      if (saveAsNew) {
        final created = await syncEngine.uploadDocumentAsNew(
          document: document.copyWith(title: trimmedTitle),
          newTitle: trimmedTitle,
        );
        _upsertPdfDocument(created, persist: true);
        activeDocument = created;
        activeDocumentId = created.id;
        _pdfAnnotationsByDocumentId[created.id] = annotations;
      } else if (document.serverId == null) {
        await syncEngine.uploadDocument(document);
        final reloaded = await _pdfDocumentsRepository?.findById(documentId);
        if (reloaded != null) {
          _upsertPdfDocument(reloaded, persist: false);
          activeDocument = reloaded;
          activeDocumentId = reloaded.id;
        }
      } else {
        await syncEngine.syncDocumentMetadata(activeDocument);
      }

      final serverId = activeDocument.serverId;
      if (serverId != null) {
        final synced = await syncEngine.syncDocumentAnnotations(
          serverId: serverId,
          documentClientId: activeDocumentId,
          annotations:
              _pdfAnnotationsByDocumentId[activeDocumentId] ?? annotations,
        );
        _pdfAnnotationsByDocumentId[activeDocumentId] = synced;
        await _persistAnnotations(synced);
      }

      await syncEngine.pushOutbox();
      await refreshCloudFiles(reconcile: false);
      await refreshCloudSyncStatus();
      return saveAsNew ? '已另存为云端新文件《$trimmedTitle》' : '已保存到云端（含批注与高亮）';
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return '保存到云端失败：$error';
    } finally {
      _cloudSyncBusy = false;
      notifyListeners();
    }
  }

  Future<void> _flushDocumentAnnotations(String documentId) async {
    final repository = _pdfDocumentsRepository;
    final annotations = _pdfAnnotationsByDocumentId[documentId];
    if (repository == null || annotations == null) {
      return;
    }
    for (final annotation in annotations) {
      await repository.saveAnnotation(annotation);
    }
  }

  Future<void> _persistAnnotations(List<PdfTextAnnotation> annotations) async {
    final repository = _pdfDocumentsRepository;
    if (repository == null) {
      return;
    }
    for (final annotation in annotations) {
      await repository.saveAnnotation(annotation, operation: 'sync_meta');
    }
  }

  Future<void> _loadCloudAnnotationsFor(PdfLibraryDocument document) async {
    final syncEngine = _fileSyncEngine;
    final serverId = document.serverId;
    if (syncEngine == null || serverId == null) {
      return;
    }
    final annotations = await syncEngine.fetchDocumentAnnotations(
      fileServerId: serverId,
      documentClientId: document.id,
    );
    _pdfAnnotationsByDocumentId[document.id] = annotations;
  }

  Future<PdfLibraryDocument?> prepareCloudFileForReading(
    CloudFileEntry entry,
  ) async {
    final syncEngine = _fileSyncEngine;
    if (syncEngine == null) {
      return null;
    }
    if (entry.isFolder) {
      throw StateError('请选择文件');
    }
    final kind = WorkspaceFileKind.fromPath(entry.title);
    if (!kind.isPdf) {
      throw StateError('科研文献仅支持 PDF。文本或 PPT 请使用「文档查阅」。');
    }
    final existing = _findDocumentByServerId(entry.serverId);
    if (existing != null && File(existing.path).existsSync()) {
      ensureInReadingList(existing.id);
      await _loadCloudAnnotationsFor(existing);
      notifyListeners();
      return existing;
    }
    final downloaded = await syncEngine.importCloudFileToLocal(
      entry,
      persist: false,
      cloudOnly: true,
    );
    final readingDocument = downloaded.copyWith(inReadingList: true);
    _upsertPdfDocument(readingDocument, persist: false);
    await _loadCloudAnnotationsFor(readingDocument);
    notifyListeners();
    return readingDocument;
  }

  Future<PdfLibraryDocument?> prepareCloudFileForView(
    CloudFileEntry entry,
  ) async {
    final syncEngine = _fileSyncEngine;
    if (syncEngine == null) {
      return null;
    }
    if (entry.isFolder) {
      throw StateError('请选择文件');
    }
    final kind = WorkspaceFileKind.fromPath(entry.title);
    if (!kind.isViewable) {
      throw StateError('文档查阅仅支持文本或 PPT 文件。');
    }
    final existing = _findDocumentByServerId(entry.serverId);
    if (existing != null && File(existing.path).existsSync()) {
      notifyListeners();
      return existing;
    }
    final downloaded = await syncEngine.importCloudFileToLocal(
      entry,
      persist: true,
      cloudOnly: false,
    );
    final viewDoc = downloaded.copyWith(
      fileKind: kind,
      inReadingList: false,
      cloudOnly: false,
    );
    _upsertPdfDocument(viewDoc, persist: true);
    notifyListeners();
    return viewDoc;
  }

  Future<PdfLibraryDocument> saveProcessedOutput({
    required PdfProcessOutput output,
    required PdfLibraryDocument source,
    String? category,
  }) async {
    await ensurePdfLibraryLoaded();
    final kind = WorkspaceFileKind.fromPath(output.fileName);
    final materials = await _localWorkspaceService.resolveMaterialsDirectory(
      category: category ?? source.category,
    );
    final target = File(
      '${materials.path}${Platform.pathSeparator}${_safeOutputName(output.fileName)}',
    );
    await target.writeAsBytes(output.bytes, flush: true);
    final now = DateTime.now();
    final document = PdfLibraryDocument(
      id: 'file_${now.microsecondsSinceEpoch}',
      title: _fileTitleFromPath(target.path),
      path: target.path,
      fileKind: kind,
      category: category ?? source.category,
      createdAt: now,
      updatedAt: now,
      inReadingList: kind.isPdf,
    );
    _pdfDocuments.insert(0, document);
    _pdfAnnotationsByDocumentId.putIfAbsent(document.id, () => const []);
    _queuePdfDocumentSave(document);
    notifyListeners();
    return document;
  }

  String _safeOutputName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<PdfLibraryDocument?> reopenCloudDocumentAfterSave({
    required int fileServerId,
    String? previousDocumentId,
  }) async {
    final entry = cloudFileEntryByServerId(fileServerId);
    if (entry == null) {
      return previousDocumentId == null
          ? null
          : pdfDocumentById(previousDocumentId);
    }
    return prepareCloudFileForReading(entry);
  }

  Future<PdfLibraryDocument?> moveCloudEntryToLocal(
    CloudFileEntry entry,
  ) async {
    final syncEngine = _fileSyncEngine;
    if (syncEngine == null) {
      return null;
    }
    if (entry.isFolder) {
      throw StateError('文件夹无法移到本地');
    }
    await ensurePdfLibraryLoaded();
    final existing = _findDocumentByServerId(entry.serverId);
    if (existing != null && !existing.cloudOnly) {
      return existing;
    }
    final imported = await syncEngine.importCloudFileToLocal(
      entry,
      persist: true,
      cloudOnly: false,
    );
    final materialized = imported.copyWith(cloudOnly: false);
    _upsertPdfDocument(materialized, persist: true);
    _pdfAnnotationsByDocumentId.putIfAbsent(materialized.id, () => const []);
    notifyListeners();
    return materialized;
  }

  PdfLibraryDocument? _findDocumentByServerId(int serverId) {
    for (final document in _pdfDocuments) {
      if (document.serverId == serverId) {
        return document;
      }
    }
    return null;
  }

  void _upsertPdfDocument(
    PdfLibraryDocument document, {
    required bool persist,
  }) {
    final index = _pdfDocuments.indexWhere((item) => item.id == document.id);
    if (index == -1) {
      _pdfDocuments.insert(0, document);
    } else {
      _pdfDocuments[index] = document;
    }
    if (persist) {
      _queuePdfDocumentSave(document);
    }
  }

  CloudFileService get _cloudFileService =>
      _cloudFileServiceOverride ??
      CloudFileService(
        apiClient: ApiClient(
          accessTokenReader: () => AuthController.accessToken,
        ),
      );

  Future<CloudFileEntry?> createCloudFolder({
    required String title,
    int? parentId,
  }) async {
    if (!cloudSyncEnabled) {
      return null;
    }
    final folder = await _cloudFileService.createFolder(
      title: title,
      parentId: parentId,
    );
    await refreshCloudFiles(reconcile: false);
    return folder;
  }

  Future<String?> renameCloudEntry({
    required CloudFileEntry entry,
    required String title,
  }) async {
    if (!cloudSyncEnabled) {
      return '请先登录';
    }
    if (entry.systemRoot) {
      return '根目录不可重命名';
    }
    try {
      await _cloudFileService.renameEntry(entry: entry, title: title);
      await refreshCloudFiles(reconcile: false);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return '重命名失败：$error';
    }
  }

  Future<String?> deleteCloudEntry(CloudFileEntry entry) async {
    if (!cloudSyncEnabled) {
      return '请先登录';
    }
    if (entry.systemRoot) {
      return '根目录不可删除';
    }
    try {
      await _cloudFileService.deleteEntry(entry.serverId);
      final doc = _findDocumentByServerId(entry.serverId);
      if (doc != null) {
        _pdfDocuments.removeWhere((item) => item.id == doc.id);
        _pdfAnnotationsByDocumentId.remove(doc.id);
        _queuePdfDocumentDelete(doc.id);
        notifyListeners();
      }
      await refreshCloudFiles(reconcile: false);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return '删除失败：$error';
    }
  }

  Future<String?> moveCloudEntry({
    required CloudFileEntry entry,
    required int parentId,
  }) async {
    if (!cloudSyncEnabled) {
      return '请先登录';
    }
    if (entry.systemRoot) {
      return '根目录不可移动';
    }
    try {
      await _cloudFileService.moveEntry(
        serverId: entry.serverId,
        parentId: parentId,
      );
      await refreshCloudFiles(reconcile: false);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return '移动失败：$error';
    }
  }

  Future<File> ensureCloudEntryFile(CloudFileEntry entry) async {
    if (entry.isFolder) {
      throw StateError('请选择文件而非文件夹');
    }
    final existing = _findDocumentByServerId(entry.serverId);
    if (existing != null &&
        existing.path.isNotEmpty &&
        File(existing.path).existsSync()) {
      return File(existing.path);
    }
    final cacheDir = await _localWorkspaceService.resolveMaterialsDirectory(
      category: '_cloud_cache',
    );
    final safeName = entry.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final target = File(
      '${cacheDir.path}${Platform.pathSeparator}cloud_${entry.serverId}_$safeName',
    );
    if (!target.existsSync()) {
      await _cloudFileService.downloadToCache(
        serverId: entry.serverId,
        targetPath: target.path,
      );
    }
    return target;
  }

  Future<String?> uploadFileToCloudFolder({
    required int parentId,
    required String filePath,
  }) async {
    if (!cloudSyncEnabled) {
      return '请先登录';
    }
    final file = File(filePath);
    if (!file.existsSync()) {
      return '文件不存在';
    }
    try {
      await _cloudFileService.uploadFileToParent(
        parentId: parentId,
        file: file,
        knownEntries: _cloudFileEntries,
      );
      await refreshCloudFiles(reconcile: false);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return '上传失败：$error';
    }
  }

  Future<String?> uploadLocalDocumentToCloud({
    required String documentId,
    required int parentId,
  }) async {
    if (!cloudSyncEnabled) {
      return '请先登录';
    }
    final doc = pdfDocumentById(documentId);
    if (doc == null) {
      return '未找到该文件';
    }
    if (doc.path.isEmpty || !File(doc.path).existsSync()) {
      return '本地文件不存在';
    }
    try {
      final entry = await _cloudFileService.uploadFileToParent(
        parentId: parentId,
        file: File(doc.path),
        knownEntries: _cloudFileEntries,
      );
      final updated = doc.copyWith(
        serverId: entry.serverId,
        syncVersion: entry.version,
        syncState: 'synced',
        storageKey: entry.storageKey,
        contentHash: entry.contentHash,
        updatedAt: DateTime.now(),
      );
      _upsertPdfDocument(updated, persist: true);
      await refreshCloudFiles(reconcile: false);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return '上传失败：$error';
    }
  }

  @Deprecated('使用 uploadFileToCloudFolder')
  Future<String?> uploadPdfToCloudFolder({
    required int parentId,
    required String filePath,
  }) => uploadFileToCloudFolder(parentId: parentId, filePath: filePath);

  Future<String?> uploadBytesToCloudFolder({
    required int parentId,
    required List<int> bytes,
    required String fileName,
  }) async {
    final cacheDir = await _localWorkspaceService.resolveMaterialsDirectory(
      category: '_cloud_cache',
    );
    final safe = _safeOutputName(fileName);
    final temp = File('${cacheDir.path}${Platform.pathSeparator}upload_$safe');
    await temp.writeAsBytes(bytes, flush: true);
    return uploadFileToCloudFolder(parentId: parentId, filePath: temp.path);
  }

  Future<String?> persistProcessedOutput({
    required PdfProcessOutput output,
    required PdfLibraryDocument source,
    required bool saveLocal,
    required bool saveCloud,
    int? cloudParentId,
    String? category,
  }) async {
    PdfLibraryDocument? localDoc;
    if (saveLocal) {
      localDoc = await saveProcessedOutput(
        output: output,
        source: source,
        category: category,
      );
    }
    if (saveCloud && cloudParentId != null) {
      final message = await uploadBytesToCloudFolder(
        parentId: cloudParentId,
        bytes: output.bytes,
        fileName: output.fileName,
      );
      if (message != null) {
        return message;
      }
      await refreshCloudFiles(reconcile: false);
    }
    if (saveLocal && saveCloud) {
      return '已保存到本地并上传云端';
    }
    if (saveLocal && localDoc != null) {
      return '已保存到本地《${localDoc.title}》';
    }
    if (saveCloud) {
      return '已上传到云端';
    }
    return null;
  }

  Future<String?> renameLocalPdfDocument(String id, String title) {
    return _runTrackedPdfOperation(() => _renameLocalPdfDocument(id, title));
  }

  Future<String?> _renameLocalPdfDocument(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return '名称不能为空';
    }
    final index = _pdfDocuments.indexWhere((document) => document.id == id);
    if (index == -1) {
      return '未找到该文件';
    }
    final cached = _pdfDocuments[index];
    final original = await _pdfDocumentsRepository?.findById(id) ?? cached;
    if (original.isDeleted) {
      _pdfDocuments.removeAt(index);
      notifyListeners();
      return null;
    }
    final originalFile = File(original.path);
    final renameTarget = await _localWorkspaceService
        .resolveManagedRenameTarget(originalFile, trimmed);
    final changesPath =
        _normalizeFilePath(renameTarget.path) !=
        _normalizeFilePath(originalFile.path);
    if (changesPath) {
      await _localWorkspaceService.writeManagedFileOperationJournal(
        type: 'rename',
        documentId: id,
        original: originalFile,
        target: renameTarget,
      );
    }
    final renamedFile = await _localWorkspaceService.renameManagedFile(
      originalFile,
      trimmed,
    );
    final updated = original.copyWith(
      title: _fileTitleFromPath(renamedFile.path),
      path: renamedFile.path,
      updatedAt: DateTime.now(),
    );
    try {
      await _pdfDocumentsRepository?.saveDocument(updated, operation: 'rename');
    } catch (_) {
      var restored = !changesPath;
      if (await renamedFile.exists() &&
          _normalizeFilePath(renamedFile.path) !=
              _normalizeFilePath(originalFile.path)) {
        await renamedFile.rename(originalFile.path);
        restored = true;
      }
      if (restored && changesPath) {
        await _localWorkspaceService.clearManagedFileOperationJournal();
      }
      try {
        await _pdfDocumentsRepository?.saveDocument(
          original,
          operation: 'rename',
        );
      } catch (_) {
        // Preserve the original persistence error for the caller.
      }
      rethrow;
    }
    _pdfDocuments[index] = updated;
    notifyListeners();
    if (changesPath) {
      try {
        await _localWorkspaceService.clearManagedFileOperationJournal();
      } catch (_) {
        // The manifest and payload rename are committed. Retain the journal
        // so startup recovery can verify the target and finish cleanup.
      }
    }
    return null;
  }

  Future<void> syncLibraryToCloud() async {
    final syncEngine = _fileSyncEngine;
    if (syncEngine == null) {
      _cloudSyncMessage = '同步引擎未初始化';
      _cloudSyncIsError = true;
      notifyListeners();
      return;
    }
    if (!cloudSyncEnabled) {
      _cloudSyncMessage = '请先登录云端账号后再同步';
      _cloudSyncIsError = true;
      notifyListeners();
      return;
    }
    if (_cloudSyncBusy) {
      return;
    }
    _cloudSyncBusy = true;
    _cloudSyncMessage = null;
    _cloudSyncIsError = false;
    notifyListeners();
    try {
      final report = await syncEngine.syncAll();
      await reloadPdfLibrary();
      if (report.uploadedFileCount > 0) {
        _cloudSyncMessage = '云同步完成：${report.uploadedFileCount} 个 PDF 已上传至云端';
      } else {
        _cloudSyncMessage = '云同步完成（元数据已同步；PDF 若已上传过则不会重复传）';
      }
      _cloudSyncIsError = false;
    } on ApiException catch (error) {
      _cloudSyncMessage = error.message;
      _cloudSyncIsError = true;
    } catch (error) {
      _cloudSyncMessage = '同步失败：$error';
      _cloudSyncIsError = true;
    } finally {
      _cloudSyncBusy = false;
      notifyListeners();
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

  Future<PdfLibraryDocument> addWorkspaceFileFromPath(
    String path, {
    String category = _defaultPdfCategory,
  }) {
    return _runTrackedPdfOperation(
      () => _addWorkspaceFileFromPath(path, category: category),
    );
  }

  Future<PdfLibraryDocument> _addWorkspaceFileFromPath(
    String path, {
    required String category,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('找不到文件。');
    }
    final kind = WorkspaceFileKind.fromPath(path);

    await ensurePdfLibraryLoaded();
    final now = DateTime.now();
    final archived = await _localWorkspaceService
        .copyFileIntoMaterialsWithResult(file, category: category);
    final archivedFile = archived.file;
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
        fileKind: kind,
        category: normalizedCategory,
        lastOpenedAt: now,
        updatedAt: now,
        inReadingList: kind.isPdf
            ? true
            : _pdfDocuments[existingIndex].inReadingList,
      );
      try {
        await _pdfDocumentsRepository?.saveDocument(updatedDocument);
      } catch (_) {
        if (archived.created && await archivedFile.exists()) {
          await archivedFile.delete();
        }
        rethrow;
      }
      _pdfDocuments
        ..removeAt(existingIndex)
        ..insert(0, updatedDocument);
      notifyListeners();
      return updatedDocument;
    }

    final document = PdfLibraryDocument(
      id: 'file_${now.microsecondsSinceEpoch}',
      title: _fileTitleFromPath(archivedFile.path),
      path: archivedFile.path,
      fileKind: kind,
      category: normalizedCategory,
      lastOpenedAt: now,
      createdAt: now,
      updatedAt: now,
      inReadingList: kind.isPdf,
    );
    try {
      await _pdfDocumentsRepository?.saveDocument(document);
    } catch (_) {
      if (archived.created && await archivedFile.exists()) {
        await archivedFile.delete();
      }
      rethrow;
    }
    _pdfDocuments.insert(0, document);
    _pdfAnnotationsByDocumentId[document.id] = const [];
    notifyListeners();
    return document;
  }

  Future<PdfLibraryDocument> addPdfDocumentFromPath(
    String path, {
    String category = _defaultPdfCategory,
  }) async {
    if (_extensionOf(path) != 'pdf') {
      throw StateError('科研文献仅支持 PDF 文件。');
    }
    return addWorkspaceFileFromPath(path, category: category);
  }

  String removeFromReadingList(String id) {
    final index = _pdfDocuments.indexWhere((document) => document.id == id);
    if (index == -1) {
      return '没有找到这份 PDF。';
    }

    final document = _pdfDocuments[index];
    if (document.isDeleted) {
      _pdfDocuments.removeAt(index);
      _pdfAnnotationsByDocumentId.remove(id);
      notifyListeners();
      return '已删除。';
    }
    if (!document.inReadingList) {
      return '《${document.title}》已不在阅读列表中。';
    }

    final updated = document.copyWith(
      inReadingList: false,
      updatedAt: DateTime.now(),
    );
    _pdfDocuments[index] = updated;
    _queuePdfDocumentSave(updated);
    notifyListeners();
    return '已从阅读列表移除《${document.title}》。';
  }

  void ensureInReadingList(String id) {
    final index = _pdfDocuments.indexWhere((document) => document.id == id);
    if (index == -1) {
      return;
    }
    final document = _pdfDocuments[index];
    if (document.inReadingList) {
      return;
    }
    final updated = document.copyWith(
      inReadingList: true,
      updatedAt: DateTime.now(),
    );
    _pdfDocuments[index] = updated;
    _queuePdfDocumentSave(updated);
    notifyListeners();
  }

  Future<String> deletePdfDocument(String id) {
    return _runTrackedPdfOperation(() => _deletePdfDocument(id));
  }

  Future<String> _deletePdfDocument(String id) async {
    final index = _pdfDocuments.indexWhere((document) => document.id == id);
    if (index == -1) {
      return '没有找到这份 PDF。';
    }

    final cached = _pdfDocuments[index];
    final document = await _pdfDocumentsRepository?.findById(id) ?? cached;
    if (document.isDeleted) {
      _pdfDocuments.removeAt(index);
      _pdfAnnotationsByDocumentId.remove(id);
      notifyListeners();
      return '已删除。';
    }
    final originalFile = File(document.path);
    final stagedTarget = await originalFile.exists()
        ? await _localWorkspaceService.resolveManagedDeletionStagingFile(
            originalFile,
          )
        : null;
    if (stagedTarget != null) {
      await _localWorkspaceService.writeManagedFileOperationJournal(
        type: 'delete',
        documentId: id,
        original: originalFile,
        target: stagedTarget,
      );
    }
    final stagedFile = await _localWorkspaceService.stageManagedFileDeletion(
      originalFile,
      stagedFile: stagedTarget,
    );
    try {
      await _pdfDocumentsRepository?.deleteDocument(id);
    } catch (_) {
      if (stagedFile != null) {
        await _localWorkspaceService.restoreStagedManagedFile(
          stagedFile,
          originalFile,
        );
        await _localWorkspaceService.clearManagedFileOperationJournal();
      }
      rethrow;
    }
    try {
      if (stagedFile != null && await stagedFile.exists()) {
        await _localWorkspaceService.deleteManagedStagedFile(stagedFile);
      }
    } catch (_) {
      try {
        await _pdfDocumentsRepository?.saveDocument(document);
        if (stagedFile != null) {
          await _localWorkspaceService.restoreStagedManagedFile(
            stagedFile,
            originalFile,
          );
          await _localWorkspaceService.clearManagedFileOperationJournal();
        }
      } catch (error, stackTrace) {
        _pdfDocuments.removeAt(index);
        _pdfAnnotationsByDocumentId.remove(id);
        notifyListeners();
        Error.throwWithStackTrace(error, stackTrace);
      }
      rethrow;
    }
    _pdfDocuments.removeAt(index);
    _pdfAnnotationsByDocumentId.remove(id);
    notifyListeners();
    if (stagedFile != null) {
      try {
        await _localWorkspaceService.clearManagedFileOperationJournal();
      } catch (_) {
        // The tombstone and payload deletion are committed. Retain the
        // journal for idempotent cleanup on the next startup.
      }
    }
    return '已删除《${document.title}》。';
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
    PdfAnnotationContentType contentType = PdfAnnotationContentType.text,
    String? latexContent,
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
      contentType: contentType,
      latexContent: latexContent?.trim().isEmpty == true
          ? null
          : latexContent?.trim(),
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
    PdfAnnotationContentType? contentType,
    String? latexContent,
    bool clearLatex = false,
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
    final normalizedLatex = clearLatex
        ? null
        : latexContent == null
        ? current.latexContent
        : latexContent.trim().isEmpty
        ? null
        : latexContent.trim();
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
      contentType: contentType ?? current.contentType,
      latexContent: normalizedLatex,
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

  Future<String?> analyzeCurrentInput() {
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
      _enqueueSessionSync(session);
    } else {
      _replaceSessionRecord(session);
      _enqueueSessionSync(session);
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
    _enqueueSessionDelete(removedSession.id);
    final removedEventIds = [
      for (final event in removedSession.events) event.id,
    ];
    if (removedEventIds.isNotEmpty) {
      _queueTodoStatusDelete(removedEventIds);
      _todoStatus = {..._todoStatus}
        ..removeWhere((eventId, _) => removedEventIds.contains(eventId));
    }
    notifyListeners();
    if (removedSession.isInstitutionCalendar) {
      return '已删除校历导入记录，并从主页日历移除相关校历事件。';
    }
    return '已删除历史记录，并移除相关人物、待办和规划事件。';
  }

  Future<String> fillSampleAndAnalyze() async {
    _editingSessionId = null;
    _editingInstitutionCalendarSessionId = null;
    analysisController.loadTextInput(
      sampleText.trim(),
      sourceType: AnalysisSourceType.text,
    );
    final message = await analyzeCurrentInput();
    return message ?? '已填入示例并完成分析。';
  }

  String addManualEvent({
    required DateTime date,
    required String title,
    required ItemCategory category,
    required EventType type,
    DateTime? time,
  }) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return '标题不能为空。';
    }

    final day = DateTime(date.year, date.month, date.day);
    final startAt = time == null
        ? day
        : DateTime(day.year, day.month, day.day, time.hour, time.minute);
    final event = EventItem(
      id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
      title: normalizedTitle,
      category: category,
      type: type,
      startAt: startAt,
      endAt: startAt,
      origin: EventOrigin.manual,
      sourceLabel: '手动添加',
    );
    _manualEvents = [..._manualEvents, event];
    _queueManualEventPersistence(event);
    notifyListeners();
    return '已添加记录。';
  }

  Future<String> deleteManualEvent(String eventId) async {
    await waitForPendingManualEventPersistence();
    await waitForPendingTodoStatusPersistence();
    await ensureManualEventsLoaded();
    await ensureTodoStatusLoaded();

    final eventIndex = _manualEvents.indexWhere((event) => event.id == eventId);
    if (eventIndex == -1 || !_manualEvents[eventIndex].isEditable) {
      return '该记录不允许删除。';
    }

    final repository = _manualEventsRepository;
    if (repository != null) {
      await repository.deleteManualEvent(eventId);
    }

    _manualEvents = [..._manualEvents]..removeAt(eventIndex);
    _todoStatus = {..._todoStatus}..remove(eventId);
    notifyListeners();
    return '已删除记录。';
  }

  /// 切换待办完成状态；完成时记录完成时间，撤销时清空。
  Future<void> toggleTodoDone(String eventId) async {
    await ensureTodoStatusLoaded();
    final event = _findEventById(eventId);
    if (event == null) {
      return;
    }

    final current = _todoStatus[eventId];
    final nextDone = !(current?.isDone ?? false);
    final nextState = EventTodoState(
      eventId: eventId,
      isDone: nextDone,
      priority: current?.priority ?? event.priority,
      completedAt: nextDone ? DateTime.now() : null,
    );
    _todoStatus = {..._todoStatus, eventId: nextState};
    _queueTodoStatusPersistence(nextState);
    _enqueueEventSync(event);
    notifyListeners();
  }

  /// 设置待办优先级。
  Future<void> setTodoPriority(String eventId, TodoPriority priority) async {
    await ensureTodoStatusLoaded();
    final event = _findEventById(eventId);
    if (event == null) {
      return;
    }

    final current = _todoStatus[eventId];
    final nextState = EventTodoState(
      eventId: eventId,
      isDone: current?.isDone ?? event.isDone,
      priority: priority,
      completedAt: current?.completedAt,
    );
    _todoStatus = {..._todoStatus, eventId: nextState};
    _queueTodoStatusPersistence(nextState);
    _enqueueEventSync(event);
    notifyListeners();
  }

  String updateEditableEvent({
    required String eventId,
    required String title,
    required ItemCategory category,
    required EventType type,
    DateTime? time,
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

      final startAt = _resolveStartAt(target.startAt, time);
      final nextManualEvents = [..._manualEvents];
      final updatedEvent = target.copyWith(
        title: normalizedTitle,
        category: category,
        type: type,
        startAt: startAt,
        endAt: startAt,
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

    final startAt = _resolveStartAt(target.startAt, time);
    final updatedEvents = [...session.events];
    updatedEvents[sessionIndex] = target.copyWith(
      title: normalizedTitle,
      category: category,
      type: type,
      startAt: startAt,
      endAt: startAt,
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
      _syncColorThemeListenable();
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
    _syncColorThemeListenable();
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

  Future<void> ensureGlassSettingsLoaded() async {
    if (_glassSettingsLoaded || _glassSettingsBusy) {
      return;
    }

    _glassSettingsBusy = true;
    try {
      _glassSettings = await _loadStoredGlassSettings();
      _glassSettingsLoaded = true;
      notifyListeners();
    } finally {
      _glassSettingsBusy = false;
    }
  }

  Future<void> saveGlassSettings(GlassSettings settings) async {
    _glassSettings = settings;
    _glassSettingsLoaded = true;
    notifyListeners();
    await _saveStoredGlassSettings(settings);
  }

  Future<void> ensureRemoteLlmAnalysisSettingsLoaded() async {
    if (_remoteLlmAnalysisSettingsLoaded || _remoteLlmAnalysisSettingsBusy) {
      return;
    }

    _setRemoteLlmAnalysisSettingsBusy(true);
    try {
      _remoteLlmAnalysisSettings = const RemoteLlmAnalysisSettings();
      _remoteLlmAnalysisSettingsLoaded = true;
      notifyListeners();
    } finally {
      _setRemoteLlmAnalysisSettingsBusy(false);
    }
  }

  Future<RemoteLlmAnalysisSettings> _remoteLlmSettingsForAnalysis() async {
    await ensureRemoteLlmAnalysisSettingsLoaded();
    return _remoteLlmAnalysisSettings;
  }

  Future<String> saveRemoteLlmAnalysisSettings(
    RemoteLlmAnalysisSettings _,
  ) async {
    _setRemoteLlmAnalysisSettingsBusy(true);
    try {
      _remoteLlmAnalysisSettings = const RemoteLlmAnalysisSettings();
      _remoteLlmAnalysisSettingsLoaded = true;
      notifyListeners();
      return '远程模型凭据将在接入 Windows 安全凭据后开放。';
    } finally {
      _setRemoteLlmAnalysisSettingsBusy(false);
    }
  }

  Future<void> ensurePetCompanionLoaded({bool autoStart = false}) async {
    if (_petCompanionLoaded) {
      if (autoStart && _petAutoStart && !petRunning) {
        await startPetCompanion();
      }
      return;
    }

    _petCompanionLoadFuture ??= _loadPetCompanionDataOnce().whenComplete(() {
      _petCompanionLoadFuture = null;
    });
    await _petCompanionLoadFuture;
    if (autoStart && _petAutoStart && !petRunning) {
      await startPetCompanion();
    }
  }

  Future<void> _loadPetCompanionDataOnce() async {
    if (_petCompanionLoaded) {
      return;
    }

    _setPetCompanionBusy(true);
    try {
      final settings = await _loadStoredPetCompanionSettings();
      _petAutoStart = settings.autoStart;
      _petCloseWithApp = settings.closeWithApp;
      _petCloseWithAppConfigured = settings.closeWithAppConfigured;
      _selectedPetId = settings.selectedPetId;
      _availablePets = await _petCompanionService.loadAvailablePets();
      _activePet = _findPetById(_selectedPetId) ?? _availablePets.first;
      _selectedPetId = _activePet?.id;
      _petCompanionLoaded = true;
      notifyListeners();
    } finally {
      _setPetCompanionBusy(false);
    }
  }

  Future<String> importPetPackage() async {
    await ensurePetCompanionLoaded();
    final selectedDirectory = await getDirectoryPath();
    if (selectedDirectory == null) {
      return '已取消导入桌宠。';
    }

    _setPetCompanionBusy(true);
    try {
      final imported = await _petCompanionService.importPetDirectory(
        selectedDirectory,
      );
      _availablePets = await _petCompanionService.loadAvailablePets();
      _activePet = _findPetById(imported.id) ?? imported;
      _selectedPetId = _activePet?.id;
      await _saveStoredPetCompanionSettings();
      notifyListeners();
      return '已导入桌宠：${imported.displayName}。';
    } on PetImportException catch (error) {
      return '导入桌宠失败：${error.message}';
    } on FileSystemException catch (error) {
      return '导入桌宠失败：${error.message}';
    } catch (error) {
      return '导入桌宠失败：$error';
    } finally {
      _setPetCompanionBusy(false);
    }
  }

  Future<String> selectPet(String petId) async {
    await ensurePetCompanionLoaded();
    final pet = _findPetById(petId);
    if (pet == null) {
      return '找不到这个桌宠。';
    }
    _activePet = pet;
    _selectedPetId = pet.id;
    _petAnimationState = 'idle';
    await _saveStoredPetCompanionSettings();
    notifyListeners();
    return '已切换桌宠：${pet.displayName}。';
  }

  Future<String> setPetAutoStart(bool value) async {
    await ensurePetCompanionLoaded();
    _petAutoStart = value;
    await _saveStoredPetCompanionSettings();
    notifyListeners();
    return value ? '已开启随研究生活启动桌宠。' : '已关闭随研究生活启动桌宠。';
  }

  Future<String> setPetCloseWithApp(bool value) async {
    await ensurePetCompanionLoaded();
    _petCloseWithApp = value;
    _petCloseWithAppConfigured = true;
    await _saveStoredPetCompanionSettings();
    notifyListeners();
    return value ? '退出研究生活时会关闭桌宠。' : '退出研究生活时会保留桌宠状态。';
  }

  Future<String> startPetCompanion() async {
    await ensurePetCompanionLoaded();
    if (petRunning) {
      return '桌宠已在运行。';
    }

    _setPetCompanionBusy(true);
    try {
      _petRunning = true;
      _petAnimationState = 'idle';
      notifyListeners();
      unawaited(_sendPetTodayTaskReminderOnce());
      return '已启动桌宠。';
    } finally {
      _setPetCompanionBusy(false);
    }
  }

  Future<String> stopPetCompanion() async {
    if (!petRunning) {
      return '桌宠当前没有运行。';
    }

    _setPetCompanionBusy(true);
    try {
      _petRunning = false;
      _petBubbleTimer?.cancel();
      _petBubbleText = null;
      _petAnimationState = 'idle';
      notifyListeners();
      return '已关闭桌宠。';
    } finally {
      _setPetCompanionBusy(false);
    }
  }

  Future<String> sendPetTestMessage() async {
    if (!petRunning) {
      return '请先启动桌宠。';
    }
    _playPetMessage('研究生活已经连接到桌宠。', animationState: 'waving');
    return '已发送测试消息给桌宠。';
  }

  Future<void> _sendPetTodayTaskReminderOnce() async {
    if (_petTodayTaskReminderSent ||
        _petTodayTaskReminderSending ||
        !petRunning) {
      return;
    }

    _petTodayTaskReminderSending = true;
    try {
      await ensureSessionHistoryLoaded();
      await ensureManualEventsLoaded();

      final tasks = _collectTodayTaskReminders(
        now: DateTime.now(),
        limit: _petTodayTaskLimit,
      );
      if (!petRunning) {
        return;
      }

      if (tasks.isEmpty) {
        _playPetMessage('今天暂时没有到期任务，可以先从最重要的一件事开始。', animationState: 'idle');
      } else {
        _playPetMessage(
          _buildPetTodayTaskReminder(tasks),
          animationState: 'review',
        );
      }
      _petTodayTaskReminderSent = true;
    } catch (_) {
      // Startup reminders should never interrupt opening the app.
    } finally {
      _petTodayTaskReminderSending = false;
    }
  }

  Future<void> ensureWeatherApiLoaded() async {
    if (_weatherApiLoaded) {
      return;
    }
    _weatherApiLoaded = true;
    _weatherApiKey = (await _loadStoredWeatherApiKey()) ?? '';
    _weatherApiHost = (await _loadStoredWeatherApiHost()) ?? '';
    _weatherService.setCredentials(
      apiKey: _weatherApiKey,
      apiHost: _weatherApiHost,
    );
    await ensureWeatherAnimationPreferenceLoaded();
  }

  Future<void> ensureWeatherAnimationPreferenceLoaded() async {
    if (_weatherAnimationPreferenceLoaded) {
      return;
    }
    _weatherAnimationPreferenceLoaded = true;
    _weatherAnimationEnabled =
        await _preferencesRepository?.loadWeatherAnimationEnabled() ?? true;
  }

  Future<void> setWeatherAnimationEnabled(bool enabled) async {
    _weatherAnimationEnabled = enabled;
    notifyListeners();
    await _preferencesRepository?.saveWeatherAnimationEnabled(enabled);
  }

  Future<String> saveWeatherApiSettings({
    required String apiKey,
    required String apiHost,
  }) async {
    final normalizedKey = apiKey.trim();
    final normalizedHost = apiHost.trim();

    await _saveStoredWeatherApiSettings(normalizedKey, normalizedHost);
    _weatherApiKey = normalizedKey;
    _weatherApiHost = normalizedHost;
    _weatherApiLoaded = true;
    _weatherService.setCredentials(
      apiKey: normalizedKey,
      apiHost: normalizedHost,
    );
    _weatherSnapshot = null;
    _weatherLoaded = false;
    notifyListeners();

    if (normalizedKey.isEmpty || normalizedHost.isEmpty) {
      return '天气设置已保存，填好 API Key 和 API Host 后天气会正常显示。';
    }

    await ensureWeatherLoaded(force: true);
    return _weatherError == null
        ? '天气设置已保存，天气已刷新。'
        : '天气设置已保存，但刷新失败：$_weatherError';
  }

  Future<void> ensureWeatherLoaded({bool force = false}) async {
    if (_weatherBusy) {
      return;
    }
    if (_weatherLoaded && !force) {
      _ensureWeatherRefreshTimer();
      return;
    }

    await ensureWeatherApiLoaded();
    if (_weatherApiKey.isEmpty) {
      _weatherLoaded = true;
      _weatherError = '未配置天气 API Key，请到设置页填写。';
      notifyListeners();
      return;
    }
    if (_weatherApiHost.isEmpty) {
      _weatherLoaded = true;
      _weatherError = '未配置天气 API Host，请到设置页填写。';
      notifyListeners();
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

  Future<GlassSettings> _loadStoredGlassSettings() async {
    final rawSettings = await _preferencesRepository?.loadGlassSettings();
    if (rawSettings == null || rawSettings.trim().isEmpty) {
      return const GlassSettings();
    }

    try {
      final decoded = jsonDecode(rawSettings);
      if (decoded is Map) {
        return GlassSettings.fromJson(decoded.cast<String, Object?>());
      }
    } on FormatException {
      return const GlassSettings();
    }
    return const GlassSettings();
  }

  Future<void> _saveStoredGlassSettings(GlassSettings settings) async {
    await _preferencesRepository?.saveGlassSettings(
      jsonEncode(settings.toJson()),
    );
  }

  /*
  Future<RemoteLlmAnalysisSettings>
  _loadStoredRemoteLlmAnalysisSettings() async {
    final rawSettings = await _preferencesRepository
        ?.loadRemoteLlmAnalysisSettings();
    if (rawSettings == null || rawSettings.trim().isEmpty) {
      return const RemoteLlmAnalysisSettings();
    }

    try {
      final decoded = jsonDecode(rawSettings);
      if (decoded is Map) {
        return RemoteLlmAnalysisSettings.fromJson(
          decoded.cast<String, Object?>(),
        );
      }
    } on FormatException {
      return const RemoteLlmAnalysisSettings();
    }
    return const RemoteLlmAnalysisSettings();
  }

  // ignore: unused_element
  Future<void> _saveStoredRemoteLlmAnalysisSettings(
    RemoteLlmAnalysisSettings settings,
  ) async {
    await _preferencesRepository?.saveRemoteLlmAnalysisSettings(
      jsonEncode(settings.toJson()),
    );
  }

  */

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

  Future<String?> _loadStoredWeatherApiKey() async {
    return _preferencesRepository?.loadWeatherApiKey();
  }

  Future<String?> _loadStoredWeatherApiHost() async {
    return _preferencesRepository?.loadWeatherApiHost();
  }

  Future<void> _saveStoredWeatherApiSettings(
    String apiKey,
    String apiHost,
  ) async {
    await _preferencesRepository?.saveWeatherApiKey(apiKey);
    await _preferencesRepository?.saveWeatherApiHost(apiHost);
  }

  Future<_PetCompanionSettings> _loadStoredPetCompanionSettings() async {
    final rawSettings = await _preferencesRepository
        ?.loadPetCompanionSettings();
    if (rawSettings == null || rawSettings.trim().isEmpty) {
      return const _PetCompanionSettings();
    }

    try {
      final decoded = jsonDecode(rawSettings);
      if (decoded is Map) {
        return _PetCompanionSettings.fromJson(decoded.cast<String, Object?>());
      }
    } on FormatException {
      return const _PetCompanionSettings();
    }
    return const _PetCompanionSettings();
  }

  Future<void> _saveStoredPetCompanionSettings() async {
    await _preferencesRepository?.savePetCompanionSettings(
      jsonEncode(
        _PetCompanionSettings(
          selectedPetId: _selectedPetId,
          autoStart: _petAutoStart,
          closeWithApp: _petCloseWithApp,
          closeWithAppConfigured: _petCloseWithAppConfigured,
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
      final backupService = BackupService(
        workspaceService: _localWorkspaceService,
      );
      final result = await backupService.createBackup();
      return '数据库已备份到：${result.directory.path}';
    } on BackupException catch (error) {
      return '备份数据库失败：${error.message}';
    } on FileSystemException catch (error) {
      return '备份数据库失败：${error.message}';
    }
  }

  Future<String?> exportConsultingPackage() async {
    await ensureHomeGalleryReady();

    _setGalleryBusy(true);
    try {
      final storageDirectory = await _localWorkspaceService
          .resolveStorageDirectory();
      final outputDirectory = Directory(
        '${storageDirectory.path}${Platform.pathSeparator}consulting_packages',
      );
      final projectRoot = await ConsultingPackageService.locateProjectRoot();
      final service = ConsultingPackageService(projectRoot: projectRoot);
      final result = await service.exportPackage(
        outputDirectory: outputDirectory,
      );
      return '咨询包已导出到：${result.packageFile.path}';
    } on ConsultingPackageException catch (error) {
      return '导出咨询包失败：${error.message}';
    } on FileSystemException catch (error) {
      return '导出咨询包失败：${error.message}';
    } finally {
      _setGalleryBusy(false);
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
    _reminderTimer?.cancel();
    _idleLockTimer?.cancel();
    if (_petCloseWithApp) {
      _petRunning = false;
      _petBubbleTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _weatherRefreshTimer?.cancel();
    _reminderTimer?.cancel();
    _idleLockTimer?.cancel();
    _petBubbleTimer?.cancel();
    analysisController.dispose();
    colorThemeListenable.dispose();
    super.dispose();
  }

  void _syncColorThemeListenable() {
    if (colorThemeListenable.value != _colorTheme) {
      colorThemeListenable.value = _colorTheme;
    }
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

  void _setPetCompanionBusy(bool value) {
    if (_petCompanionBusy == value) {
      return;
    }
    _petCompanionBusy = value;
    notifyListeners();
  }

  void _setRemoteLlmAnalysisSettingsBusy(bool value) {
    if (_remoteLlmAnalysisSettingsBusy == value) {
      return;
    }
    _remoteLlmAnalysisSettingsBusy = value;
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

  List<EventItem> _collectTodayTaskReminders({
    required DateTime now,
    required int limit,
  }) {
    final today = _startOfDay(now);
    final candidates =
        calendarEvents.where((event) {
          if (event.type != EventType.plan ||
              event.origin == EventOrigin.holiday) {
            return false;
          }

          final dueDay = _startOfDay(event.startAt);
          return dueDay == today;
        }).toList()..sort((left, right) {
          final dateComparison = left.startAt.compareTo(right.startAt);
          if (dateComparison != 0) {
            return dateComparison;
          }
          return left.title.compareTo(right.title);
        });

    return candidates.take(limit).toList();
  }

  String _buildPetTodayTaskReminder(List<EventItem> tasks) {
    final lines = <String>[
      tasks.length == 1 ? '今天有一件任务要处理：' : '今天这些任务需要留意：',
      for (var index = 0; index < tasks.length; index++)
        '${index + 1}. ${tasks[index].title}',
      '先从最重要的一件开始就好。',
    ];
    return lines.join('\n');
  }

  void _playPetMessage(
    String message, {
    String animationState = 'idle',
    Duration duration = const Duration(seconds: 12),
  }) {
    _petBubbleTimer?.cancel();
    _petBubbleText = message;
    _petAnimationState = animationState;
    notifyListeners();

    _petBubbleTimer = Timer(duration, () {
      _petBubbleText = null;
      _petAnimationState = 'idle';
      notifyListeners();
    });
  }

  PetDefinition? _findPetById(String? id) {
    if (id == null || id.trim().isEmpty) {
      return null;
    }
    for (final pet in _availablePets) {
      if (pet.id == id) {
        return pet;
      }
    }
    return null;
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

  List<EventItem> _applyTodoStatusToEvents(List<EventItem> events) {
    if (_todoStatus.isEmpty) {
      return events;
    }
    return [for (final event in events) _applyTodoStatus(event)];
  }

  EventItem _applyTodoStatus(EventItem event) {
    final state = _todoStatus[event.id];
    if (state == null) {
      return event;
    }
    return EventItem(
      id: event.id,
      title: event.title,
      category: event.category,
      type: event.type,
      startAt: event.startAt,
      endAt: event.endAt,
      origin: event.origin,
      personNames: event.personNames,
      sourceLabel: event.sourceLabel,
      isDone: state.isDone,
      priority: state.priority,
      completedAt: state.completedAt,
    );
  }

  EventItem? _findEventById(String eventId) {
    for (final event in calendarEvents) {
      if (event.id == eventId) {
        return event;
      }
    }
    return null;
  }

  /// 解析事件开始时间：time 非空时套用具体时刻，为空则回到当日零点（无具体时间）。
  DateTime _resolveStartAt(DateTime original, DateTime? time) {
    if (time == null) {
      return DateTime(original.year, original.month, original.day);
    }
    return DateTime(
      original.year,
      original.month,
      original.day,
      time.hour,
      time.minute,
    );
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
        .then((_) => _enqueueEventSync(event))
        .catchError((Object error) {
          _manualEventPersistenceError = error;
        });
    unawaited(_pendingManualEventPersistence);
  }

  /// 事件本体或待办状态变更后，若已登录云同步，则将事件写入同步 Outbox。
  void _enqueueEventSync(EventItem event) {
    if (!cloudSyncEnabled) {
      return;
    }
    final engine = _fileSyncEngine;
    if (engine == null) {
      return;
    }
    final state = _todoStatus[event.id];
    unawaited(
      engine.enqueueEvent(
        event: event,
        isDone: state?.isDone ?? false,
        priority: state?.priority.name ?? event.priority.name,
        completedAt: state?.completedAt,
      ),
    );
  }

  void _queueTodoStatusPersistence(EventTodoState state) {
    final repository = _todoStatusRepository;
    if (repository == null) {
      return;
    }

    _todoStatusPersistenceError = null;
    _pendingTodoStatusPersistence = _pendingTodoStatusPersistence
        .then((_) => repository.upsert(state))
        .catchError((Object error) {
          _todoStatusPersistenceError = error;
        });
    unawaited(_pendingTodoStatusPersistence);
  }

  void _queueTodoStatusDelete(List<String> eventIds) {
    final repository = _todoStatusRepository;
    if (repository == null || eventIds.isEmpty) {
      return;
    }

    _todoStatusPersistenceError = null;
    _pendingTodoStatusPersistence = _pendingTodoStatusPersistence
        .then((_) => repository.deleteForEvents(eventIds))
        .catchError((Object error) {
          _todoStatusPersistenceError = error;
        });
    unawaited(_pendingTodoStatusPersistence);
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
        .then((_) => repository.saveDocument(document, operation: 'metadata'))
        .catchError((Object error) {
          _pdfPersistenceError = error;
        });
    unawaited(_pendingPdfPersistence);
  }

  Future<T> _runTrackedPdfOperation<T>(Future<T> Function() operation) {
    _pdfPersistenceError = null;
    final result = _localDataOperationCoordinator.runExclusive(operation);
    final previous = _pendingPdfPersistence;
    final tracked = result.then<void>((_) {}).catchError((Object error) {
      _pdfPersistenceError = error;
    });
    _pendingPdfPersistence = Future.wait<void>([previous, tracked]);
    return result;
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

class _PetCompanionSettings {
  const _PetCompanionSettings({
    this.selectedPetId,
    this.autoStart = true,
    this.closeWithApp = true,
    this.closeWithAppConfigured = false,
  });

  factory _PetCompanionSettings.fromJson(Map<String, Object?> json) {
    final selectedPetId = json['selectedPetId'];
    final closeWithAppConfigured = json['closeWithAppConfigured'] == true;
    return _PetCompanionSettings(
      selectedPetId: selectedPetId is String && selectedPetId.trim().isNotEmpty
          ? selectedPetId
          : null,
      autoStart: json['autoStart'] is bool ? json['autoStart'] == true : true,
      closeWithApp: closeWithAppConfigured
          ? json['closeWithApp'] == true
          : true,
      closeWithAppConfigured: closeWithAppConfigured,
    );
  }

  final String? selectedPetId;
  final bool autoStart;
  final bool closeWithApp;
  final bool closeWithAppConfigured;

  Map<String, Object?> toJson() {
    return {
      'selectedPetId': selectedPetId,
      'autoStart': autoStart,
      'closeWithApp': closeWithApp,
      'closeWithAppConfigured': closeWithAppConfigured,
    };
  }
}
