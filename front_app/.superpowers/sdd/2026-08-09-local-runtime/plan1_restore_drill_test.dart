import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/local_app_runtime.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/storage/backup_manifest.dart';
import 'package:research_life/services/storage/backup_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';

void main() {
  test('Plan 1 migration backup restores every local data class after restart',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'research_life_plan1_restore_drill',
    );
    final workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    LocalAppRuntime? activeRuntime;

    late Future<BackupRestoreResult> Function(Directory) restoreRuntime;
    restoreRuntime = (backupDirectory) async {
      final retiring = activeRuntime!;
      await retiring.close();
      final result = await BackupService(
        workspaceService: workspace,
      ).restoreBackup(backupDirectory);
      activeRuntime = await LocalAppRuntime.open(
        workspaceService: workspace,
        restoreRuntime: restoreRuntime,
        requestExit: () async {},
        initializeTray: false,
      );
      return result;
    };

    addTearDown(() async {
      try {
        await activeRuntime?.close();
      } catch (_) {
        // The drill reports the primary assertion or restore failure.
      }
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    activeRuntime = await _step(
      'initial runtime open',
      LocalAppRuntime.open(
        workspaceService: workspace,
        restoreRuntime: restoreRuntime,
        requestExit: () async {},
        initializeTray: false,
      ),
    );
    final controller = activeRuntime!.controller;
    controller.addManualEvent(
      date: DateTime(2026, 8, 11),
      title: '原始科研事件',
      category: ItemCategory.study,
      type: EventType.plan,
    );
    await controller.createNote(
      title: '原始笔记',
      contentMarkdown: '原始笔记内容',
    );
    final source = File('${root.path}${Platform.pathSeparator}original.pdf');
    await source.writeAsBytes(<int>[1, 3, 3, 7, 9], flush: true);
    final document = await controller.addPdfDocumentFromPath(source.path);
    final annotation = await controller.addPdfAnnotation(
      documentId: document.id,
      pageNumber: 1,
      kind: PdfAnnotationKind.highlight,
      selectedText: '原始批注文本',
      rects: const [
        PdfAnnotationRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      ],
      colorValue: 0xFFFFCC00,
      opacity: 0.35,
      note: '原始批注',
    );
    expect(annotation, isNotNull);
    await controller.flushLocalPersistence();
    final originalHash = sha256
        .convert(await File(document.path).readAsBytes())
        .toString();

    final backup = await _step(
      'migration backup create',
      BackupService(
        workspaceService: workspace,
      ).createBackup(purpose: BackupPurpose.migration),
    );
    expect(
      await BackupService(
        workspaceService: workspace,
      ).validateBackup(backup.directory),
      isNotNull,
    );

    controller.addManualEvent(
      date: DateTime(2026, 8, 12),
      title: '篡改事件',
      category: ItemCategory.life,
      type: EventType.record,
    );
    final note = controller.notes.single;
    await controller.updateNote(
      note.id,
      title: '篡改笔记',
      contentMarkdown: '篡改内容',
    );
    await controller.renameLocalPdfDocument(document.id, 'mutated-document');
    final mutatedDocument = controller.pdfDocumentById(document.id)!;
    await File(mutatedDocument.path).writeAsBytes(
      <int>[9, 9, 9],
      flush: true,
    );
    controller.updatePdfAnnotation(
      document.id,
      annotation!.id,
      note: '篡改批注',
    );
    await controller.flushLocalPersistence();

    await _step(
      'runtime restore and reopen',
      activeRuntime!.backupController.restore(backup.directory),
    );

    final restoredController = activeRuntime!.controller;
    expect(
      restoredController.manualEvents.map((event) => event.title),
      contains('原始科研事件'),
    );
    expect(
      restoredController.manualEvents.map((event) => event.title),
      isNot(contains('篡改事件')),
    );
    expect(restoredController.notes.single.title, '原始笔记');
    expect(restoredController.notes.single.contentMarkdown, '原始笔记内容');
    final restoredDocument = restoredController.pdfDocumentById(document.id)!;
    expect(restoredDocument.title, 'original');
    expect(await File(restoredDocument.path).exists(), isTrue);
    expect(
      sha256.convert(await File(restoredDocument.path).readAsBytes()).toString(),
      originalHash,
    );
    final restoredAnnotation = restoredController
        .pdfAnnotationsFor(document.id)
        .single;
    expect(restoredAnnotation.selectedText, '原始批注文本');
    expect(restoredAnnotation.note, '原始批注');
  });
}

Future<T> _step<T>(String label, Future<T> operation) async {
  // ignore: avoid_print
  print('DRILL STEP: $label');
  final result = await operation.timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException(label),
  );
  // ignore: avoid_print
  print('DRILL PASS: $label');
  return result;
}
