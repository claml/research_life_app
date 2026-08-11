import 'dart:async';
import 'dart:io';

import '../services/analysis/analysis_engine_coordinator.dart';
import '../services/analysis/analysis_service.dart';
import '../services/agent/ai_profile_repository.dart';
import '../services/agent/ai_runtime_services.dart';
import '../services/agent/openai_compatible_chat_client.dart';
import '../services/agent/windows_ai_credential_store.dart';
import '../services/calendar/institution_calendar_service.dart';
import '../services/database/app_database.dart';
import '../services/database/database_connection.dart';
import '../services/database/repositories/agent_chat_repository.dart';
import '../services/database/repositories/campus_places_repository.dart';
import '../services/database/repositories/manual_events_repository.dart';
import '../services/database/repositories/notes_repository.dart';
import '../services/database/repositories/pdf_documents_repository.dart';
import '../services/database/repositories/preferences_repository.dart';
import '../services/database/repositories/sessions_repository.dart';
import '../services/database/repositories/todo_status_repository.dart';
import '../services/import/import_service.dart';
import '../services/review/review_service.dart';
import '../services/storage/backup_service.dart';
import '../services/storage/local_data_operation_coordinator.dart';
import '../services/storage/local_file_library_store.dart';
import '../services/storage/local_folder_service.dart';
import '../services/storage/local_workspace_service.dart';
import '../services/tray/tray_service.dart';
import '../state/local_backup_controller.dart';
import '../state/research_life_controller.dart';

abstract interface class AppRuntime {
  ResearchLifeController get controller;

  LocalBackupController get backupController;

  AiRuntimeServices get aiServices;

  Future<void> flushLocalPersistence();

  Future<BackupRestoreResult> restoreBackup(Directory backupDirectory);

  /// Returns true when the close request was handled without exiting.
  Future<bool> handleWindowCloseRequest();

  Future<void> close();
}

typedef LocalAppRuntimeFactory =
    Future<AppRuntime> Function(RuntimeRestore restoreRuntime);

typedef RuntimeCleanup = FutureOr<void> Function();

class RuntimeDisposalCoordinator {
  RuntimeDisposalCoordinator({
    required RuntimeCleanup prepareController,
    required RuntimeCleanup flushPersistence,
    required RuntimeCleanup waitForTrayInitialization,
    required RuntimeCleanup disposeTray,
    required RuntimeCleanup disposeBackupController,
    required RuntimeCleanup disposeController,
    required RuntimeCleanup closeDatabase,
  }) : _steps = [
         prepareController,
         flushPersistence,
         waitForTrayInitialization,
         disposeTray,
         disposeBackupController,
         disposeController,
         closeDatabase,
       ];

  final List<RuntimeCleanup> _steps;
  Future<void>? _closeFuture;

  Future<void> close() {
    return _closeFuture ??= _performClose();
  }

  Future<void> _performClose() async {
    Object? primaryError;
    StackTrace? primaryStackTrace;
    for (final step in _steps) {
      try {
        await step();
      } catch (error, stackTrace) {
        primaryError ??= error;
        primaryStackTrace ??= stackTrace;
      }
    }
    final error = primaryError;
    if (error != null) {
      Error.throwWithStackTrace(error, primaryStackTrace!);
    }
  }
}

class LocalAppRuntime implements AppRuntime {
  LocalAppRuntime._({
    required this.controller,
    required this.backupController,
    required this.aiServices,
    required BackupService backupService,
    required AppDatabase database,
    required TrayService trayService,
  }) : _backupService = backupService,
       _trayService = trayService {
    _disposalCoordinator = RuntimeDisposalCoordinator(
      prepareController: controller.prepareForAppExit,
      flushPersistence: controller.flushLocalPersistence,
      waitForTrayInitialization: () => _trayInitialization,
      disposeTray: trayService.dispose,
      disposeBackupController: backupController.dispose,
      disposeController: controller.dispose,
      closeDatabase: database.close,
    );
  }

  @override
  final ResearchLifeController controller;

  @override
  final LocalBackupController backupController;

  @override
  final AiRuntimeServices aiServices;

  final BackupService _backupService;
  final TrayService _trayService;
  Future<void> _trayInitialization = Future<void>.value();
  late final RuntimeDisposalCoordinator _disposalCoordinator;

