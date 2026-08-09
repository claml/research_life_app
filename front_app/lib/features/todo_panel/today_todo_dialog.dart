import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../state/research_life_controller.dart';

/// 今日待办面板：点击侧边栏「今日待办」按钮弹出，可勾选完成、跳转待办中心。
class TodayTodoDialog extends StatefulWidget {
  const TodayTodoDialog({
    required this.controller,
    required this.onOpenTodos,
    super.key,
  });

  final ResearchLifeController controller;
  final VoidCallback onOpenTodos;

  @override
  State<TodayTodoDialog> createState() => _TodayTodoDialogState();
}

class _TodayTodoDialogState extends State<TodayTodoDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final today = widget.controller.todayTodoEvents;

        return AlertDialog(
          title: Row(
            children: [
              const Icon(
                Icons.today_rounded,
                size: 22,
                color: Color(0xFFF76B15),
              ),
              const SizedBox(width: 10),
              Text(
                '今日待办 ${today.length} 项',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            height: 340,
            child: today.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.celebration_rounded,
                          size: 42,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '今天没有待办',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '添加计划或做一次周分析，今天的待办会出现在这里。',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: today.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final event = today[index];
                      return _TodayTodoTile(
                        event: event,
                        onToggle: () =>
                            widget.controller.toggleTodoDone(event.id),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenTodos();
              },
              child: const Text('打开待办中心'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}

class _TodayTodoTile extends StatelessWidget {
  const _TodayTodoTile({required this.event, required this.onToggle});

  final EventItem event;
  final VoidCallback onToggle;

  Color _priorityColor(TodoPriority priority) => switch (priority) {
    TodoPriority.high => const Color(0xFFE5484D),
    TodoPriority.medium => const Color(0xFFF76B15),
    TodoPriority.low => const Color(0xFF3E63DD),
    TodoPriority.none => const Color(0xFF9AA4B2),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Row(
        children: [
          Checkbox(
            value: event.isDone,
            onChanged: (_) => onToggle(),
            shape: const CircleBorder(),
            activeColor: const Color(0xFF2F7D4F),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                decoration: event.isDone ? TextDecoration.lineThrough : null,
                color: event.isDone ? tokens.textMuted : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _priorityColor(event.priority),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
