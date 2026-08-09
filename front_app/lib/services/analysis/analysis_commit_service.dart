import '../../core/models/app_models.dart';
import '../database/repositories/sessions_repository.dart';
import '../review/review_service.dart';

class AnalysisCommitService {
  const AnalysisCommitService({
    ReviewService reviewService = const ReviewService(),
    SessionsRepository? sessionsRepository,
  }) : _reviewService = reviewService,
       _sessionsRepository = sessionsRepository;

  final ReviewService _reviewService;
  final SessionsRepository? _sessionsRepository;

  SessionRecord buildSession({
    required String id,
    required String title,
    required AnalysisInput input,
    required AnalysisDraft draft,
    required ReviewPreview preview,
    required String sessionKey,
    required DateTime confirmedAt,
    String? sourceLabel,
  }) {
    final sessionDraft = _buildSessionDraft(draft, sessionKey);
    final sessionPreview = sessionDraft.id == draft.id
        ? preview
        : _reviewService.buildPreview(sessionDraft);
    final events = _buildEventsFromDraft(sessionDraft, sourceLabel);
    final people = _buildPeopleFromDraft(sessionDraft);

    return SessionRecord(
      id: id,
      title: title,
      input: input,
      draft: sessionDraft,
      preview: sessionPreview,
      events: events,
      people: people,
      confirmedAt: confirmedAt,
    );
  }

  Future<void> saveSession(SessionRecord session) async {
    await _sessionsRepository?.saveSession(session);
  }

  Future<void> deleteSession(String sessionId) async {
    await _sessionsRepository?.deleteSession(sessionId);
  }

  List<EventItem> _buildEventsFromDraft(
    AnalysisDraft draft,
    String? sourceLabel,
  ) {
    final anchor = draft.createdAt;
    return List<EventItem>.generate(draft.tasks.length, (index) {
      final task = draft.tasks[index];
      final startDate = _resolveDate(task, anchor, index);
      final endDate = _resolveEndDate(task, anchor, startDate);
      return EventItem(
        id: 'event_${draft.id}_$index',
        title: task.content,
        category: task.category,
        type: task.type,
        startAt: startDate,
        endAt: endDate,
        origin: EventOrigin.analysis,
        personNames: task.relatedPersonNames,
        sourceLabel: sourceLabel,
      );
    });
  }

  List<PersonProfile> _buildPeopleFromDraft(AnalysisDraft draft) {
    return draft.persons.map((person) {
      final relatedPlans = person.relatedTaskIndexes
          .where((index) => index < draft.tasks.length)
          .map((index) => draft.tasks[index])
          .where((task) => task.type == EventType.plan)
          .map((task) => task.content)
          .toList();

      return PersonProfile(
        id: person.id,
        name: person.name,
        role: person.role,
        aliases: person.aliases,
        relatedTaskCount: person.relatedTaskIndexes.length,
        relatedPlanTitles: relatedPlans,
      );
    }).toList();
  }

  AnalysisDraft _buildSessionDraft(AnalysisDraft draft, String sessionKey) {
    final updatedPeople = draft.persons
        .map(
          (person) =>
              person.copyWith(id: 'session_${sessionKey}__${person.id}'),
        )
        .toList();
    return draft.copyWith(id: 'draft_$sessionKey', persons: updatedPeople);
  }

  DateTime _resolveDate(ExtractedTaskDraft task, DateTime anchor, int index) {
    if (task.type == EventType.plan) {
      final hint = task.timeHint;
      if (hint != null) {
        final weekday = switch (hint) {
          '下周一' || '周一' => DateTime.monday,
          '下周二' || '周二' => DateTime.tuesday,
          '下周三' || '周三' => DateTime.wednesday,
          '下周四' || '周四' => DateTime.thursday,
          '下周五' || '周五' => DateTime.friday,
          '下周六' || '周六' => DateTime.saturday,
          '下周日' || '下周末' || '周日' || '周末' => DateTime.sunday,
          _ => null,
        };
        final isNextWeekHint = hint.startsWith('下周');

        if (weekday != null) {
          return isNextWeekHint
              ? _nextWeekSpecificWeekday(anchor, weekday)
              : _nextWeekday(anchor, weekday);
        }
        if (hint == '明天') {
          return anchor.add(const Duration(days: 1));
        }
        if (hint == '后天') {
          return anchor.add(const Duration(days: 2));
        }
        if (hint == '下周') {
          return anchor.add(const Duration(days: 7));
        }
      }

      return anchor.add(Duration(days: index + 1));
    }

    if (task.timeHint == '本周' || task.timeHint == '这周') {
      return _weekStart(anchor);
    }

    return anchor.subtract(Duration(days: index % 5));
  }

  DateTime _resolveEndDate(
    ExtractedTaskDraft task,
    DateTime anchor,
    DateTime startDate,
  ) {
    if (task.type == EventType.record &&
        (task.timeHint == '本周' || task.timeHint == '这周')) {
      return _dateOnly(anchor);
    }
    return startDate;
  }

  DateTime _weekStart(DateTime date) {
    return _dateOnly(
      date,
    ).subtract(Duration(days: date.weekday - DateTime.monday));
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _nextWeekday(DateTime from, int targetWeekday) {
    var candidate = from.add(const Duration(days: 1));
    while (candidate.weekday != targetWeekday) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return DateTime(candidate.year, candidate.month, candidate.day, 14);
  }

  DateTime _nextWeekSpecificWeekday(DateTime from, int targetWeekday) {
    final startOfDay = DateTime(from.year, from.month, from.day);
    final currentWeekMonday = startOfDay.subtract(
      Duration(days: startOfDay.weekday - DateTime.monday),
    );
    final nextWeekMonday = currentWeekMonday.add(const Duration(days: 7));
    final targetDate = nextWeekMonday.add(
      Duration(days: targetWeekday - DateTime.monday),
    );
    return DateTime(targetDate.year, targetDate.month, targetDate.day, 14);
  }
}
