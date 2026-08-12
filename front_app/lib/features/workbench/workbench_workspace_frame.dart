import 'package:flutter/material.dart';

import '../../app/workbench_destination.dart';
import '../../app/workbench_navigation_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/workspace_tabs.dart';

class WorkbenchWorkspaceFrame extends StatelessWidget {
  const WorkbenchWorkspaceFrame({
    required this.workspace,
    required this.navigation,
    required this.pages,
    this.primaryAction,
    super.key,
  });

  final WorkbenchWorkspace workspace;
  final WorkbenchNavigationController navigation;
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
        final content = IndexedStack(
          index: selectedIndex < 0 ? 0 : selectedIndex,
          children: [
            for (final tab in tabs)
              KeyedSubtree(
                key: ValueKey('workspace-page-${tab.name}'),
                child: pages[tab] ?? const SizedBox.shrink(),
              ),
          ],
        );
        if (tabs.length == 1 && primaryAction == null) {
          return content;
        }
        final tokens = context.tokens;
        return ColoredBox(
          color: tokens.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                key: const Key('workspace-navigation-bar'),
                decoration: BoxDecoration(
                  color: tokens.shellSurface,
                  border: Border(bottom: BorderSide(color: tokens.borderFaint)),
                ),
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppLayout.pageHorizontalPadding,
                    ),
                    child: Row(
                      children: [
                        if (tabs.length > 1)
                          Expanded(
                            child: WorkspaceTabs<WorkbenchTab>(
                              items: [
                                for (final tab in tabs)
                                  WorkspaceTabItem(
                                    value: tab,
                                    label: tab.label,
                                  ),
                              ],
                              selected: selected,
                              onSelected: navigation.selectTab,
                            ),
                          )
                        else
                          const Spacer(),
                        if (primaryAction != null) ...[
                          const SizedBox(width: 16),
                          primaryAction!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}
