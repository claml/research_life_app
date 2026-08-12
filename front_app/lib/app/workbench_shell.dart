import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_tokens.dart';
import '../features/home/home_page.dart';
import '../features/pet_overlay/pet_overlay.dart';
import '../features/quick_capture/quick_capture_dialog.dart';
import '../features/reminder/reminder_overlay.dart';
import '../features/search/search_page.dart';
import '../features/todo_panel/today_todo_dialog.dart';
import '../features/workbench/life_workspace.dart';
import '../features/workbench/materials_workspace.dart';
import '../features/workbench/research_workspace.dart';
import '../features/workbench/settings_workspace.dart';
import '../features/workbench/today_workspace.dart';
import '../state/research_life_controller.dart';
import 'research_life_scope.dart';
import 'workbench_destination.dart';
import 'workbench_navigation_controller.dart';

typedef WorkbenchWorkspaceBuilder =
    Widget Function(
      BuildContext context,
      WorkbenchNavigationController navigation,
      WorkbenchWorkspace workspace,
    );
typedef WorkbenchWeatherBuilder = Widget Function(BuildContext context);

class WorkbenchShell extends StatefulWidget {
  const WorkbenchShell({
    this.workspaceBuilder,
    this.weatherBuilder,
    this.navigationController,
    this.onSearchRequested,
    super.key,
  });

  final WorkbenchNavigationController? navigationController;
  final WorkbenchWorkspaceBuilder? workspaceBuilder;
  final WorkbenchWeatherBuilder? weatherBuilder;
  final VoidCallback? onSearchRequested;

  @override
  State<WorkbenchShell> createState() => _WorkbenchShellState();
}

class _WorkbenchShellState extends State<WorkbenchShell> {
  static const _expandedSidebarWidth = 216.0;
  static const _collapsedSidebarWidth = 72.0;
  static const _compactBreakpoint = 1040.0;

  late WorkbenchNavigationController _navigation;
  late bool _ownsNavigation;
  final FocusNode _weatherEntryFocus = FocusNode(debugLabel: 'weather-entry');
  final Map<WorkbenchWorkspace, FocusNode> _workspaceFocus = {
    for (final workspace in WorkbenchWorkspace.values)
      workspace: FocusNode(debugLabel: 'workspace-${workspace.name}'),
  };
  ResearchLifeController? _controller;
  bool Function(KeyEvent)? _hardwareKeyHandler;
  bool _sidebarCollapsed = false;

  bool get _usesProductionContent =>
      widget.workspaceBuilder == null && widget.weatherBuilder == null;

  @override
  void initState() {
    super.initState();
    _attachNavigation(widget.navigationController);
    _hardwareKeyHandler = _handleHardwareKeyEvent;
    HardwareKeyboard.instance.addHandler(_hardwareKeyHandler!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_usesProductionContent) {
      return;
    }
    final controller = ResearchLifeScope.read(context);
    if (identical(controller, _controller)) {
      return;
    }
    _detachController();
    _controller = controller;
    controller.addListener(_handleCrossWorkspaceNavigation);
    controller.todayTodoDialogRequests.addListener(_handleTodayTodoRequested);
  }

