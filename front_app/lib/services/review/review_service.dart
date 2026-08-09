import '../../core/models/app_models.dart';

class ReviewService {
  const ReviewService();

  ReviewPreview buildPreview(AnalysisDraft draft) {
    final completedTasks = draft.tasks
        .where((task) => task.type == EventType.record)
        .toList();
    final plannedTasks = draft.tasks
        .where((task) => task.type == EventType.plan)
        .toList();
    final relationLabels = draft.persons
        .map((person) => person.role.label)
        .toSet()
        .toList();

    return ReviewPreview(
      id: 'preview_${draft.id}',
      completedTasks: completedTasks,
      plannedTasks: plannedTasks,
      persons: draft.persons,
      summary: draft.summary,
      warnings: draft.warnings,
      relationLabels: relationLabels,
    );
  }
}
