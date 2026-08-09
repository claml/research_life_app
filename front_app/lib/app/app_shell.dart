import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/app_models.dart';
import '../core/theme/app_tokens.dart';
import '../features/agent/agent_page.dart';
import '../features/analysis/analysis_page.dart';
import '../features/calendar/calendar_page.dart';
import '../features/campus_map/campus_map_page.dart';
import '../features/history/history_page.dart';
import '../features/home/home_page.dart';
import '../features/persons/persons_page.dart';
import '../features/pet_overlay/pet_overlay.dart';
import '../features/quick_capture/quick_capture_dialog.dart';
import '../features/reminder/reminder_overlay.dart';
import '../features/todo_panel/today_todo_dialog.dart';
import '../features/files/my_files_page.dart';
import '../features/notes/my_notes_page.dart';
import '../features/document_view/document_viewer_page.dart';
import '../features/pdf_tools/pdf_tools_page.dart';
import '../features/reading/reading_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../features/stats/stats_page.dart';
import '../features/todos/todo_page.dart';
import '../state/research_life_controller.dart';
import 'app_section.dart';
import 'research_life_scope.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _sidebarExpandedWidth = 232;
  static const double _sidebarCollapsedWidth = 80;
  static const double _contentGap = 20;

  AppSection _current = AppSection.home;
  late final List<Widget> _sectionPages;
  ResearchLifeController? _controller;
  bool Function(KeyEvent)? _hardwareKeyHandler;

  @override
  void initState() {
    super.initState();
    _sectionPages = <Widget>[
      const HomePage(),
      const CalendarPage(),
      const TodoPage(),
      const StatsPage(),
      SearchPage(onNavigate: _selectSection),
      const CampusMapPage(),
      const ReadingPage(),
      const MyNotesPage(),
      const MyFilesPage(),
      const DocumentViewerPage(),
      const PdfToolsPage(),
      const AgentPage(),
      const AnalysisPage(),
      const PersonsPage(),
      HistoryPage(onEditSession: _openRecordForEditing),
      const SettingsPage(),
    ];

    // 全局快捷键（Ctrl+Shift+C 快速捕获）：使用 HardwareKeyboard 不依赖焦点树。
    _hardwareKeyHandler = _handleHardwareKeyEvent;
    HardwareKeyboard.instance.addHandler(_hardwareKeyHandler!);
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ResearchLifeScope.read(context);
    if (!identical(_controller, controller)) {
      _controller?.removeListener(_handleCrossSectionNavigation);
      _controller?.todayTodoDialogRequests.removeListener(
        _handleTodayTodoRequested,
      );
      _controller = controller;
      controller.addListener(_handleCrossSectionNavigation);
      controller.todayTodoDialogRequests.addListener(
        _handleTodayTodoRequested,
      );
    }
  }

  void _handleTodayTodoRequested() {
    if (mounted) {
      _openTodayTodo();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleCrossSectionNavigation);
    _controller?.todayTodoDialogRequests.removeListener(
      _handleTodayTodoRequested,
    );
    final handler = _hardwareKeyHandler;
    if (handler != null) {
      HardwareKeyboard.instance.removeHandler(handler);
      _hardwareKeyHandler = null;
    }
    super.dispose();
  }

  void _handleCrossSectionNavigation() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.hasPendingReadingOpen && _current != AppSection.reading) {
      setState(() => _current = AppSection.reading);
      return;
    }
    if (controller.hasPendingDocumentViewOpen &&
        _current != AppSection.documentView) {
      setState(() => _current = AppSection.documentView);
      return;
    }
    if (controller.consumePdfToolsNavigationRequest() &&
        _current != AppSection.pdfTools) {
      setState(() => _current = AppSection.pdfTools);
    }
  }

  void _openRecordForEditing(SessionRecord session) {
    _controller?.discardUnconsumedOpenRequests();
    setState(
      () => _current = session.isInstitutionCalendar
          ? AppSection.settings
          : AppSection.analysis,
    );
  }

  void _selectSection(AppSection next) {
    if (next != _current) {
      _controller?.discardUnconsumedOpenRequests();
      setState(() => _current = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    final controller = ResearchLifeScope.read(context);
    return Listener(
      onPointerDown: (_) => controller.notifyUserActivity(),
      onPointerHover: (_) => controller.notifyUserActivity(),
      onPointerMove: (_) => controller.notifyUserActivity(),
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Stack(
          children: [
            Container(
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
                    final metrics = _ShellMetrics.resolve(
                      maxWidth: constraints.maxWidth,
                      expandedWidth: _sidebarExpandedWidth,
                      collapsedWidth: _sidebarCollapsedWidth,
                      gap: _contentGap,
                    );

                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: _ShellLayout(
                        metrics: metrics,
                        current: _current,
                        sectionIndex: _current.index,
                        sections: _sectionPages,
                        onSectionChanged: _selectSection,
                        onOpenTodayTodo: _openTodayTodo,
                      ),
                    );
                  },
                ),
              ),
            ),
            const PetOverlay(),
            const ReminderOverlay(),
          ],
        ),
      ),
    );
  }

  void _openTodayTodo() {
    if (!mounted) {
      return;
    }
    final controller = ResearchLifeScope.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => TodayTodoDialog(
        controller: controller,
        onOpenTodos: () => _selectSection(AppSection.todos),
      ),
    );
  }

  void _openQuickCapture() {
    if (!mounted) {
      return;
    }
    final controller = ResearchLifeScope.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => QuickCaptureDialog(controller: controller),
    );
  }
}

