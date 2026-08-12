import 'package:flutter/foundation.dart';

import 'workbench_destination.dart';

class WeatherReturnSnapshot {
  WeatherReturnSnapshot({
    required this.workspace,
    required Map<WorkbenchWorkspace, WorkbenchTab> tabs,
  }) : tabs = Map.unmodifiable(tabs);

  final WorkbenchWorkspace workspace;
  final Map<WorkbenchWorkspace, WorkbenchTab> tabs;
}

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
  WeatherReturnSnapshot? _weatherSnapshot;

  WorkbenchWorkspace get workspace => _workspace;
  WorkbenchTab get activeTab => _tabs[_workspace]!;
  bool get weatherOpen => _weatherSnapshot != null;
  WeatherReturnSnapshot? get weatherSnapshot => _weatherSnapshot;
  Map<WorkbenchWorkspace, WorkbenchTab> get selectedTabs =>
      Map.unmodifiable(_tabs);

  void selectWorkspace(WorkbenchWorkspace workspace) {
    if (weatherOpen || workspace == _workspace) {
      return;
    }
    _workspace = workspace;
    notifyListeners();
  }

  void selectTab(WorkbenchTab tab) {
    if (weatherOpen || tab.workspace != _workspace || tab == activeTab) {
      return;
    }
    _tabs = {..._tabs, _workspace: tab};
    notifyListeners();
  }

  void navigateToTab(WorkbenchTab tab) {
    final nextTabs = {..._tabs, tab.workspace: tab};
    final changed =
        _weatherSnapshot != null ||
        _workspace != tab.workspace ||
        _tabs[tab.workspace] != tab;
    if (!changed) {
      return;
    }
    _weatherSnapshot = null;
    _workspace = tab.workspace;
    _tabs = nextTabs;
    notifyListeners();
  }

  void openWeather() {
    if (weatherOpen) {
      return;
    }
    _weatherSnapshot = WeatherReturnSnapshot(
      workspace: _workspace,
      tabs: _tabs,
    );
    notifyListeners();
  }

  void exitWeather() {
    final snapshot = _weatherSnapshot;
    if (snapshot == null) {
      return;
    }
    _workspace = snapshot.workspace;
    _tabs = Map.of(snapshot.tabs);
    _weatherSnapshot = null;
    notifyListeners();
  }
}
