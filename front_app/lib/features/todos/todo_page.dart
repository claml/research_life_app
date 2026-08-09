import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/status_badge.dart';

/// 待办中心：汇集周分析/手动产生的「计划」事件，支持完成勾选与优先级。
class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  bool _showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final today = _sortedPending(controller.todayTodoEvents);
        final pending = _sortedPending(controller.pendingTodoEvents);
        final todayIds = {for (final event in today) event.id};
        final upcoming = [
          for (final event in pending)
            if (!todayIds.contains(event.id)) event,
        ];
        final completed = controller.completedTodoEvents;
        final hasAny = pending.isNotEmpty || completed.isNotEmpty;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  StatusBadge(
                    label: '今日待办 ${today.length}',
                    color: tokens.accent,
                  ),
                  StatusBadge(
                    label: '未完成 ${pending.length}',
                    color: tokens.textSecondary,
                  ),
                  StatusBadge(
                    label: '已完成 ${completed.length}',
                    color: const Color(0xFF2F7D4F),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '待办中心',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '周分析产生的「计划」与日历中手动添加的计划会汇集到这里，'
                '勾选即可标记完成，右键标记可调整优先级。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 22),
              if (today.isNotEmpty) ...[
                _SectionHeader(title: '今日待办', count: today.length),
                const SizedBox(height: 10),
                for (final event in today) ...[
                  _TodoTile(
                    event: event,
                    onToggle: () => controller.toggleTodoDone(event.id),
                    onPriorityChanged: (priority) =>
                        controller.setTodoPriority(event.id, priority),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 12),
              ],
              if (upcoming.isNotEmpty) ...[
                _SectionHeader(title: '未完成', count: upcoming.length),
                const SizedBox(height: 10),
                for (final event in upcoming) ...[
                  _TodoTile(
                    event: event,
                    onToggle: () => controller.toggleTodoDone(event.id),
                    onPriorityChanged: (priority) =>
                        controller.setTodoPriority(event.id, priority),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 12),
              ],
              if (completed.isNotEmpty) ...[
                _CollapsibleCompletedHeader(
                  count: completed.length,
                  expanded: _showCompleted,
                  onToggle: () =>
                      setState(() => _showCompleted = !_showCompleted),
                ),
                if (_showCompleted) ...[
                  const SizedBox(height: 10),
                  for (final event in completed) ...[
                    _TodoTile(
                      event: event,
                      onToggle: () => controller.toggleTodoDone(event.id),
                      onPriorityChanged: (priority) =>
                          controller.setTodoPriority(event.id, priority),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
              if (!hasAny)
                const EmptyState(
                  title: '还没有待办',
                  description:
                      '去「周分析」导入一周记录，产生的计划会自动出现在这里；'
                      '也可以到「日历」手动添加计划事项。',
                  icon: Icons.check_circle_outline_rounded,
                ),
            ],
          ),
        );
      },
    );
  }

  List<EventItem> _sortedPending(List<EventItem> events) {
    final sorted = [...events]
      ..sort((left, right) {
        final byPriority = _priorityRank(
          right.priority,
        ).compareTo(_priorityRank(left.priority));
        if (byPriority != 0) {
          return byPriority;
        }
        return left.startAt.compareTo(right.startAt);
      });
    return sorted;
  }

  int _priorityRank(TodoPriority priority) => switch (priority) {
    TodoPriority.high => 3,
    TodoPriority.medium => 2,
    TodoPriority.low => 1,
    TodoPriority.none => 0,
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: theme.textTheme.titleMedium?.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}

class _CollapsibleCompletedHeader extends StatelessWidget {
  const _CollapsibleCompletedHeader({
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '已完成',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: theme.textTheme.titleMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
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

  String _formatTodoDate(EventItem event) {
    final start = event.startAt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(start.year, start.month, start.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) {
      return '今天';
    }
    if (diff == 1) {
      return '明天';
    }
    if (diff == -1) {
      return '昨天';
    }
    if (start.year == now.year) {
      return '${start.month}月${start.day}日';
    }
    return '${start.year}年${start.month}月${start.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final done = event.isDone;
    final accent = _priorityColor(event.priority);

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 8, 10),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Checkbox(
            value: done,
            onChanged: (_) => onToggle(),
            shape: const CircleBorder(),
            activeColor: const Color(0xFF2F7D4F),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? tokens.textMuted : null,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _formatTodoDate(event),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    if (event.sourceLabel != null)
                      Text(
                        event.sourceLabel!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    Text(
                      event.category.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                    if (event.priority != TodoPriority.none)
                      Text(
                        '优先级：${event.priority.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
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
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _priorityColor(priority),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('优先级：${priority.label}'),
                      if (priority == event.priority) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
            icon: Icon(Icons.flag_rounded, size: 18, color: accent),
          ),
        ],
      ),
    );
  }
}
