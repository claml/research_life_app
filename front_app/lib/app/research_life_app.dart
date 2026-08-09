import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_tokens.dart';
import '../core/theme/app_theme.dart';
import '../features/pin_lock/pin_lock_gate.dart';
import '../services/analysis/analysis_engine_coordinator.dart';
import '../services/analysis/analysis_service.dart';
import '../services/analysis/remote_llm_analysis_provider.dart';
import '../services/calendar/institution_calendar_service.dart';
import '../services/database/app_database.dart';
import '../services/database/database_connection.dart';
import '../services/database/repositories/campus_places_repository.dart';
import '../services/database/repositories/manual_events_repository.dart';
import '../services/database/repositories/notes_repository.dart';
import '../core/network/api_client.dart';
import '../services/database/repositories/pdf_documents_repository.dart';
import '../services/database/repositories/preferences_repository.dart';
import '../services/database/repositories/sessions_repository.dart';
import '../services/database/repositories/sync_outbox_repository.dart';
import '../services/database/repositories/todo_status_repository.dart';
import '../services/import/import_service.dart';
import '../services/review/review_service.dart';
import '../services/storage/local_file_library_store.dart';
import '../services/storage/local_workspace_service.dart';
import '../services/sync/cloud_file_service.dart';
import '../services/sync/device_id_service.dart';
import '../services/sync/file_sync_engine.dart';
import '../services/tray/tray_service.dart';
import '../state/auth_controller.dart';
import '../state/research_life_controller.dart';
import 'app_services_scope.dart';
import 'auth_gate.dart';
import 'auth_scope.dart';
import 'research_life_scope.dart';

class ResearchLifeApp extends StatefulWidget {
  const ResearchLifeApp({super.key});

  @override
  State<ResearchLifeApp> createState() => _ResearchLifeAppState();
}

class _ResearchLifeAppState extends State<ResearchLifeApp> {
  static const _nativeLifecycleChannel = MethodChannel(
    'research_life/window_lifecycle',
  );

  late final LocalWorkspaceService _workspaceService;
  late final AppDatabase _database;
  late final PreferencesRepository _preferencesRepository;
  late final SessionsRepository _sessionsRepository;
  late final ManualEventsRepository _manualEventsRepository;
  late final CampusPlacesRepository _campusPlacesRepository;
  late final PdfDocumentsRepository _pdfDocumentsRepository;
  late final SyncOutboxRepository _syncOutboxRepository;
  late final TodoStatusRepository _todoStatusRepository;
  late final NotesRepository _notesRepository;
  late final DeviceIdService _deviceIdService;
  late final ApiClient _cloudApiClient;
  late final CloudFileService _cloudFileService;
  late final FileSyncEngine _fileSyncEngine;
  late final AuthController _authController;
  late final ResearchLifeController _controller;
  late final TrayService _trayService;
  late final AppLifecycleListener _appLifecycleListener;
  Future<void>? _shutdownFuture;
  bool _databaseClosed = false;

