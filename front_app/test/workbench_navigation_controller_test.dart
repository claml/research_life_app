import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/workbench_destination.dart';
import 'package:research_life/app/workbench_navigation_controller.dart';

void main() {
  test(
    'Weather behaves like a normal destination and never traps navigation',
    () {
      final navigation = WorkbenchNavigationController();
      expect(navigation.weatherOpen, isFalse);
      navigation.selectWorkspace(WorkbenchWorkspace.research);
      navigation.selectTab(WorkbenchTab.researchNotes);

      navigation.openWeather();
      expect(navigation.weatherOpen, isTrue);
      navigation.selectWorkspace(WorkbenchWorkspace.life);

      expect(navigation.weatherOpen, isFalse);
      expect(navigation.workspace, WorkbenchWorkspace.life);
      expect(navigation.activeTab, WorkbenchTab.lifeCampus);

      navigation.selectWorkspace(WorkbenchWorkspace.research);
      expect(navigation.activeTab, WorkbenchTab.researchNotes);
    },
  );

  test('tabs are remembered independently for every workspace', () {
    final navigation = WorkbenchNavigationController();
    navigation.selectTab(WorkbenchTab.todayTodos);
    navigation.selectWorkspace(WorkbenchWorkspace.materials);
    navigation.selectTab(WorkbenchTab.materialsPdfTools);
    navigation.selectWorkspace(WorkbenchWorkspace.today);

    expect(navigation.activeTab, WorkbenchTab.todayTodos);
    navigation.selectWorkspace(WorkbenchWorkspace.materials);
    expect(navigation.activeTab, WorkbenchTab.materialsPdfTools);
  });

  test('rejects a tab that does not belong to the current workspace', () {
    final navigation = WorkbenchNavigationController();
    var notifications = 0;
    navigation.addListener(() => notifications++);

    navigation.selectTab(WorkbenchTab.researchNotes);

    expect(navigation.workspace, WorkbenchWorkspace.today);
    expect(navigation.activeTab, WorkbenchTab.todayOverview);
    expect(notifications, 0);
  });

  test('exposes the approved primary order and concise labels', () {
    expect(workbenchDestinations.map((item) => item.label), [
      '今天',
      '科研',
      '资料',
      '生活',
      '设置',
    ]);
    expect(WorkbenchWorkspace.research.tabs.map((tab) => tab.label), [
      '概览',
      '文献',
      '笔记',
      '周分析',
      '人物',
      '统计',
    ]);
    expect(WorkbenchWorkspace.life.tabs, [WorkbenchTab.lifeCampus]);
  });

  test(
    'navigateToTab closes Weather and opens the requested workspace tab',
    () {
      final navigation = WorkbenchNavigationController();
      addTearDown(navigation.dispose);
      navigation.openWeather();

      navigation.navigateToTab(WorkbenchTab.materialsPdfTools);

      expect(navigation.weatherOpen, isFalse);
      expect(navigation.workspace, WorkbenchWorkspace.materials);
      expect(navigation.activeTab, WorkbenchTab.materialsPdfTools);
    },
  );
}
