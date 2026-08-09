import '../../core/models/app_models.dart';

/// 单日统计。
class DailyStats {
  const DailyStats({
    required this.date,
    required this.recordCount,
    required this.planCount,
    required this.readingMinutes,
  });

  final DateTime date;
  final int recordCount;
  final int planCount;
  final int readingMinutes;

  int get totalCount => recordCount + planCount;

  /// 活跃度评分：事件数 + 每 10 分钟阅读 + 1，用于热力图深浅。
  int get activityScore => totalCount + readingMinutes ~/ 10;
}

/// 单周阅读统计。
class WeeklyReadingStats {
  const WeeklyReadingStats({
    required this.weekStart,
    required this.readingMinutes,
  });

  final DateTime weekStart;
  final int readingMinutes;
}

/// 分类分布。
class CategoryDistribution {
  const CategoryDistribution({required this.category, required this.count});

  final ItemCategory category;
  final int count;
}

/// 待办完成统计。
class TodoStats {
  const TodoStats({required this.total, required this.completed});

  final int total;
  final int completed;

  double get completionRate => total == 0 ? 0 : completed / total;
}

/// 人物互动排行条目。
class PersonRanking {
  const PersonRanking({
    required this.name,
    required this.role,
    required this.taskCount,
  });

  final String name;
  final PersonRole role;
  final int taskCount;
}

/// 基于事件列表的只读统计计算，纯函数、无副作用，便于单元测试。
abstract final class StatsCalculator {
  /// 是否为阅读时长事件（阅读达到最短时长后自动写入的记录）。
  static bool isReadingEvent(EventItem event) =>
      event.origin == EventOrigin.manual && event.sourceLabel == '阅读';

  /// 单次阅读事件的分钟数（按 startAt/endAt 差值）。
  static int readingMinutesOf(EventItem event) {
    if (!isReadingEvent(event) || event.endAt == null) {
      return 0;
    }
    final minutes = event.endAt!.difference(event.startAt).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  /// 近 [days] 天（含今天）的逐日统计，从最早一天排到今天。
  static List<DailyStats> dailyStats(
    List<EventItem> events, {
    required int days,
    DateTime? now,
  }) {
    final today = _startOfDay(now ?? DateTime.now());
    final result = <DailyStats>[];
    for (var offset = days - 1; offset >= 0; offset -= 1) {
      final date = today.subtract(Duration(days: offset));
      final dayEvents = events
          .where((event) => _sameDay(event.startAt, date))
          .toList();
      result.add(
        DailyStats(
          date: date,
          recordCount: dayEvents
              .where((event) => event.type == EventType.record)
              .length,
          planCount: dayEvents
              .where((event) => event.type == EventType.plan)
              .length,
          readingMinutes: dayEvents.fold(
            0,
            (sum, event) => sum + readingMinutesOf(event),
          ),
        ),
      );
    }
    return result;
  }

  /// 近 [weeks] 周（以周一为起点，含本周）的阅读时长汇总。
  static List<WeeklyReadingStats> weeklyReading(
    List<EventItem> events, {
    required int weeks,
    DateTime? now,
  }) {
    final today = _startOfDay(now ?? DateTime.now());
    final thisWeekStart = _weekStart(today);
    final result = <WeeklyReadingStats>[];
    for (var offset = weeks - 1; offset >= 0; offset -= 1) {
      final weekStart = thisWeekStart.subtract(Duration(days: offset * 7));
      final weekEnd = weekStart.add(const Duration(days: 7));
      final minutes = events
          .where((event) {
            final start = event.startAt;
            return !start.isBefore(weekStart) && start.isBefore(weekEnd);
          })
          .fold(0, (sum, event) => sum + readingMinutesOf(event));
      result.add(
        WeeklyReadingStats(weekStart: weekStart, readingMinutes: minutes),
      );
    }
    return result;
  }

  /// 事件按分类统计（[type] 为空表示全部类型；[since] 可限制起始日期）。
  static List<CategoryDistribution> categoryDistribution(
    List<EventItem> events, {
    EventType? type,
    DateTime? since,
  }) {
    final counts = <ItemCategory, int>{};
    for (final event in events) {
      if (type != null && event.type != type) {
        continue;
      }
      if (since != null && event.startAt.isBefore(since)) {
        continue;
      }
      counts[event.category] = (counts[event.category] ?? 0) + 1;
    }
    return [
      for (final category in ItemCategory.values)
        CategoryDistribution(category: category, count: counts[category] ?? 0),
    ];
  }

  /// 待办完成情况（total 为计划事件总数，completed 为已完成数）。
  static TodoStats todoStats(List<EventItem> todos) {
    var completed = 0;
    for (final todo in todos) {
      if (todo.isDone) {
        completed += 1;
      }
    }
    return TodoStats(total: todos.length, completed: completed);
  }

  /// 人物互动排行：跨会话按姓名聚合关联事项数，取前 [limit] 名。
  static List<PersonRanking> personRanking(
    List<SessionRecord> sessions, {
    int limit = 5,
  }) {
    final byName = <String, ({PersonRole role, int count})>{};
    for (final session in sessions) {
      for (final person in session.people) {
        final existing = byName[person.name];
        byName[person.name] = (
          role: existing?.role ?? person.role,
          count: (existing?.count ?? 0) + person.relatedTaskCount,
        );
      }
    }

    final ranking = [
      for (final entry in byName.entries)
        PersonRanking(
          name: entry.key,
          role: entry.value.role,
          taskCount: entry.value.count,
        ),
    ]..sort((left, right) => right.taskCount.compareTo(left.taskCount));
    return ranking.take(limit).toList();
  }

  static DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  /// 所在周的周一（一周从周一开始）。
  static DateTime _weekStart(DateTime date) {
    final day = _startOfDay(date);
    return day.subtract(Duration(days: day.weekday - 1));
  }
}
