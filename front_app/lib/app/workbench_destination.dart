import 'package:flutter/material.dart';

enum WorkbenchWorkspace { today, research, materials, life, settings }

enum WorkbenchTab {
  todayOverview,
  researchOverview,
  researchReading,
  researchNotes,
  researchStats,
  materialsFiles,
  materialsDocumentView,
  materialsPdfTools,
  lifeCampus,
  lifeAnalysis,
  lifePersons,
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
    WorkbenchWorkspace.today => const [WorkbenchTab.todayOverview],
    WorkbenchWorkspace.research => const [
      WorkbenchTab.researchOverview,
      WorkbenchTab.researchReading,
      WorkbenchTab.researchNotes,
      WorkbenchTab.researchStats,
    ],
    WorkbenchWorkspace.materials => const [
      WorkbenchTab.materialsFiles,
      WorkbenchTab.materialsPdfTools,
    ],
    WorkbenchWorkspace.life => const [
      WorkbenchTab.lifeCampus,
      WorkbenchTab.lifeAnalysis,
      WorkbenchTab.lifePersons,
    ],
    WorkbenchWorkspace.settings => const [WorkbenchTab.settingsOverview],
  };

  WorkbenchTab get defaultTab => tabs.first;
}

extension WorkbenchTabMetadata on WorkbenchTab {
  WorkbenchWorkspace get workspace => switch (this) {
    WorkbenchTab.todayOverview => WorkbenchWorkspace.today,
    WorkbenchTab.researchOverview ||
    WorkbenchTab.researchReading ||
    WorkbenchTab.researchNotes ||
    WorkbenchTab.researchStats => WorkbenchWorkspace.research,
    WorkbenchTab.materialsFiles ||
    WorkbenchTab.materialsDocumentView ||
    WorkbenchTab.materialsPdfTools => WorkbenchWorkspace.materials,
    WorkbenchTab.lifeCampus ||
    WorkbenchTab.lifeAnalysis ||
    WorkbenchTab.lifePersons => WorkbenchWorkspace.life,
    WorkbenchTab.settingsOverview => WorkbenchWorkspace.settings,
  };

  String get label => switch (this) {
    WorkbenchTab.todayOverview => '今天',
    WorkbenchTab.researchOverview => '概览',
    WorkbenchTab.researchReading => '文献',
    WorkbenchTab.researchNotes => '笔记',
    WorkbenchTab.researchStats => '统计',
    WorkbenchTab.materialsFiles => '资料库',
    WorkbenchTab.materialsDocumentView => '文档查看',
    WorkbenchTab.materialsPdfTools => 'PDF 工具',
    WorkbenchTab.lifeCampus => '校园',
    WorkbenchTab.lifeAnalysis => '周分析',
    WorkbenchTab.lifePersons => '人物',
    WorkbenchTab.settingsOverview => '设置',
  };
}
