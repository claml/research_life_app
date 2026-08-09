import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/stats/stats_calculator.dart';

EventItem _event({
  required String id,
  required EventType type,
  required DateTime startAt,
  ItemCategory category = ItemCategory.study,
  EventOrigin origin = EventOrigin.analysis,
  String? sourceLabel,
  DateTime? endAt,
}) {
  return EventItem(
    id: id,
    title: id,
    category: category,
    type: type,
    startAt: startAt,
    endAt: endAt,
    origin: origin,
    sourceLabel: sourceLabel,
  );
}

EventItem _readingEvent({
  required String id,
  required DateTime startAt,
  required Duration duration,
}) {
  return _event(
    id: id,
    type: EventType.record,
    startAt: startAt,
    origin: EventOrigin.manual,
    sourceLabel: '阅读',
    endAt: startAt.add(duration),
  );
}

void main() {
  group('StatsCalculator.readingMinutesOf', () {
    test('returns 0 for non-reading events', () {
      final event = _event(
        id: 'plan_1',
        type: EventType.plan,
        startAt: DateTime(2026, 4, 26),
      );

      expect(StatsCalculator.readingMinutesOf(event), 0);
    });

    test('computes minutes from start and end', () {
      final event = _readingEvent(
        id: 'reading_1',
        startAt: DateTime(2026, 4, 26, 9),
        duration: const Duration(hours: 1, minutes: 30),
      );

      expect(StatsCalculator.readingMinutesOf(event), 90);
    });

    test('returns 0 for reading event without end time', () {
      final event = _event(
        id: 'reading_1',
        type: EventType.record,
        startAt: DateTime(2026, 4, 26, 9),
        origin: EventOrigin.manual,
        sourceLabel: '阅读',
      );

      expect(StatsCalculator.readingMinutesOf(event), 0);
    });
  });

  group('StatsCalculator.dailyStats', () {
    final now = DateTime(2026, 4, 26, 20);

    test('builds one entry per day ending today', () {
      final stats = StatsCalculator.dailyStats(const [], days: 7, now: now);

      expect(stats, hasLength(7));
      expect(stats.last.date, DateTime(2026, 4, 26));
      expect(stats.first.date, DateTime(2026, 4, 20));
    });

    test('counts records, plans and reading minutes per day', () {
      final events = [
        _event(
          id: 'r1',
          type: EventType.record,
          startAt: DateTime(2026, 4, 26, 9),
        ),
        _event(
          id: 'p1',
          type: EventType.plan,
          startAt: DateTime(2026, 4, 26, 10),
        ),
        _readingEvent(
          id: 'reading_1',
          startAt: DateTime(2026, 4, 26, 14),
          duration: const Duration(minutes: 40),
        ),
      ];

      final stats = StatsCalculator.dailyStats(events, days: 7, now: now);

      final today = stats.last;
      expect(today.recordCount, 2);
      expect(today.planCount, 1);
      expect(today.readingMinutes, 40);
      expect(today.totalCount, 3);
      expect(today.activityScore, 3 + 4);
    });
  });

  group('StatsCalculator.weeklyReading', () {
    test('aggregates reading minutes into weeks starting Monday', () {
      // 2026-04-20 是周一，本周（周一 4/20 起）与上周（4/13 起）。
      final events = [
        _readingEvent(
          id: 'a',
          startAt: DateTime(2026, 4, 13, 10),
          duration: const Duration(minutes: 30),
        ),
        _readingEvent(
          id: 'b',
          startAt: DateTime(2026, 4, 21, 10),
          duration: const Duration(minutes: 60),
        ),
        _readingEvent(
          id: 'c',
          startAt: DateTime(2026, 4, 22, 10),
          duration: const Duration(minutes: 45),
        ),
      ];

      final weekly = StatsCalculator.weeklyReading(
        events,
        weeks: 2,
        now: DateTime(2026, 4, 26),
      );

      expect(weekly, hasLength(2));
      expect(weekly.first.weekStart, DateTime(2026, 4, 13));
      expect(weekly.first.readingMinutes, 30);
      expect(weekly.last.weekStart, DateTime(2026, 4, 20));
      expect(weekly.last.readingMinutes, 105);
    });
  });

  group('StatsCalculator.categoryDistribution', () {
    test('counts by category and filters by type', () {
      final events = [
        _event(
          id: '1',
          type: EventType.record,
          startAt: DateTime(2026, 4, 26),
          category: ItemCategory.study,
        ),
        _event(
          id: '2',
          type: EventType.plan,
          startAt: DateTime(2026, 4, 26),
          category: ItemCategory.study,
        ),
        _event(
          id: '3',
          type: EventType.plan,
          startAt: DateTime(2026, 4, 26),
          category: ItemCategory.life,
        ),
      ];

      final all = StatsCalculator.categoryDistribution(events);
      expect(all.firstWhere((item) => item.category == ItemCategory.study).count, 2);
      expect(all.firstWhere((item) => item.category == ItemCategory.life).count, 1);
      expect(all.firstWhere((item) => item.category == ItemCategory.work).count, 0);

      final plansOnly = StatsCalculator.categoryDistribution(
        events,
        type: EventType.plan,
      );
      expect(
        plansOnly.firstWhere((item) => item.category == ItemCategory.study).count,
        1,
      );
    });
  });

  group('StatsCalculator.todoStats', () {
    test('computes completion rate', () {
      final todos = [
        _event(
          id: 't1',
          type: EventType.plan,
          startAt: DateTime(2026, 4, 26),
          origin: EventOrigin.analysis,
        ),
        _event(
          id: 't2',
          type: EventType.plan,
          startAt: DateTime(2026, 4, 26),
          origin: EventOrigin.analysis,
        ),
      ];

      final done = StatsCalculator.todoStats([
        todos[0].copyWith(isDone: true),
        todos[1],
      ]);

      expect(done.total, 2);
      expect(done.completed, 1);
      expect(done.completionRate, 0.5);
    });

    test('completion rate is 0 for empty todos', () {
      final stats = StatsCalculator.todoStats(const []);

      expect(stats.total, 0);
      expect(stats.completed, 0);
      expect(stats.completionRate, 0);
    });
  });

  group('StatsCalculator.personRanking', () {
    SessionRecord _sessionWithPeople({
      required String sessionId,
      required List<PersonProfile> people,
    }) {
      return SessionRecord(
        id: sessionId,
        title: sessionId,
        input: AnalysisInput(
          rawText: '',
          sourceType: AnalysisSourceType.text,
        ),
        draft: AnalysisDraft(
          id: 'draft_$sessionId',
          tasks: const [],
          persons: const [],
          summary: '',
          warnings: const [],
          createdAt: DateTime(2026, 4, 26),
        ),
        preview: ReviewPreview(
          id: 'preview_$sessionId',
          completedTasks: const [],
          plannedTasks: const [],
          persons: const [],
          summary: '',
          warnings: const [],
          relationLabels: const [],
        ),
        events: const [],
        people: people,
        confirmedAt: DateTime(2026, 4, 26),
      );
    }

    test('aggregates task counts by name across sessions', () {
      final sessions = [
        _sessionWithPeople(
          sessionId: 's1',
          people: const [
            PersonProfile(
              id: 'p1',
              name: '王老师',
              role: PersonRole.teacher,
              aliases: [],
              relatedTaskCount: 4,
              relatedPlanTitles: [],
            ),
          ],
        ),
        _sessionWithPeople(
          sessionId: 's2',
          people: const [
            PersonProfile(
              id: 'p1',
              name: '王老师',
              role: PersonRole.teacher,
              aliases: [],
              relatedTaskCount: 2,
              relatedPlanTitles: [],
            ),
            PersonProfile(
              id: 'p2',
              name: '小李',
              role: PersonRole.classmate,
              aliases: [],
              relatedTaskCount: 1,
              relatedPlanTitles: [],
            ),
          ],
        ),
      ];

      final ranking = StatsCalculator.personRanking(sessions);

      expect(ranking, hasLength(2));
      expect(ranking.first.name, '王老师');
      expect(ranking.first.taskCount, 6);
      expect(ranking.last.name, '小李');
      expect(ranking.last.taskCount, 1);
    });

    test('respects limit and returns empty for no sessions', () {
      expect(StatsCalculator.personRanking(const []), isEmpty);

      final sessions = [
        _sessionWithPeople(
          sessionId: 's1',
          people: const [
            PersonProfile(
              id: 'p1',
              name: 'A',
              role: PersonRole.other,
              aliases: [],
              relatedTaskCount: 3,
              relatedPlanTitles: [],
            ),
            PersonProfile(
              id: 'p2',
              name: 'B',
              role: PersonRole.other,
              aliases: [],
              relatedTaskCount: 2,
              relatedPlanTitles: [],
            ),
          ],
        ),
      ];

      final ranking = StatsCalculator.personRanking(sessions, limit: 1);
      expect(ranking, hasLength(1));
      expect(ranking.single.name, 'A');
    });
  });
}
