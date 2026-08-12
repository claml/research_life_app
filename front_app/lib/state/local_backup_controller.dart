import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/database/repositories/preferences_repository.dart';
import '../services/storage/backup_manifest.dart';
import '../services/storage/backup_service.dart';

typedef RuntimeRestore =
    Future<BackupRestoreResult> Function(Directory backupDirectory);

class LocalBackupController extends ChangeNotifier {
  LocalBackupController({
    required BackupService backupService,
    required LocalMigrationPreferences migrationPreferences,
    required Future<void> Function() flushLocalWrites,
    required RuntimeRestore restoreRuntime,
  }) : _backupService = backupService,
       _migrationPreferences = migrationPreferences,
       _flushLocalWrites = flushLocalWrites,
       _restoreRuntime = restoreRuntime;

  final BackupService _backupService;
  final LocalMigrationPreferences _migrationPreferences;
  final Future<void> Function() _flushLocalWrites;
  final RuntimeRestore _restoreRuntime;

  bool _busy = false;
  bool _disposed = false;
  String? _message;
  bool _messageIsError = false;
  List<BackupCreateResult> _backups = const [];

  bool get busy => _busy;
  String? get message => _message;
  bool get messageIsError => _messageIsError;
  List<BackupCreateResult> get backups => List.unmodifiable(_backups);
  BackupCreateResult? get latestBackup =>
      _backups.isEmpty ? null : _backups.first;
  String? get backupDirectoryPath => latestBackup?.directory.parent.path;

  Future<BackupManifest> inspectBackup(Directory backupDirectory) {
    return _run<BackupManifest>(
      () => _backupService.validateBackup(backupDirectory),
      flushWrites: false,
    );
  }

  Future<void> openBackupDirectory() async {
    final path = backupDirectoryPath;
    if (path == null) {
      throw const BackupException('尚无可打开的备份目录。');
    }
    await Process.start('explorer.exe', [path]);
  }

  Future<void> ensureMigrationBackup() {
    return _run<void>(() async {
      final completed = await _migrationPreferences
          .loadLocalMigrationBackupComplete();
      final recordedPath = await _migrationPreferences
          .loadLocalMigrationBackupPath();
      if (completed && recordedPath != null && recordedPath.trim().isNotEmpty) {
        try {
          final manifest = await _backupService.validateBackup(
            Directory(recordedPath),
          );
          if (manifest.purpose == BackupPurpose.migration) {
            await _refreshBackups(notify: false);
            return;
          }
        } on BackupException {
          // A missing or damaged recorded backup must be replaced before local
          // migration is considered safe again.
        } on FileSystemException {
          // Treat an unreadable recorded path as incomplete migration safety.
        }
      }

      if (completed || recordedPath != null) {
        await _migrationPreferences.invalidateLocalMigrationBackupRecord();
      }

      await _flushLocalWrites();
      final created = await _backupService.createBackup(
        purpose: BackupPurpose.migration,
      );
      final validated = await _backupService.validateBackup(created.directory);
      if (validated.purpose != BackupPurpose.migration) {
        throw const BackupValidationException('迁移安全备份用途校验失败。');
      }
      await _backupService.pruneBackups(
        keep: 10,
        purposes: const {BackupPurpose.migration},
        protectedPaths: {created.directory.absolute.path},
      );
      await _refreshBackups(notify: false);
      final retained = await _backupService.validateBackup(created.directory);
      if (retained.purpose != BackupPurpose.migration) {
        throw const BackupValidationException('迁移安全备份保留校验失败。');
      }
      await _migrationPreferences.saveLocalMigrationBackupRecord(
        created.directory.absolute.path,
      );
      _message = '迁移安全备份已完成。';
      _messageIsError = false;
    }, flushWrites: false);
  }

  Future<BackupCreateResult> createManualBackup() {
    return _run<BackupCreateResult>(() async {
      final created = await _backupService.createBackup();
      await _refreshBackups(notify: false);
      _message = '备份已完成。';
      _messageIsError = false;
      return created;
    });
  }

  Future<BackupRestoreResult> restore(Directory backupDirectory) {
    return _run<BackupRestoreResult>(() async {
      await _backupService.validateBackup(backupDirectory);
      // Runtime replacement is a terminal handoff. The callback may dispose
      // this controller and close the service before its Future completes.
      return _restoreRuntime(backupDirectory);
    });
  }

  Future<void> refreshBackups() {
    return _run<void>(() => _refreshBackups(notify: false), flushWrites: false);
  }

  Future<void> _refreshBackups({bool notify = true}) async {
    _backups = await _backupService.listBackups();
    if (notify) {
      _notifyListenersIfActive();
    }
  }

  Future<T> _run<T>(
    Future<T> Function() action, {
    bool flushWrites = true,
  }) async {
    if (_busy) {
      throw const BackupException('已有备份或恢复任务正在进行。');
    }
    _busy = true;
    _message = null;
    _messageIsError = false;
    _notifyListenersIfActive();
    try {
      if (flushWrites) {
        await _flushLocalWrites();
      }
      return await action();
    } catch (error) {
      _message = '$error';
      _messageIsError = true;
      rethrow;
    } finally {
      _busy = false;
      _notifyListenersIfActive();
    }
  }

  void _notifyListenersIfActive() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
