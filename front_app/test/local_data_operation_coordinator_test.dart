import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';

void main() {
  test(
    'serializes concurrent local-data operations and permits re-entry',
    () async {
      final coordinator = LocalDataOperationCoordinator();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final events = <String>[];

      final first = coordinator.runExclusive(() async {
        events.add('first-start');
        firstStarted.complete();
        await releaseFirst.future;
        await coordinator.runExclusive(() async {
          events.add('nested');
        });
        events.add('first-end');
      });
      await firstStarted.future;
      final second = coordinator.runExclusive(() async {
        events.add('second');
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, ['first-start']);

      releaseFirst.complete();
      await Future.wait([first, second]);

      expect(events, ['first-start', 'nested', 'first-end', 'second']);
    },
  );

  test('structured writes wait behind a backup lease', () async {
    final coordinator = LocalDataOperationCoordinator();
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final preferences = PreferencesRepository(
      database,
      operationCoordinator: coordinator,
    );
    final backupStarted = Completer<void>();
    final releaseBackup = Completer<void>();
    var writeCompleted = false;

    final backup = coordinator.runExclusive(() async {
      backupStarted.complete();
      await releaseBackup.future;
    });
    await backupStarted.future;
    final write = preferences.saveColorTheme('green').then((_) {
      writeCompleted = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(writeCompleted, isFalse);
    expect(await preferences.loadColorTheme(), isNull);

    releaseBackup.complete();
    await Future.wait([backup, write]);
    expect(await preferences.loadColorTheme(), 'green');
  });

  test(
    'migration marker transaction stays wholly behind a backup lease',
    () async {
      final coordinator = LocalDataOperationCoordinator();
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final preferences = PreferencesRepository(
        database,
        operationCoordinator: coordinator,
      );
      final backupStarted = Completer<void>();
      final releaseBackup = Completer<void>();

      final backup = coordinator.runExclusive(() async {
        backupStarted.complete();
        await releaseBackup.future;
      });
      await backupStarted.future;
      final markerWrite = preferences.saveLocalMigrationBackupRecord('backup');
      await Future<void>.delayed(Duration.zero);

      expect(await preferences.loadLocalMigrationBackupComplete(), isFalse);
      expect(await preferences.loadLocalMigrationBackupPath(), isNull);

      releaseBackup.complete();
      await Future.wait([backup, markerWrite]);
      expect(await preferences.loadLocalMigrationBackupComplete(), isTrue);
      expect(await preferences.loadLocalMigrationBackupPath(), 'backup');
    },
  );

  test(
    'separate coordinators serialize through the same OS lock file',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'research_life_os_data_lock',
      );
      addTearDown(() => root.delete(recursive: true));
      final lockFile = File(
        '${root.path}${Platform.pathSeparator}.local_data.lock',
      );
      final firstCoordinator = LocalDataOperationCoordinator(
        lockFileResolver: () async => lockFile,
      );
      final secondCoordinator = LocalDataOperationCoordinator(
        lockFileResolver: () async => lockFile,
      );
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var secondStarted = false;

      final first = firstCoordinator.runExclusive(() async {
        firstStarted.complete();
        await releaseFirst.future;
      });
      await firstStarted.future;
      final second = secondCoordinator.runExclusive(() async {
        secondStarted = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(secondStarted, isFalse);

      releaseFirst.complete();
      await Future.wait([first, second]);
      expect(secondStarted, isTrue);
    },
  );
}
