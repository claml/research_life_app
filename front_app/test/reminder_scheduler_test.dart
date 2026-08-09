import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/reminder/reminder_scheduler.dart';

EventItem _plan({
  required String id,
  required DateTime startAt,
  EventOrigin origin = EventOrigin.analysis,
}) {
  return EventItem(
    id: id,
    title: '任务 $id',
    category: ItemCategory.study,
    type: EventType.plan,
    startAt: startAt,
    origin: origin,
    sourceLabel: '周分析',
  );
}

void main() {
  final now = DateTime(2026, 4, 26, 10, 0);

  group('ReminderScheduler.dueReminders', () {
    test('reminds plan events due today', () {
      final events = [
        _plan(id: 'today', startAt: DateTime(2026, 4, 26)),
      ];

      final due = ReminderScheduler.dueReminders(
        events: events,
        now: now,
        alreadyReminded: const {},
      );

      expect(due, hasLength(1));
      expect(due.single.eventId, 'today');
    });

    test('skips already reminded events', () {
      final events = [
        _plan(id: 'dup', startAt: DateTime(2026, 4, 26)),
      ];

      final due = ReminderScheduler.dueReminders(
        events: events,
        now: now,
        alreadyReminded: {'dup'},
      );

      expect(due, isEmpty);
    });

    test('skips events not due today', () {
      final events = [
        _plan(id: 'yesterday', startAt: DateTime(2026, 4, 25)),
        _plan(id: 'tomorrow', startAt: DateTime(2026, 4, 27)),
      ];

      final due = ReminderScheduler.dueReminders(
        events: events,
        now: now,
        alreadyReminded: const {},
      );

      expect(due, isEmpty);
    });

    test('skips record events, holidays and institution calendar', () {
      final events = [
        EventItem(
          id: 'record',
          title: '已完成事项',
          category: ItemCategory.work,
          type: EventType.record,
          startAt: DateTime(2026, 4, 26),
          origin: EventOrigin.manual,
        ),
        _plan(
          id: 'holiday',
          startAt: DateTime(2026, 4, 26),
          origin: EventOrigin.holiday,
        ),
        _plan(
          id: 'institution',
          startAt: DateTime(2026, 4, 26),
          origin: EventOrigin.institutionCalendar,
        ),
      ];

      final due = ReminderScheduler.dueReminders(
        events: events,
        now: now,
        alreadyReminded: const {},
      );

      expect(due, isEmpty);
    });

    test('shows time label for events with explicit time', () {
      expect(
        DueReminder(
          eventId: 'timed',
          title: '任务 timed',
          startAt: DateTime(2026, 4, 26, 14, 30),
          sourceLabel: null,
        ).timeLabel,
        '14:30',
      );
    });

    test('shows "今天" for events without explicit time', () {
      final due = ReminderScheduler.dueReminders(
        events: [_plan(id: 'plain', startAt: DateTime(2026, 4, 26))],
        now: now,
        alreadyReminded: const {},
      );

      expect(due.single.timeLabel, '今天');
    });

    test('reminds timed events within the due window', () {
      final events = [
        _plan(
          id: 'due_now',
          startAt: DateTime(2026, 4, 26, 9, 59, 30),
        ),
      ];

      final due = ReminderScheduler.dueReminders(
        events: events,
        now: DateTime(2026, 4, 26, 10, 0),
        alreadyReminded: const {},
      );

      expect(due, hasLength(1));
      expect(due.single.eventId, 'due_now');
    });

    test('pre-reminds timed events starting within the next 5 minutes', () {
      final events = [
        _plan(id: 'upcoming', startAt: DateTime(2026, 4, 26, 10, 3)),
      ];

      final due = ReminderScheduler.dueReminders(
        events: events,
        now: DateTime(2026, 4, 26, 10, 0),
        alreadyReminded: const {},
      );

      expect(due, hasLength(1));
      expect(due.single.eventId, 'upcoming');
    });

    test('skips timed events outside the due window', () {
      final events = [
        _plan(id: 'too_early', startAt: DateTime(2026, 4, 26, 8, 30)),
        _plan(id: 'too_late', startAt: DateTime(2026, 4, 26, 11, 30)),
      ];

      final due = ReminderScheduler.dueReminders(
        events: events,
        now: DateTime(2026, 4, 26, 10, 0),
        alreadyReminded: const {},
      );

      expect(due, isEmpty);
    });
  });
}
