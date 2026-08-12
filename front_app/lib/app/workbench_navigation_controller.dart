import 'package:flutter/foundation.dart';

import 'workbench_destination.dart';

class WorkbenchNavigationController extends ChangeNotifier {
  WorkbenchNavigationController({
    WorkbenchWorkspace initialWorkspace = WorkbenchWorkspace.today,
  }) : _workspace = initialWorkspace,
       _tabs = {
         for (final workspace in WorkbenchWorkspace.values)
           workspace: workspace.defaultTab,
       };

  WorkbenchWorkspace _workspace;
  Map<WorkbenchWorkspace, WorkbenchTab> _tabs;
  bool _weatherOpen = false;

  WorkbenchWorkspace get workspace => _workspace;
  WorkbenchTab get activeTab => _tabs[_workspace]!;
  bool get weatherOpen => _weatherOpen;
  Map<WorkbenchWorkspace, WorkbenchTab> get selectedTabs =>
      Map.unmodifiable(_tabs);

  void selectWorkspace(WorkbenchWorkspace workspace) {
    if (!weatherOpen && workspace == _workspace) {
      return;
    }
    _weatherOpen = false;
    _workspace = workspace;
    notifyListeners();
  }

  void selectTab(WorkbenchTab tab) {
    if (tab.workspace != _workspace || (!weatherOpen && tab == activeTab)) {
      return;
    }
    _weatherOpen = false;
    _tabs = {..._tabs, _workspace: tab};
    notifyListeners();
  }

  void navigateToTab(WorkbenchTab tab) {
    final nextTabs = {..._tabs, tab.workspace: tab};
    final changed =
        _weatherOpen ||
        _workspace != tab.workspace ||
        _tabs[tab.workspace] != tab;
    if (!changed) {
      return;
    }
    _weatherOpen = false;
    _workspace = tab.workspace;
    _tabs = nextTabs;
    notifyListeners();
  }

  void openWeather() {
    if (weatherOpen) {
      return;
    }
    _weatherOpen = true;
    notifyListeners();
  }
}
