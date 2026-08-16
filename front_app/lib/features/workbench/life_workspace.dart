import 'package:flutter/material.dart';

import '../../app/workbench_destination.dart';
import '../../app/workbench_navigation_controller.dart';
import '../analysis/analysis_page.dart';
import '../campus_map/campus_map_page.dart';
import '../persons/persons_page.dart';
import 'workbench_workspace_frame.dart';

class LifeWorkspace extends StatelessWidget {
  const LifeWorkspace({required this.navigation, this.pages, super.key});

  final WorkbenchNavigationController navigation;
  final Map<WorkbenchTab, Widget>? pages;

  @override
  Widget build(BuildContext context) {
    return WorkbenchWorkspaceFrame(
      key: const Key('life-workspace'),
      workspace: WorkbenchWorkspace.life,
      navigation: navigation,
      pages:
          pages ??
          const {
            WorkbenchTab.lifeCampus: CampusMapPage(),
            WorkbenchTab.lifeAnalysis: AnalysisPage(),
            WorkbenchTab.lifePersons: PersonsPage(),
          },
    );
  }
}
