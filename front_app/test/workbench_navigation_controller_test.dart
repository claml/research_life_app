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
    navigation.selectWorkspace(WorkbenchWorkspace.life);
    navigation.selectTab(WorkbenchTab.lifePersons);
    navigation.selectWorkspace(WorkbenchWorkspace.materials);
    navigation.selectTab(WorkbenchTab.materialsPdfTools);
    navigation.selectWorkspace(WorkbenchWorkspace.life);

    expect(navigation.activeTab, WorkbenchTab.lifePersons);
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
      '统计',
    ]);
    expect(WorkbenchWorkspace.today.tabs, [WorkbenchTab.todayOverview]);
    expect(WorkbenchWorkspace.materials.tabs, [
      WorkbenchTab.materialsFiles,
      WorkbenchTab.materialsPdfTools,
    ]);
    expect(WorkbenchWorkspace.life.tabs.map((tab) => tab.label), [
      '校园',
      '周分析',
      '人物',
    ]);
  });

  test('Calendar is a normal standalone destination', () {
    final navigation = WorkbenchNavigationController();
    navigation.openCalendar();

    expect(navigation.calendarOpen, isTrue);
    expect(navigation.weatherOpen, isFalse);

    navigation.selectWorkspace(WorkbenchWorkspace.research);
    expect(navigation.calendarOpen, isFalse);
    expect(navigation.workspace, WorkbenchWorkspace.research);
  });

  test('AI assistant is a normal standalone destination', () {
    final navigation = WorkbenchNavigationController();
    navigation.openAi();

    expect(navigation.aiOpen, isTrue);
    expect(navigation.weatherOpen, isFalse);
    expect(navigation.calendarOpen, isFalse);

    navigation.selectWorkspace(WorkbenchWorkspace.materials);
    expect(navigation.aiOpen, isFalse);
    expect(navigation.workspace, WorkbenchWorkspace.materials);
  });

  test(
    'standalone destinations are mutually exclusive and tabs close them',
    () {
      final navigation = WorkbenchNavigationController();
      addTearDown(navigation.dispose);

      navigation.openWeather();
      expect(navigation.weatherOpen, isTrue);

      navigation.openCalendar();
      expect(navigation.weatherOpen, isFalse);
      expect(navigation.calendarOpen, isTrue);

      navigation.openAi();
      expect(navigation.calendarOpen, isFalse);
      expect(navigation.aiOpen, isTrue);

      navigation.navigateToTab(WorkbenchTab.lifeAnalysis);
      expect(navigation.aiOpen, isFalse);
      expect(navigation.workspace, WorkbenchWorkspace.life);
      expect(navigation.activeTab, WorkbenchTab.lifeAnalysis);
    },
  );

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
