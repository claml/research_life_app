import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../services/analysis/analysis_service.dart';
import '../services/calendar/institution_calendar_service.dart';
import '../services/database/app_database.dart';
import '../services/database/database_connection.dart';
import '../services/database/repositories/campus_places_repository.dart';
import '../services/database/repositories/manual_events_repository.dart';
import '../services/database/repositories/pdf_documents_repository.dart';
import '../services/database/repositories/preferences_repository.dart';
import '../services/database/repositories/sessions_repository.dart';
import '../services/import/import_service.dart';
import '../services/review/review_service.dart';
import '../services/storage/local_workspace_service.dart';
import '../state/research_life_controller.dart';
import 'app_shell.dart';
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
  late final ResearchLifeController _controller;
  late final AppLifecycleListener _appLifecycleListener;
  Future<void>? _shutdownFuture;
  bool _databaseClosed = false;

  @override
  void initState() {
    super.initState();
    _workspaceService = const LocalWorkspaceService();
    _database = AppDatabase(openDatabaseConnection(_workspaceService));
    _preferencesRepository = PreferencesRepository(_database);
    _sessionsRepository = SessionsRepository(_database);
    _manualEventsRepository = ManualEventsRepository(_database);
    _campusPlacesRepository = CampusPlacesRepository(_database);
    _pdfDocumentsRepository = PdfDocumentsRepository(_database);
    _controller = ResearchLifeController(
      importService: const ImportService(),
      analysisService: const AnalysisService(),
      reviewService: const ReviewService(),
      institutionCalendarService: const InstitutionCalendarService(),
      localWorkspaceService: _workspaceService,
      preferencesRepository: _preferencesRepository,
      sessionsRepository: _sessionsRepository,
      manualEventsRepository: _manualEventsRepository,
      campusPlacesRepository: _campusPlacesRepository,
      pdfDocumentsRepository: _pdfDocumentsRepository,
    );
    _appLifecycleListener = AppLifecycleListener(
      onExitRequested: _handleExitRequested,
    );
    _nativeLifecycleChannel.setMethodCallHandler(_handleNativeLifecycleCall);
    unawaited(_controller.ensureColorThemeLoaded());
    unawaited(_controller.ensureWeatherLoaded());
    unawaited(_controller.ensureCampusPlacesLoaded());
    unawaited(_initializeStartupRecordsAndPet());
  }

  Future<void> _initializeStartupRecordsAndPet() async {
    await _controller.ensureSessionHistoryLoaded();
    await _controller.ensureManualEventsLoaded();
    await _controller.ensurePdfLibraryLoaded();
    await _controller.ensureVPetCompanionLoaded(autoStart: true);
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
    _nativeLifecycleChannel.setMethodCallHandler(null);
    _appLifecycleListener.dispose();
    if (_shutdownFuture == null) {
      unawaited(_shutdownForExit());
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResearchLifeScope(
      controller: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return MaterialApp(
            title: '研究生活',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(_controller.colorTheme),
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
