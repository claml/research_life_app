import 'package:flutter/material.dart';

enum WorkbenchWorkspace { today, research, materials, life, settings }

enum WorkbenchTab {
  todayOverview,
  todayCalendar,
  todayTodos,
  researchOverview,
  researchReading,
  researchNotes,
  researchAnalysis,
  researchPersons,
  researchStats,
  materialsFiles,
  materialsDocumentView,
  materialsPdfTools,
  lifeCampus,
  settingsOverview,
}

class WorkbenchDestination {
  const WorkbenchDestination({
    required this.workspace,
    required this.label,
    required this.icon,
  });

  final WorkbenchWorkspace workspace;
  final String label;
  final IconData icon;
}

class WeatherDestination {
  const WeatherDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

const weatherDestination = WeatherDestination(
  label: '天气',
  icon: Icons.cloud_outlined,
);

const workbenchDestinations = <WorkbenchDestination>[
  WorkbenchDestination(
    workspace: WorkbenchWorkspace.today,
    label: '今天',
    icon: Icons.today_outlined,
  ),
  WorkbenchDestination(
    workspace: WorkbenchWorkspace.research,
    label: '科研',
    icon: Icons.science_outlined,
  ),
  WorkbenchDestination(
    workspace: WorkbenchWorkspace.materials,
    label: '资料',
    icon: Icons.folder_outlined,
  ),
  WorkbenchDestination(
    workspace: WorkbenchWorkspace.life,
    label: '生活',
    icon: Icons.spa_outlined,
  ),
  WorkbenchDestination(
    workspace: WorkbenchWorkspace.settings,
    label: '设置',
    icon: Icons.settings_outlined,
  ),
];

extension WorkbenchWorkspaceMetadata on WorkbenchWorkspace {
  List<WorkbenchTab> get tabs => switch (this) {
    WorkbenchWorkspace.today => const [
      WorkbenchTab.todayOverview,
      WorkbenchTab.todayCalendar,
      WorkbenchTab.todayTodos,
    ],
    WorkbenchWorkspace.research => const [
      WorkbenchTab.researchOverview,
      WorkbenchTab.researchReading,
      WorkbenchTab.researchNotes,
      WorkbenchTab.researchAnalysis,
      WorkbenchTab.researchPersons,
      WorkbenchTab.researchStats,
    ],
    WorkbenchWorkspace.materials => const [
      WorkbenchTab.materialsFiles,
      WorkbenchTab.materialsDocumentView,
      WorkbenchTab.materialsPdfTools,
    ],
    WorkbenchWorkspace.life => const [WorkbenchTab.lifeCampus],
    WorkbenchWorkspace.settings => const [WorkbenchTab.settingsOverview],
  };

  WorkbenchTab get defaultTab => tabs.first;
}

extension WorkbenchTabMetadata on WorkbenchTab {
  WorkbenchWorkspace get workspace => switch (this) {
    WorkbenchTab.todayOverview ||
    WorkbenchTab.todayCalendar ||
    WorkbenchTab.todayTodos => WorkbenchWorkspace.today,
    WorkbenchTab.researchOverview ||
    WorkbenchTab.researchReading ||
    WorkbenchTab.researchNotes ||
    WorkbenchTab.researchAnalysis ||
    WorkbenchTab.researchPersons ||
    WorkbenchTab.researchStats => WorkbenchWorkspace.research,
    WorkbenchTab.materialsFiles ||
    WorkbenchTab.materialsDocumentView ||
    WorkbenchTab.materialsPdfTools => WorkbenchWorkspace.materials,
    WorkbenchTab.lifeCampus => WorkbenchWorkspace.life,
    WorkbenchTab.settingsOverview => WorkbenchWorkspace.settings,
  };

  String get label => switch (this) {
    WorkbenchTab.todayOverview => '今天',
    WorkbenchTab.todayCalendar => '日历',
    WorkbenchTab.todayTodos => '待办',
    WorkbenchTab.researchOverview => '概览',
    WorkbenchTab.researchReading => '文献',
    WorkbenchTab.researchNotes => '笔记',
    WorkbenchTab.researchAnalysis => '周分析',
    WorkbenchTab.researchPersons => '人物',
    WorkbenchTab.researchStats => '统计',
    WorkbenchTab.materialsFiles => '文件',
    WorkbenchTab.materialsDocumentView => '文档查看',
    WorkbenchTab.materialsPdfTools => 'PDF 工具',
    WorkbenchTab.lifeCampus => '校园',
    WorkbenchTab.settingsOverview => '设置',
  };
}
