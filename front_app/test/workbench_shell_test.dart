import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/workbench_destination.dart';
import 'package:research_life/app/workbench_navigation_controller.dart';
import 'package:research_life/app/workbench_shell.dart';
import 'package:research_life/core/theme/app_theme.dart';

void main() {
  testWidgets('shows the approved primary navigation order', (tester) async {
    await _setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(_testShell());

    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((widget) => widget.properties.label)
        .whereType<String>()
        .where(
          (label) => const {'天气', '今天', '科研', '资料', '生活', '设置'}.contains(label),
        )
        .toList();
    expect(labels, containsAllInOrder(['天气', '今天', '科研', '资料', '生活', '设置']));
  });

  testWidgets('Escape exits only Weather and restores its entry focus', (
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

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('research:researchNotes'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('weather-entry'),
    );
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

    await tester.tap(find.text('收起导航'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('workbench-sidebar'))).width,
      72,
    );
    await tester.tap(find.byTooltip('展开导航'));
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
    expect(indicator, findsOneWidget);
    expect(
      tester.getCenter(indicator).dx,
      lessThan(tester.getCenter(selectedIcon).dx),
    );
  });
}

Widget _testShell({WorkbenchNavigationController? navigation}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: WorkbenchShell(
      navigationController: navigation,
      workspaceBuilder: (context, controller, workspace) =>
          Center(child: Text('${workspace.name}:${controller.activeTab.name}')),
      weatherBuilder: (context, onExit) => Center(
        child: TextButton(
          key: const Key('weather-view'),
          onPressed: onExit,
          child: const Text('返回'),
        ),
      ),
    ),
  );
}

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
