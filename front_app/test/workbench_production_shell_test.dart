import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/research_life_scope.dart';
import 'package:research_life/app/workbench_destination.dart';
import 'package:research_life/app/workbench_navigation_controller.dart';
import 'package:research_life/app/workbench_shell.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/features/workbench/materials_workspace.dart';
import 'package:research_life/features/workbench/today_workspace.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  testWidgets('production shell maps PDF requests into Materials tabs', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    final controller = _createController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ResearchLifeScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const WorkbenchShell(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(TodayWorkspace), findsOneWidget);
    expect(find.byKey(const Key('today-open-workspace')), findsOneWidget);
    expect(find.byKey(const Key('today-timeline')), findsOneWidget);
    expect(find.byKey(const Key('today-todo-list')), findsOneWidget);

    controller.requestOpenPdfTools();
    await tester.pump();

    expect(find.byType(MaterialsWorkspace), findsOneWidget);
    final pdfTab = tester.widget<Semantics>(find.bySemanticsLabel('PDF 工具'));
    expect(pdfTab.properties.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real Research overview lays out inside the production shell', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    final controller = _createController();
    final navigation = WorkbenchNavigationController(
      initialWorkspace: WorkbenchWorkspace.research,
    );
    addTearDown(controller.dispose);
    addTearDown(navigation.dispose);

    await tester.pumpWidget(
      ResearchLifeScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: WorkbenchShell(navigationController: navigation),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('最近文献'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

ResearchLifeController _createController() {
  return ResearchLifeController(
    importService: const ImportService(),
    analysisService: const AnalysisService(),
    reviewService: const ReviewService(),
    institutionCalendarService: const InstitutionCalendarService(),
    localWorkspaceService: const LocalWorkspaceService(),
  );
}
