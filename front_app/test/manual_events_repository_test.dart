import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/manual_events_repository.dart';
import 'package:research_life/services/database/repositories/todo_status_repository.dart';

void main() {
  late AppDatabase database;
  late ManualEventsRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = ManualEventsRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('saves and loads manual events', () async {
    final event = EventItem(
      id: 'manual_1',
      title: 'Write weekly report',
      category: ItemCategory.work,
      type: EventType.plan,
      startAt: DateTime(2026, 4, 26),
      endAt: DateTime(2026, 4, 26),
      origin: EventOrigin.manual,
      sourceLabel: '手动添加',
    );

    await repository.saveManualEvent(event);

    final loaded = await repository.loadManualEvents();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, event.id);
    expect(loaded.single.title, event.title);
    expect(loaded.single.category, event.category);
    expect(loaded.single.type, event.type);
    expect(loaded.single.origin, EventOrigin.manual);
  });

  test('updates an existing manual event by id', () async {
    final event = EventItem(
      id: 'manual_1',
      title: 'Write weekly report',
      category: ItemCategory.work,
      type: EventType.plan,
      startAt: DateTime(2026, 4, 26),
      endAt: DateTime(2026, 4, 26),
      origin: EventOrigin.manual,
      sourceLabel: '手动添加',
    );

    await repository.saveManualEvent(event);
    await repository.saveManualEvent(
      event.copyWith(
        title: 'Submit weekly report',
        category: ItemCategory.study,
        type: EventType.record,
      ),
    );

    final loaded = await repository.loadManualEvents();

    expect(loaded, hasLength(1));
    expect(loaded.single.title, 'Submit weekly report');
    expect(loaded.single.category, ItemCategory.study);
    expect(loaded.single.type, EventType.record);
  });

  test('deletes a manual event and its todo state atomically', () async {
    final event = EventItem(
      id: 'manual_delete_1',
      title: 'Delete draft task',
      category: ItemCategory.work,
      type: EventType.plan,
      startAt: DateTime(2026, 4, 27),
      endAt: DateTime(2026, 4, 27),
      origin: EventOrigin.manual,
      sourceLabel: '手动添加',
    );
    final todoRepository = TodoStatusRepository(database);
    await repository.saveManualEvent(event);
    await todoRepository.upsert(
      const EventTodoState(
        eventId: 'manual_delete_1',
        isDone: true,
        priority: TodoPriority.high,
      ),
    );

    await repository.deleteManualEvent(event.id);

    expect(await repository.loadManualEvents(), isEmpty);
    expect(await todoRepository.loadAll(), isNot(contains(event.id)));
  });
}
