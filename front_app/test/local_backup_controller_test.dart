import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/storage/backup_manifest.dart';
import 'package:research_life/services/storage/backup_service.dart';
import 'package:research_life/state/local_backup_controller.dart';

void main() {
  group('LocalBackupController', () {
    test(
      'migration backup runs once and is marked only after validation',
      () async {
        final preferences = _FakeLocalMigrationPreferences();
        final backup = _FakeBackupService();
        var flushCount = 0;
        final controller = LocalBackupController(
          backupService: backup,
          migrationPreferences: preferences,
          flushLocalWrites: () async => flushCount += 1,
          restoreRuntime: (_) async => backup.fakeRestoreResult,
        );
        addTearDown(controller.dispose);

        await controller.ensureMigrationBackup();
        await controller.ensureMigrationBackup();

        expect(backup.createdPurposes, [BackupPurpose.migration]);
        expect(preferences.completed, isTrue);
        expect(preferences.backupPath, backup.lastCreatedDirectory.path);
        expect(flushCount, 1);
        expect(controller.busy, isFalse);
        expect(controller.messageIsError, isFalse);
        expect(controller.backups, hasLength(1));
        expect(backup.prunedPurposes, [
          {BackupPurpose.migration},
        ]);
        expect(backup.prunedProtectedPaths, [
          {backup.lastCreatedDirectory.absolute.path},
        ]);
      },
    );

    test('failed migration backup never marks migration complete', () async {
      final preferences = _FakeLocalMigrationPreferences();
      final backup = _FakeBackupService()..failCreate = true;
      final controller = LocalBackupController(
        backupService: backup,
        migrationPreferences: preferences,
        flushLocalWrites: () async {},
        restoreRuntime: (_) async => backup.fakeRestoreResult,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.ensureMigrationBackup(),
        throwsA(isA<BackupException>()),
      );

      expect(preferences.completed, isFalse);
      expect(preferences.backupPath, isNull);
      expect(controller.busy, isFalse);
      expect(controller.messageIsError, isTrue);
    });

    test('failed validation never marks migration complete', () async {
      final preferences = _FakeLocalMigrationPreferences();
      final backup = _FakeBackupService()..failValidation = true;
      final controller = LocalBackupController(
        backupService: backup,
        migrationPreferences: preferences,
        flushLocalWrites: () async {},
        restoreRuntime: (_) async => backup.fakeRestoreResult,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.ensureMigrationBackup(),
        throwsA(isA<BackupValidationException>()),
      );

      expect(preferences.completed, isFalse);
      expect(preferences.backupPath, isNull);
    });

    test('failed preference write never marks migration complete', () async {
      final preferences = _FakeLocalMigrationPreferences()..failSave = true;
      final backup = _FakeBackupService();
      final controller = LocalBackupController(
        backupService: backup,
        migrationPreferences: preferences,
        flushLocalWrites: () async {},
        restoreRuntime: (_) async => backup.fakeRestoreResult,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.ensureMigrationBackup(),
        throwsA(isA<FileSystemException>()),
      );

      expect(preferences.completed, isFalse);
    });

    test(
      'stale completed record is invalidated before replacement creation',
      () async {
        final preferences = _FakeLocalMigrationPreferences()
          ..completed = true
          ..backupPath = r'C:\backups\missing-migration';
        final backup = _FakeBackupService()..failCreate = true;
        final controller = LocalBackupController(
          backupService: backup,
          migrationPreferences: preferences,
          flushLocalWrites: () async {},
          restoreRuntime: (_) async => backup.fakeRestoreResult,
        );
        addTearDown(controller.dispose);

        await expectLater(
          controller.ensureMigrationBackup(),
          throwsA(isA<BackupException>()),
        );

        expect(preferences.completed, isFalse);
        expect(preferences.backupPath, isNull);
      },
    );

    test('prune failure never marks migration complete', () async {
      final preferences = _FakeLocalMigrationPreferences();
      final backup = _FakeBackupService()..failPrune = true;
      final controller = LocalBackupController(
        backupService: backup,
        migrationPreferences: preferences,
        flushLocalWrites: () async {},
        restoreRuntime: (_) async => backup.fakeRestoreResult,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.ensureMigrationBackup(),
        throwsA(isA<BackupException>()),
      );

      expect(preferences.completed, isFalse);
      expect(preferences.backupPath, isNull);
    });

    test(
      'backup-list refresh failure never marks migration complete',
      () async {
        final preferences = _FakeLocalMigrationPreferences();
        final backup = _FakeBackupService()..failList = true;
        final controller = LocalBackupController(
          backupService: backup,
          migrationPreferences: preferences,
          flushLocalWrites: () async {},
          restoreRuntime: (_) async => backup.fakeRestoreResult,
        );
        addTearDown(controller.dispose);

        await expectLater(
          controller.ensureMigrationBackup(),
          throwsA(isA<BackupException>()),
        );

        expect(preferences.completed, isFalse);
        expect(preferences.backupPath, isNull);
      },
    );

    test(
      'post-retention validation failure never marks migration complete',
      () async {
        final preferences = _FakeLocalMigrationPreferences();
        final backup = _FakeBackupService()..failValidationOnCall = 2;
        final controller = LocalBackupController(
          backupService: backup,
          migrationPreferences: preferences,
          flushLocalWrites: () async {},
          restoreRuntime: (_) async => backup.fakeRestoreResult,
        );
        addTearDown(controller.dispose);

        await expectLater(
          controller.ensureMigrationBackup(),
          throwsA(isA<BackupValidationException>()),
        );

        expect(backup.validationCalls, 2);
        expect(preferences.completed, isFalse);
        expect(preferences.backupPath, isNull);
      },
    );

    test('migration record persists an absolute backup path', () async {
      final preferences = _FakeLocalMigrationPreferences();
      final backup = _FakeBackupService()..useRelativeDirectories = true;
      final controller = LocalBackupController(
        backupService: backup,
        migrationPreferences: preferences,
        flushLocalWrites: () async {},
        restoreRuntime: (_) async => backup.fakeRestoreResult,
      );
      addTearDown(controller.dispose);

      await controller.ensureMigrationBackup();

      expect(Directory(preferences.backupPath!).isAbsolute, isTrue);
    });

    test(
      'manual backup flushes writes and refreshes the visible list',
      () async {
        final backup = _FakeBackupService();
        var flushCount = 0;
        final controller = LocalBackupController(
          backupService: backup,
          migrationPreferences: _FakeLocalMigrationPreferences(),
          flushLocalWrites: () async => flushCount += 1,
          restoreRuntime: (_) async => backup.fakeRestoreResult,
        );
        addTearDown(controller.dispose);

        final result = await controller.createManualBackup();

        expect(result.purpose, BackupPurpose.manual);
        expect(backup.createdPurposes, [BackupPurpose.manual]);
        expect(flushCount, 1);
        expect(controller.backups.single.directory.path, result.directory.path);
        expect(controller.messageIsError, isFalse);
      },
    );

    test(
      'restore validates, flushes, and delegates runtime replacement',
      () async {
        final backup = _FakeBackupService();
        final source = await backup.createBackup();
        var flushCount = 0;
        Directory? restoredDirectory;
        final controller = LocalBackupController(
          backupService: backup,
          migrationPreferences: _FakeLocalMigrationPreferences(),
          flushLocalWrites: () async => flushCount += 1,
          restoreRuntime: (directory) async {
            restoredDirectory = directory;
            return backup.fakeRestoreResult;
          },
        );
        addTearDown(controller.dispose);

        final result = await controller.restore(source.directory);

        expect(restoredDirectory?.path, source.directory.path);
        expect(result.restoredBackupDirectory.path, 'C:\\backups\\restored');
        expect(flushCount, 1);
        expect(controller.busy, isFalse);
      },
    );

    test(
      'restore callback may dispose the old controller and close its service',
      () async {
        final backup = _FakeBackupService();
        final source = await backup.createBackup();
        late LocalBackupController controller;
        controller = LocalBackupController(
          backupService: backup,
          migrationPreferences: _FakeLocalMigrationPreferences(),
          flushLocalWrites: () async {},
          restoreRuntime: (_) async {
            controller.dispose();
            backup.closed = true;
            return backup.fakeRestoreResult;
          },
        );

        final result = await controller.restore(source.directory);

        expect(result.restoredBackupDirectory.path, r'C:\backups\restored');
        expect(backup.listCallsAfterClose, 0);
      },
    );

    test('rejects a second backup operation while one is active', () async {
      final backup = _FakeBackupService();
      final gate = Completer<void>();
      backup.createGate = gate;
      final controller = LocalBackupController(
        backupService: backup,
        migrationPreferences: _FakeLocalMigrationPreferences(),
        flushLocalWrites: () async {},
        restoreRuntime: (_) async => backup.fakeRestoreResult,
      );
      addTearDown(controller.dispose);

      final first = controller.createManualBackup();
      await Future<void>.delayed(Duration.zero);

      expect(controller.busy, isTrue);
      await expectLater(
        controller.createManualBackup(),
        throwsA(isA<BackupException>()),
      );
      gate.complete();
      await first;
      expect(controller.busy, isFalse);
    });

    test(
      'completed migration check is serialized behind an active operation',
      () async {
        final backup = _FakeBackupService();
        final migration = await backup.createBackup(
          purpose: BackupPurpose.migration,
        );
        final preferences = _FakeLocalMigrationPreferences()
          ..completed = true
          ..backupPath = migration.directory.path;
        final gate = Completer<void>();
        backup.createGate = gate;
        final controller = LocalBackupController(
          backupService: backup,
          migrationPreferences: preferences,
          flushLocalWrites: () async {},
          restoreRuntime: (_) async => backup.fakeRestoreResult,
        );
        addTearDown(controller.dispose);

        final active = controller.createManualBackup();
        await Future<void>.delayed(Duration.zero);
        final loadsBefore = preferences.loadCount;

        await expectLater(
          controller.ensureMigrationBackup(),
          throwsA(isA<BackupException>()),
        );
        expect(preferences.loadCount, loadsBefore);

        gate.complete();
        await active;
      },
    );
  });
}

