import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/local_services_scope.dart';
import 'package:research_life/app/research_life_scope.dart';
import 'package:research_life/core/models/weather_models.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/core/theme/app_tokens.dart';
import 'package:research_life/features/settings/settings_page.dart';
import 'package:research_life/services/agent/ai_credential_store.dart';
import 'package:research_life/services/agent/ai_profile_repository.dart';
import 'package:research_life/services/agent/ai_runtime_services.dart';
import 'package:research_life/services/agent/openai_compatible_chat_client.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/agent_chat_repository.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/backup_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';
import 'package:research_life/services/weather/weather_service.dart';
import 'package:research_life/state/local_backup_controller.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  testWidgets('local Settings edits and saves weather credentials only', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final preferences = PreferencesRepository(database);
    await preferences.saveWeatherApiKey('old-key');
    await preferences.saveWeatherApiHost('old.example.com');
    final lifeController = ResearchLifeController(
      importService: const ImportService(),
      analysisService: const AnalysisService(),
      reviewService: const ReviewService(),
      institutionCalendarService: const InstitutionCalendarService(),
      localWorkspaceService: const LocalWorkspaceService(),
      preferencesRepository: preferences,
      weatherService: _SettingsWeatherService(),
    );
    addTearDown(lifeController.dispose);
    final backupController = LocalBackupController(
      backupService: _UnusedBackupService(),
      migrationPreferences: _UnusedMigrationPreferences(),
      flushLocalWrites: () async {},
      restoreRuntime: (_) async => throw StateError('unused'),
    );
    addTearDown(backupController.dispose);

    await tester.pumpWidget(
      ResearchLifeScope(
        controller: lifeController,
        child: MaterialApp(
          theme: AppTheme.build(AppColorTheme.green),
          home: LocalServicesScope(
            backupController: backupController,
            aiServices: AiRuntimeServices(
              profiles: AiProfileRepository(preferences),
              credentials: _UnusedCredentialStore(),
              chats: AgentChatRepository(
                database,
                operationCoordinator: LocalDataOperationCoordinator(),
              ),
              client: OpenAiCompatibleChatClient(),
            ),
            restoreAndRestart: (_) async => throw StateError('unused'),
            child: const Scaffold(
              body: SizedBox(width: 1200, height: 900, child: SettingsPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('weather-api-key')), findsOneWidget);
    expect(find.byKey(const Key('weather-api-host')), findsOneWidget);
    expect(find.byKey(const Key('agent-api-key')), findsNothing);
    await tester.enterText(find.byKey(const Key('weather-api-key')), 'new-key');
    await tester.enterText(
      find.byKey(const Key('weather-api-host')),
      'new.example.com',
    );
    await tester.ensureVisible(find.byKey(const Key('weather-settings-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weather-settings-save')));
    await tester.pumpAndSettle();

    expect(await preferences.loadWeatherApiKey(), 'new-key');
    expect(await preferences.loadWeatherApiHost(), 'new.example.com');
  });
}

class _SettingsWeatherService extends WeatherService {
  @override
  Future<WeatherLocation> detectLocalLocation() async =>
      throw StateError('unused');

  @override
  Future<WeatherSnapshot> fetchCurrentWeather(WeatherLocation location) async =>
      throw StateError('unused');
}

class _UnusedCredentialStore extends Fake implements AiCredentialStore {}

class _UnusedMigrationPreferences implements LocalMigrationPreferences {
  @override
  Future<void> invalidateLocalMigrationBackupRecord() async {}
  @override
  Future<bool> loadLocalMigrationBackupComplete() async => false;
  @override
  Future<String?> loadLocalMigrationBackupPath() async => null;
  @override
  Future<void> saveLocalMigrationBackupRecord(String path) async {}
}

class _UnusedBackupService extends Fake implements BackupService {
  @override
  Future<List<BackupCreateResult>> listBackups() async => const [];
}
