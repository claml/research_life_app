import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  test('idle PIN lock defaults to three hours and persists changes', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final preferences = PreferencesRepository(database);

    ResearchLifeController createController() {
      final controller = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: const LocalWorkspaceService(),
        preferencesRepository: preferences,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    final first = createController();
    expect(first.idleLockTimeout, const Duration(hours: 3));

    await first.setIdleLockTimeout(const Duration(hours: 6));
    expect(first.idleLockTimeout, const Duration(hours: 6));
    expect(await preferences.loadIdleLockTimeoutMinutes(), 360);

    final restored = createController();
    await restored.ensurePinLockLoaded();
    expect(restored.idleLockTimeout, const Duration(hours: 6));
  });
}
