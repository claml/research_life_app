import 'package:flutter/material.dart';

import '../../app/workbench_destination.dart';
import '../../app/workbench_navigation_controller.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../../shared/widgets/workspace_tabs.dart';

class WorkbenchWorkspaceFrame extends StatelessWidget {
  const WorkbenchWorkspaceFrame({
    required this.workspace,
    required this.navigation,
    required this.title,
    required this.pages,
    this.description,
    this.primaryAction,
    super.key,
  });

  final WorkbenchWorkspace workspace;
  final WorkbenchNavigationController navigation;
  final String title;
  final String? description;
  final Map<WorkbenchTab, Widget> pages;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: navigation,
      builder: (context, _) {
        final tabs = workspace.tabs;
        final selected = navigation.selectedTabs[workspace]!;
        final selectedIndex = tabs.indexOf(selected);
        return PageScaffold(
          title: title,
          description: description,
          primaryAction: primaryAction,
          tabs: WorkspaceTabs<WorkbenchTab>(
            items: [
              for (final tab in tabs)
                WorkspaceTabItem(value: tab, label: tab.label),
            ],
            selected: selected,
            onSelected: navigation.selectTab,
          ),
          contentPadding: EdgeInsets.zero,
          body: IndexedStack(
            index: selectedIndex < 0 ? 0 : selectedIndex,
            children: [
              for (final tab in tabs)
                KeyedSubtree(
                  key: ValueKey('workspace-page-${tab.name}'),
                  child: pages[tab] ?? const SizedBox.shrink(),
                ),
            ],
          ),
        );
      },
    );
  }
}
