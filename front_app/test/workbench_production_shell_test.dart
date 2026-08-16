import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/research_life_scope.dart';
import 'package:research_life/app/workbench_destination.dart';
import 'package:research_life/app/workbench_navigation_controller.dart';
import 'package:research_life/app/workbench_shell.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/features/workbench/materials_workspace.dart';
import 'package:research_life/features/workbench/today_workspace.dart';
import 'package:research_life/features/document_view/document_viewer_page.dart';
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
    expect(find.byKey(const Key('workspace-navigation-bar')), findsNothing);

    controller.requestOpenPdfTools();
    await tester.pump();

    expect(find.byType(MaterialsWorkspace), findsOneWidget);
    final pdfTab = tester.widget<Semantics>(find.bySemanticsLabel('PDF 工具'));
    expect(pdfTab.properties.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today groups and controls real pending and completed todos', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    final controller = _createController();
    addTearDown(controller.dispose);
    controller.addManualEvent(
      date: DateTime.now(),
      title: '今日中优先级',
      category: ItemCategory.work,
      type: EventType.plan,
    );
    final todayId = controller.pendingTodoEvents.single.id;
    await controller.setTodoPriority(todayId, TodoPriority.medium);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    controller.addManualEvent(
      date: DateTime.now().add(const Duration(days: 1)),
      title: '未来高优先级',
      category: ItemCategory.study,
      type: EventType.plan,
    );
    final futureHighId = controller.pendingTodoEvents.last.id;
    await controller.setTodoPriority(futureHighId, TodoPriority.high);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    controller.addManualEvent(
      date: DateTime.now().add(const Duration(days: 1)),
      title: '未来低优先级',
      category: ItemCategory.life,
      type: EventType.plan,
    );
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

    expect(
      tester.getTopLeft(find.text('接下来')).dy,
      lessThan(tester.getTopLeft(find.text('未来高优先级')).dy),
    );
    expect(
      tester.getTopLeft(find.text('未来高优先级')).dy,
      lessThan(tester.getTopLeft(find.text('未来低优先级')).dy),
    );
    await tester.tap(find.byTooltip('设置优先级').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('优先级：高').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      controller.pendingTodoEvents
          .singleWhere((event) => event.id == todayId)
          .priority,
      TodoPriority.high,
    );

    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(find.text('未来低优先级'), findsNothing);
    expect(find.text('已完成 1'), findsOneWidget);
    await tester.tap(find.text('已完成 1'));
    await tester.pump();
    expect(find.text('未来低优先级'), findsOneWidget);
    expect(controller.completedTodoEvents.single.title, '未来低优先级');
    expect(tester.takeException(), isNull);
  });

  testWidgets('document request reaches the real Materials viewer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    final temporaryRoot = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('research_life_document_view_'),
    ))!;
    addTearDown(() async {
      if (await temporaryRoot.exists()) {
        await temporaryRoot.delete(recursive: true);
      }
    });
    final source = File(
      '${temporaryRoot.path}${Platform.pathSeparator}真实资料.ppt',
    );
    await tester.runAsync(() => source.writeAsString('legacy ppt fixture'));
    final controller = _createController(
      workspace: LocalWorkspaceService(
        storageDirectoryResolver: () async => temporaryRoot,
      ),
    );
    addTearDown(controller.dispose);
    final document = (await tester.runAsync(
      () => controller.addWorkspaceFileFromPath(source.path),
    ))!;

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

    controller.requestOpenDocumentView(documentId: document.id);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(find.byType(MaterialsWorkspace), findsOneWidget);
    expect(find.byType(DocumentViewerPage), findsOneWidget);
    expect(find.text('旧版 .ppt 请另存为 .pptx 后再查阅。'), findsOneWidget);
    expect(find.text('文档查看'), findsNothing);
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

ResearchLifeController _createController({LocalWorkspaceService? workspace}) {
  return ResearchLifeController(
    importService: const ImportService(),
    analysisService: const AnalysisService(),
    reviewService: const ReviewService(),
    institutionCalendarService: const InstitutionCalendarService(),
    localWorkspaceService: workspace ?? const LocalWorkspaceService(),
  );
}
