import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/database/app_database.dart'
    hide CampusPlace;
import 'package:research_life/services/database/repositories/campus_places_repository.dart';
import 'package:research_life/services/database/repositories/notes_repository.dart';
import 'package:research_life/services/database/repositories/sessions_repository.dart';
import 'package:research_life/services/database/repositories/todo_status_repository.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';

void main() {
  test('structured repository writes wait behind the backup barrier', () async {
    final coordinator = LocalDataOperationCoordinator();
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final sessions = SessionsRepository(
      database,
      operationCoordinator: coordinator,
    );
    final todos = TodoStatusRepository(
      database,
      operationCoordinator: coordinator,
    );
    final notes = NotesRepository(database, operationCoordinator: coordinator);
    final places = CampusPlacesRepository(
      database,
      operationCoordinator: coordinator,
    );
    final backupStarted = Completer<void>();
    final releaseBackup = Completer<void>();
    final completed = <String>[];

    final backup = coordinator.runExclusive(() async {
      backupStarted.complete();
      await releaseBackup.future;
    });
    await backupStarted.future;

    final writes = <Future<void>>[
      sessions.deleteSession('missing').then((_) => completed.add('session')),
      todos
          .upsert(
            const EventTodoState(
              eventId: 'event-1',
              isDone: false,
              priority: TodoPriority.medium,
            ),
          )
          .then((_) => completed.add('todo')),
      notes
          .saveNote(
            UserNote(
              id: 'note-1',
              title: 'Barrier note',
              createdAt: DateTime(2026, 8, 12),
              updatedAt: DateTime(2026, 8, 12),
            ),
          )
          .then((_) => completed.add('note')),
      places
          .saveCampusPlaces([
            CampusPlace(
              id: 'place-1',
              name: 'Library',
              category: PlaceCategory.study,
              note: '',
              normalizedDx: 0.5,
              normalizedDy: 0.5,
              iconKey: 'book',
              colorKey: 'forest',
              createdAt: DateTime(2026, 8, 12),
              updatedAt: DateTime(2026, 8, 12),
            ),
          ])
          .then((_) => completed.add('place')),
    ];
    await Future<void>.delayed(Duration.zero);

    expect(completed, isEmpty);
    expect(await todos.loadAll(), isEmpty);
    expect(await notes.loadNotes(), isEmpty);
    expect(await places.loadCampusPlaces(), isEmpty);

    releaseBackup.complete();
    await Future.wait([backup, ...writes]);

    expect(completed, containsAll(['session', 'todo', 'note', 'place']));
    expect(await todos.loadAll(), contains('event-1'));
    expect(await notes.loadNotes(), hasLength(1));
    expect(await places.loadCampusPlaces(), hasLength(1));
  });
}
