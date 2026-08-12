import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../database/app_database.dart';
import '../database/repositories/preferences_repository.dart';
import 'backup_manifest.dart';
import 'local_data_operation_coordinator.dart';
import 'local_workspace_service.dart';

class BackupService {
  BackupService({
    required LocalWorkspaceService workspaceService,
    this.appVersion = '0.1.0+1',
    this.schemaVersion = AppDatabase.currentSchemaVersion,
    DateTime Function()? clock,
    LocalDataOperationCoordinator? operationCoordinator,
    Future<void> Function(FileSystemEntity entity)? rollbackArtifactCleaner,
    Future<void> Function(FileSystemEntity entity)? beforeMoveAside,
    Future<void> Function(File source, File target)? beforeRestoreCopy,
    Future<void> Function(File target)? rollbackTargetCleaner,
  }) : _workspaceService = workspaceService,
       _clock = clock,
       _operationCoordinator =
           operationCoordinator ?? LocalDataOperationCoordinator(),
       _rollbackArtifactCleaner = rollbackArtifactCleaner,
       _beforeMoveAside = beforeMoveAside,
       _beforeRestoreCopy = beforeRestoreCopy,
       _rollbackTargetCleaner = rollbackTargetCleaner;

  final LocalWorkspaceService _workspaceService;
  final String appVersion;
  final int schemaVersion;
  final DateTime Function()? _clock;
  final LocalDataOperationCoordinator _operationCoordinator;
  final Future<void> Function(FileSystemEntity entity)?
  _rollbackArtifactCleaner;
  final Future<void> Function(FileSystemEntity entity)? _beforeMoveAside;
  final Future<void> Function(File source, File target)? _beforeRestoreCopy;
  final Future<void> Function(File target)? _rollbackTargetCleaner;

  Future<BackupCreateResult> createBackup({
    BackupPurpose purpose = BackupPurpose.manual,
  }) {
    return _operationCoordinator.runExclusive(
      () => _createBackup(
        createdAt: _now(),
        requireDatabase: true,
        purpose: purpose,
      ),
    );
  }

