import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/storage/backup_manifest.dart';
import 'package:research_life/services/storage/backup_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/services/storage/workspace_manifest_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('BackupService', () {
    test('creates backup successfully', () async {
      final fixture = await _BackupFixture.create(
        timestamp: DateTime(2026, 5, 13, 9, 10, 11),
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('original');
      await fixture.workspaceService.saveWeeklyPromptTemplate('template');
      await WorkspaceManifestService(
        workspaceService: fixture.workspaceService,
      ).writeManifest(createdAt: DateTime(2026, 5, 13, 9));
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"doc_1"}]}',
      );
      await fixture.writeLocalLibraryFile(
        'annotations.json',
        '{"items":[{"id":"anno_1"}]}',
      );

      final result = await fixture.service.createBackup();

      expect(
        result.directory.path,
        endsWith(
          '${Platform.pathSeparator}.research_life'
          '${Platform.pathSeparator}backups'
          '${Platform.pathSeparator}2026-05-13_091011',
        ),
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}research_life.sqlite',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}preferences.json',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}workspace_manifest.json',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}local_files'
          '${Platform.pathSeparator}library_manifest.json',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}local_files'
          '${Platform.pathSeparator}annotations.json',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}backup_manifest.json',
        ).exists(),
        isTrue,
      );
    });

    test('writes correct manifest content', () async {
      final fixture = await _BackupFixture.create(
        timestamp: DateTime(2026, 5, 13, 9, 10, 11),
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('manifest-check');
      await fixture.workspaceService.saveWeeklyPromptTemplate('template');
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"doc_manifest"}]}',
      );

      final result = await fixture.service.createBackup();
      final manifestFile = File(
        '${result.directory.path}${Platform.pathSeparator}backup_manifest.json',
      );
      final manifest = BackupManifest.fromJson(
        (jsonDecode(await manifestFile.readAsString()) as Map)
            .cast<String, Object?>(),
      );
      final databaseBackup = File(
        '${result.directory.path}${Platform.pathSeparator}${manifest.databaseFile.path}',
      );
      final preferencesBackup = File(
        '${result.directory.path}${Platform.pathSeparator}${manifest.preferencesFile.path}',
      );
      final localFiles = manifest.localFileLibraryFiles;

      expect(manifest.manifestVersion, BackupManifest.currentManifestVersion);
      expect(manifest.appVersion, '0.1.0+1');
      expect(manifest.createdAt, DateTime(2026, 5, 13, 9, 10, 11));
      expect(manifest.schemaVersion, AppDatabase.currentSchemaVersion);
      expect(manifest.workspacePath, fixture.workspaceDirectory.path);
      expect(manifest.databaseFile.path, 'research_life.sqlite');
      expect(manifest.databaseFile.sizeBytes, await databaseBackup.length());
      expect(manifest.databaseFile.sha256, await _sha256(databaseBackup));
      expect(manifest.preferencesFile.path, 'preferences.json');
      expect(
        manifest.preferencesFile.sizeBytes,
        await preferencesBackup.length(),
      );
      expect(manifest.preferencesFile.sha256, await _sha256(preferencesBackup));
      expect(localFiles, isNotNull);
      expect(localFiles!.map((file) => file.path), [
        'local_files/library_manifest.json',
      ]);
      final localLibraryBackup = File(
        '${result.directory.path}${Platform.pathSeparator}${localFiles.single.path.replaceAll('/', Platform.pathSeparator)}',
      );
      expect(localFiles.single.sizeBytes, await localLibraryBackup.length());
      expect(localFiles.single.sha256, await _sha256(localLibraryBackup));
    });

    test('rejects restore when sha256 validation fails', () async {
      final fixture = await _BackupFixture.create(
        timestamp: DateTime(2026, 5, 13, 9, 10, 11),
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('original');
      await fixture.workspaceService.saveWeeklyPromptTemplate('template');
      final result = await fixture.service.createBackup();
      await fixture.writeDatabaseValue('current');
      await File(
        '${result.directory.path}${Platform.pathSeparator}research_life.sqlite',
      ).writeAsString('tampered');

      expect(
        fixture.service.restoreBackup(result.directory),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await fixture.readDatabaseValue(), 'current');
    });

    test('creates safety backup before restore', () async {
      var timestamp = DateTime(2026, 5, 13, 9, 10, 11);
      final fixture = await _BackupFixture.create(clock: () => timestamp);
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('backup-version');
      await fixture.workspaceService.saveWeeklyPromptTemplate(
        'backup-template',
      );
      final backup = await fixture.service.createBackup();

      await fixture.writeDatabaseValue('current-version');
      await fixture.workspaceService.saveWeeklyPromptTemplate(
        'current-template',
      );
      timestamp = DateTime(2026, 5, 13, 9, 11, 12);

      final restore = await fixture.service.restoreBackup(backup.directory);

      expect(await fixture.readDatabaseValue(), 'backup-version');
      expect(await restore.safetyBackup.directory.exists(), isTrue);
      expect(
        restore.safetyBackup.directory.path,
        endsWith(
          '${Platform.pathSeparator}.research_life'
          '${Platform.pathSeparator}backups'
          '${Platform.pathSeparator}2026-05-13_091112',
        ),
      );
      final safetyDatabase = File(
        '${restore.safetyBackup.directory.path}${Platform.pathSeparator}research_life.sqlite',
      );
      expect(_readDatabaseValue(safetyDatabase), 'current-version');
    });

    test('restores local PDF library files', () async {
      var timestamp = DateTime(2026, 5, 13, 9, 10, 11);
      final fixture = await _BackupFixture.create(clock: () => timestamp);
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('backup-version');
      await fixture.workspaceService.saveWeeklyPromptTemplate('template');
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"backup_doc"}]}',
      );
      await fixture.writeLocalLibraryFile(
        'annotations.json',
        '{"items":[{"id":"backup_annotation"}]}',
      );
      final backup = await fixture.service.createBackup();

      await fixture.writeDatabaseValue('current-version');
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"current_doc"}]}',
      );
      await fixture.writeLocalLibraryFile(
        'annotations.json',
        '{"items":[{"id":"current_annotation"}]}',
      );
      timestamp = DateTime(2026, 5, 13, 9, 11, 12);

      final restore = await fixture.service.restoreBackup(backup.directory);

      expect(await fixture.readDatabaseValue(), 'backup-version');
      expect(
        await fixture.readLocalLibraryFile('library_manifest.json'),
        '{"documents":[{"id":"backup_doc"}]}',
      );
      expect(
        await fixture.readLocalLibraryFile('annotations.json'),
        '{"items":[{"id":"backup_annotation"}]}',
      );
      final safetyLibraryManifest = File(
        '${restore.safetyBackup.directory.path}${Platform.pathSeparator}local_files'
        '${Platform.pathSeparator}library_manifest.json',
      );
      expect(
        await safetyLibraryManifest.readAsString(),
        contains('current_doc'),
      );
    });
  });
}

