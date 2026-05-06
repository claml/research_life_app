import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef StorageDirectoryResolver = Future<Directory> Function();

const _defaultWorkspaceRootPath = r'D:\桌面\研究生活';

Future<Directory> _defaultStorageDirectoryResolver() async {
  return Directory(_defaultWorkspaceRootPath);
}

class LocalWorkspaceService {
  const LocalWorkspaceService({
    StorageDirectoryResolver storageDirectoryResolver =
        _defaultStorageDirectoryResolver,
  }) : _storageDirectoryResolver = storageDirectoryResolver;

  static const _workspaceFolderName = '.research_life';
  static const _preferencesFileName = 'preferences.json';
  static const _databaseFileName = 'research_life.sqlite';
  static const _databaseBackupsFolderName = 'database_backups';
  static const _materialsFolderName = '资料';
  static const _defaultPdfCategory = '未分类';
  static const _weeklyPromptTemplateKey = 'weeklyPromptTemplate';

  final StorageDirectoryResolver _storageDirectoryResolver;

  String get statusLabel => '本地存储已启用';

  Future<Directory> resolveStorageDirectory() async {
    final baseDirectory = await _storageDirectoryResolver();
    final workspaceDirectory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}$_workspaceFolderName',
    );
    await _migrateLegacyWorkspaceIfNeeded(baseDirectory, workspaceDirectory);
    await workspaceDirectory.create(recursive: true);
    return workspaceDirectory;
  }

  Future<File> resolveDatabaseFile() async {
    final storageDirectory = await resolveStorageDirectory();
    return File(
      '${storageDirectory.path}${Platform.pathSeparator}$_databaseFileName',
    );
  }

  Future<Directory> resolveDatabaseBackupsDirectory() async {
    final storageDirectory = await resolveStorageDirectory();
    final backupsDirectory = Directory(
      '${storageDirectory.path}${Platform.pathSeparator}$_databaseBackupsFolderName',
    );
    await backupsDirectory.create(recursive: true);
    return backupsDirectory;
  }

  Future<Directory> resolveMaterialsDirectory({
    String category = _defaultPdfCategory,
  }) async {
    final baseDirectory = await _storageDirectoryResolver();
    final categoryFolderName = _safePathSegment(category).isEmpty
        ? _defaultPdfCategory
        : _safePathSegment(category);
    final materialsDirectory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}$_materialsFolderName'
      '${Platform.pathSeparator}$categoryFolderName',
    );
    await materialsDirectory.create(recursive: true);
    return materialsDirectory;
  }

  Future<File> copyPdfIntoMaterials(
    File source, {
    String category = _defaultPdfCategory,
  }) async {
    if (!await source.exists()) {
      throw FileSystemException('PDF 文件不存在', source.path);
    }

    final materialsDirectory = await resolveMaterialsDirectory(
      category: category,
    );
    final sourceFileName = _fileNameFromPath(source.path);
    final fileName = _safeFileName(sourceFileName).isEmpty
        ? 'document.pdf'
        : _safeFileName(sourceFileName);
    final target = File(
      '${materialsDirectory.path}${Platform.pathSeparator}$fileName',
    );

    if (_normalizePath(source.path) == _normalizePath(target.path)) {
      return source;
    }
    if (await target.exists()) {
      if (await _hasSameFileContent(source, target)) {
        return target;
      }
      final availableTarget = await _nextAvailableFile(target);
      return source.copy(availableTarget.path);
    }
    return source.copy(target.path);
  }

  Future<List<File>> backupDatabaseFiles({DateTime? timestamp}) async {
    final databaseFile = await resolveDatabaseFile();
    if (!await databaseFile.exists()) {
      return const [];
    }

    final backupsDirectory = await resolveDatabaseBackupsDirectory();
    final suffix = _formatBackupTimestamp(timestamp ?? DateTime.now());
    final backupBasePath =
        '${backupsDirectory.path}${Platform.pathSeparator}research_life_$suffix.sqlite';
    final copiedFiles = <File>[];

    final sources = <({File source, String targetPath})>[
      (source: databaseFile, targetPath: backupBasePath),
      (
        source: File('${databaseFile.path}-wal'),
        targetPath: '$backupBasePath-wal',
      ),
      (
        source: File('${databaseFile.path}-shm'),
        targetPath: '$backupBasePath-shm',
      ),
    ];

    for (final item in sources) {
      if (!await item.source.exists()) {
        continue;
      }
      copiedFiles.add(await item.source.copy(item.targetPath));
    }

    return copiedFiles;
  }

  Future<String?> loadWeeklyPromptTemplate() async {
    final preferences = await _readPreferences();
    final value = preferences[_weeklyPromptTemplateKey];
    if (value is! String) {
      return null;
    }

    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      return null;
    }
    return normalizedValue;
  }

  Future<void> saveWeeklyPromptTemplate(String template) async {
    final preferences = await _readPreferences();
    preferences[_weeklyPromptTemplateKey] = template.trim();
    await _writePreferences(preferences);
  }

  Future<Map<String, dynamic>> _readPreferences() async {
    final file = await _preferencesFile();
    if (!await file.exists()) {
      return <String, dynamic>{};
    }

    try {
      final rawContent = await file.readAsString();
      final decoded = jsonDecode(rawContent);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FileSystemException {
      return <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }

    return <String, dynamic>{};
  }

  Future<void> _writePreferences(Map<String, dynamic> preferences) async {
    final file = await _preferencesFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(preferences),
    );
  }

  Future<File> _preferencesFile() async {
    final workspaceDirectory = await resolveStorageDirectory();
    return File(
      '${workspaceDirectory.path}${Platform.pathSeparator}$_preferencesFileName',
    );
  }

  Future<void> _migrateLegacyWorkspaceIfNeeded(
    Directory baseDirectory,
    Directory workspaceDirectory,
  ) async {
    if (!_isDefaultWorkspaceRoot(baseDirectory)) {
      return;
    }
    if (await workspaceDirectory.exists()) {
      return;
    }

    final legacyBaseDirectory = await getApplicationSupportDirectory();
    final legacyWorkspaceDirectory = Directory(
      '${legacyBaseDirectory.path}${Platform.pathSeparator}$_workspaceFolderName',
    );
    if (!await legacyWorkspaceDirectory.exists()) {
      return;
    }
    if (_normalizePath(legacyWorkspaceDirectory.path) ==
        _normalizePath(workspaceDirectory.path)) {
      return;
    }

    try {
      await _copyDirectory(legacyWorkspaceDirectory, workspaceDirectory);
    } on FileSystemException {
      // Keep startup resilient if the old location cannot be copied.
    }
  }

  bool _isDefaultWorkspaceRoot(Directory directory) {
    return _normalizePath(directory.path) ==
        _normalizePath(_defaultWorkspaceRootPath);
  }

  String _normalizePath(String path) {
    return path
        .replaceAll('/', '\\')
        .replaceAll(RegExp(r'\\+$'), '')
        .toLowerCase();
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('/', Platform.pathSeparator);
    final separatorIndex = normalized.lastIndexOf(Platform.pathSeparator);
    if (separatorIndex == -1 || separatorIndex == normalized.length - 1) {
      return normalized;
    }
    return normalized.substring(separatorIndex + 1);
  }

  String _safePathSegment(String value) {
    return value.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  }

  String _safeFileName(String value) {
    final fileName = _safePathSegment(value);
    if (fileName == '.' || fileName == '..') {
      return '';
    }
    return fileName;
  }

  Future<bool> _hasSameFileContent(File left, File right) async {
    try {
      final leftStat = await left.stat();
      final rightStat = await right.stat();
      if (leftStat.size != rightStat.size) {
        return false;
      }
      final leftBytes = await left.readAsBytes();
      final rightBytes = await right.readAsBytes();
      for (var index = 0; index < leftBytes.length; index += 1) {
        if (leftBytes[index] != rightBytes[index]) {
          return false;
        }
      }
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<File> _nextAvailableFile(File preferredFile) async {
    final path = preferredFile.path;
    final separatorIndex = path.lastIndexOf(Platform.pathSeparator);
    final folderPath = separatorIndex == -1
        ? ''
        : path.substring(0, separatorIndex);
    final fileName = separatorIndex == -1
        ? path
        : path.substring(separatorIndex + 1);
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
    final extension = dotIndex <= 0 ? '' : fileName.substring(dotIndex);

    for (var index = 1; index < 10000; index += 1) {
      final candidatePath = folderPath.isEmpty
          ? '$baseName ($index)$extension'
          : '$folderPath${Platform.pathSeparator}$baseName ($index)$extension';
      final candidate = File(candidatePath);
      if (!await candidate.exists()) {
        return candidate;
      }
    }
    throw FileSystemException('无法生成可用文件名', preferredFile.path);
  }

  String _formatBackupTimestamp(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${timestamp.year}'
        '${twoDigits(timestamp.month)}'
        '${twoDigits(timestamp.day)}_'
        '${twoDigits(timestamp.hour)}'
        '${twoDigits(timestamp.minute)}'
        '${twoDigits(timestamp.second)}';
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);

    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
      if (name.isEmpty) {
        continue;
      }

      final targetPath = '${target.path}${Platform.pathSeparator}$name';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }
}
