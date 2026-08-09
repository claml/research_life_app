import '../../core/models/app_models.dart';

/// 一条到期提醒。
class DueReminder {
  const DueReminder({
    required this.eventId,
    required this.title,
    required this.startAt,
    required this.sourceLabel,
  });

  final String eventId;
  final String title;
  final DateTime startAt;
  final String? sourceLabel;

  /// 计划时间标签：带具体时刻则显示 HH:mm，否则显示“今天”。
  String get timeLabel {
    if (startAt.hour != 0 || startAt.minute != 0) {
      return '${startAt.hour.toString().padLeft(2, '0')}:'
          '${startAt.minute.toString().padLeft(2, '0')}';
    }
    return '今天';
  }
}

/// 日历事件提醒调度：判定哪些「计划」事件需要提醒。
///
/// 提醒语义：
/// - 事件带具体时刻（时分非 0）→ **到点提醒**：开始时间落在
///   `[now - lookback, now + forwardWindow]` 内提醒（即将开始/刚到点）；
/// - 事件只有日期（当日零点，历史数据）→ **当天提醒**：在其所属日期当天提醒一次。
/// 纯函数、无副作用，便于单元测试。
abstract final class ReminderScheduler {
  /// 找出在 [now] 时刻需要提醒的计划事件。
  ///
  /// - 仅提醒「计划」类事件，排除节假日与校历安排；
  /// - 已存在于 [alreadyReminded] 的事件跳过，避免重复提醒。
  static List<DueReminder> dueReminders({
    required List<EventItem> events,
    required DateTime now,
    required Set<String> alreadyReminded,
    Duration lookback = const Duration(minutes: 1),
    Duration forwardWindow = const Duration(minutes: 5),
  }) {
    final result = <DueReminder>[];

    for (final event in events) {
      if (event.type != EventType.plan) {
        continue;
      }
      if (event.origin == EventOrigin.holiday ||
          event.origin == EventOrigin.institutionCalendar) {
        continue;
      }
      if (alreadyReminded.contains(event.id)) {
        continue;
      }

      final start = event.startAt;
      final hasExplicitTime = start.hour != 0 || start.minute != 0;
      if (hasExplicitTime) {
        final windowStart = now.subtract(lookback);
        final windowEnd = now.add(forwardWindow);
        if (start.isBefore(windowStart) || start.isAfter(windowEnd)) {
          continue;
        }
      } else {
        if (start.year != now.year ||
            start.month != now.month ||
            start.day != now.day) {
          continue;
        }
      }

      result.add(
        DueReminder(
          eventId: event.id,
          title: event.title,
          startAt: start,
          sourceLabel: event.sourceLabel,
        ),
      );
    }
    return result;
  }
}
