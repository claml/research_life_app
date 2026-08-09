import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../services/reminder/reminder_scheduler.dart';
import '../../shared/widgets/frosted_glass.dart';

/// 日历事件到期提醒浮层：右下角玻璃卡片，自动消失或手动关闭。
class ReminderOverlay extends StatelessWidget {
  const ReminderOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final reminders = controller.pendingReminders;
          if (reminders.isEmpty) {
            return const SizedBox.shrink();
          }

          final shown = reminders.take(3).toList();
          return Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 24, bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final reminder in shown) ...[
                    _ReminderCard(
                      reminder: reminder,
                      onDismiss: () =>
                          controller.dismissReminder(reminder.eventId),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder, required this.onDismiss});

  final DueReminder reminder;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.onSurface;
    final mutedColor = primaryColor.withValues(alpha: 0.62);

    return FrostedGlass(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        width: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.alarm_rounded,
                  size: 18,
                  color: Color(0xFFF76B15),
                ),
                const SizedBox(width: 8),
                Text(
                  '日程提醒 · ${reminder.timeLabel}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: mutedColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              reminder.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: primaryColor,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (reminder.sourceLabel != null &&
                reminder.sourceLabel!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                reminder.sourceLabel!,
                style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              '去「待办」页处理这条计划',
              style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
            ),
          ],
        ),
      ),
    );
  }
}
