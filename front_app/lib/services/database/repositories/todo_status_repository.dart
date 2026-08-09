import 'package:drift/drift.dart';

import '../../../core/models/app_models.dart';
import '../app_database.dart';

/// 单条事件的待办状态（与事件本体分离存储）。
class EventTodoState {
  const EventTodoState({
    required this.eventId,
    required this.isDone,
    required this.priority,
    this.completedAt,
  });

  final String eventId;
  final bool isDone;
  final TodoPriority priority;
  final DateTime? completedAt;

  EventTodoState copyWith({
    bool? isDone,
    TodoPriority? priority,
    DateTime? completedAt,
  }) {
    return EventTodoState(
      eventId: eventId,
      isDone: isDone ?? this.isDone,
      priority: priority ?? this.priority,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class TodoStatusRepository {
  const TodoStatusRepository(this._database);

  final AppDatabase _database;

  Future<Map<String, EventTodoState>> loadAll() async {
    final rows = await _database.select(_database.todoStatus).get();
    return {
      for (final row in rows)
        row.eventId: EventTodoState(
          eventId: row.eventId,
          isDone: row.isDone,
          priority: _priorityFromName(row.priority),
          completedAt: row.completedAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(row.completedAt!),
        ),
    };
  }

  Future<void> upsert(EventTodoState state) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database
        .into(_database.todoStatus)
        .insertOnConflictUpdate(
          TodoStatusCompanion.insert(
            eventId: state.eventId,
            isDone: Value(state.isDone),
            priority: Value(state.priority.name),
            completedAt: Value(state.completedAt?.millisecondsSinceEpoch),
            updatedAt: now,
          ),
        );
  }

  Future<void> deleteForEvents(List<String> eventIds) async {
    if (eventIds.isEmpty) {
      return;
    }
    await (_database.delete(
      _database.todoStatus,
    )..where((row) => row.eventId.isIn(eventIds))).go();
  }

  TodoPriority _priorityFromName(String name) {
    for (final value in TodoPriority.values) {
      if (value.name == name) {
        return value;
      }
    }
    return TodoPriority.none;
  }
}
