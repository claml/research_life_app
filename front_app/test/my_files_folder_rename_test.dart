import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:research_life/app/research_life_scope.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/features/files/my_files_page.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens folder rename with the selected document folder name', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    final fixture = (await tester.runAsync(_createFixture))!;
    addTearDown(fixture.controller.dispose);
    addTearDown(fixture.database.close);
    addTearDown(() => fixture.root.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ResearchLifeScope(
          controller: fixture.controller,
          child: const Scaffold(body: MyFilesPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.pdf'));
    await tester.pump();

    await tester.tap(find.text('重命名文件夹'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '旧文件夹');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final selectedTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'a.pdf'),
    );
    expect(selectedTile.selected, isTrue);
  });
}

Future<
  ({
    Directory root,
    Directory payloads,
    AppDatabase database,
    ResearchLifeController controller,
  })
>
_createFixture() async {
  final root = await Directory.systemTemp.createTemp(
    'my_files_folder_rename_test',
  );
  final workspace = LocalWorkspaceService(
    storageDirectoryResolver: () async => root,
  );
  final coordinator = LocalDataOperationCoordinator();
  final store = LocalFileLibraryStore(
    workspace,
    operationCoordinator: coordinator,
  );
  final service = LocalFolderService(
    workspaceService: workspace,
    store: store,
    operationCoordinator: coordinator,
  );
  final payloads = await workspace.resolveManagedFilePayloadsDirectory();
  final folder = Directory(p.join(payloads.path, '旧文件夹'));
  await folder.create(recursive: true);
  final file = File(p.join(folder.path, 'a.pdf'));
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
  final controller = ResearchLifeController(
    importService: const ImportService(),
    analysisService: const AnalysisService(),
    reviewService: const ReviewService(),
    institutionCalendarService: const InstitutionCalendarService(),
    localWorkspaceService: workspace,
    pdfDocumentsRepository: PdfDocumentsRepository(database, localStore: store),
    localFolderService: service,
    localDataOperationCoordinator: coordinator,
  );
  await controller.ensurePdfLibraryLoaded();
  return (
    root: root,
    payloads: payloads,
    database: database,
    controller: controller,
  );
}
