import 'package:flutter/material.dart';

import '../../app/workbench_destination.dart';
import '../../app/workbench_navigation_controller.dart';
import '../settings/settings_page.dart';
import 'workbench_workspace_frame.dart';

class SettingsWorkspace extends StatelessWidget {
  const SettingsWorkspace({required this.navigation, super.key});

  final WorkbenchNavigationController navigation;

  @override
  Widget build(BuildContext context) {
    return WorkbenchWorkspaceFrame(
      key: const Key('settings-workspace'),
      workspace: WorkbenchWorkspace.settings,
      navigation: navigation,
      pages: const {WorkbenchTab.settingsOverview: SettingsPage()},
    );
  }
}
