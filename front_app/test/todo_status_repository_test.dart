import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/todo_status_repository.dart';

void main() {
  late AppDatabase database;
  late TodoStatusRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = TodoStatusRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('loads empty map when no status rows exist', () async {
    final loaded = await repository.loadAll();

    expect(loaded, isEmpty);
  });

  test('upserts and loads a todo status', () async {
    final state = EventTodoState(
      eventId: 'event_1',
      isDone: true,
      priority: TodoPriority.high,
      completedAt: DateTime(2026, 4, 26, 10),
    );

    await repository.upsert(state);

    final loaded = await repository.loadAll();

    expect(loaded, hasLength(1));
    final restored = loaded['event_1']!;
    expect(restored.eventId, 'event_1');
    expect(restored.isDone, isTrue);
    expect(restored.priority, TodoPriority.high);
    expect(restored.completedAt, DateTime(2026, 4, 26, 10));
  });

  test('upserting same event id overwrites previous state', () async {
    await repository.upsert(
      const EventTodoState(
        eventId: 'event_1',
        isDone: false,
        priority: TodoPriority.none,
      ),
    );
    await repository.upsert(
      const EventTodoState(
        eventId: 'event_1',
        isDone: true,
        priority: TodoPriority.medium,
      ),
    );

    final loaded = await repository.loadAll();

    expect(loaded, hasLength(1));
    expect(loaded['event_1']!.isDone, isTrue);
    expect(loaded['event_1']!.priority, TodoPriority.medium);
  });

  test('deletes status rows for the given event ids only', () async {
    await repository.upsert(
      const EventTodoState(
        eventId: 'event_1',
        isDone: true,
        priority: TodoPriority.high,
      ),
    );
    await repository.upsert(
      const EventTodoState(
        eventId: 'event_2',
        isDone: false,
        priority: TodoPriority.low,
      ),
    );

    await repository.deleteForEvents(['event_1']);

    final loaded = await repository.loadAll();
    expect(loaded.keys, ['event_2']);
  });

  test('delete with empty list is a no-op', () async {
    await repository.deleteForEvents(const []);

    expect(await repository.loadAll(), isEmpty);
  });
}
