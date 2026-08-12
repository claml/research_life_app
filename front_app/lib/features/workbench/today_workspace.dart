import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../app/workbench_destination.dart';
import '../../app/workbench_navigation_controller.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../calendar/calendar_page.dart';
import '../todos/todo_page.dart';
import 'workbench_workspace_frame.dart';

class TodayWorkspace extends StatelessWidget {
  const TodayWorkspace({
    required this.navigation,
    this.pages,
    this.onQuickCapture,
    super.key,
  });

  final WorkbenchNavigationController navigation;
  final Map<WorkbenchTab, Widget>? pages;
  final VoidCallback? onQuickCapture;

  @override
  Widget build(BuildContext context) {
    final resolvedPages =
        pages ??
        const {
          WorkbenchTab.todayOverview: _TodayOverview(),
          WorkbenchTab.todayCalendar: CalendarPage(),
          WorkbenchTab.todayTodos: TodoPage(),
        };
    return WorkbenchWorkspaceFrame(
      key: const Key('today-workspace'),
      workspace: WorkbenchWorkspace.today,
      navigation: navigation,
      title: '今天',
      pages: resolvedPages,
      primaryAction: FilledButton.icon(
        onPressed: onQuickCapture,
        icon: const Icon(Icons.add_rounded, size: 19),
        label: const Text('快速记录'),
      ),
    );
  }
}

class _TodayOverview extends StatefulWidget {
  const _TodayOverview();

  @override
  State<_TodayOverview> createState() => _TodayOverviewState();
}

class _TodayOverviewState extends State<_TodayOverview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ResearchLifeScope.of(context);
      unawaited(controller.ensureSessionHistoryLoaded());
      unawaited(controller.ensureManualEventsLoaded());
      unawaited(controller.ensureTodoStatusLoaded());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final now = DateTime.now();
        final events =
            controller.calendarEvents
                .where(
                  (event) =>
                      event.startAt.year == now.year &&
                      event.startAt.month == now.month &&
                      event.startAt.day == now.day,
                )
                .toList()
              ..sort((left, right) => left.startAt.compareTo(right.startAt));
        final todos = controller.todayTodoEvents;
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final timeline = _OverviewSection(
              key: const Key('today-timeline'),
              title: '今日日程',
              trailing: '${events.length} 项',
              leadingIcon: Icons.schedule_rounded,
              child: events.isEmpty
                  ? const _EmptyOverview(message: '今天还没有安排')
                  : Column(
                      children: [
                        for (final event in events.take(6))
                          _TimelineItem(event: event),
                      ],
                    ),
            );
            final todoPanel = _OverviewSection(
              key: const Key('today-todo-list'),
              title: '今日待办',
              trailing: '${todos.length} 项',
              leadingIcon: Icons.check_circle_outline_rounded,
              child: todos.isEmpty
                  ? const _EmptyOverview(message: '今天的任务已清空')
                  : Column(
                      children: [
                        for (final todo in todos.take(6))
                          _TodoItem(
                            event: todo,
                            onToggle: () => controller.toggleTodoDone(todo.id),
                          ),
                      ],
                    ),
            );
            return SingleChildScrollView(
              key: const Key('today-open-workspace'),
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: context.tokens.borderFaint),
                  borderRadius: BorderRadius.circular(
                    context.tokens.radiusLarge,
                  ),
                  color: context.tokens.panelSurface.withValues(alpha: 0.5),
                ),
                child: compact
                    ? Column(
                        children: [
                          timeline,
                          Divider(height: 1, color: context.tokens.borderFaint),
                          todoPanel,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: timeline),
                          Container(
                            width: 1,
                            constraints: const BoxConstraints(minHeight: 430),
                            color: context.tokens.borderFaint,
                          ),
                          Expanded(flex: 5, child: todoPanel),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.trailing,
    required this.leadingIcon,
    required this.child,
    super.key,
  });

  final String title;
  final String trailing;
  final IconData leadingIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(leadingIcon, size: 19, color: tokens.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                trailing,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 22),
          child,
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.event});

  final EventItem event;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final minute = event.startAt.minute.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              '${event.startAt.hour.toString().padLeft(2, '0')}:$minute',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: tokens.textSecondary),
            ),
          ),
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: tokens.panelSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: tokens.accent, width: 1.5),
                  ),
                ),
                Container(width: 1, height: 50, color: tokens.borderSoft),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (event.sourceLabel?.trim().isNotEmpty ?? false) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.sourceLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoItem extends StatelessWidget {
  const _TodoItem({required this.event, required this.onToggle});

  final EventItem event;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final minute = event.startAt.minute.toString().padLeft(2, '0');
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
      hoverColor: tokens.accentSoft.withValues(alpha: 0.32),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.borderFaint)),
        ),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: '完成 ${event.title}',
              child: Icon(
                Icons.check_box_outline_blank_rounded,
                size: 21,
                color: tokens.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${event.startAt.hour.toString().padLeft(2, '0')}:$minute',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyOverview extends StatelessWidget {
  const _EmptyOverview({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Center(
        child: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.tokens.textMuted),
        ),
      ),
    );
  }
}