class _FakeLocalMigrationPreferences implements LocalMigrationPreferences {
  bool completed = false;
  String? backupPath;
  bool failSave = false;
  int loadCount = 0;

  @override
  Future<bool> loadLocalMigrationBackupComplete() async {
    loadCount += 1;
    return completed;
  }

  @override
  Future<String?> loadLocalMigrationBackupPath() async {
    loadCount += 1;
    return backupPath;
  }

  @override
  Future<void> saveLocalMigrationBackupRecord(String path) async {
    if (failSave) {
      backupPath = path;
      throw const FileSystemException('preference write failed');
    }
    backupPath = path;
    completed = true;
  }

  @override
  Future<void> invalidateLocalMigrationBackupRecord() async {
    completed = false;
    backupPath = null;
  }
}

class _FakeBackupService extends Fake implements BackupService {
  final List<BackupPurpose> createdPurposes = [];
  final List<Set<BackupPurpose>?> prunedPurposes = [];
  final List<Set<String>> prunedProtectedPaths = [];
  final List<BackupCreateResult> _backups = [];
  bool failCreate = false;
  bool failValidation = false;
  int? failValidationOnCall;
  int validationCalls = 0;
  bool failPrune = false;
  bool failList = false;
  bool useRelativeDirectories = false;
  bool closed = false;
  int listCallsAfterClose = 0;
  Completer<void>? createGate;