class _BackupFixture {
  _BackupFixture({
    required this.tempDirectory,
    required this.workspaceService,
    required this.service,
    required this.workspaceDirectory,
  });

  final Directory tempDirectory;
  final LocalWorkspaceService workspaceService;
  final BackupService service;
  final Directory workspaceDirectory;

  static Future<_BackupFixture> create({
    DateTime? timestamp,
    DateTime Function()? clock,
  }) async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'research_life_backup_service_test',
    );
    final workspaceService = LocalWorkspaceService(
      storageDirectoryResolver: () async => tempDirectory,
    );
    final workspaceDirectory = await workspaceService.resolveStorageDirectory();
    final service = BackupService(
      workspaceService: workspaceService,
      clock: clock ?? () => timestamp ?? DateTime(2026, 5, 13, 9, 10, 11),
    );
    return _BackupFixture(
      tempDirectory: tempDirectory,
      workspaceService: workspaceService,
      service: service,
      workspaceDirectory: workspaceDirectory,
    );
  }

  Future<void> writeDatabaseValue(String value) async {
    final databaseFile = await workspaceService.resolveDatabaseFile();
    await databaseFile.parent.create(recursive: true);
    final database = sqlite3.open(databaseFile.path);
    try {
      database
        ..execute('CREATE TABLE IF NOT EXISTS notes (value TEXT NOT NULL);')
        ..execute('DELETE FROM notes;')
        ..execute('INSERT INTO notes (value) VALUES (?);', [value])
        ..execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } finally {
      database.close();
    }
  }

  Future<String> readDatabaseValue() async {
    final databaseFile = await workspaceService.resolveDatabaseFile();
    return _readDatabaseValue(databaseFile);
  }

  Future<void> writeLocalLibraryFile(String fileName, String content) async {
    final directory = await workspaceService.resolveLocalFileLibraryDirectory();
    await File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    ).writeAsString(content);
  }

  Future<String> readLocalLibraryFile(String fileName) async {
    final directory = await workspaceService.resolveLocalFileLibraryDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    ).readAsString();
  }

  Future<void> dispose() {
    return tempDirectory.delete(recursive: true);
  }
}

String _readDatabaseValue(File databaseFile) {
  final database = sqlite3.open(databaseFile.path);
  try {
    final result = database.select('SELECT value FROM notes LIMIT 1;');
    return result.first['value'] as String;
  } finally {
    database.close();
  }
}

Future<String> _sha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
