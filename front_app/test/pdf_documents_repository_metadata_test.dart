import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/database/app_database.dart'
    hide PdfLibraryDocument;
import 'package:research_life/services/database/repositories/pdf_documents_repository.dart';
import 'package:research_life/services/storage/local_file_library_store.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';

void main() {
  test('metadata save preserves a peer-renamed managed path', () async {
    final root = await Directory.systemTemp.createTemp(
      'pdf_repository_metadata_merge',
    );
    addTearDown(() => root.delete(recursive: true));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    final source = File('${root.path}${Platform.pathSeparator}old.pdf');
    await source.writeAsBytes([1, 2, 3]);
    final managed = await workspace.copyFileIntoMaterials(source);
    final now = DateTime(2026, 8, 12);
    final original = PdfLibraryDocument(
      id: 'shared-document',
      title: 'old',
      path: managed.path,
      createdAt: now,
      updatedAt: now,
    );
    final peerStore = LocalFileLibraryStore(workspace);
    final repository = PdfDocumentsRepository(
      database,
      localStore: LocalFileLibraryStore(workspace),
    );
    await peerStore.saveDocument(original);
    final stale = (await repository.loadDocuments()).single;
    final renamed = await workspace.renameManagedFile(managed, 'new');
    await peerStore.saveDocument(
      original.copyWith(title: 'new', path: renamed.path),
    );

    await repository.saveDocument(
      stale.copyWith(lastPage: 7),
      operation: 'metadata',
    );

    final persisted = (await peerStore.loadDocuments()).single;
    expect(persisted.title, 'new');
    expect(persisted.path, renamed.path);
    expect(persisted.lastPage, 7);
    expect(await renamed.exists(), isTrue);
  });
}