  Future<List<BackupCreateResult>> listBackups() async {
    final backupsDirectory = await _workspaceService.resolveBackupsDirectory();
    final backups = <BackupCreateResult>[];
    await for (final entity in backupsDirectory.list(followLinks: false)) {
      if (entity is! Directory ||
          _pathName(entity.path).startsWith('.pending-')) {
        continue;
      }
      try {
        final manifest = await validateBackup(entity);
        backups.add(
          BackupCreateResult(
            directory: entity,
            manifest: manifest,
            purpose: manifest.purpose,
          ),
        );
      } on BackupException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    backups.sort((left, right) {
      final byCreatedAt = right.manifest.createdAt.compareTo(
        left.manifest.createdAt,
      );
      if (byCreatedAt != 0) {
        return byCreatedAt;
      }
      return right.directory.path.compareTo(left.directory.path);
    });
    return backups;
  }

  Future<int> pruneBackups({
    int keep = 10,
    Set<BackupPurpose>? purposes,
    Set<String> protectedPaths = const {},
  }) async {
    if (keep < 1) {
      throw ArgumentError.value(keep, 'keep');
    }
    final backups = await listBackups();
    final candidates =
        (purposes == null
                ? backups
                : backups.where((backup) => purposes.contains(backup.purpose)))
            .toList();
    final normalizedProtectedPaths = protectedPaths
        .map(_normalizedDirectoryPath)
        .toSet();
    final protected = candidates
        .where(
          (backup) => normalizedProtectedPaths.contains(
            _normalizedDirectoryPath(backup.directory.path),
          ),
        )
        .toList();
    if (protected.length > keep) {
      throw ArgumentError.value(
        protectedPaths,
        'protectedPaths',
        'Matched protected backups cannot exceed keep.',
      );
    }
    final unprotected = candidates
        .where(
          (backup) => !normalizedProtectedPaths.contains(
            _normalizedDirectoryPath(backup.directory.path),
          ),
        )
        .toList();
    final unprotectedToKeep = keep > protected.length
        ? keep - protected.length
        : 0;
    var removed = 0;
    for (final backup in unprotected.skip(unprotectedToKeep)) {
      await backup.directory.delete(recursive: true);
      removed += 1;
    }
    return removed;
  }

  String _normalizedDirectoryPath(String path) {
    final absolute = Directory(path).absolute.path;
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }

  Future<BackupManifest> validateBackup(Directory backupDirectory) async {
    final manifestFile = File(
      '${backupDirectory.path}${Platform.pathSeparator}backup_manifest.json',
    );
    if (!await manifestFile.exists()) {
      throw BackupValidationException('备份缺少 backup_manifest.json。');
    }

    final manifest = await _readBackupManifest(manifestFile);
    if (manifest.manifestVersion != BackupManifest.currentManifestVersion) {
      throw BackupValidationException(
        '不支持的备份 manifestVersion：${manifest.manifestVersion}。',
      );
    }
    if (manifest.schemaVersion > schemaVersion) {
      throw BackupValidationException(
        '备份数据库版本 ${manifest.schemaVersion} 高于当前支持版本 $schemaVersion。',
      );
    }

    await _validateFileInfo(backupDirectory, manifest.databaseFile);
    await _validateDatabaseSchema(backupDirectory, manifest);
    await _validateFileInfo(backupDirectory, manifest.preferencesFile);
    final workspaceManifestFile = manifest.workspaceManifestFile;
    if (workspaceManifestFile != null) {
      await _validateFileInfo(backupDirectory, workspaceManifestFile);
    }
    final localFileLibraryFiles = manifest.localFileLibraryFiles;
    if (localFileLibraryFiles != null) {
      for (final fileInfo in localFileLibraryFiles) {
        _localFileLibraryRelativePath(fileInfo.path);
        await _validateFileInfo(backupDirectory, fileInfo);
      }
      await _validateManagedFileReferences(
        backupDirectory,
        localFileLibraryFiles,
      );
    }
    return manifest;
  }

  Future<void> _validateManagedFileReferences(
    Directory backupDirectory,
    List<BackupFileInfo> localFiles,
  ) async {
    const manifestPath = 'local_files/library_manifest.json';
    if (!localFiles.any((info) => info.path == manifestPath)) {
      return;
    }
    final manifestFile = _fileInBackup(backupDirectory, manifestPath);
    try {
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map || decoded['documents'] is! List) {
        throw const FormatException('library manifest is invalid');
      }
      final copiedPaths = localFiles.map((info) => info.path).toSet();
      for (final raw in (decoded['documents'] as List).whereType<Map>()) {
        if (raw['isDeleted'] == true || raw['cloudOnly'] == true) {
          continue;
        }
        final storedPath = '${raw['path'] ?? ''}'.replaceAll('\\', '/');
        if (storedPath.isEmpty) {
          throw const BackupValidationException('资料清单包含没有文件路径的活动记录');
        }
        final isAbsoluteWindowsPath = RegExp(
          r'^[A-Za-z]:/',
        ).hasMatch(storedPath);
        if (storedPath.startsWith('/') || isAbsoluteWindowsPath) {
          throw BackupValidationException('资料清单仍包含工作区外的绝对路径：$storedPath');
        }
        if (!storedPath.startsWith('payloads/') ||
            storedPath.split('/').contains('..')) {
          throw BackupValidationException('资料清单路径非法：$storedPath');
        }
        final expectedBackupPath = 'local_files/$storedPath';
        if (!copiedPaths.contains(expectedBackupPath)) {
          throw BackupValidationException('备份缺少资料实体文件：$expectedBackupPath');
        }
      }
    } on FormatException catch (error) {
      throw BackupValidationException('资料清单无效：${error.message}');
    }
  }

