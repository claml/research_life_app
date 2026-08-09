import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../database/app_database.dart';
import 'backup_manifest.dart';
import 'local_workspace_service.dart';

class BackupService {
  const BackupService({
    required LocalWorkspaceService workspaceService,
    this.appVersion = '0.1.0+1',
    this.schemaVersion = AppDatabase.currentSchemaVersion,
    DateTime Function()? clock,
  }) : _workspaceService = workspaceService,
       _clock = clock;

  final LocalWorkspaceService _workspaceService;
  final String appVersion;
  final int schemaVersion;
  final DateTime Function()? _clock;

  Future<BackupCreateResult> createBackup() {
    return _createBackup(createdAt: _now(), requireDatabase: true);
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

    await _validateFileInfo(backupDirectory, manifest.databaseFile);
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
    }
    return manifest;
  }

  Future<BackupRestoreResult> restoreBackup(Directory backupDirectory) async {
    final manifest = await validateBackup(backupDirectory);
    final safetyBackup = await _createBackup(
      createdAt: _now(),
      requireDatabase: true,
      purpose: BackupPurpose.safety,
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
        await item.source.copy(item.target.path);
      }

      if (localFileLibraryFiles != null) {
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

      for (final rollback in rollbackFiles) {
        await _deleteIfExists(rollback.rollback);
      }
      if (localFileLibraryRollback != null) {
        await _deleteDirectoryIfExists(localFileLibraryRollback.rollback);
      }

      return BackupRestoreResult(
        restoredBackupDirectory: backupDirectory,
        safetyBackup: safetyBackup,
      );
    } catch (error) {
      for (final item in restorePlan) {
        await _deleteIfExists(item.target);
      }
      if (manifest.localFileLibraryFiles != null) {
        await _deleteDirectoryIfExists(localFileLibraryDirectory);
      }
      for (final rollback in rollbackFiles.reversed) {
        if (await rollback.rollback.exists()) {
          await rollback.rollback.rename(rollback.original.path);
        }
      }
      if (localFileLibraryRollback != null &&
          await localFileLibraryRollback.rollback.exists()) {
        await localFileLibraryRollback.rollback.rename(
          localFileLibraryRollback.original.path,
        );
      }
      throw BackupRestoreException('恢复备份失败，已尝试回滚当前文件：$error');
    }
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

    final backupDirectory = await _createTimestampedBackupDirectory(createdAt);
    final databaseTarget = File(
      '${backupDirectory.path}${Platform.pathSeparator}research_life.sqlite',
    );
    final preferencesTarget = File(
      '${backupDirectory.path}${Platform.pathSeparator}preferences.json',
    );
    final workspaceManifestTarget = File(
      '${backupDirectory.path}${Platform.pathSeparator}workspace_manifest.json',
    );

    await databaseFile.copy(databaseTarget.path);
    await preferencesFile.copy(preferencesTarget.path);

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

    return BackupCreateResult(
      directory: backupDirectory,
      manifest: manifest,
      purpose: purpose,
    );
  }

  Future<Directory> _createTimestampedBackupDirectory(
    DateTime createdAt,
  ) async {
    final backupsDirectory = await _workspaceService.resolveBackupsDirectory();
    var candidateTime = createdAt;
    for (var attempts = 0; attempts < 10000; attempts += 1) {
      final candidate = Directory(
        '${backupsDirectory.path}${Platform.pathSeparator}'
        '${_formatBackupTimestamp(candidateTime)}',
      );
      if (!await candidate.exists()) {
        await candidate.create(recursive: true);
        return candidate;
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

enum BackupPurpose { manual, safety }

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
