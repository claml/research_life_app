import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

class ConsultingPackageService {
  ConsultingPackageService({Directory? projectRoot, DateTime Function()? clock})
    : _projectRoot = projectRoot,
      _clock = clock;

  final Directory? _projectRoot;
  final DateTime Function()? _clock;

  static const contextFileName = 'PROJECT_CONTEXT_SANITIZED.md';

  static const _includedRootFiles = ['pubspec.yaml'];
  static const _includedRootDirectories = ['lib', 'test', 'docs'];
  static const _projectIntroFileNames = [
    'README.md',
    'README_CN.md',
    'README.zh-CN.md',
    'PROJECT.md',
    'PROJECT_CONTEXT.md',
  ];
  static const _excludedDirectoryNames = {
    '.research_life',
    'build',
    '.dart_tool',
    '资料',
    'home_images',
    '桌宠形象',
    'logs',
    'log',
  };

  Future<ConsultingPackageResult> exportPackage({
    Directory? outputDirectory,
  }) async {
    final projectRoot = await resolveProjectRoot();
    final effectiveOutputDirectory =
        outputDirectory ??
        Directory(
          '${projectRoot.path}${Platform.pathSeparator}.research_life'
          '${Platform.pathSeparator}consulting_packages',
        );
    await effectiveOutputDirectory.create(recursive: true);

    final archive = Archive();
    final includedPaths = <String>{};
    for (final fileName in _includedRootFiles) {
      await _addFileIfAllowed(
        archive,
        File('${projectRoot.path}${Platform.pathSeparator}$fileName'),
        projectRoot,
        includedPaths,
      );
    }
    for (final directoryName in _includedRootDirectories) {
      await _addDirectoryIfAllowed(
        archive,
        Directory('${projectRoot.path}${Platform.pathSeparator}$directoryName'),
        projectRoot,
        includedPaths,
      );
    }
    for (final fileName in _projectIntroFileNames) {
      await _addFileIfAllowed(
        archive,
        File('${projectRoot.path}${Platform.pathSeparator}$fileName'),
        projectRoot,
        includedPaths,
      );
    }

    final contextContent = _buildSanitizedProjectContext(
      projectRoot: projectRoot,
      includedPaths: includedPaths.toList()..sort(),
    );
    archive.addFile(ArchiveFile.string(contextFileName, contextContent));
    includedPaths.add(contextFileName);

    final createdAt = _now();
    final packageFile = await _nextAvailablePackageFile(
      effectiveOutputDirectory,
      createdAt,
    );
    final packageBytes = ZipEncoder().encodeBytes(archive);
    await packageFile.writeAsBytes(packageBytes, flush: true);

    return ConsultingPackageResult(
      packageFile: packageFile,
      projectRoot: projectRoot,
      includedPaths: includedPaths.toList()..sort(),
      createdAt: createdAt,
    );
  }

  Future<Directory> resolveProjectRoot() async {
    final explicitRoot = _projectRoot;
    if (explicitRoot != null) {
      return explicitRoot;
    }
    return locateProjectRoot();
  }

  static Future<Directory> locateProjectRoot({
    Directory? startDirectory,
  }) async {
    var current = startDirectory ?? Directory.current;
    for (var depth = 0; depth < 8; depth += 1) {
      if (await _looksLikeFlutterProject(current)) {
        return current;
      }
      final parent = current.parent;
      if (_samePath(parent.path, current.path)) {
        break;
      }
      current = parent;
    }

    final appDirectory = Directory(
      '${(startDirectory ?? Directory.current).path}${Platform.pathSeparator}应用',
    );
    if (await _looksLikeFlutterProject(appDirectory)) {
      return appDirectory;
    }

    throw const ConsultingPackageException('未找到 Flutter 项目根目录。');
  }

