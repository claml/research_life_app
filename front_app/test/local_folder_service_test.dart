import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/database/app_database.dart'
    hide PdfLibraryDocument;
import 'package:research_life/services/database/repositories/pdf_documents_repository.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';
import 'package:research_life/services/storage/local_file_library_store.dart';
import 'package:research_life/services/storage/local_folder_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  late Directory root;
  late LocalWorkspaceService workspace;
  late LocalDataOperationCoordinator coordinator;
  late _FailingPathStore store;
  late LocalFolderService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('local_folder_service_test');
    workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    coordinator = LocalDataOperationCoordinator();
    store = _FailingPathStore(workspace, operationCoordinator: coordinator);
    service = LocalFolderService(
      workspaceService: workspace,
      store: store,
      operationCoordinator: coordinator,
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'renames a folder and rewrites every descendant document path',
    () async {
      final payloads = await workspace.resolveManagedFilePayloadsDirectory();
      final oldFolder = Directory(p.join(payloads.path, '旧文件夹'));
      final nestedFolder = Directory(p.join(oldFolder.path, '子目录'));
      await nestedFolder.create(recursive: true);
      final firstFile = File(p.join(oldFolder.path, 'a.pdf'));
      final secondFile = File(p.join(nestedFolder.path, 'b.pdf'));
      await firstFile.writeAsBytes(const [1]);
      await secondFile.writeAsBytes(const [2]);
      final createdAt = DateTime(2026, 8, 11);
      await store.saveDocument(
        PdfLibraryDocument(
          id: 'doc_a',
          title: 'a.pdf',
          path: firstFile.path,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      await store.saveDocument(
        PdfLibraryDocument(
          id: 'doc_b',
          title: 'b.pdf',
          path: secondFile.path,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );

      final renamed = await service.renameFolder(
        folder: oldFolder,
        newName: '新文件夹',
      );

      expect(renamed.path, p.join(payloads.path, '新文件夹'));
      expect(await oldFolder.exists(), isFalse);
      expect(await File(p.join(renamed.path, 'a.pdf')).exists(), isTrue);
      expect(
        (await store.findById('doc_a'))!.path,
        p.join(renamed.path, 'a.pdf'),
      );
      expect(
        (await store.findById('doc_b'))!.path,
        p.join(renamed.path, '子目录', 'b.pdf'),
      );
    },
  );

  test('manifest failure rolls the directory name back', () async {
    final payloads = await workspace.resolveManagedFilePayloadsDirectory();
    final oldFolder = Directory(p.join(payloads.path, '旧文件夹'));
    await oldFolder.create(recursive: true);
    final file = File(p.join(oldFolder.path, 'a.pdf'));
    await file.writeAsBytes(const [1]);
    final createdAt = DateTime(2026, 8, 11);
    await store.saveDocument(
      PdfLibraryDocument(
        id: 'doc_a',
        title: 'a.pdf',
        path: file.path,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    store.failNextPathReplacement = true;

    await expectLater(
      service.renameFolder(folder: oldFolder, newName: '新文件夹'),
      throwsA(isA<LocalFolderException>()),
    );

    expect(await oldFolder.exists(), isTrue);
    expect(await Directory(p.join(payloads.path, '新文件夹')).exists(), isFalse);
    expect((await store.findById('doc_a'))!.path, file.path);
  });

  test(
    'controller reloads renamed paths while preserving document ids',
    () async {
      final payloads = await workspace.resolveManagedFilePayloadsDirectory();
      final oldFolder = Directory(p.join(payloads.path, '旧文件夹'));
      await oldFolder.create(recursive: true);
      final file = File(p.join(oldFolder.path, 'a.pdf'));
      await file.writeAsBytes(const [1]);
      final createdAt = DateTime(2026, 8, 11);
      await store.saveDocument(
        PdfLibraryDocument(
          id: 'selected_doc',
          title: 'a.pdf',
          path: file.path,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final controller = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspace,
        pdfDocumentsRepository: PdfDocumentsRepository(
          database,
          localStore: store,
        ),
        localFolderService: service,
        localDataOperationCoordinator: coordinator,
      );
      addTearDown(controller.dispose);
      await controller.ensurePdfLibraryLoaded();

      final message = await controller.renameLocalFolder(
        oldFolder.path,
        '新文件夹',
      );

      expect(message, '已重命名文件夹。');
      expect(controller.pdfDocumentById('selected_doc'), isNotNull);
      expect(
        controller.pdfDocumentById('selected_doc')!.path,
        p.join(payloads.path, '新文件夹', 'a.pdf'),
      );
    },
  );
}

class _FailingPathStore extends LocalFileLibraryStore {
  _FailingPathStore(
    super.workspaceService, {
    required super.operationCoordinator,
  });

  bool failNextPathReplacement = false;

  @override
  Future<void> replaceDocumentPaths(Map<String, String> paths) {
    if (failNextPathReplacement) {
      failNextPathReplacement = false;
      throw StateError('simulated manifest failure');
    }
    return super.replaceDocumentPaths(paths);
  }
}
