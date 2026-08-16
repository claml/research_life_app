import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../app/workbench_destination.dart';
import '../../app/workbench_navigation_controller.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
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
        {
          WorkbenchTab.todayOverview: _TodayOverview(
            onQuickCapture: onQuickCapture,
          ),
        };
    return WorkbenchWorkspaceFrame(
      key: const Key('today-workspace'),
      workspace: WorkbenchWorkspace.today,
      navigation: navigation,
      pages: resolvedPages,
    );
  }
}

class _TodayOverview extends StatefulWidget {
  const _TodayOverview({this.onQuickCapture});

  final VoidCallback? onQuickCapture;

  @override
  State<_TodayOverview> createState() => _TodayOverviewState();
}

class _TodayOverviewState extends State<_TodayOverview> {
  bool _showCompleted = false;

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
        final todos = _sortedPending(controller.todayTodoEvents);
        final todayIds = {for (final todo in todos) todo.id};
        final upcoming = [
          for (final todo in _sortedPending(controller.pendingTodoEvents))
            if (!todayIds.contains(todo.id)) todo,
        ];
        final completed = controller.completedTodoEvents;
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final timeline = _OverviewSection(
              key: const Key('today-timeline'),
              title: '今日日程',
              trailing: '${events.length} 项',
              leadingIcon: Icons.schedule_rounded,
              action: FilledButton.tonalIcon(
                onPressed: widget.onQuickCapture,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('快速记录'),
              ),
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
              trailing: '${todos.length + upcoming.length} 项未完成',
              leadingIcon: Icons.check_circle_outline_rounded,
              child: todos.isEmpty && upcoming.isEmpty && completed.isEmpty
                  ? const _EmptyOverview(message: '今天的任务已清空')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (todos.isNotEmpty) ...[
                          const _TodoGroupLabel(label: '今天'),
                          for (final todo in todos)
                            _TodoItem(
                              event: todo,
                              onToggle: () =>
                                  controller.toggleTodoDone(todo.id),
                              onPriorityChanged: (priority) =>
                                  controller.setTodoPriority(todo.id, priority),
                            ),
                        ],
                        if (upcoming.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          const _TodoGroupLabel(label: '接下来'),
                          for (final todo in upcoming)
                            _TodoItem(
                              event: todo,
                              onToggle: () =>
                                  controller.toggleTodoDone(todo.id),
                              onPriorityChanged: (priority) =>
                                  controller.setTodoPriority(todo.id, priority),
                            ),
                        ],
                        if (completed.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _CompletedTodoHeader(
                            count: completed.length,
                            expanded: _showCompleted,
                            onTap: () => setState(
                              () => _showCompleted = !_showCompleted,
                            ),
                          ),
                          if (_showCompleted)
                            for (final todo in completed)
                              _TodoItem(
                                event: todo,
                                onToggle: () =>
                                    controller.toggleTodoDone(todo.id),
                                onPriorityChanged: (priority) => controller
                                    .setTodoPriority(todo.id, priority),
                              ),
                        ],
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

  List<EventItem> _sortedPending(List<EventItem> events) {
    return [...events]..sort((left, right) {
      final priority = _priorityRank(
        right.priority,
      ).compareTo(_priorityRank(left.priority));
      return priority != 0 ? priority : left.startAt.compareTo(right.startAt);
    });
  }

  int _priorityRank(TodoPriority priority) => switch (priority) {
    TodoPriority.high => 3,
    TodoPriority.medium => 2,
    TodoPriority.low => 1,
    TodoPriority.none => 0,
  };
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.trailing,
    required this.leadingIcon,
    required this.child,
    this.action,
    super.key,
  });

  final String title;
  final String trailing;
  final IconData leadingIcon;
  final Widget child;
  final Widget? action;

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
              if (action != null) ...[const SizedBox(width: 12), action!],
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
  const _TodoItem({
    required this.event,
    required this.onToggle,
    required this.onPriorityChanged,
  });

  final EventItem event;
  final VoidCallback onToggle;
  final ValueChanged<TodoPriority> onPriorityChanged;

  Color _priorityColor(TodoPriority priority) => switch (priority) {
    TodoPriority.high => const Color(0xFFE5484D),
    TodoPriority.medium => const Color(0xFFF76B15),
    TodoPriority.low => const Color(0xFF3E63DD),
    TodoPriority.none => const Color(0xFF9AA4B2),
  };

  String _dateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(
      event.startAt.year,
      event.startAt.month,
      event.startAt.day,
    );
    final difference = date.difference(today).inDays;
    if (difference == 0) return '今天';
    if (difference == 1) return '明天';
    return '${event.startAt.month}月${event.startAt.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final priorityColor = _priorityColor(event.priority);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderFaint)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: event.isDone,
            onChanged: (_) => onToggle(),
            shape: const CircleBorder(),
            visualDensity: VisualDensity.compact,
          ),
          Container(
            width: 3,
            height: 28,
            decoration: BoxDecoration(
              color: priorityColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: event.isDone ? tokens.textMuted : tokens.textPrimary,
                    fontWeight: FontWeight.w500,
                    decoration: event.isDone
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_dateLabel()} · ${event.category.label}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          PopupMenuButton<TodoPriority>(
            tooltip: '设置优先级',
            onSelected: onPriorityChanged,
            itemBuilder: (context) => [
              for (final priority in TodoPriority.values)
                PopupMenuItem(
                  value: priority,
                  child: Text('优先级：${priority.label}'),
                ),
            ],
            icon: Icon(Icons.flag_rounded, size: 18, color: priorityColor),
          ),
        ],
      ),
    );
  }
}

class _TodoGroupLabel extends StatelessWidget {
  const _TodoGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: context.tokens.textSecondary,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _CompletedTodoHeader extends StatelessWidget {
  const _CompletedTodoHeader({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(context.tokens.radiusSmall),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
            size: 19,
            color: context.tokens.textSecondary,
          ),
          const SizedBox(width: 6),
          Text('已完成 $count', style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    ),
  );
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