  Future<BackupRestoreResult> restoreBackup(Directory backupDirectory) {
    return _operationCoordinator.runExclusive(
      () => _restoreBackup(backupDirectory),
    );
  }

  Future<BackupRestoreResult> _restoreBackup(Directory backupDirectory) async {
    final manifest = await validateBackup(backupDirectory);
    final safetyBackup = await _createBackup(
      createdAt: _now(),
      requireDatabase: true,
      purpose: BackupPurpose.safety,
    );
    await validateBackup(safetyBackup.directory);
    await pruneBackups(
      keep: 10,
      purposes: const {BackupPurpose.safety},
      protectedPaths: {
        safetyBackup.directory.absolute.path,
        backupDirectory.absolute.path,
      },
    );

    final workspaceDirectory = await _workspaceService
        .resolveStorageDirectory();
    final databaseFile = await _workspaceService.resolveDatabaseFile();
    final preferencesFile = await _workspaceService.resolvePreferencesFile();
    final workspaceManifestFile = await _workspaceService
        .resolveWorkspaceManifestFile();
    final localFileLibraryDirectory = await _workspaceService
        .resolveLocalFileLibraryDirectory(create: false);
    final restorePlan = <_RestoreItem>[
      _RestoreItem(
        source: _fileInBackup(backupDirectory, manifest.databaseFile.path),
        target: databaseFile,
      ),
      _RestoreItem(
        source: _fileInBackup(backupDirectory, manifest.preferencesFile.path),
        target: preferencesFile,
      ),
    ];

    final backupWorkspaceManifest = manifest.workspaceManifestFile;
    if (backupWorkspaceManifest != null) {
      restorePlan.add(
        _RestoreItem(
          source: _fileInBackup(backupDirectory, backupWorkspaceManifest.path),
          target: workspaceManifestFile,
        ),
      );
    }

    final rollbackFiles = <_RollbackFile>[];
    _RollbackDirectory? localFileLibraryRollback;
    final installStartedTargets = <File>{};
    var localFileLibraryInstallStarted = false;
    try {
      await workspaceDirectory.create(recursive: true);
      final sidecars = [
        File('${databaseFile.path}-wal'),
        File('${databaseFile.path}-shm'),
      ];
      for (final sidecar in sidecars) {
        final rollback = await _moveExistingAside(sidecar);
        if (rollback != null) {
          rollbackFiles.add(rollback);
        }
      }

      for (final item in restorePlan) {
        final rollback = await _moveExistingAside(item.target);
        if (rollback != null) {
          rollbackFiles.add(rollback);
        }
      }

      final localFileLibraryFiles = manifest.localFileLibraryFiles;
      if (localFileLibraryFiles != null) {
        localFileLibraryRollback = await _moveExistingDirectoryAside(
          localFileLibraryDirectory,
        );
      }

      for (final item in restorePlan) {
        await item.target.parent.create(recursive: true);
        installStartedTargets.add(item.target);
        await _beforeRestoreCopy?.call(item.source, item.target);
        await item.source.copy(item.target.path);
      }

      if (localFileLibraryFiles != null) {
        localFileLibraryInstallStarted = true;
        await localFileLibraryDirectory.create(recursive: true);
        for (final fileInfo in localFileLibraryFiles) {
          final relativePath = _localFileLibraryRelativePath(fileInfo.path);
          final target = File(
            '${localFileLibraryDirectory.path}${Platform.pathSeparator}'
            '${relativePath.replaceAll('/', Platform.pathSeparator)}',
          );
          await target.parent.create(recursive: true);
          await _fileInBackup(backupDirectory, fileInfo.path).copy(target.path);
        }
      }
    } catch (error, stackTrace) {
      Object? rollbackFailure;
      StackTrace? rollbackStackTrace;
      void recordRollbackFailure(Object failure, StackTrace failureStack) {
        rollbackFailure ??= failure;
        rollbackStackTrace ??= failureStack;
      }

      for (final target in installStartedTargets) {
        try {
          final cleaner = _rollbackTargetCleaner;
          if (cleaner != null) {
            await cleaner(target);
          } else {
            await _deleteIfExists(target);
          }
        } catch (failure, failureStack) {
          recordRollbackFailure(failure, failureStack);
        }
      }
      if (localFileLibraryInstallStarted) {
        try {
          await _deleteDirectoryIfExists(localFileLibraryDirectory);
        } catch (failure, failureStack) {
          recordRollbackFailure(failure, failureStack);
        }
      }
      for (final rollback in rollbackFiles.reversed) {
        try {
          if (await rollback.rollback.exists()) {
            await rollback.rollback.rename(rollback.original.path);
          }
        } catch (failure, failureStack) {
          recordRollbackFailure(failure, failureStack);
        }
      }
      try {
        if (localFileLibraryRollback != null &&
            await localFileLibraryRollback.rollback.exists()) {
          await localFileLibraryRollback.rollback.rename(
            localFileLibraryRollback.original.path,
          );
        }
      } catch (failure, failureStack) {
        recordRollbackFailure(failure, failureStack);
      }
      final rollbackDetail = rollbackFailure == null
          ? ''
          : '；部分回滚失败：$rollbackFailure';
      Error.throwWithStackTrace(
        BackupRestoreException('恢复备份失败，已尝试回滚全部当前文件：$error$rollbackDetail'),
        rollbackFailure == null ? stackTrace : rollbackStackTrace!,
      );
    }

    // The new snapshot is committed once every target copy succeeds. Cleanup
    // is deliberately best-effort and outside the rollback catch: deleting
    // one rollback artifact must never make a later cleanup failure erase the
    // already committed restore.
    for (final rollback in rollbackFiles) {
      await _cleanupRollbackArtifact(rollback.rollback);
    }
    if (localFileLibraryRollback != null) {
      await _cleanupRollbackArtifact(localFileLibraryRollback.rollback);
    }

    return BackupRestoreResult(
      restoredBackupDirectory: backupDirectory,
      safetyBackup: safetyBackup,
    );
  }