  Directory get lastCreatedDirectory => _backups.last.directory;

  BackupRestoreResult get fakeRestoreResult => BackupRestoreResult(
    restoredBackupDirectory: Directory('C:\\backups\\restored'),
    safetyBackup: _backups.isEmpty
        ? _result(BackupPurpose.safety, 0)
        : _backups.last,
  );

  @override
  Future<BackupCreateResult> createBackup({
    BackupPurpose purpose = BackupPurpose.manual,
  }) async {
    if (failCreate) {
      throw const BackupException('create failed');
    }
    await createGate?.future;
    createdPurposes.add(purpose);
    final result = _result(purpose, _backups.length + 1);
    _backups.add(result);
    return result;
  }

  @override
  Future<BackupManifest> validateBackup(Directory backupDirectory) async {
    validationCalls += 1;
    if (failValidation || validationCalls == failValidationOnCall) {
      throw const BackupValidationException('validation failed');
    }
    for (final backup in _backups) {
      if (backup.directory.path == backupDirectory.path) {
        return backup.manifest;
      }
    }
    throw const BackupValidationException('backup not found');
  }

  @override
  Future<List<BackupCreateResult>> listBackups() async {
    if (closed) {
      listCallsAfterClose += 1;
      throw const BackupException('backup service is closed');
    }
    if (failList) {
      throw const BackupException('list failed');
    }
    return List.unmodifiable(_backups.reversed);
  }

  @override
  Future<int> pruneBackups({
    int keep = 10,
    Set<BackupPurpose>? purposes,
    Set<String> protectedPaths = const {},
  }) async {
    if (failPrune) {
      throw const BackupException('prune failed');
    }
    prunedPurposes.add(purposes);
    prunedProtectedPaths.add(protectedPaths);
    return 0;
  }

  BackupCreateResult _result(BackupPurpose purpose, int index) {
    final directory = useRelativeDirectories
        ? Directory('relative_backup_$index')
        : Directory('C:\\backups\\backup_$index');
    final manifest = BackupManifest(
      purpose: purpose,
      appVersion: 'test',
      createdAt: DateTime(2026, 8, 9, 10, 0, index),
      schemaVersion: 1,
      workspacePath: 'C:\\workspace',
      databaseFile: const BackupFileInfo(
        path: 'research_life.sqlite',
        sha256: 'database-sha',
        sizeBytes: 1,
      ),
      preferencesFile: const BackupFileInfo(
        path: 'preferences.json',
        sha256: 'preferences-sha',
        sizeBytes: 1,
      ),
    );
    return BackupCreateResult(
      directory: directory,
      manifest: manifest,
      purpose: purpose,
    );
  }
}
