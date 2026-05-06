import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models/app_models.dart';
import '../core/theme/app_tokens.dart';
import '../features/analysis/analysis_page.dart';
import '../features/calendar/calendar_page.dart';
import '../features/campus_map/campus_map_page.dart';
import '../features/history/history_page.dart';
import '../features/home/home_page.dart';
import '../features/persons/persons_page.dart';
import '../features/reading/reading_page.dart';
import '../features/settings/settings_page.dart';
import 'app_section.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _sidebarExpandedWidth = 248;
  static const double _sidebarCollapsedWidth = 96;
  static const double _contentGap = 20;

  AppSection _current = AppSection.home;
  bool _sidebarCollapsed = false;

  void _openRecordForEditing(SessionRecord session) {
    setState(
      () => _current = session.isInstitutionCalendar
          ? AppSection.settings
          : AppSection.analysis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final pages = <AppSection, Widget>{
      AppSection.home: const HomePage(),
      AppSection.calendar: const CalendarPage(),
      AppSection.campusMap: const CampusMapPage(),
      AppSection.reading: const ReadingPage(),
      AppSection.analysis: const AnalysisPage(),
      AppSection.persons: const PersonsPage(),
      AppSection.history: HistoryPage(onEditSession: _openRecordForEditing),
      AppSection.settings: const SettingsPage(),
    };

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Container(
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Sidebar(
                      current: _current,
                      collapsed: _sidebarCollapsed,
                      expandedWidth: metrics.expandedSidebarWidth,
                      collapsedWidth: metrics.collapsedSidebarWidth,
                      onChanged: (next) => setState(() => _current = next),
                      onToggle: () => setState(
                        () => _sidebarCollapsed = !_sidebarCollapsed,
                      ),
                    ),
                    SizedBox(width: metrics.contentGap),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.shellSurface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(
                            tokens.radiusXLarge + 4,
                          ),
                          border: Border.all(color: tokens.shellBorder),
                          boxShadow: tokens.shadowMd,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            tokens.radiusXLarge + 4,
                          ),
                          child: pages[_current]!,
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
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.current,
    required this.collapsed,
    required this.expandedWidth,
    required this.collapsedWidth,
    required this.onChanged,
    required this.onToggle,
  });

  final AppSection current;
  final bool collapsed;
  final double expandedWidth;
  final double collapsedWidth;
  final ValueChanged<AppSection> onChanged;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: collapsed ? collapsedWidth : expandedWidth,
      padding: EdgeInsets.fromLTRB(
        collapsed ? 12 : 18,
        24,
        collapsed ? 12 : 18,
        18,
      ),
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
      child: Column(
        crossAxisAlignment: collapsed
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (collapsed) ...[
            const _SidebarLogo(),
            const SizedBox(height: 10),
            _SidebarToggleButton(collapsed: collapsed, onPressed: onToggle),
          ] else ...[
            Row(
              children: [
                const _SidebarLogo(),
                const Spacer(),
                _SidebarToggleButton(collapsed: collapsed, onPressed: onToggle),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '\u7814\u7a76\u751f\u6d3b',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 28),
          for (final section in AppSection.values) ...[
            _SidebarItem(
              section: section,
              selected: section == current,
              collapsed: collapsed,
              onTap: () => onChanged(section),
            ),
            const SizedBox(height: 8),
          ],
          const Spacer(),
        ],
      ),
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
    final resolvedCollapsedWidth = maxWidth < 980 ? 84.0 : collapsedWidth;
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
    required this.section,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final AppSection section;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final item = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: selected
              ? tokens.sidebarSelected
              : Colors.white.withValues(alpha: collapsed ? 0 : 0.02),
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
              color: selected ? tokens.sidebarSurfaceStrong : Colors.white,
            ),
            if (!collapsed) ...[
              const SizedBox(width: 12),
              Text(
                section.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: selected ? tokens.sidebarSurfaceStrong : Colors.white,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