  Future<BackupCreateResult> _createBackup({
    required DateTime createdAt,
    required bool requireDatabase,
    BackupPurpose purpose = BackupPurpose.manual,
  }) async {
    final workspaceDirectory = await _workspaceService
        .resolveStorageDirectory();
    final databaseFile = await _workspaceService.resolveDatabaseFile();
    final preferencesFile = await _workspaceService.resolvePreferencesFile();
    final workspaceManifestFile = await _workspaceService
        .resolveWorkspaceManifestFile();
    final localFileLibraryDirectory = await _workspaceService
        .resolveLocalFileLibraryDirectory(create: false);

    if (!await databaseFile.exists()) {
      if (requireDatabase) {
        throw BackupException('数据库文件还没有创建，暂无可备份内容。');
      }
    } else {
      await _checkpointSqliteWal(databaseFile);
    }

    if (!await preferencesFile.exists()) {
      await preferencesFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{}),
      );
    }

    final backupDirectory = await _createPendingBackupDirectory(createdAt);
    final databaseTarget = File(
      '${backupDirectory.path}${Platform.pathSeparator}research_life.sqlite',
    );
    final preferencesTarget = File(
      '${backupDirectory.path}${Platform.pathSeparator}preferences.json',
    );
    final workspaceManifestTarget = File(
      '${backupDirectory.path}${Platform.pathSeparator}workspace_manifest.json',
    );

    try {
      await databaseFile.copy(databaseTarget.path);
      await preferencesFile.copy(preferencesTarget.path);
      await _sanitizeBackupDatabase(databaseTarget);
      await _sanitizeBackupPreferences(preferencesTarget);

      BackupFileInfo? workspaceManifestInfo;
      if (await workspaceManifestFile.exists()) {
        await workspaceManifestFile.copy(workspaceManifestTarget.path);
        workspaceManifestInfo = await _fileInfo(
          workspaceManifestTarget,
          'workspace_manifest.json',
        );
      }
      final localFileLibraryFiles = await _copyDirectoryToBackup(
        source: localFileLibraryDirectory,
        backupDirectory: backupDirectory,
        relativeRoot: 'local_files',
      );

      final manifest = BackupManifest(
        purpose: purpose,
        appVersion: appVersion,
        createdAt: createdAt,
        schemaVersion: schemaVersion,
        workspacePath: workspaceDirectory.path,
        databaseFile: await _fileInfo(databaseTarget, 'research_life.sqlite'),
        preferencesFile: await _fileInfo(preferencesTarget, 'preferences.json'),
        workspaceManifestFile: workspaceManifestInfo,
        localFileLibraryFiles: localFileLibraryFiles,
      );
      final manifestFile = File(
        '${backupDirectory.path}${Platform.pathSeparator}backup_manifest.json',
      );
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      );
      await validateBackup(backupDirectory);
      final publishedDirectory = await _publishPendingDirectory(
        backupDirectory,
        createdAt,
      );

      return BackupCreateResult(
        directory: publishedDirectory,
        manifest: manifest,
        purpose: purpose,
      );
    } catch (error, stackTrace) {
      try {
        if (await backupDirectory.exists()) {
          await backupDirectory.delete(recursive: true);
        }
      } catch (_) {
        // Preserve the original backup failure. A stale pending directory is
        // ignored by listing and retention and can be inspected manually.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Directory> _createPendingBackupDirectory(DateTime createdAt) async {
    final backupsDirectory = await _workspaceService.resolveBackupsDirectory();
    final timestamp = _formatBackupTimestamp(createdAt);
    return backupsDirectory.createTemp('.pending-$timestamp-');
  }

  Future<Directory> _publishPendingDirectory(
    Directory pending,
    DateTime createdAt,
  ) async {
    final backupsDirectory = pending.parent;
    var candidateTime = createdAt;
    for (var attempts = 0; attempts < 10000; attempts += 1) {
      final timestamp = _formatBackupTimestamp(candidateTime);
      final published = Directory(
        '${backupsDirectory.path}${Platform.pathSeparator}'
        '$timestamp',
      );
      try {
        return await pending.rename(published.path);
      } on FileSystemException {
        if (!await published.exists()) {
          rethrow;
        }
      }
      candidateTime = candidateTime.add(const Duration(seconds: 1));
    }
    throw BackupException('无法创建可用备份目录。');
  }

  Future<BackupManifest> _readBackupManifest(File manifestFile) async {
    try {
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is Map<String, dynamic>) {
        return BackupManifest.fromJson(decoded);
      }
      if (decoded is Map) {
        return BackupManifest.fromJson(
          decoded.map((key, value) => MapEntry('$key', value)),
        );
      }
      throw const FormatException('backup_manifest.json 不是 JSON object。');
    } on FormatException catch (error) {
      throw BackupValidationException('备份 manifest 无效：${error.message}');
    }
  }

  Future<void> _validateFileInfo(
    Directory backupDirectory,
    BackupFileInfo info,
  ) async {
    final file = _fileInBackup(backupDirectory, info.path);
    if (!await file.exists()) {
      throw BackupValidationException('备份缺少文件：${info.path}');
    }

    final actualInfo = await _fileInfo(file, info.path);
    if (actualInfo.sizeBytes != info.sizeBytes) {
      throw BackupValidationException('备份文件大小校验失败：${info.path}');
    }
    if (actualInfo.sha256 != info.sha256) {
      throw BackupValidationException('备份文件 sha256 校验失败：${info.path}');
    }
  }

  Future<BackupFileInfo> _fileInfo(File file, String relativePath) async {
    final stat = await file.stat();
    return BackupFileInfo(
      path: relativePath,
      sha256: await _sha256(file),
      sizeBytes: stat.size,
    );
  }

  Future<List<BackupFileInfo>> _copyDirectoryToBackup({
    required Directory source,
    required Directory backupDirectory,
    required String relativeRoot,
  }) async {
    if (!await source.exists()) {
      return const [];
    }

    final copiedFiles = <BackupFileInfo>[];
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final childRelativePath = _relativePath(source, entity);
      final backupRelativePath = '$relativeRoot/$childRelativePath';
      final target = _fileInBackup(backupDirectory, backupRelativePath);
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
      copiedFiles.add(await _fileInfo(target, backupRelativePath));
    }
    copiedFiles.sort((a, b) => a.path.compareTo(b.path));
    return copiedFiles;
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<void> _validateDatabaseSchema(
    Directory backupDirectory,
    BackupManifest manifest,
  ) async {
    final databaseFile = _fileInBackup(
      backupDirectory,
      manifest.databaseFile.path,
    );
    try {
      final database = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
      try {
        final rows = database.select('PRAGMA user_version;');
        final actual = rows.isEmpty
            ? null
            : _intValue(rows.first['user_version']);
        if (actual != manifest.schemaVersion) {
          throw BackupValidationException(
            '备份数据库版本与清单不一致：数据库 $actual，清单 ${manifest.schemaVersion}。',
          );
        }
      } finally {
        database.close();
      }
    } on BackupValidationException {
      rethrow;
    } catch (error) {
      throw BackupValidationException('无法读取备份数据库版本：$error');
    }
  }

  Future<void> _sanitizeBackupDatabase(File databaseFile) async {
    final database = sqlite3.open(databaseFile.path);
    try {
      database.execute('PRAGMA secure_delete = ON;');
      final preferencesTable = database.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'preferences';",
      );
      if (preferencesTable.isEmpty) {
        return;
      }
      database.execute('DELETE FROM preferences WHERE "key" IN (?, ?, ?);', [
        PreferencesRepository.agentLlmSettingsKey,
        PreferencesRepository.remoteLlmAnalysisSettingsKey,
        PreferencesRepository.weatherApiKeyKey,
      ]);
      database.execute('VACUUM;');
      database.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } finally {
      database.close();
    }
  }

  Future<void> _sanitizeBackupPreferences(File preferencesFile) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await preferencesFile.readAsString());
    } on FormatException {
      throw BackupValidationException('备份偏好文件无效，已取消备份。');
    }
    if (decoded is! Map) {
      throw BackupValidationException('备份偏好文件无效，已取消备份。');
    }
    final sanitized = Map<String, Object?>.from(decoded.cast());
    sanitized
      ..remove(PreferencesRepository.agentLlmSettingsKey)
      ..remove(PreferencesRepository.remoteLlmAnalysisSettingsKey)
      ..remove(PreferencesRepository.weatherApiKeyKey);
    await preferencesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(sanitized),
    );
  }

  Future<void> _cleanupRollbackArtifact(FileSystemEntity entity) async {
    try {
      final cleaner = _rollbackArtifactCleaner;
      if (cleaner != null) {
        await cleaner(entity);
        return;
      }
      if (entity is File) {
        await _deleteIfExists(entity);
      } else if (entity is Directory) {
        await _deleteDirectoryIfExists(entity);
      }
    } catch (_) {
      // Restore has already committed. Keep the rollback artifact for manual
      // cleanup rather than attempting a partial rollback of the new snapshot.
    }
  }

  Future<void> _checkpointSqliteWal(File databaseFile) async {
    try {
      final database = sqlite3.open(databaseFile.path);
      try {
        final result = database.select('PRAGMA wal_checkpoint(TRUNCATE);');
        final busy = result.isEmpty ? 0 : _intValue(result.first['busy']) ?? 0;
        if (busy != 0 && await File('${databaseFile.path}-wal').exists()) {
          throw BackupException('SQLite WAL 正在被使用，无法安全备份。');
        }
      } finally {
        database.close();
      }
    } catch (error) {
      final walFile = File('${databaseFile.path}-wal');
      if (await walFile.exists()) {
        throw BackupException('处理 SQLite WAL 失败：$error');
      }
    }
  }

  Future<_RollbackFile?> _moveExistingAside(File file) async {
    if (!await file.exists()) {
      return null;
    }

    await _beforeMoveAside?.call(file);

    final rollbackFile = File(
      '${file.path}.pre_restore_${DateTime.now().microsecondsSinceEpoch}',
    );
    await file.rename(rollbackFile.path);
    return _RollbackFile(original: file, rollback: rollbackFile);
  }

  Future<_RollbackDirectory?> _moveExistingDirectoryAside(
    Directory directory,
  ) async {
    if (!await directory.exists()) {
      return null;
    }

    await _beforeMoveAside?.call(directory);

    final rollbackDirectory = Directory(
      '${directory.path}.pre_restore_${DateTime.now().microsecondsSinceEpoch}',
    );
    await directory.rename(rollbackDirectory.path);
    return _RollbackDirectory(original: directory, rollback: rollbackDirectory);
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  File _fileInBackup(Directory backupDirectory, String relativePath) {
    final portablePath = relativePath.replaceAll('\\', '/');
    final isAbsoluteWindowsPath = RegExp(r'^[A-Za-z]:/').hasMatch(portablePath);
    if (portablePath.startsWith('/') ||
        isAbsoluteWindowsPath ||
        portablePath.split('/').contains('..')) {
      throw BackupValidationException('备份文件路径非法：$relativePath');
    }
    final normalized = relativePath.replaceAll('\\', Platform.pathSeparator);
    return File('${backupDirectory.path}${Platform.pathSeparator}$normalized');
  }

  String _localFileLibraryRelativePath(String manifestPath) {
    final portablePath = manifestPath.replaceAll('\\', '/');
    const prefix = 'local_files/';
    if (!portablePath.startsWith(prefix) ||
        portablePath.length == prefix.length) {
      throw BackupValidationException('澶囦唤 local_files 璺緞闈炴硶锛?manifestPath');
    }
    return portablePath.substring(prefix.length);
  }

  String _relativePath(Directory root, File file) {
    final rootPath = root.absolute.path.replaceAll('\\', '/');
    final filePath = file.absolute.path.replaceAll('\\', '/');
    final prefix = rootPath.endsWith('/') ? rootPath : '$rootPath/';
    if (!filePath.startsWith(prefix)) {
      throw BackupException('鏂囦欢涓嶅湪澶囦唤鐩綍鍐咃細${file.path}');
    }
    return filePath.substring(prefix.length);
  }

  DateTime _now() {
    return _clock?.call() ?? DateTime.now();
  }

  String _formatBackupTimestamp(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${timestamp.year}-'
        '${twoDigits(timestamp.month)}-'
        '${twoDigits(timestamp.day)}_'
        '${twoDigits(timestamp.hour)}'
        '${twoDigits(timestamp.minute)}'
        '${twoDigits(timestamp.second)}';
  }

  String _pathName(String path) {
    return path.replaceAll('\\', '/').split('/').last;
  }
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

class BackupCreateResult {
  const BackupCreateResult({
    required this.directory,
    required this.manifest,
    required this.purpose,
  });

  final Directory directory;
  final BackupManifest manifest;
  final BackupPurpose purpose;
}

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.restoredBackupDirectory,
    required this.safetyBackup,
  });

  final Directory restoredBackupDirectory;
  final BackupCreateResult safetyBackup;
}

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupValidationException extends BackupException {
  const BackupValidationException(super.message);
}

class BackupRestoreException extends BackupException {
  const BackupRestoreException(super.message);
}

class _RestoreItem {
  const _RestoreItem({required this.source, required this.target});

  final File source;
  final File target;
}

class _RollbackFile {
  const _RollbackFile({required this.original, required this.rollback});

  final File original;
  final File rollback;
}

class _RollbackDirectory {
  const _RollbackDirectory({required this.original, required this.rollback});

  final Directory original;
  final Directory rollback;
}
