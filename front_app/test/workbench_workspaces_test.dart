import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/research_life_scope.dart';
import 'package:research_life/app/workbench_destination.dart';
import 'package:research_life/app/workbench_navigation_controller.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/core/theme/app_tokens.dart';
import 'package:research_life/features/workbench/materials_workspace.dart';
import 'package:research_life/features/workbench/research_workspace.dart';
import 'package:research_life/features/workbench/today_workspace.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  testWidgets('AI action exists only in Research', (tester) async {
    final controller = _createController();
    final researchNavigation = WorkbenchNavigationController(
      initialWorkspace: WorkbenchWorkspace.research,
    );
    await tester.pumpWidget(
      _testApp(
        controller,
        ResearchWorkspace(
          navigation: researchNavigation,
          pages: _pagesFor(WorkbenchWorkspace.research),
        ),
      ),
    );
    expect(find.text('AI 助手'), findsOneWidget);

    final materialsNavigation = WorkbenchNavigationController(
      initialWorkspace: WorkbenchWorkspace.materials,
    );
    await tester.pumpWidget(
      _testApp(
        controller,
        MaterialsWorkspace(
          navigation: materialsNavigation,
          pages: _pagesFor(WorkbenchWorkspace.materials),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('AI 助手'), findsNothing);

    researchNavigation.dispose();
    materialsNavigation.dispose();
  });

  testWidgets('Materials keeps file state while visiting another tab', (
    tester,
  ) async {
    final controller = _createController();
    final navigation = WorkbenchNavigationController(
      initialWorkspace: WorkbenchWorkspace.materials,
    );
    final pages = _pagesFor(WorkbenchWorkspace.materials);
    pages[WorkbenchTab.materialsFiles] = const _CounterPage();

    await tester.pumpWidget(
      _testApp(
        controller,
        MaterialsWorkspace(navigation: navigation, pages: pages),
      ),
    );
    await tester.tap(find.text('选中文件'));
    await tester.pump();
    expect(find.text('已选择 1'), findsOneWidget);

    await tester.tap(find.text('文档查看'));
    await tester.pump();
    await tester.tap(find.text('文件'));
    await tester.pump();

    expect(find.text('已选择 1'), findsOneWidget);
    navigation.dispose();
  });

  testWidgets('Today quick capture is a single primary action', (tester) async {
    final controller = _createController();
    final navigation = WorkbenchNavigationController();
    var requests = 0;
    await tester.pumpWidget(
      _testApp(
        controller,
        TodayWorkspace(
          navigation: navigation,
          pages: _pagesFor(WorkbenchWorkspace.today),
          onQuickCapture: () => requests += 1,
        ),
      ),
    );

    expect(find.text('快速记录'), findsOneWidget);
    await tester.tap(find.text('快速记录'));
    expect(requests, 1);
    navigation.dispose();
  });
}

Map<WorkbenchTab, Widget> _pagesFor(WorkbenchWorkspace workspace) => {
  for (final tab in workspace.tabs)
    tab: ColoredBox(
      key: ValueKey('page-${tab.name}'),
      color: Colors.transparent,
      child: Center(child: Text('page-${tab.name}')),
    ),
};

Widget _testApp(ResearchLifeController controller, Widget child) {
  return ResearchLifeScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.build(AppColorTheme.green),
      home: Scaffold(body: SizedBox(width: 1100, height: 760, child: child)),
    ),
  );
}

ResearchLifeController _createController() {
  final controller = ResearchLifeController(
    importService: const ImportService(),
    analysisService: const AnalysisService(),
    reviewService: const ReviewService(),
    institutionCalendarService: const InstitutionCalendarService(),
    localWorkspaceService: const LocalWorkspaceService(),
  );
  addTearDown(controller.dispose);
  return controller;
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(
        onPressed: () => setState(() => count += 1),
        child: Text(count == 0 ? '选中文件' : '已选择 $count'),
      ),
    );
  }
}
