import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/workbench_destination.dart';
import 'package:research_life/app/workbench_navigation_controller.dart';
import 'package:research_life/app/workbench_shell.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/features/search/search_page.dart';

void main() {
  test(
    'SearchPage can be embedded without a calendar destination callback',
    () {
      const page = SearchPage(onNavigate: _ignoreNavigation);

      expect(page.onOpenCalendar, isNull);
    },
  );

  testWidgets('shows the approved primary navigation order', (tester) async {
    await _setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(_testShell());

    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((widget) => widget.properties.label)
        .whereType<String>()
        .where(
          (label) => const {
            '天气',
            'AI 助手',
            '日历',
            '今天',
            '科研',
            '资料',
            '生活',
            '设置',
          }.contains(label),
        )
        .toList();
    expect(
      labels,
      containsAllInOrder(['天气', 'AI 助手', '日历', '今天', '科研', '资料', '生活', '设置']),
    );
  });

  testWidgets('primary navigation leaves Weather without a return control', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1280, 800));
    final navigation = WorkbenchNavigationController();
    addTearDown(navigation.dispose);
    navigation.selectWorkspace(WorkbenchWorkspace.research);
    navigation.selectTab(WorkbenchTab.researchNotes);
    await tester.pumpWidget(_testShell(navigation: navigation));

    await tester.tap(find.bySemanticsLabel('天气'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weather-view')), findsOneWidget);

    expect(find.text('返回'), findsNothing);
    await tester.tap(find.bySemanticsLabel('科研'));
    await tester.pumpAndSettle();

    expect(find.text('research:researchNotes'), findsOneWidget);
  });

  testWidgets('collapses at desktop and forces compact navigation at 980px', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(_testShell());
    expect(
      tester.getSize(find.byKey(const Key('workbench-sidebar'))).width,
      216,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('sidebar-toggle'))).dy,
      lessThan(tester.getTopLeft(find.bySemanticsLabel('搜索')).dy),
    );
    expect(
      tester.getSize(find.byKey(const Key('sidebar-toggle'))),
      const Size(48, 48),
    );

    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('workbench-sidebar'))).width,
      72,
    );
    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('workbench-sidebar'))).width,
      216,
    );

    await _setSurface(tester, const Size(980, 800), resetAfter: false);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('workbench-sidebar'))).width,
      72,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected navigation indicator stays left of its icon', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(_testShell());

    final indicator = find.byKey(const Key('sidebar-selected-indicator'));
    final selectedIcon = find.byIcon(Icons.today_outlined);
    final selectedSurface = find.byKey(const Key('sidebar-selected-surface'));
    expect(indicator, findsOneWidget);
    expect(selectedSurface, findsOneWidget);
    expect(
      tester.getCenter(indicator).dx,
      lessThan(tester.getCenter(selectedIcon).dx),
    );
    expect(
      tester.getCenter(selectedIcon).dy,
      closeTo(tester.getCenter(selectedSurface).dy, 0.5),
    );
  });

  testWidgets('AI assistant opens in the workspace beside the sidebar', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(_testShell());

    final weather = find.bySemanticsLabel('天气');
    final ai = find.bySemanticsLabel('AI 助手');
    expect(ai, findsOneWidget);
    expect(
      tester.getTopLeft(ai).dy,
      greaterThan(tester.getTopLeft(weather).dy),
    );

    await tester.tap(ai);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-view')), findsOneWidget);
    expect(find.byKey(const Key('workbench-sidebar')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('资料'));
    await tester.pumpAndSettle();
    expect(find.text('materials:materialsFiles'), findsOneWidget);
  });

  testWidgets('Calendar opens below AI as a standalone destination', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(_testShell());

    final ai = find.bySemanticsLabel('AI 助手');
    final calendar = find.bySemanticsLabel('日历');
    expect(
      tester.getTopLeft(calendar).dy,
      greaterThan(tester.getTopLeft(ai).dy),
    );

    await tester.tap(calendar);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-view')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('生活'));
    await tester.pumpAndSettle();
    expect(find.text('life:lifeCampus'), findsOneWidget);
  });
}

Widget _testShell({WorkbenchNavigationController? navigation}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: WorkbenchShell(
      navigationController: navigation,
      workspaceBuilder: (context, controller, workspace) =>
          Center(child: Text('${workspace.name}:${controller.activeTab.name}')),
      weatherBuilder: (context) =>
          const Center(child: Text('天气', key: Key('weather-view'))),
      calendarBuilder: (context) =>
          const Center(child: Text('日历', key: Key('calendar-view'))),
      agentBuilder: (context) =>
          const Center(child: Text('AI 助手', key: Key('agent-view'))),
    ),
  );
}

void _ignoreNavigation(WorkbenchTab _) {}

Future<void> _setSurface(
  WidgetTester tester,
  Size size, {
  bool resetAfter = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  if (resetAfter) {
    addTearDown(tester.view.reset);
  }
}
