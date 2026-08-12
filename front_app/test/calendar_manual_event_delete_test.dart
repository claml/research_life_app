import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/research_life_scope.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/features/calendar/calendar_page.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('confirms before deleting an editable manual event', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final root = (await tester.runAsync(
      () =>
          Directory.systemTemp.createTemp('calendar_manual_event_delete_test'),
    ))!;
    addTearDown(() => root.delete(recursive: true));
    final controller = ResearchLifeController(
      importService: const ImportService(),
      analysisService: const AnalysisService(),
      reviewService: const ReviewService(),
      institutionCalendarService: const InstitutionCalendarService(),
      localWorkspaceService: LocalWorkspaceService(
        storageDirectoryResolver: () async => root,
      ),
    );
    addTearDown(controller.dispose);
    final today = DateTime.now();
    controller.addManualEvent(
      date: today,
      title: '删除这条日历记录',
      category: ItemCategory.work,
      type: EventType.plan,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ResearchLifeScope(
          controller: controller,
          child: const Scaffold(body: CalendarPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑记录'));
    await tester.pumpAndSettle();

    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除记录？'), findsOneWidget);
    expect(find.text('确定删除“删除这条日历记录”吗？'), findsOneWidget);
    expect(controller.manualEvents, hasLength(1));

    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(controller.manualEvents, isEmpty);
    expect(find.text('已删除记录。'), findsOneWidget);
  });
}