  static Future<LocalAppRuntime> open({
    LocalWorkspaceService? workspaceService,
    required RuntimeRestore restoreRuntime,
    required Future<void> Function() requestExit,
    bool initializeTray = true,
    OpenAiCompatibleChatClient? aiChatClient,
  }) async {
    final workspace = workspaceService ?? const LocalWorkspaceService();
    final database = AppDatabase(openDatabaseConnection(workspace));
    final localDataOperations = LocalDataOperationCoordinator(
      lockFileResolver: () async {
        final storage = await workspace.resolveStorageDirectory();
        return File('${storage.path}${Platform.pathSeparator}.local_data.lock');
      },
    );
    final preferences = PreferencesRepository(
      database,
      operationCoordinator: localDataOperations,
    );
    final sessions = SessionsRepository(
      database,
      operationCoordinator: localDataOperations,
    );
    final manualEvents = ManualEventsRepository(
      database,
      operationCoordinator: localDataOperations,
    );
    final todoStatuses = TodoStatusRepository(
      database,
      operationCoordinator: localDataOperations,
    );
    final notes = NotesRepository(
      database,
      operationCoordinator: localDataOperations,
    );
    final campusPlaces = CampusPlacesRepository(
      database,
      operationCoordinator: localDataOperations,
    );
    final localFiles = LocalFileLibraryStore(
      workspace,
      operationCoordinator: localDataOperations,
    );
    final pdfDocuments = PdfDocumentsRepository(
      database,
      localStore: localFiles,
    );
    final localFolders = LocalFolderService(
      workspaceService: workspace,
      store: localFiles,
      operationCoordinator: localDataOperations,
    );
    final aiServices = AiRuntimeServices(
      profiles: AiProfileRepository(preferences),
      credentials: WindowsAiCredentialStore(),
      chats: AgentChatRepository(
        database,
        operationCoordinator: localDataOperations,
      ),
      client:
          aiChatClient ??
          OpenAiCompatibleChatClient(
            connectTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 60),
          ),
    );
    final controller = ResearchLifeController(
      importService: const ImportService(),
      analysisService: const AnalysisService(),
      reviewService: const ReviewService(),
      institutionCalendarService: const InstitutionCalendarService(),
      localWorkspaceService: workspace,
      preferencesRepository: preferences,
      sessionsRepository: sessions,
      manualEventsRepository: manualEvents,
      todoStatusRepository: todoStatuses,
      notesRepository: notes,
      campusPlacesRepository: campusPlaces,
      pdfDocumentsRepository: pdfDocuments,
      localFolderService: localFolders,
      localDataOperationCoordinator: localDataOperations,
      analysisEngineCoordinator: AnalysisEngineCoordinator(
        ruleBasedAnalysisService: const AnalysisService(),
      ),
    );
    final backupService = BackupService(
      workspaceService: workspace,
      operationCoordinator: localDataOperations,
    );
    final backupController = LocalBackupController(
      backupService: backupService,
      migrationPreferences: preferences,
      flushLocalWrites: controller.flushLocalPersistence,
      restoreRuntime: restoreRuntime,
    );
    final trayService = TrayService(
      controller: controller,
      requestExit: requestExit,
    );
    final runtime = LocalAppRuntime._(
      controller: controller,
      backupController: backupController,
      aiServices: aiServices,
      backupService: backupService,
      database: database,
      trayService: trayService,
    );

    try {
      // Portable managed-file migration must finish before the migration
      // backup is taken, otherwise the snapshot can reference files outside
      // the workspace and omit their payload bytes.
      await controller.ensurePdfLibraryLoaded();
      await backupController.ensureMigrationBackup();
      await runtime._initializeLocalState();
    } catch (error, stackTrace) {
      try {
        await runtime.close();
      } catch (_) {
        // Preserve the startup failure after best-effort ownership cleanup.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (initializeTray) {
      runtime._trayInitialization = runtime._initializeTraySafely();
      unawaited(runtime._trayInitialization);
    }
    return runtime;
  }

  Future<void> _initializeLocalState() async {
    await controller.ensureColorThemeLoaded();
    await controller.ensureCampusPlacesLoaded();
    await controller.ensureCloseToTrayLoaded();
    await controller.ensureSessionHistoryLoaded();
    await controller.ensureManualEventsLoaded();
    await controller.ensureTodoStatusLoaded();
    await controller.ensureGlassSettingsLoaded();
    await controller.ensureCalendarRemindersLoaded();
    await controller.ensureNotesLoaded();
    await controller.ensurePinLockLoaded();
    await controller.ensurePdfLibraryLoaded();
    await controller.ensurePetCompanionLoaded(autoStart: true);
  }

  Future<void> _initializeTraySafely() async {
    try {
      await _trayService.initialize();
    } catch (_) {
      // Tray integration is optional; the local workbench remains usable when
      // the host platform or plugin is unavailable.
    }
  }

  @override
  Future<void> flushLocalPersistence() {
    return controller.flushLocalPersistence();
  }

  @override
  Future<BackupRestoreResult> restoreBackup(Directory backupDirectory) {
    return _backupService.restoreBackup(backupDirectory);
  }

  @override
  Future<bool> handleWindowCloseRequest() {
    return _trayService.handleWindowCloseRequest();
  }

  @override
  Future<void> close() {
    return _disposalCoordinator.close();
  }
}