  @override
  void didUpdateWidget(covariant WorkbenchShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.navigationController,
      widget.navigationController,
    )) {
      if (_ownsNavigation) {
        _navigation.dispose();
      }
      _attachNavigation(widget.navigationController);
    }
  }

  void _attachNavigation(WorkbenchNavigationController? controller) {
    _ownsNavigation = controller == null;
    _navigation = controller ?? WorkbenchNavigationController();
  }

  @override
  void dispose() {
    _detachController();
    final handler = _hardwareKeyHandler;
    if (handler != null) {
      HardwareKeyboard.instance.removeHandler(handler);
      _hardwareKeyHandler = null;
    }
    if (_ownsNavigation) {
      _navigation.dispose();
    }
    _weatherEntryFocus.dispose();
    for (final node in _workspaceFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _detachController() {
    _controller?.removeListener(_handleCrossWorkspaceNavigation);
    _controller?.todayTodoDialogRequests.removeListener(
      _handleTodayTodoRequested,
    );
    _controller = null;
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    _controller?.notifyUserActivity();
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed) {
      _openQuickCapture();
      return true;
    }
    return false;
  }

  void _handleCrossWorkspaceNavigation() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.hasPendingReadingOpen) {
      _navigation.navigateToTab(WorkbenchTab.researchReading);
      return;
    }
    if (controller.hasPendingDocumentViewOpen) {
      _navigation.navigateToTab(WorkbenchTab.materialsDocumentView);
      return;
    }
    if (controller.consumePdfToolsNavigationRequest()) {
      _navigation.navigateToTab(WorkbenchTab.materialsPdfTools);
      return;
    }
    if (controller.consumeAiSettingsNavigationRequest()) {
      _navigation.navigateToTab(WorkbenchTab.settingsOverview);
    }
  }

  void _handleTodayTodoRequested() {
    if (mounted) _openTodayTodo();
  }

  void _openWeather() {
    _weatherEntryFocus.requestFocus();
    _navigation.openWeather();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final workspaceBuilder =
        widget.workspaceBuilder ?? _buildProductionWorkspace;
    final weatherBuilder = widget.weatherBuilder ?? _buildProductionWeather;
    final shell = AnimatedBuilder(
      animation: _navigation,
      builder: (context, _) => Scaffold(
        backgroundColor: tokens.canvas,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tokens.backdropTop,
                tokens.backdropMiddle,
                tokens.backdropBottom,
              ],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final forcedCompact =
                    constraints.maxWidth <= _compactBreakpoint;
                final collapsed = forcedCompact || _sidebarCollapsed;
                final sidebarWidth = collapsed
                    ? _collapsedSidebarWidth
                    : _expandedSidebarWidth;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WorkbenchSidebar(
                        sidebarKey: const Key('workbench-sidebar'),
                        width: sidebarWidth,
                        forcedCompact: forcedCompact,
                        reduceMotion: reduceMotion,
                        navigation: _navigation,
                        weatherFocusNode: _weatherEntryFocus,
                        workspaceFocusNodes: _workspaceFocus,
                        onWeatherSelected: _openWeather,
                        onWorkspaceSelected: _navigation.selectWorkspace,
                        onSearchRequested:
                            widget.onSearchRequested ??
                            (_usesProductionContent ? _openSearch : () {}),
                        onToggle: () => setState(
                          () => _sidebarCollapsed = !_sidebarCollapsed,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: RepaintBoundary(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.shellSurface.withValues(
                                alpha: 0.97,
                              ),
                              borderRadius: BorderRadius.circular(
                                tokens.radiusXLarge,
                              ),
                              border: Border.all(color: tokens.shellBorder),
                              boxShadow: tokens.shadowMd,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                tokens.radiusXLarge,
                              ),
                              child: _WorkbenchContent(
                                navigation: _navigation,
                                workspaceBuilder: workspaceBuilder,
                                weatherBuilder: weatherBuilder,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    if (!_usesProductionContent) {
      return shell;
    }
    final controller = _controller ?? ResearchLifeScope.read(context);
    return Listener(
      onPointerDown: (_) => controller.notifyUserActivity(),
      onPointerHover: (_) => controller.notifyUserActivity(),
      onPointerMove: (_) => controller.notifyUserActivity(),
      child: Stack(
        children: [
          Positioned.fill(child: shell),
          const PetOverlay(),
          const ReminderOverlay(),
        ],
      ),
    );
  }

  Widget _buildProductionWorkspace(
    BuildContext context,
    WorkbenchNavigationController navigation,
    WorkbenchWorkspace workspace,
  ) {
    return switch (workspace) {
      WorkbenchWorkspace.today => TodayWorkspace(
        navigation: navigation,
        onQuickCapture: _openQuickCapture,
      ),
      WorkbenchWorkspace.research => ResearchWorkspace(navigation: navigation),
      WorkbenchWorkspace.materials => MaterialsWorkspace(
        navigation: navigation,
      ),
      WorkbenchWorkspace.life => LifeWorkspace(navigation: navigation),
      WorkbenchWorkspace.settings => SettingsWorkspace(navigation: navigation),
    };
  }

  Widget _buildProductionWeather(BuildContext context) => const HomePage();

  void _openQuickCapture() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => QuickCaptureDialog(controller: controller),
    );
  }

  void _openTodayTodo() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => TodayTodoDialog(
        controller: controller,
        onOpenTodos: () => _navigation.navigateToTab(WorkbenchTab.todayTodos),
      ),
    );
  }

  void _openSearch() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: IconButton(
                  tooltip: '关闭搜索',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
            Expanded(
              child: SearchPage(
                onNavigate: (tab) {
                  Navigator.of(dialogContext).pop();
                  _navigation.navigateToTab(tab);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchSidebar extends StatelessWidget {
  const _WorkbenchSidebar({
    required this.sidebarKey,
    required this.width,
    required this.forcedCompact,
    required this.reduceMotion,
    required this.navigation,
    required this.weatherFocusNode,
    required this.workspaceFocusNodes,
    required this.onWeatherSelected,
    required this.onWorkspaceSelected,
    required this.onSearchRequested,
    required this.onToggle,
  });

  final Key sidebarKey;
  final double width;
  final bool forcedCompact;
  final bool reduceMotion;
  final WorkbenchNavigationController navigation;
  final FocusNode weatherFocusNode;
  final Map<WorkbenchWorkspace, FocusNode> workspaceFocusNodes;
  final VoidCallback onWeatherSelected;
  final ValueChanged<WorkbenchWorkspace> onWorkspaceSelected;
  final VoidCallback onSearchRequested;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final regularDestinations = workbenchDestinations.where(
      (item) => item.workspace != WorkbenchWorkspace.settings,
    );
    final settings = workbenchDestinations.last;
    return AnimatedContainer(
      key: sidebarKey,
      duration: reduceMotion ? Duration.zero : AppLayout.quickMotion,
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tokens.sidebarSurface, tokens.sidebarSurfaceStrong],
        ),
        borderRadius: BorderRadius.circular(tokens.radiusXLarge),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: tokens.shadowSm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final visuallyCollapsed = constraints.maxWidth < 150;
          return ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusXLarge),
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  visuallyCollapsed ? 8 : 14,
                  16,
                  visuallyCollapsed ? 8 : 14,
                  14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SidebarBrand(
                      collapsed: visuallyCollapsed,
                      forcedCompact: forcedCompact,
                      onToggle: onToggle,
                    ),
                    const SizedBox(height: 14),
                    _SidebarUtilityButton(
                      collapsed: visuallyCollapsed,
                      label: '搜索',
                      icon: Icons.search_rounded,
                      onPressed: onSearchRequested,
                    ),
                    const SizedBox(height: 14),
                    _SidebarNavButton(
                      label: weatherDestination.label,
                      icon: weatherDestination.icon,
                      collapsed: visuallyCollapsed,
                      selected: navigation.weatherOpen,
                      focusNode: weatherFocusNode,
                      onPressed: onWeatherSelected,
                    ),
                    const SizedBox(height: 8),
                    Divider(color: Colors.white.withValues(alpha: 0.12)),
                    const SizedBox(height: 6),
                    for (final destination in regularDestinations) ...[
                      _SidebarNavButton(
                        label: destination.label,
                        icon: destination.icon,
                        collapsed: visuallyCollapsed,
                        selected:
                            !navigation.weatherOpen &&
                            navigation.workspace == destination.workspace,
                        focusNode: workspaceFocusNodes[destination.workspace]!,
                        onPressed: () =>
                            onWorkspaceSelected(destination.workspace),
                      ),
                      const SizedBox(height: 6),
                    ],
                    const Spacer(),
                    _SidebarNavButton(
                      label: settings.label,
                      icon: settings.icon,
                      collapsed: visuallyCollapsed,
                      selected:
                          !navigation.weatherOpen &&
                          navigation.workspace == settings.workspace,
                      focusNode: workspaceFocusNodes[settings.workspace]!,
                      onPressed: () => onWorkspaceSelected(settings.workspace),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({
    required this.collapsed,
    required this.forcedCompact,
    required this.onToggle,
  });

  final bool collapsed;
  final bool forcedCompact;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final brand = Text(
      collapsed ? '研' : '研LIFE',
      maxLines: 1,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
    );
    if (collapsed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!forcedCompact)
            _SidebarUtilityButton(
              key: const Key('sidebar-toggle'),
              collapsed: true,
              label: '展开导航',
              icon: Icons.keyboard_double_arrow_right_rounded,
              onPressed: onToggle,
            ),
          if (!forcedCompact) const SizedBox(height: 8),
          SizedBox(height: 34, child: Center(child: brand)),
        ],
      );
    }
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(child: brand),
          _SidebarUtilityButton(
            key: const Key('sidebar-toggle'),
            collapsed: true,
            label: '收起导航',
            icon: Icons.keyboard_double_arrow_left_rounded,
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }
}

