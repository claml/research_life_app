import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';

void main() {
  group('LocalWorkspaceService', () {
    test('resolves storage directory under provided base directory', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_storage_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final service = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );

      final storageDirectory = await service.resolveStorageDirectory();

      expect(
        storageDirectory.path,
        '${tempDir.path}${Platform.pathSeparator}.research_life',
      );
      expect(await storageDirectory.exists(), isTrue);
    });

    test(
      'saves and loads weekly prompt template in storage directory',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'research_life_preferences_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final service = LocalWorkspaceService(
          storageDirectoryResolver: () async => tempDir,
        );

        await service.saveWeeklyPromptTemplate('测试模板');
        final storageDirectory = await service.resolveStorageDirectory();
        final preferencesFile = File(
          '${storageDirectory.path}${Platform.pathSeparator}preferences.json',
        );

        expect(await preferencesFile.exists(), isTrue);
        expect(await service.loadWeeklyPromptTemplate(), '测试模板');
      },
    );

    test('returns no backup files when database does not exist', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_empty_database_backup_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final service = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );

      final copiedFiles = await service.backupDatabaseFiles(
        timestamp: DateTime(2026, 4, 26, 12, 34, 56),
      );

      expect(copiedFiles, isEmpty);
    });

    test('backs up database, wal, and shm files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_database_backup_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final service = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );

      final databaseFile = await service.resolveDatabaseFile();
      await databaseFile.writeAsString('database');
      await File('${databaseFile.path}-wal').writeAsString('wal');
      await File('${databaseFile.path}-shm').writeAsString('shm');

      final copiedFiles = await service.backupDatabaseFiles(
        timestamp: DateTime(2026, 4, 26, 12, 34, 56),
      );

      final storageDirectory = await service.resolveStorageDirectory();
      final backupsPath =
          '${storageDirectory.path}${Platform.pathSeparator}database_backups';
      final expectedFiles = [
        File(
          '$backupsPath${Platform.pathSeparator}research_life_20260426_123456.sqlite',
        ),
        File(
          '$backupsPath${Platform.pathSeparator}research_life_20260426_123456.sqlite-wal',
        ),
        File(
          '$backupsPath${Platform.pathSeparator}research_life_20260426_123456.sqlite-shm',
        ),
      ];

      expect(
        copiedFiles.map((file) => file.path),
        expectedFiles.map((file) => file.path),
      );
      expect(await expectedFiles[0].readAsString(), 'database');
      expect(await expectedFiles[1].readAsString(), 'wal');
      expect(await expectedFiles[2].readAsString(), 'shm');
    });

    test(
      'copies imported pdfs into the backed-up managed payload folder',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'research_life_materials_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final service = LocalWorkspaceService(
          storageDirectoryResolver: () async => tempDir,
        );
        final source = File(
          '${tempDir.path}${Platform.pathSeparator}source.pdf',
        );
        await source.writeAsString('pdf-content');

        final copied = await service.copyPdfIntoMaterials(source);

        expect(
          copied.path,
          '${tempDir.path}${Platform.pathSeparator}.research_life'
          '${Platform.pathSeparator}local_files'
          '${Platform.pathSeparator}payloads'
          '${Platform.pathSeparator}未分类'
          '${Platform.pathSeparator}source.pdf',
        );
        expect(await copied.readAsString(), 'pdf-content');
      },
    );

    test('keeps distinct imported pdfs when names collide', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_materials_collision_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final service = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );
      final firstFolder = Directory(
        '${tempDir.path}${Platform.pathSeparator}first',
      );
      final secondFolder = Directory(
        '${tempDir.path}${Platform.pathSeparator}second',
      );
      await firstFolder.create();
      await secondFolder.create();
      final firstSource = File(
        '${firstFolder.path}${Platform.pathSeparator}paper.pdf',
      );
      final secondSource = File(
        '${secondFolder.path}${Platform.pathSeparator}paper.pdf',
      );
      await firstSource.writeAsString('first');
      await secondSource.writeAsString('second');

      final firstCopied = await service.copyPdfIntoMaterials(firstSource);
      final secondCopied = await service.copyPdfIntoMaterials(secondSource);

      expect(firstCopied.path.endsWith('paper.pdf'), isTrue);
      expect(secondCopied.path.endsWith('paper (1).pdf'), isTrue);
      expect(await firstCopied.readAsString(), 'first');
      expect(await secondCopied.readAsString(), 'second');
    });
  });
}