  Future<void> _addDirectoryIfAllowed(
    Archive archive,
    Directory directory,
    Directory projectRoot,
    Set<String> includedPaths,
  ) async {
    if (!await directory.exists()) {
      return;
    }

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      await _addFileIfAllowed(archive, entity, projectRoot, includedPaths);
    }
  }

  Future<void> _addFileIfAllowed(
    Archive archive,
    File file,
    Directory projectRoot,
    Set<String> includedPaths,
  ) async {
    if (!await file.exists()) {
      return;
    }

    final relativePath = _archiveRelativePath(file, projectRoot);
    if (_shouldExclude(relativePath)) {
      return;
    }
    if (!includedPaths.add(relativePath)) {
      return;
    }

    archive.addFile(ArchiveFile.bytes(relativePath, await file.readAsBytes()));
  }

  bool _shouldExclude(String relativePath) {
    final normalizedPath = relativePath.replaceAll('\\', '/');
    final segments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.any(_excludedDirectoryNames.contains)) {
      return true;
    }

    final fileName = segments.isEmpty ? normalizedPath : segments.last;
    final lowerFileName = fileName.toLowerCase();
    if (lowerFileName == 'preferences.json') {
      return true;
    }
    if (lowerFileName.endsWith('.sqlite') ||
        lowerFileName.endsWith('.sqlite-wal') ||
        lowerFileName.endsWith('.sqlite-shm') ||
        lowerFileName.endsWith('.pdf') ||
        lowerFileName.endsWith('.log') ||
        lowerFileName.contains('.log.')) {
      return true;
    }
    return false;
  }

  String _archiveRelativePath(File file, Directory projectRoot) {
    final relativePath = path.relative(file.path, from: projectRoot.path);
    return relativePath.replaceAll('\\', '/');
  }

  String _buildSanitizedProjectContext({
    required Directory projectRoot,
    required List<String> includedPaths,
  }) {
    final topLevelEntries =
        includedPaths.map((entry) => entry.split('/').first).toSet().toList()
          ..sort();
    final moduleHints = <String>[
      if (includedPaths.any((entry) => entry.startsWith('lib/features/')))
        '- `lib/features/`: UI pages and feature-level state wiring.',
      if (includedPaths.any((entry) => entry.startsWith('lib/services/')))
        '- `lib/services/`: analysis, import, database, storage, weather, and integration services.',
      if (includedPaths.any((entry) => entry.startsWith('lib/state/')))
        '- `lib/state/`: application controller and cross-feature orchestration.',
      if (includedPaths.any((entry) => entry.startsWith('test/')))
        '- `test/`: unit and widget tests for parsing, persistence, backup, and feature behavior.',
      if (includedPaths.any((entry) => entry.startsWith('docs/')))
        '- `docs/`: project notes intended for engineering context.',
    ];

    return '''
# Research Life Consulting Package Context

This sanitized package is prepared for external technical consultation.

## Privacy Boundary

The package intentionally excludes local runtime data, personal notes, person relationship data, real PDFs, images, SQLite databases, preferences, generated build output, logs, and workspace-private folders.

Do not infer production user data from this package. It is limited to source code, tests, project documentation, and this generated context summary.

## Project Root

`${projectRoot.path}`

## Included Top-Level Entries

${topLevelEntries.map((entry) => '- `$entry`').join('\n')}

## Architecture Summary

Research Life is a Flutter desktop application. The codebase is organized around feature pages, a shared `ResearchLifeController`, service-layer modules, and Drift/SQLite persistence.

${moduleHints.isEmpty ? '- No module hints available from the exported file list.' : moduleHints.join('\n')}

## Review Notes For Consultants

- Treat all included examples as code fixtures unless explicitly marked otherwise.
- The export excludes real weekly journals, people relationship records, PDF contents, local preferences, and database snapshots.
- If more context is needed, ask for a new sanitized export rather than requesting raw local workspace data.
''';
  }

  Future<File> _nextAvailablePackageFile(
    Directory outputDirectory,
    DateTime createdAt,
  ) async {
    var timestamp = createdAt;
    for (var attempts = 0; attempts < 10000; attempts += 1) {
      final file = File(
        '${outputDirectory.path}${Platform.pathSeparator}'
        'research_life_consulting_${_formatTimestamp(timestamp)}.zip',
      );
      if (!await file.exists()) {
        return file;
      }
      timestamp = timestamp.add(const Duration(seconds: 1));
    }
    throw const ConsultingPackageException('无法创建可用咨询包文件名。');
  }

  DateTime _now() {
    return _clock?.call() ?? DateTime.now();
  }

  static Future<bool> _looksLikeFlutterProject(Directory directory) async {
    final hasPubspec = await File(
      '${directory.path}${Platform.pathSeparator}pubspec.yaml',
    ).exists();
    if (!hasPubspec) {
      return false;
    }
    return Directory('${directory.path}${Platform.pathSeparator}lib').exists();
  }

  static bool _samePath(String left, String right) {
    return path.normalize(left).toLowerCase() ==
        path.normalize(right).toLowerCase();
  }

  String _formatTimestamp(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${timestamp.year}-'
        '${twoDigits(timestamp.month)}-'
        '${twoDigits(timestamp.day)}_'
        '${twoDigits(timestamp.hour)}'
        '${twoDigits(timestamp.minute)}'
        '${twoDigits(timestamp.second)}';
  }
}

class ConsultingPackageResult {
  const ConsultingPackageResult({
    required this.packageFile,
    required this.projectRoot,
    required this.includedPaths,
    required this.createdAt,
  });

  final File packageFile;
  final Directory projectRoot;
  final List<String> includedPaths;
  final DateTime createdAt;
}

class ConsultingPackageException implements Exception {
  const ConsultingPackageException(this.message);

  final String message;

  @override
  String toString() => message;
}