/// 侧栏与主内容并排；折叠状态仅重建本组件，避免牵动整棵 AppShell。
class _ShellLayout extends StatefulWidget {
  const _ShellLayout({
    required this.metrics,
    required this.current,
    required this.sectionIndex,
    required this.sections,
    required this.onSectionChanged,
    required this.onOpenTodayTodo,
  });

  final _ShellMetrics metrics;
  final AppSection current;
  final int sectionIndex;
  final List<Widget> sections;
  final ValueChanged<AppSection> onSectionChanged;
  final VoidCallback onOpenTodayTodo;

  @override
  State<_ShellLayout> createState() => _ShellLayoutState();
}

class _ShellLayoutState extends State<_ShellLayout> {
  bool _sidebarCollapsed = false;

  void _toggleSidebar() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sidebarWidth = _sidebarCollapsed
        ? widget.metrics.collapsedSidebarWidth
        : widget.metrics.expandedSidebarWidth;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          child: _Sidebar(
            current: widget.current,
            collapsed: _sidebarCollapsed,
            width: sidebarWidth,
            onChanged: widget.onSectionChanged,
            onToggle: _toggleSidebar,
            onOpenTodayTodo: widget.onOpenTodayTodo,
          ),
        ),
        SizedBox(width: widget.metrics.contentGap),
        Expanded(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.shellSurface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(tokens.radiusXLarge + 4),
                border: Border.all(color: tokens.shellBorder),
                boxShadow: tokens.shadowMd,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radiusXLarge + 4),
                child: _LazySectionStack(
                  index: widget.sectionIndex,
                  sections: widget.sections,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 仅构建已访问过的页面；隐藏页停止 ticker，避免 IndexedStack 一次性布局全部子页。
class _LazySectionStack extends StatefulWidget {
  const _LazySectionStack({required this.index, required this.sections});

  final int index;
  final List<Widget> sections;

  @override
  State<_LazySectionStack> createState() => _LazySectionStackState();
}

class _LazySectionStackState extends State<_LazySectionStack> {
  final Set<int> _visited = {0};

  @override
  void didUpdateWidget(covariant _LazySectionStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final sectionIndex in _visited)
          Positioned.fill(
            child: TickerMode(
              enabled: sectionIndex == widget.index,
              child: IgnorePointer(
                ignoring: sectionIndex != widget.index,
                child: RepaintBoundary(
                  child: Offstage(
                    offstage: sectionIndex != widget.index,
                    child: widget.sections[sectionIndex],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.current,
    required this.collapsed,
    required this.width,
    required this.onChanged,
    required this.onToggle,
    required this.onOpenTodayTodo,
  });

  final AppSection current;
  final bool collapsed;
  final double width;
  final ValueChanged<AppSection> onChanged;
  final VoidCallback onToggle;
  final VoidCallback onOpenTodayTodo;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  late Set<String> _expandedGroupIds;

  @override
  void initState() {
    super.initState();
    _expandedGroupIds = {_sidebarGroups.first.id};
    _showCurrentGroup();
  }

  @override
  void didUpdateWidget(covariant _Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current) {
      final group = _groupForSection(widget.current);
      if (group != null && !_expandedGroupIds.contains(group.id)) {
        _expandedGroupIds = {..._expandedGroupIds, group.id};
      }
    }
  }

  void _showCurrentGroup() {
    final group = _groupForSection(widget.current);
    if (group != null) {
      _expandedGroupIds = {..._expandedGroupIds, group.id};
    }
  }

  void _toggleGroup(String groupId) {
    setState(() {
      if (_expandedGroupIds.contains(groupId)) {
        _expandedGroupIds = {..._expandedGroupIds}..remove(groupId);
      } else {
        _expandedGroupIds = {..._expandedGroupIds, groupId};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return SizedBox(
      width: widget.width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tokens.sidebarSurface, tokens.sidebarSurfaceStrong],
          ),
          borderRadius: BorderRadius.circular(tokens.radiusXLarge + 4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: tokens.shadowMd,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            widget.collapsed ? 10 : 16,
            20,
            widget.collapsed ? 10 : 16,
            16,
          ),
          child: Column(
            crossAxisAlignment: widget.collapsed
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (widget.collapsed) ...[
                const _SidebarLogo(),
                const SizedBox(height: 8),
                _SidebarToggleButton(
                  collapsed: widget.collapsed,
                  onPressed: widget.onToggle,
                ),
                const SizedBox(height: 8),
                _SidebarSearchButton(
                  collapsed: true,
                  onPressed: () => widget.onChanged(AppSection.search),
                ),
                const SizedBox(height: 4),
                _SidebarTodayTodoButton(
                  collapsed: true,
                  onPressed: widget.onOpenTodayTodo,
                ),
              ] else ...[
                Row(
                  children: [
                    const _SidebarLogo(),
                    const Spacer(),
                    _SidebarToggleButton(
                      collapsed: widget.collapsed,
                      onPressed: widget.onToggle,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '\u7814\u7a76\u751f\u6d3b',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _SidebarSearchButton(
                  collapsed: false,
                  onPressed: () => widget.onChanged(AppSection.search),
                ),
                const SizedBox(height: 8),
                _SidebarTodayTodoButton(
                  collapsed: false,
                  onPressed: widget.onOpenTodayTodo,
                ),
              ],
              SizedBox(height: widget.collapsed ? 16 : 22),
              Expanded(
                child: widget.collapsed
                    ? _CollapsedSidebarNav(
                        current: widget.current,
                        onChanged: widget.onChanged,
                      )
                    : _ExpandedSidebarNav(
                        current: widget.current,
                        expandedGroupIds: _expandedGroupIds,
                        onChanged: widget.onChanged,
                        onToggleGroup: _toggleGroup,
                      ),
              ),
              const SizedBox(height: 12),
              const _SidebarDivider(),
              const SizedBox(height: 8),
              for (final section in _footerSections) ...[
                _SidebarItem(
                  key: ValueKey('footer-${section.name}'),
                  section: section,
                  selected: section == widget.current,
                  collapsed: widget.collapsed,
                  onTap: () => widget.onChanged(section),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedSidebarNav extends StatelessWidget {
  const _ExpandedSidebarNav({
    required this.current,
    required this.expandedGroupIds,
    required this.onChanged,
    required this.onToggleGroup,
  });

  final AppSection current;
  final Set<String> expandedGroupIds;
  final ValueChanged<AppSection> onChanged;
  final ValueChanged<String> onToggleGroup;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final section in _primarySections) ...[
          _SidebarItem(
            key: ValueKey('primary-${section.name}'),
            section: section,
            selected: section == current,
            collapsed: false,
            onTap: () => onChanged(section),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 10),
        for (final group in _sidebarGroups) ...[
          _SidebarGroupHeader(
            group: group,
            active: group.contains(current),
            expanded: expandedGroupIds.contains(group.id),
            onTap: () => onToggleGroup(group.id),
          ),
          if (expandedGroupIds.contains(group.id)) ...[
            const SizedBox(height: 6),
            for (final section in group.sections) ...[
              _SidebarItem(
                key: ValueKey('group-${group.id}-${section.name}'),
                section: section,
                selected: section == current,
                collapsed: false,
                nested: true,
                onTap: () => onChanged(section),
              ),
              const SizedBox(height: 6),
            ],
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CollapsedSidebarNav extends StatelessWidget {
  const _CollapsedSidebarNav({required this.current, required this.onChanged});

  final AppSection current;
  final ValueChanged<AppSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final section in _primarySections) ...[
          _SidebarItem(
            key: ValueKey('collapsed-primary-${section.name}'),
            section: section,
            selected: section == current,
            collapsed: true,
            onTap: () => onChanged(section),
          ),
          const SizedBox(height: 6),
        ],
        const _SidebarDivider(),
        for (final group in _sidebarGroups) ...[
          const SizedBox(height: 6),
          for (final section in group.sections) ...[
            _SidebarItem(
              key: ValueKey('collapsed-${group.id}-${section.name}'),
              section: section,
              selected: section == current,
              collapsed: true,
              onTap: () => onChanged(section),
            ),
            const SizedBox(height: 6),
          ],
          const _SidebarDivider(),
        ],
      ],
    );
  }
}

class _SidebarGroupHeader extends StatelessWidget {
  const _SidebarGroupHeader({
    required this.group,
    required this.active,
    required this.expanded,
    required this.onTap,
  });

  final _SidebarGroup group;
  final bool active;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final foreground = Colors.white.withValues(alpha: active ? 0.98 : 0.72);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
        ),
        child: Row(
          children: [
            Icon(group.icon, size: 18, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: foreground,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      color: Colors.white.withValues(alpha: 0.10),
    );
  }
}

class _ShellMetrics {
  const _ShellMetrics({
    required this.expandedSidebarWidth,
    required this.collapsedSidebarWidth,
    required this.contentGap,
  });

  final double expandedSidebarWidth;
  final double collapsedSidebarWidth;
  final double contentGap;

  static _ShellMetrics resolve({
    required double maxWidth,
    required double expandedWidth,
    required double collapsedWidth,
    required double gap,
  }) {
    final resolvedGap = maxWidth < 1100 ? 14.0 : gap;
    final resolvedCollapsedWidth = maxWidth < 980 ? 76.0 : collapsedWidth;
    final desiredExpandedWidth = maxWidth < 1280 ? 224.0 : expandedWidth;
    const contentPriorityMinWidth = 760.0;

    final maxExpandedWidth = math.max(
      resolvedCollapsedWidth,
      maxWidth - resolvedGap - contentPriorityMinWidth,
    );

    final resolvedExpandedWidth = desiredExpandedWidth.clamp(
      resolvedCollapsedWidth,
      maxExpandedWidth,
    );

    return _ShellMetrics(
      expandedSidebarWidth: resolvedExpandedWidth.toDouble(),
      collapsedSidebarWidth: resolvedCollapsedWidth,
      contentGap: resolvedGap,
    );
  }
}

const List<AppSection> _primarySections = [
  AppSection.home,
  AppSection.calendar,
  AppSection.todos,
  AppSection.agent,
];

const List<AppSection> _footerSections = [
  AppSection.history,
  AppSection.settings,
];

const List<_SidebarGroup> _sidebarGroups = [
  _SidebarGroup(
    id: 'research',
    label: '学研工作',
    icon: Icons.school_rounded,
    sections: [
      AppSection.stats,
      AppSection.reading,
      AppSection.myNotes,
      AppSection.analysis,
      AppSection.persons,
    ],
  ),
  _SidebarGroup(
    id: 'resources',
    label: '资料工具',
    icon: Icons.inventory_2_rounded,
    sections: [
      AppSection.myFiles,
      AppSection.documentView,
      AppSection.pdfTools,
    ],
  ),
  _SidebarGroup(
    id: 'campus',
    label: '校园生活',
    icon: Icons.explore_rounded,
    sections: [AppSection.campusMap],
  ),
];

class _SidebarGroup {
  const _SidebarGroup({
    required this.id,
    required this.label,
    required this.icon,
    required this.sections,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<AppSection> sections;

  bool contains(AppSection section) => sections.contains(section);
}

_SidebarGroup? _groupForSection(AppSection section) {
  for (final group in _sidebarGroups) {
    if (group.contains(section)) {
      return group;
    }
  }
  return null;
}

class _SidebarLogo extends StatelessWidget {
  const _SidebarLogo();

  static const String _assetPath = 'assets/logo/searchlife_logo.png';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusMedium - 1),
        child: Padding(
          padding: const EdgeInsets.all(0.5),
          child: Image.asset(
            _assetPath,
            fit: BoxFit.contain,
            semanticLabel: 'Research Life logo',
            cacheWidth: 112,
            cacheHeight: 112,
          ),
        ),
      ),
    );
  }
}

/// 侧边栏顶部的「今日待办」入口：点击弹出今日待办面板。
class _SidebarTodayTodoButton extends StatelessWidget {
  const _SidebarTodayTodoButton({
    required this.collapsed,
    required this.onPressed,
  });

  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return IconButton(
        onPressed: onPressed,
        tooltip: '今日待办',
        icon: Icon(
          Icons.task_alt_rounded,
          color: context.tokens.sidebarSelected,
        ),
        style: IconButton.styleFrom(
          foregroundColor: context.tokens.sidebarSelected,
          backgroundColor: Colors.transparent,
          hoverColor: Colors.white.withValues(alpha: 0.08),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.task_alt_rounded, size: 18, color: Colors.white),
        label: const Text(
          '今日待办',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          foregroundColor: Colors.white,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

/// 侧边栏顶部的全局搜索入口。
class _SidebarSearchButton extends StatelessWidget {
  const _SidebarSearchButton({
    required this.collapsed,
    required this.onPressed,
  });

  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (collapsed) {
      return IconButton(
        onPressed: onPressed,
        tooltip: '全局搜索',
        icon: Icon(Icons.search_rounded, color: tokens.sidebarSelected),
        style: IconButton.styleFrom(
          foregroundColor: tokens.sidebarSelected,
          backgroundColor: Colors.transparent,
          hoverColor: Colors.white.withValues(alpha: 0.08),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.search_rounded, size: 18, color: Colors.white),
        label: const Text(
          '全局搜索',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          foregroundColor: Colors.white,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class _SidebarToggleButton extends StatelessWidget {
  const _SidebarToggleButton({
    required this.collapsed,
    required this.onPressed,
  });

  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: collapsed
          ? '\u5c55\u5f00\u4fa7\u680f'
          : '\u6536\u8d77\u4fa7\u680f',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        fixedSize: const Size(40, 40),
      ),
      icon: Icon(
        collapsed ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    super.key,
    required this.section,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.nested = false,
  });

  final AppSection section;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final item = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        constraints: BoxConstraints(minHeight: collapsed ? 42 : 40),
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : (nested ? 12 : 14),
          vertical: collapsed ? 9 : 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? tokens.sidebarSelected
              : Colors.white.withValues(alpha: collapsed ? 0 : 0.015),
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: selected
              ? Border.all(color: Colors.white.withValues(alpha: 0.2))
              : null,
        ),
        child: Row(
          mainAxisAlignment: collapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(
              section.icon,
              size: collapsed ? 22 : (nested ? 18 : 20),
              color: selected ? tokens.sidebarSurfaceStrong : Colors.white,
            ),
            if (!collapsed) ...[
              SizedBox(width: nested ? 10 : 12),
              Flexible(
                child: Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? tokens.sidebarSurfaceStrong
                        : Colors.white,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!collapsed) {
      return item;
    }

    return Tooltip(message: section.label, child: item);
  }
}
