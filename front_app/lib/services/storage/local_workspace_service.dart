import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef StorageDirectoryResolver = Future<Directory> Function();
const _workspaceRootEnvKey = 'RESEARCH_LIFE_WORKSPACE';

const _defaultWorkspaceRootPath = r'D:\桌面\研究生活';

Future<Directory> _defaultStorageDirectoryResolver() async {
  final configuredPath = Platform.environment[_workspaceRootEnvKey]?.trim();
  if (configuredPath != null && configuredPath.isNotEmpty) {
    return Directory(configuredPath);
  }
  return Directory(_defaultWorkspaceRootPath);
}

class LocalWorkspaceService {
  const LocalWorkspaceService({
    StorageDirectoryResolver storageDirectoryResolver =
        _defaultStorageDirectoryResolver,
  }) : _storageDirectoryResolver = storageDirectoryResolver;

  static const _workspaceFolderName = '.research_life';
  static const _projectAppFolderName = '应用';
  static const _pubspecFileName = 'pubspec.yaml';
  static const _assetsFolderName = 'assets';
  static const _preferencesFileName = 'preferences.json';
  static const _databaseFileName = 'research_life.sqlite';
  static const _workspaceManifestFileName = 'workspace_manifest.json';
  static const _localFileLibraryFolderName = 'local_files';
  static const _managedFilePayloadsFolderName = 'payloads';
  static const _backupsFolderName = 'backups';
  static const _databaseBackupsFolderName = 'database_backups';
  static const _customPetsFolderName = 'pets';
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

  Future<File> resolvePreferencesFile() async {
    final storageDirectory = await resolveStorageDirectory();
    return File(
      '${storageDirectory.path}${Platform.pathSeparator}$_preferencesFileName',
    );
  }

  Future<File> resolveWorkspaceManifestFile() async {
    final storageDirectory = await resolveStorageDirectory();
    return File(
      '${storageDirectory.path}${Platform.pathSeparator}$_workspaceManifestFileName',
    );
  }

