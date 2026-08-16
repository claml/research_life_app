import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/research_life_scope.dart';
import 'package:research_life/app/workbench_destination.dart';
import 'package:research_life/app/workbench_navigation_controller.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/core/theme/app_tokens.dart';
import 'package:research_life/features/workbench/materials_workspace.dart';
import 'package:research_life/features/workbench/research_workspace.dart';
import 'package:research_life/features/workbench/life_workspace.dart';
import 'package:research_life/features/workbench/today_workspace.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  testWidgets('Research header contains only workspace navigation', (
    tester,
  ) async {
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
    expect(find.text('AI 助手'), findsNothing);
    expect(find.byKey(const Key('workspace-navigation-bar')), findsOneWidget);

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

  testWidgets('Materials keeps file state while visiting PDF tools', (
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

    await tester.tap(find.text('PDF 工具'));
    await tester.pump();
    await tester.tap(find.text('文件'));
    await tester.pump();

    expect(find.text('已选择 1'), findsOneWidget);
    navigation.dispose();
  });

  testWidgets(
    'Materials renders a requested document without exposing it as a tab',
    (tester) async {
      final controller = _createController();
      final navigation = WorkbenchNavigationController(
        initialWorkspace: WorkbenchWorkspace.materials,
      );
      final pages = _pagesFor(WorkbenchWorkspace.materials)
        ..[WorkbenchTab.materialsDocumentView] = const Center(
          child: Text('请求的文档内容'),
        );

      await tester.pumpWidget(
        _testApp(
          controller,
          MaterialsWorkspace(navigation: navigation, pages: pages),
        ),
      );
      navigation.navigateToTab(WorkbenchTab.materialsDocumentView);
      await tester.pump();

      expect(find.text('请求的文档内容'), findsOneWidget);
      expect(find.text('文件'), findsOneWidget);
      expect(find.text('PDF 工具'), findsOneWidget);
      expect(find.text('文档查看'), findsNothing);
      navigation.dispose();
    },
  );

  testWidgets('Today quick capture is a single primary action', (tester) async {
    final controller = _createController();
    final navigation = WorkbenchNavigationController();
    var requests = 0;
    await tester.pumpWidget(
      _testApp(
        controller,
        TodayWorkspace(
          navigation: navigation,
          onQuickCapture: () => requests += 1,
        ),
      ),
    );

    expect(find.text('快速记录'), findsOneWidget);
    expect(find.byKey(const Key('page-header')), findsNothing);
    expect(find.byKey(const Key('workspace-navigation-bar')), findsNothing);
    await tester.tap(find.text('快速记录'));
    expect(requests, 1);
    navigation.dispose();
  });

  testWidgets('Life owns Campus, weekly analysis, and Persons tabs', (
    tester,
  ) async {
    final controller = _createController();
    final navigation = WorkbenchNavigationController(
      initialWorkspace: WorkbenchWorkspace.life,
    );
    await tester.pumpWidget(
      _testApp(
        controller,
        LifeWorkspace(
          navigation: navigation,
          pages: const {
            WorkbenchTab.lifeCampus: Center(child: Text('校园内容')),
            WorkbenchTab.lifeAnalysis: Center(child: Text('周分析内容')),
            WorkbenchTab.lifePersons: Center(child: Text('人物内容')),
          },
        ),
      ),
    );

    expect(find.text('生活'), findsNothing);
    expect(find.text('校园地点与常用信息。'), findsNothing);
    expect(find.byKey(const Key('workspace-navigation-bar')), findsOneWidget);
    expect(find.text('校园内容'), findsOneWidget);
    expect(find.text('周分析'), findsOneWidget);
    expect(find.text('人物'), findsOneWidget);
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