class _SidebarUtilityButton extends StatelessWidget {
  const _SidebarUtilityButton({
    required this.collapsed,
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final bool collapsed;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          splashColor: Colors.white.withValues(alpha: 0.1),
          child: Container(
            height: 42,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.075),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(icon, size: 19, color: Colors.white),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return collapsed
        ? Tooltip(message: label, excludeFromSemantics: true, child: button)
        : button;
  }
}

class _SidebarNavButton extends StatelessWidget {
  const _SidebarNavButton({
    required this.label,
    required this.icon,
    required this.collapsed,
    required this.selected,
    required this.focusNode,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool collapsed;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final button = Focus(
      focusNode: focusNode,
      child: AnimatedBuilder(
        animation: focusNode,
        builder: (context, _) => Semantics(
          container: true,
          button: true,
          selected: selected,
          label: label,
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onPressed,
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
              hoverColor: Colors.white.withValues(alpha: 0.06),
              highlightColor: Colors.transparent,
              splashColor: Colors.white.withValues(alpha: 0.1),
              child: AnimatedContainer(
                key: selected ? const Key('sidebar-selected-surface') : null,
                duration: AppLayout.quickMotion,
                height: 48,
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 14),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(tokens.radiusSmall),
                  border: focusNode.hasFocus
                      ? Border.all(color: Colors.white.withValues(alpha: 0.86))
                      : null,
                ),
                child: Stack(
                  children: [
                    if (selected)
                      Positioned(
                        key: const Key('sidebar-selected-indicator'),
                        left: 0,
                        top: 12,
                        bottom: 12,
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: collapsed
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.start,
                        children: [
                          if (!collapsed) const SizedBox(width: 8),
                          Icon(icon, size: 20, color: Colors.white),
                          if (!collapsed) ...[
                            const SizedBox(width: 12),
                            Text(
                              label,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    height: 1,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return collapsed
        ? Tooltip(message: label, excludeFromSemantics: true, child: button)
        : button;
  }
}

class _WorkbenchContent extends StatefulWidget {
  const _WorkbenchContent({
    required this.navigation,
    required this.workspaceBuilder,
    required this.weatherBuilder,
  });

  final WorkbenchNavigationController navigation;
  final WorkbenchWorkspaceBuilder workspaceBuilder;
  final WorkbenchWeatherBuilder weatherBuilder;

  @override
  State<_WorkbenchContent> createState() => _WorkbenchContentState();
}

class _WorkbenchContentState extends State<_WorkbenchContent> {
  final Set<WorkbenchWorkspace> _visited = {WorkbenchWorkspace.today};
  bool _weatherVisited = false;

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.navigation.workspace);
    _weatherVisited = _weatherVisited || widget.navigation.weatherOpen;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final workspace in WorkbenchWorkspace.values)
          if (_visited.contains(workspace))
            Positioned.fill(
              key: ValueKey(workspace),
              child: TickerMode(
                enabled:
                    !widget.navigation.weatherOpen &&
                    widget.navigation.workspace == workspace,
                child: IgnorePointer(
                  ignoring:
                      widget.navigation.weatherOpen ||
                      widget.navigation.workspace != workspace,
                  child: Offstage(
                    offstage:
                        widget.navigation.weatherOpen ||
                        widget.navigation.workspace != workspace,
                    child: widget.workspaceBuilder(
                      context,
                      widget.navigation,
                      workspace,
                    ),
                  ),
                ),
              ),
            ),
        if (_weatherVisited)
          Positioned.fill(
            key: const ValueKey('weather-content'),
            child: TickerMode(
              enabled: widget.navigation.weatherOpen,
              child: IgnorePointer(
                ignoring: !widget.navigation.weatherOpen,
                child: Offstage(
                  offstage: !widget.navigation.weatherOpen,
                  child: widget.weatherBuilder(context),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