  Future<Directory> resolveLocalFileLibraryDirectory({
    bool create = true,
  }) async {
    final storageDirectory = await resolveStorageDirectory();
    final directory = Directory(
      '${storageDirectory.path}${Platform.pathSeparator}$_localFileLibraryFolderName',
    );
    if (create) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> resolveManagedFilePayloadsDirectory({
    String? category,
    bool create = true,
  }) async {
    final libraryDirectory = await resolveLocalFileLibraryDirectory(
      create: create,
    );
    var directory = Directory(
      '${libraryDirectory.path}${Platform.pathSeparator}'
      '$_managedFilePayloadsFolderName',
    );
    if (category != null) {
      final safeCategory = _safePathSegment(category);
      directory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '${safeCategory.isEmpty ? _defaultPdfCategory : safeCategory}',
      );
    }
    if (create) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> resolveBackupsDirectory() async {
    final storageDirectory = await resolveStorageDirectory();
    final backupsDirectory = Directory(
      '${storageDirectory.path}${Platform.pathSeparator}$_backupsFolderName',
    );
    await backupsDirectory.create(recursive: true);
    return backupsDirectory;
  }

  Future<Directory> resolveDatabaseBackupsDirectory() async {
    final storageDirectory = await resolveStorageDirectory();
    final backupsDirectory = Directory(
      '${storageDirectory.path}${Platform.pathSeparator}$_databaseBackupsFolderName',
    );
    await backupsDirectory.create(recursive: true);
    return backupsDirectory;
  }

  Future<File> createDatabaseBackup() async {
    final source = await resolveDatabaseFile();
    if (!await source.exists()) {
      throw StateError('本地数据库不存在');
    }
    final backupsDirectory = await resolveDatabaseBackupsDirectory();
    final backupFile = File(
      '${backupsDirectory.path}${Platform.pathSeparator}'
      'backup_${DateTime.now().millisecondsSinceEpoch}.sqlite',
    );
    await source.copy(backupFile.path);
    return backupFile;
  }

  Future<Directory> resolveCustomPetsDirectory() async {
    return resolveProjectPetsDirectory();
  }

  Future<Directory> resolveProjectPetsDirectory() async {
    final appDirectory = await resolveProjectAppDirectory();
    final petsDirectory = Directory(
      '${appDirectory.path}${Platform.pathSeparator}$_assetsFolderName'
      '${Platform.pathSeparator}$_customPetsFolderName',
    );
    await petsDirectory.create(recursive: true);
    return petsDirectory;
  }

  Future<Directory> resolveProjectAppDirectory() async {
    final baseDirectory = await _storageDirectoryResolver();
    final candidates = <Directory>[
      if (_looksLikeFlutterProject(baseDirectory)) baseDirectory,
      Directory(
        '${baseDirectory.path}${Platform.pathSeparator}$_projectAppFolderName',
      ),
      Directory.current,
      ..._parentDirectories(Directory.current),
    ];

    for (final candidate in candidates) {
      if (await _looksLikeFlutterProjectAsync(candidate)) {
        return candidate;
      }
    }

    return Directory(
      '${baseDirectory.path}${Platform.pathSeparator}$_projectAppFolderName',
    );
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

  Future<File> copyFileIntoMaterials(
    File source, {
    String category = _defaultPdfCategory,
    bool reuseIdenticalFile = true,
  }) async {
    final result = await copyFileIntoMaterialsWithResult(
      source,
      category: category,
      reuseIdenticalFile: reuseIdenticalFile,
    );
    return result.file;
  }

  Future<({File file, bool created})> copyFileIntoMaterialsWithResult(
    File source, {
    String category = _defaultPdfCategory,
    bool reuseIdenticalFile = true,
  }) async {
    if (!await source.exists()) {
      throw FileSystemException('文件不存在', source.path);
    }

    final materialsDirectory = await resolveManagedFilePayloadsDirectory(
      category: category,
    );
    final sourceFileName = _fileNameFromPath(source.path);
    final fileName = _safeFileName(sourceFileName).isEmpty
        ? 'document'
        : _safeFileName(sourceFileName);
    final target = File(
      '${materialsDirectory.path}${Platform.pathSeparator}$fileName',
    );

    if (_normalizePath(source.path) == _normalizePath(target.path)) {
      return (file: source, created: false);
    }
    if (await target.exists()) {
      if (reuseIdenticalFile && await _hasSameFileContent(source, target)) {
        return (file: target, created: false);
      }
      final availableTarget = await _nextAvailableFile(target);
      return (file: await source.copy(availableTarget.path), created: true);
    }
    return (file: await source.copy(target.path), created: true);
  }

  Future<bool> isManagedFilePath(String path) async {
    final payloadsDirectory = await resolveManagedFilePayloadsDirectory(
      create: false,
    );
    final root = _normalizePath(payloadsDirectory.absolute.path);
    final candidate = _normalizePath(File(path).absolute.path);
    return candidate.startsWith('$root\\');
  }

  Future<File> resolveManagedFileOperationJournalFile() async {
    final library = await resolveLocalFileLibraryDirectory();
    return File(
      '${library.path}${Platform.pathSeparator}.managed_file_operation.json',
    );
  }

  Future<String> portableManagedFilePath(String filePath) async {
    final payloads = await resolveManagedFilePayloadsDirectory(create: false);
    final absolutePayloads = p.normalize(p.absolute(payloads.path));
    final absoluteFile = p.normalize(p.absolute(filePath));
    if (!p.isWithin(absolutePayloads, absoluteFile)) {
      throw FileSystemException('文件不在工作台管理目录内', filePath);
    }
    final library = await resolveLocalFileLibraryDirectory(create: false);
    final relative = p.relative(absoluteFile, from: p.absolute(library.path));
    return p.posix.joinAll(p.split(relative));
  }

  Future<File> resolveManagedPortableFile(String storedPath) async {
    final normalized = p.posix.normalize(storedPath.replaceAll('\\', '/'));
    if (!normalized.startsWith('payloads/') ||
        normalized.split('/').any((segment) => segment == '..')) {
      throw FileSystemException('无效的工作台文件路径', storedPath);
    }
    final library = await resolveLocalFileLibraryDirectory(create: false);
    final resolved = File(p.joinAll([library.path, ...normalized.split('/')]));
    if (!await isManagedFilePath(resolved.path)) {
      throw FileSystemException('工作台文件路径越界', storedPath);
    }
    return resolved;
  }

  Future<void> writeManagedFileOperationJournal({
    required String type,
    required String documentId,
    required File original,
    required File target,
  }) async {
    final journal = await resolveManagedFileOperationJournalFile();
    final pending = File('${journal.path}.pending');
    if (await pending.exists()) {
      await pending.delete();
    }
    await pending.writeAsString(
      jsonEncode({
        'version': 1,
        'type': type,
        'documentId': documentId,
        'originalPath': await portableManagedFilePath(original.path),
        'targetPath': await portableManagedFilePath(target.path),
      }),
      flush: true,
    );
    if (await journal.exists()) {
      await journal.delete();
    }
    await pending.rename(journal.path);
  }

  Future<void> clearManagedFileOperationJournal() async {
    final journal = await resolveManagedFileOperationJournalFile();
    final pending = File('${journal.path}.pending');
    if (await journal.exists()) {
      await journal.delete();
    }
    if (await pending.exists()) {
      await pending.delete();
    }
  }

  Future<File> resolveManagedRenameTarget(File source, String title) async {
    if (!await source.exists()) {
      throw FileSystemException('文件不存在', source.path);
    }
    if (!await isManagedFilePath(source.path)) {
      throw FileSystemException('只能重命名工作台管理的文件', source.path);
    }
    final extensionIndex = source.path.lastIndexOf('.');
    final separatorIndex = source.path.lastIndexOf(Platform.pathSeparator);
    final extension = extensionIndex > separatorIndex
        ? source.path.substring(extensionIndex)
        : '';
    var safeTitle = _safeFileName(title);
    if (extension.isNotEmpty &&
        safeTitle.toLowerCase().endsWith(extension.toLowerCase())) {
      safeTitle = safeTitle.substring(0, safeTitle.length - extension.length);
    }
    if (safeTitle.trim().isEmpty) {
      throw const FileSystemException('文件名不能为空');
    }
    final target = File(
      '${source.parent.path}${Platform.pathSeparator}$safeTitle$extension',
    );
    if (_normalizePath(source.path) != _normalizePath(target.path) &&
        await target.exists()) {
      throw FileSystemException('同名文件已存在', target.path);
    }
    return target;
  }

  Future<File> resolveManagedDeletionStagingFile(File source) async {
    if (!await isManagedFilePath(source.path)) {
      throw FileSystemException('只能删除工作台管理的文件', source.path);
    }
    return File(
      '${source.parent.path}${Platform.pathSeparator}'
      '.deleting-${DateTime.now().microsecondsSinceEpoch}-'
      '${_fileNameFromPath(source.path)}',
    );
  }

  Future<File> renameManagedFile(File source, String title) async {
    if (!await source.exists()) {
      throw FileSystemException('文件不存在', source.path);
    }
    if (!await isManagedFilePath(source.path)) {
      throw FileSystemException('只能重命名工作台管理的文件', source.path);
    }
    final extensionIndex = source.path.lastIndexOf('.');
    final separatorIndex = source.path.lastIndexOf(Platform.pathSeparator);
    final extension = extensionIndex > separatorIndex
        ? source.path.substring(extensionIndex)
        : '';
    var safeTitle = _safeFileName(title);
    if (extension.isNotEmpty &&
        safeTitle.toLowerCase().endsWith(extension.toLowerCase())) {
      safeTitle = safeTitle.substring(0, safeTitle.length - extension.length);
    }
    if (safeTitle.trim().isEmpty) {
      throw const FileSystemException('文件名不能为空');
    }
    final target = File(
      '${source.parent.path}${Platform.pathSeparator}$safeTitle$extension',
    );
    if (_normalizePath(source.path) == _normalizePath(target.path)) {
      return source;
    }
    if (await target.exists()) {
      throw FileSystemException('同名文件已存在', target.path);
    }
    return source.rename(target.path);
  }

  Future<File?> stageManagedFileDeletion(
    File source, {
    File? stagedFile,
  }) async {
    if (!await source.exists()) {
      return null;
    }
    if (!await isManagedFilePath(source.path)) {
      throw FileSystemException('只能删除工作台管理的文件', source.path);
    }
    final staged =
        stagedFile ?? await resolveManagedDeletionStagingFile(source);
    return source.rename(staged.path);
  }

  Future<void> restoreStagedManagedFile(File staged, File original) async {
    if (await staged.exists()) {
      await staged.rename(original.path);
    }
  }

  Future<void> deleteManagedStagedFile(File staged) {
    return staged.delete();
  }

  Future<File> copyPdfIntoMaterials(
    File source, {
    String category = _defaultPdfCategory,
  }) => copyFileIntoMaterials(source, category: category);

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
    return resolvePreferencesFile();
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

  bool _looksLikeFlutterProject(Directory directory) {
    return File(
          '${directory.path}${Platform.pathSeparator}$_pubspecFileName',
        ).existsSync() &&
        Directory(
          '${directory.path}${Platform.pathSeparator}$_assetsFolderName',
        ).existsSync();
  }

  Future<bool> _looksLikeFlutterProjectAsync(Directory directory) async {
    return await File(
          '${directory.path}${Platform.pathSeparator}$_pubspecFileName',
        ).exists() &&
        await Directory(
          '${directory.path}${Platform.pathSeparator}$_assetsFolderName',
        ).exists();
  }

  List<Directory> _parentDirectories(Directory directory) {
    final parents = <Directory>[];
    var current = directory.absolute;
    for (var index = 0; index < 8; index += 1) {
      final parent = current.parent;
      if (_normalizePath(parent.path) == _normalizePath(current.path)) {
        break;
      }
      parents.add(parent);
      current = parent;
    }
    return parents;
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
