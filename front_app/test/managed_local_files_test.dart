import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/core/utils/workspace_file_kind.dart';
import 'package:research_life/services/database/app_database.dart'
    show AppDatabase;
import 'package:research_life/services/storage/backup_service.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';
import 'package:research_life/services/storage/local_file_library_store.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'managed files are portable and restored with their original bytes',
    () async {
      final sourceRoot = await Directory.systemTemp.createTemp(
        'research_life_managed_source',
      );
      final restoredRoot = await Directory.systemTemp.createTemp(
        'research_life_managed_restored',
      );
      addTearDown(() => sourceRoot.delete(recursive: true));
      addTearDown(() => restoredRoot.delete(recursive: true));

      final sourceWorkspace = LocalWorkspaceService(
        storageDirectoryResolver: () async => sourceRoot,
      );
      final sourceFile = File(
        '${sourceRoot.path}${Platform.pathSeparator}experiment.csv',
      );
      await sourceFile.writeAsString('sample,value\nA,42\n');
      final managedFile = await sourceWorkspace.copyFileIntoMaterials(
        sourceFile,
        category: '数据',
      );
      final localLibrary = await sourceWorkspace
          .resolveLocalFileLibraryDirectory();
      expect(
        managedFile.absolute.path,
        startsWith('${localLibrary.absolute.path}${Platform.pathSeparator}'),
      );

      final store = LocalFileLibraryStore(sourceWorkspace);
      final now = DateTime(2026, 8, 9, 12);
      await store.saveDocument(
        PdfLibraryDocument(
          id: 'doc-1',
          title: 'experiment',
          path: managedFile.path,
          fileKind: WorkspaceFileKind.text,
          category: '数据',
          createdAt: now,
          updatedAt: now,
          inReadingList: false,
        ),
      );
      final manifest =
          jsonDecode(
                await File(
                  '${localLibrary.path}${Platform.pathSeparator}library_manifest.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final storedPath =
          (manifest['documents'] as List).single['path'] as String;
      expect(storedPath, 'payloads/数据/experiment.csv');

      await _writeSqliteDatabase(sourceWorkspace, 'source');
      final backup = await BackupService(
        workspaceService: sourceWorkspace,
      ).createBackup();

      final restoredWorkspace = LocalWorkspaceService(
        storageDirectoryResolver: () async => restoredRoot,
      );
      await _writeSqliteDatabase(restoredWorkspace, 'current');
      await BackupService(
        workspaceService: restoredWorkspace,
      ).restoreBackup(backup.directory);

      final restoredDocuments = await LocalFileLibraryStore(
        restoredWorkspace,
      ).loadDocuments();
      expect(restoredDocuments, hasLength(1));
      final restoredDocument = restoredDocuments.single;
      expect(restoredDocument.path, isNot(managedFile.path));
      expect(
        restoredDocument.path,
        startsWith('${restoredRoot.absolute.path}${Platform.pathSeparator}'),
      );
      expect(
        await File(restoredDocument.path).readAsString(),
        'sample,value\nA,42\n',
      );
    },
  );

  test(
    'loading a legacy absolute file path migrates it into managed storage',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'research_life_legacy_managed_file',
      );
      addTearDown(() => root.delete(recursive: true));
      final workspace = LocalWorkspaceService(
        storageDirectoryResolver: () async => root,
      );
      final legacy = File(
        '${root.path}${Platform.pathSeparator}资料'
        '${Platform.pathSeparator}论文${Platform.pathSeparator}legacy.md',
      );
      await legacy.parent.create(recursive: true);
      await legacy.writeAsString('# legacy');
      final library = await workspace.resolveLocalFileLibraryDirectory();
      final manifestFile = File(
        '${library.path}${Platform.pathSeparator}library_manifest.json',
      );
      await manifestFile.writeAsString(
        jsonEncode({
          'version': 1,
          'documents': [
            {
              'id': 'legacy-1',
              'title': 'legacy',
              'path': legacy.path,
              'fileKind': 'text',
              'category': '论文',
              'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
              'updatedAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
              'inReadingList': false,
            },
          ],
        }),
      );

      final loaded = await LocalFileLibraryStore(workspace).loadDocuments();

      expect(loaded, hasLength(1));
      expect(await File(loaded.single.path).readAsString(), '# legacy');
      expect(
        loaded.single.path,
        contains(
          '${Platform.pathSeparator}local_files'
          '${Platform.pathSeparator}payloads${Platform.pathSeparator}论文',
        ),
      );
      final rewritten = jsonDecode(await manifestFile.readAsString()) as Map;
      expect(
        (rewritten['documents'] as List).single['path'],
        'payloads/论文/legacy.md',
      );
    },
  );

  test('concurrent manifest saves preserve every document', () async {
    final root = await Directory.systemTemp.createTemp(
      'research_life_concurrent_manifest',
    );
    addTearDown(() => root.delete(recursive: true));
    final workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    final coordinator = LocalDataOperationCoordinator();
    final store = LocalFileLibraryStore(
      workspace,
      operationCoordinator: coordinator,
    );
    final now = DateTime(2026, 8, 9);

    await Future.wait([
      store.saveDocument(
        PdfLibraryDocument(
          id: 'one',
          title: 'one',
          path: 'one.md',
          fileKind: WorkspaceFileKind.text,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      store.saveDocument(
        PdfLibraryDocument(
          id: 'two',
          title: 'two',
          path: 'two.md',
          fileKind: WorkspaceFileKind.text,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    ]);

    expect((await store.loadDocuments()).map((doc) => doc.id).toSet(), {
      'one',
      'two',
    });
  });

  test('backup waits for the shared local-data operation lock', () async {
    final root = await Directory.systemTemp.createTemp(
      'research_life_backup_shared_lock',
    );
    addTearDown(() => root.delete(recursive: true));
    final workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    await _writeSqliteDatabase(workspace, 'locked');
    final coordinator = LocalDataOperationCoordinator();
    final backupService = BackupService(
      workspaceService: workspace,
      operationCoordinator: coordinator,
    );
    final lockAcquired = Completer<void>();
    final releaseLock = Completer<void>();
    final holding = coordinator.runExclusive(() async {
      lockAcquired.complete();
      await releaseLock.future;
    });
    await lockAcquired.future;
    var backupCompleted = false;

    final backup = backupService.createBackup().whenComplete(
      () => backupCompleted = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(backupCompleted, isFalse);

    releaseLock.complete();
    await holding;
    final completed = await backup;
    expect(await backupService.validateBackup(completed.directory), isNotNull);
  });

  test(
    'manifest load recovers the previous file after interrupted replacement',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'research_life_manifest_recovery',
      );
      addTearDown(() => root.delete(recursive: true));
      final workspace = LocalWorkspaceService(
        storageDirectoryResolver: () async => root,
      );
      final library = await workspace.resolveLocalFileLibraryDirectory();
      final previous = File(
        '${library.path}${Platform.pathSeparator}library_manifest.json.previous',
      );
      await previous.writeAsString(
        jsonEncode({
          'version': 1,
          'documents': [
            {
              'id': 'recover-me',
              'title': 'recover me',
              'path': 'missing.md',
              'fileKind': 'text',
              'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
              'updatedAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
            },
          ],
        }),
      );

      final documents = await LocalFileLibraryStore(workspace).loadDocuments();

      expect(documents.single.id, 'recover-me');
      expect(
        await File(
          '${library.path}${Platform.pathSeparator}library_manifest.json',
        ).exists(),
        isTrue,
      );
    },
  );

  test(
    'legacy records with identical names and bytes receive distinct payloads',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'research_life_legacy_alias',
      );
      addTearDown(() => root.delete(recursive: true));
      final workspace = LocalWorkspaceService(
        storageDirectoryResolver: () async => root,
      );
      final first = File(
        '${root.path}${Platform.pathSeparator}first'
        '${Platform.pathSeparator}same.md',
      );
      final second = File(
        '${root.path}${Platform.pathSeparator}second'
        '${Platform.pathSeparator}same.md',
      );
      await first.parent.create(recursive: true);
      await second.parent.create(recursive: true);
      await first.writeAsString('identical');
      await second.writeAsString('identical');
      final library = await workspace.resolveLocalFileLibraryDirectory();
      await File(
        '${library.path}${Platform.pathSeparator}library_manifest.json',
      ).writeAsString(
        jsonEncode({
          'version': 1,
          'documents': [
            _legacyDocumentJson('first', first.path),
            _legacyDocumentJson('second', second.path),
          ],
        }),
      );

      final documents = await LocalFileLibraryStore(workspace).loadDocuments();

      expect(documents.map((doc) => doc.path).toSet(), hasLength(2));
      expect(
        await Future.wait(documents.map((doc) => File(doc.path).exists())),
        everyElement(isTrue),
      );
    },
  );

  test('manifest load rolls back a rename interrupted before commit', () async {
    final root = await Directory.systemTemp.createTemp(
      'research_life_rename_journal',
    );
    addTearDown(() => root.delete(recursive: true));
    final workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    final source = File('${root.path}${Platform.pathSeparator}paper.md');
    await source.writeAsString('paper');
    final managed = await workspace.copyFileIntoMaterials(source);
    final now = DateTime(2026, 8, 9);
    await LocalFileLibraryStore(workspace).saveDocument(
      PdfLibraryDocument(
        id: 'rename-doc',
        title: 'paper',
        path: managed.path,
        fileKind: WorkspaceFileKind.text,
        category: '未分类',
        createdAt: now,
        updatedAt: now,
        inReadingList: false,
      ),
    );
    final renamed = File(
      '${managed.parent.path}${Platform.pathSeparator}renamed.md',
    );
    final library = await workspace.resolveLocalFileLibraryDirectory();
    final journal = File(
      '${library.path}${Platform.pathSeparator}.managed_file_operation.json',
    );
    await journal.writeAsString(
      jsonEncode({
        'version': 1,
        'type': 'rename',
        'documentId': 'rename-doc',
        'originalPath': 'payloads/未分类/paper.md',
        'targetPath': 'payloads/未分类/renamed.md',
      }),
    );
    await managed.rename(renamed.path);

    final documents = await LocalFileLibraryStore(workspace).loadDocuments();

    expect(documents.single.path, managed.path);
    expect(await managed.exists(), isTrue);
    expect(await renamed.exists(), isFalse);
    expect(await journal.exists(), isFalse);
  });

  test('manifest load rolls back a delete interrupted before commit', () async {
    final root = await Directory.systemTemp.createTemp(
      'research_life_delete_journal',
    );
    addTearDown(() => root.delete(recursive: true));
    final workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    final source = File('${root.path}${Platform.pathSeparator}keep.md');
    await source.writeAsString('keep');
    final managed = await workspace.copyFileIntoMaterials(source);
    final now = DateTime(2026, 8, 9);
    await LocalFileLibraryStore(workspace).saveDocument(
      PdfLibraryDocument(
        id: 'delete-doc',
        title: 'keep',
        path: managed.path,
        fileKind: WorkspaceFileKind.text,
        category: '未分类',
        createdAt: now,
        updatedAt: now,
        inReadingList: false,
      ),
    );
    final staged = File(
      '${managed.parent.path}${Platform.pathSeparator}.deleting-keep.md',
    );
    final library = await workspace.resolveLocalFileLibraryDirectory();
    final journal = File(
      '${library.path}${Platform.pathSeparator}.managed_file_operation.json',
    );
    await journal.writeAsString(
      jsonEncode({
        'version': 1,
        'type': 'delete',
        'documentId': 'delete-doc',
        'originalPath': 'payloads/未分类/keep.md',
        'targetPath': 'payloads/未分类/.deleting-keep.md',
      }),
    );
    await managed.rename(staged.path);

    final documents = await LocalFileLibraryStore(workspace).loadDocuments();

    expect(documents.single.id, 'delete-doc');
    expect(await managed.exists(), isTrue);
    expect(await staged.exists(), isFalse);
    expect(await journal.exists(), isFalse);
  });

  test('backup validation rejects a manifest with a missing payload', () async {
    final root = await Directory.systemTemp.createTemp(
      'research_life_missing_payload',
    );
    addTearDown(() => root.delete(recursive: true));
    final workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    final library = await workspace.resolveLocalFileLibraryDirectory();
    final missingPayload = File(
      '${library.path}${Platform.pathSeparator}payloads'
      '${Platform.pathSeparator}未分类${Platform.pathSeparator}missing.pdf',
    );
    final now = DateTime(2026, 8, 9);
    await LocalFileLibraryStore(workspace).saveDocument(
      PdfLibraryDocument(
        id: 'missing-doc',
        title: 'missing',
        path: missingPayload.path,
        fileKind: WorkspaceFileKind.pdf,
        category: '未分类',
        createdAt: now,
        updatedAt: now,
        inReadingList: false,
      ),
    );
    await _writeSqliteDatabase(workspace, 'source');

    expect(
      () => BackupService(workspaceService: workspace).createBackup(),
      throwsA(isA<BackupValidationException>()),
    );
  });

  test('stale metadata save preserves a peer-renamed managed path', () async {
    final root = await Directory.systemTemp.createTemp(
      'research_life_stale_metadata',
    );
    addTearDown(() => root.delete(recursive: true));
    final workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    final source = File('${root.path}${Platform.pathSeparator}old.pdf');
    await source.writeAsBytes([1, 2, 3]);
    final managed = await workspace.copyFileIntoMaterials(source);
    final now = DateTime(2026, 8, 9);
    final original = PdfLibraryDocument(
      id: 'shared-doc',
      title: 'old',
      path: managed.path,
      createdAt: now,
      updatedAt: now,
    );
    final firstStore = LocalFileLibraryStore(workspace);
    final secondStore = LocalFileLibraryStore(workspace);
    await firstStore.saveDocument(original);
    final stale = (await secondStore.loadDocuments()).single;
    final renamedFile = await workspace.renameManagedFile(managed, 'new');
    await firstStore.saveDocument(
      original.copyWith(title: 'new', path: renamedFile.path),
    );

    await secondStore.saveDocument(
      stale.copyWith(lastPage: 7, updatedAt: now.add(const Duration(hours: 1))),
      mergeMetadata: true,
    );

    final persisted = (await LocalFileLibraryStore(
      workspace,
    ).loadDocuments()).single;
    expect(persisted.path, renamedFile.path);
    expect(persisted.title, 'new');
    expect(persisted.lastPage, 7);
    expect(await renamedFile.exists(), isTrue);
  });

  test('backup validation rejects an active document with no path', () async {
    final root = await Directory.systemTemp.createTemp(
      'research_life_empty_payload_path',
    );
    addTearDown(() => root.delete(recursive: true));
    final workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    final now = DateTime(2026, 8, 9);
    await LocalFileLibraryStore(workspace).saveDocument(
      PdfLibraryDocument(
        id: 'empty-doc',
        title: 'empty',
        path: '',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _writeSqliteDatabase(workspace, 'source');

    expect(
      () => BackupService(workspaceService: workspace).createBackup(),
      throwsA(isA<BackupValidationException>()),
    );
  });
}

Map<String, Object?> _legacyDocumentJson(String id, String path) {
  return {
    'id': id,
    'title': id,
    'path': path,
    'fileKind': 'text',
    'category': '论文',
    'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
    'updatedAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
  };
}

Future<void> _writeSqliteDatabase(
  LocalWorkspaceService workspace,
  String value,
) async {
  final databaseFile = await workspace.resolveDatabaseFile();
  await databaseFile.parent.create(recursive: true);
  final database = sqlite3.open(databaseFile.path);
  try {
    database
      ..execute('CREATE TABLE IF NOT EXISTS state (value TEXT NOT NULL);')
      ..execute('DELETE FROM state;')
      ..execute('INSERT INTO state (value) VALUES (?);', [value])
      ..execute('PRAGMA user_version = ${AppDatabase.currentSchemaVersion};')
      ..execute('PRAGMA wal_checkpoint(TRUNCATE);');
  } finally {
    database.close();
  }
}