  @override
  void initState() {
    super.initState();
    _authController = AuthController(skipLoginOnStartup: true);
    _authController.addListener(_handleAuthChanged);
    _workspaceService = const LocalWorkspaceService();
    _database = AppDatabase(openDatabaseConnection(_workspaceService));
    _preferencesRepository = PreferencesRepository(_database);
    _sessionsRepository = SessionsRepository(_database);
    _manualEventsRepository = ManualEventsRepository(_database);
    _campusPlacesRepository = CampusPlacesRepository(_database);
    _deviceIdService = DeviceIdService();
    _syncOutboxRepository = SyncOutboxRepository(_database);
    _todoStatusRepository = TodoStatusRepository(_database);
    _notesRepository = NotesRepository(_database);
    _cloudApiClient = ApiClient(
      accessTokenReader: () => AuthController.accessToken,
      onUnauthorized: _authController.refreshSessionAfterUnauthorized,
    );
    _cloudFileService = CloudFileService(
      apiClient: _cloudApiClient,
      deviceIdService: _deviceIdService,
    );
    final localFileStore = LocalFileLibraryStore(_workspaceService);
    _pdfDocumentsRepository = PdfDocumentsRepository(
      _database,
      localStore: localFileStore,
      outboxRepository: _syncOutboxRepository,
      deviceIdReader: _deviceIdService.getOrCreateDeviceId,
    );
    _fileSyncEngine = FileSyncEngine(
      apiClient: _cloudApiClient,
      pdfRepository: _pdfDocumentsRepository,
      outboxRepository: _syncOutboxRepository,
      workspaceService: _workspaceService,
      manualEventsRepository: _manualEventsRepository,
      todoStatusRepository: _todoStatusRepository,
      notesRepository: _notesRepository,
      sessionsRepository: _sessionsRepository,
      deviceIdService: _deviceIdService,
      cloudFileService: _cloudFileService,
    );
    _controller = ResearchLifeController(
      importService: const ImportService(),
      analysisService: const AnalysisService(),
      reviewService: const ReviewService(),
      institutionCalendarService: const InstitutionCalendarService(),
      localWorkspaceService: _workspaceService,
      preferencesRepository: _preferencesRepository,
      sessionsRepository: _sessionsRepository,
      manualEventsRepository: _manualEventsRepository,
      todoStatusRepository: _todoStatusRepository,
      notesRepository: _notesRepository,
      campusPlacesRepository: _campusPlacesRepository,
      pdfDocumentsRepository: _pdfDocumentsRepository,
      fileSyncEngine: _fileSyncEngine,
      cloudFileService: _cloudFileService,
      isCloudSyncEnabled: () => _authController.cloudSyncEnabled,
      analysisEngineCoordinator: AnalysisEngineCoordinator(
        ruleBasedAnalysisService: const AnalysisService(),
        remoteLlmProvider: RemoteLlmAnalysisProvider(
          apiClient: _cloudApiClient,
        ),
      ),
    );
    _appLifecycleListener = AppLifecycleListener(
      onExitRequested: _handleExitRequested,
    );
    _nativeLifecycleChannel.setMethodCallHandler(_handleNativeLifecycleCall);
    _trayService = TrayService(controller: _controller);
    unawaited(_trayService.initialize());
    unawaited(_controller.ensureColorThemeLoaded());
    unawaited(_controller.ensureWeatherLoaded());
    unawaited(_controller.ensureCampusPlacesLoaded());
    unawaited(_controller.ensureCloseToTrayLoaded());
    unawaited(_initializeStartupRecordsAndPet());
  }

  void _handleAuthChanged() {
    if (_authController.cloudSyncEnabled) {
      unawaited(_runCloudSync());
    } else {
      _controller.clearCloudFileCache();
    }
  }

  Future<void> _runCloudSync() async {
    await _controller.syncCloudNow();
  }

  Future<void> _initializeStartupRecordsAndPet() async {
    await _controller.ensureSessionHistoryLoaded();
    await _controller.ensureManualEventsLoaded();
    await _controller.ensureTodoStatusLoaded();
    await _controller.ensureGlassSettingsLoaded();
    await _controller.ensureCalendarRemindersLoaded();
    await _controller.ensureNotesLoaded();
    await _controller.ensurePinLockLoaded();
    await _controller.ensurePdfLibraryLoaded();
    await _controller.ensurePetCompanionLoaded(autoStart: true);
  }

  Future<AppExitResponse> _handleExitRequested() async {
    await _shutdownForExit();
    return AppExitResponse.exit;
  }

  Future<Object?> _handleNativeLifecycleCall(MethodCall call) async {
    switch (call.method) {
      case 'requestClose':
        await _shutdownForExit();
        return true;
      default:
        throw MissingPluginException('Unknown method ${call.method}');
    }
  }

  Future<void> _shutdownForExit() async {
    return _shutdownFuture ??= _performShutdownForExit();
  }

  Future<void> _performShutdownForExit() async {
    await _controller.prepareForAppExit();
    await _controller.waitForPendingPersistence();
    if (!_databaseClosed) {
      _databaseClosed = true;
      await _database.close();
    }
  }

  @override
  void dispose() {
    _authController.removeListener(_handleAuthChanged);
    _nativeLifecycleChannel.setMethodCallHandler(null);
    _appLifecycleListener.dispose();
    if (_shutdownFuture == null) {
      unawaited(_shutdownForExit());
    }
    _authController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      controller: _authController,
      child: AppServicesScope(
        fileSyncEngine: _fileSyncEngine,
        child: ResearchLifeScope(
          controller: _controller,
          child: ValueListenableBuilder<AppColorTheme>(
            valueListenable: _controller.colorThemeListenable,
            builder: (context, colorTheme, _) {
              return MaterialApp(
                title: '研究生活',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.build(colorTheme),
                home: const PinLockGate(child: AuthGate()),
              );
            },
          ),
        ),
      ),
    );
  }
}
