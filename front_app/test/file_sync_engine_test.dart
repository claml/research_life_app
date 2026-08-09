import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/core/network/api_client.dart';
import 'package:research_life/services/database/app_database.dart' as db;
import 'package:research_life/services/database/repositories/pdf_documents_repository.dart';
import 'package:research_life/services/database/repositories/sync_outbox_repository.dart';
import 'package:research_life/services/storage/local_file_library_store.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/services/sync/device_id_service.dart';
import 'package:research_life/services/sync/file_sync_api.dart';
import 'package:research_life/services/sync/file_sync_engine.dart';
import 'package:research_life/services/sync/sync_models.dart';

void main() {
  late Directory tempDir;
  late db.AppDatabase database;
  late SyncOutboxRepository outboxRepository;
  late PdfDocumentsRepository pdfRepository;
  late FileSyncEngine engine;
  late _FakeFileSyncApi api;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_sync_engine_test');
    database = db.AppDatabase(NativeDatabase.memory());
    outboxRepository = SyncOutboxRepository(database);
    final workspaceService = LocalWorkspaceService(
      storageDirectoryResolver: () async => tempDir,
    );
    pdfRepository = PdfDocumentsRepository(
      database,
      localStore: LocalFileLibraryStore(workspaceService),
      outboxRepository: outboxRepository,
      deviceIdReader: () async => 'device_test',
    );
    api = _FakeFileSyncApi();
    engine = FileSyncEngine(
      apiClient: ApiClient(),
      pdfRepository: pdfRepository,
      outboxRepository: outboxRepository,
      workspaceService: workspaceService,
      deviceIdService: _FixedDeviceIdService(),
      fileSyncApi: api,
    );
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'does not delete remote-only annotations during annotation sync',
    () async {
      api.annotationRows = [
        _remoteAnnotation(
          serverId: 10,
          clientId: 'remote_only',
          documentClientId: 'doc_1',
        ),
        _remoteAnnotation(
          serverId: 11,
          clientId: 'delete_me',
          documentClientId: 'doc_1',
        ),
      ];

      final synced = await engine.syncDocumentAnnotations(
        serverId: 99,
        documentClientId: 'doc_1',
        annotations: [
          _annotation(id: 'local_new', documentId: 'doc_1'),
          _annotation(
            id: 'delete_me',
            documentId: 'doc_1',
            isDeleted: true,
            serverId: 11,
          ),
        ],
      );

      expect(api.createdAnnotationClientIds, ['local_new']);
      expect(api.deletedAnnotationServerIds, [11]);
      expect(api.deletedAnnotationServerIds, isNot(contains(10)));
      expect(
        synced.map((annotation) => annotation.id),
        containsAll(['local_new', 'remote_only']),
      );
    },
  );

  test('pullRemoteChanges preserves annotation rectangles', () async {
    api.pullResults = [
      SyncPullResult(
        changes: [
          SyncChange(
            clientId: 'anno_1',
            serverId: 77,
            entityType: 'document_annotation',
            version: 3,
            updatedAt: DateTime(2026, 5, 17, 12),
            deviceId: 'device_remote',
            isDeleted: false,
            payload: {
              'documentClientId': 'doc_1',
              'pageNumber': 2,
              'type': 'highlight',
              'colorValue': 0xFFFFFF00,
              'opacity': 0.35,
              'selectedText': 'important',
              'rectsJson': jsonEncode([
                {'left': 0.1, 'top': 0.2, 'right': 0.4, 'bottom': 0.5},
              ]),
            },
          ),
        ],
        nextCursor: 1,
        hasMore: false,
      ),
    ];

    await engine.pullRemoteChanges();

    final annotations = await pdfRepository.loadAnnotations('doc_1');
    expect(annotations, hasLength(1));
    expect(annotations.single.rects, hasLength(1));
    expect(annotations.single.rects.single.left, 0.1);
    expect(annotations.single.rects.single.bottom, 0.5);
  });

  test('pushOutbox removes only changes acknowledged by server', () async {
    await outboxRepository.enqueue(
      entityType: 'file_entry',
      entityId: 'doc_applied',
      operation: 'upsert',
      payload: const {'clientId': 'doc_applied'},
      syncVersion: 2,
      deviceId: 'device_test',
    );
    await outboxRepository.enqueue(
      entityType: 'file_entry',
      entityId: 'doc_pending',
      operation: 'upsert',
      payload: const {'clientId': 'doc_pending'},
      syncVersion: 2,
      deviceId: 'device_test',
    );
    api.pushResponse = [
      SyncChange(
        clientId: 'doc_applied',
        entityType: 'file_entry',
        version: 2,
        updatedAt: DateTime(2026, 5, 17),
        deviceId: 'device_test',
        isDeleted: false,
      ),
    ];

    await engine.pushOutbox();

    final pending = await outboxRepository.pending();
    expect(pending, hasLength(1));
    expect(pending.single.entityId, 'doc_pending');
    expect(pending.single.retryCount, 1);
  });

  test(
    'loadStatus reports pending uploads, retrying outbox and cursor',
    () async {
      final pdf = File('${tempDir.path}${Platform.pathSeparator}paper.pdf');
      await pdf.writeAsBytes(const [1, 2, 3]);
      final now = DateTime(2026, 5, 17, 12);
      await pdfRepository.replaceAllDocuments([
        PdfLibraryDocument(
          id: 'doc_pending_upload',
          title: 'Paper',
          path: pdf.path,
          createdAt: now,
          updatedAt: now,
        ),
        PdfLibraryDocument(
          id: 'doc_synced',
          title: 'Synced',
          path: pdf.path,
          createdAt: now,
          updatedAt: now,
          storageKey: 'objects/doc_synced.pdf',
          contentHash: 'hash',
        ),
      ]);
      await outboxRepository.enqueue(
        entityType: 'file_entry',
        entityId: 'doc_retry',
        operation: 'upsert',
        payload: const {'clientId': 'doc_retry'},
        syncVersion: 2,
        deviceId: 'device_test',
      );
      final pending = await outboxRepository.pending();
      await outboxRepository.incrementRetry(pending.single.id);
      await outboxRepository.writeCursor(FileSyncEngine.filesCursorScope, 42);

      final status = await engine.loadStatus();

      expect(status.pendingUploadCount, 1);
      expect(status.pendingOutboxCount, 1);
      expect(status.retryingOutboxCount, 1);
      expect(status.cursorValue, 42);
      expect(status.lastSyncedAt, isNotNull);
      expect(status.totalPendingCount, 2);
      expect(status.hasRetryingItems, isTrue);
    },
  );
}

PdfTextAnnotation _annotation({
  required String id,
  required String documentId,
  bool isDeleted = false,
  int? serverId,
}) {
  final now = DateTime(2026, 5, 17, 12);
  return PdfTextAnnotation(
    id: id,
    documentId: documentId,
    pageNumber: 1,
    kind: PdfAnnotationKind.highlight,
    colorValue: 0xFFFFFF00,
    opacity: 0.35,
    selectedText: 'text',
    rects: const [
      PdfAnnotationRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    ],
    createdAt: now,
    updatedAt: now,
    serverId: serverId,
    syncVersion: 1,
    isDeleted: isDeleted,
  );
}

Map<String, dynamic> _remoteAnnotation({
  required int serverId,
  required String clientId,
  required String documentClientId,
}) {
  return {
    'serverId': serverId,
    'clientId': clientId,
    'documentClientId': documentClientId,
    'pageNumber': 1,
    'type': 'highlight',
    'colorValue': 0xFFFFFF00,
    'opacity': 0.35,
    'selectedText': 'remote',
    'rectsJson': '[]',
    'version': 1,
    'deviceId': 'device_remote',
    'isDeleted': false,
  };
}

class _FixedDeviceIdService extends DeviceIdService {
  @override
  Future<String> getOrCreateDeviceId() async => 'device_test';
}

class _FakeFileSyncApi implements FileSyncRemoteApi {
  List<Map<String, dynamic>> annotationRows = [];
  List<SyncPullResult> pullResults = [];
  List<SyncChange> pushResponse = const [];
  final createdAnnotationClientIds = <String>[];
  final deletedAnnotationServerIds = <int>[];

  @override
  Future<Map<String, dynamic>> createAnnotation(
    int documentServerId,
    Map<String, dynamic> body,
  ) async {
    createdAnnotationClientIds.add('${body['clientId']}');
    return {
      ...body,
      'serverId': 100 + createdAnnotationClientIds.length,
      'version': 1,
      'createdAt': DateTime(2026, 5, 17, 12).toIso8601String(),
      'updatedAt': DateTime(2026, 5, 17, 12).toIso8601String(),
      'isDeleted': false,
    };
  }

  @override
  Future<void> deleteAnnotation(
    int documentServerId,
    int annotationServerId,
    String deviceId,
  ) async {
    deletedAnnotationServerIds.add(annotationServerId);
  }

  @override
  Future<List<Map<String, dynamic>>> listAnnotations(
    int documentServerId,
  ) async {
    return annotationRows;
  }

  @override
  Future<List<Map<String, dynamic>>> listUserNotes() async => const [];

  @override
  Future<SyncPullResult> pullChanges({int cursor = 0}) async {
    if (pullResults.isEmpty) {
      return const SyncPullResult(changes: [], nextCursor: 0, hasMore: false);
    }
    return pullResults.removeAt(0);
  }

  @override
  Future<List<SyncChange>> pushChanges({
    required String deviceId,
    required List<SyncChange> changes,
  }) async {
    return pushResponse;
  }

  @override
  Future<Map<String, dynamic>> updateAnnotation(
    int documentServerId,
    int annotationServerId,
    Map<String, dynamic> body,
  ) async {
    return {
      ...body,
      'serverId': annotationServerId,
      'version': body['version'] ?? 1,
      'createdAt': DateTime(2026, 5, 17, 12).toIso8601String(),
      'updatedAt': DateTime(2026, 5, 17, 12).toIso8601String(),
      'isDeleted': false,
    };
  }

  @override
  Future<Map<String, dynamic>> completeUpload(Map<String, dynamic> body) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> createFile(Map<String, dynamic> body) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> createFolder(Map<String, dynamic> body) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteFile(int serverId, String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> directUpload(FormData form) {
    throw UnimplementedError();
  }

  @override
  Future<String> downloadUrl(int serverId) {
    throw UnimplementedError();
  }

  @override
  Future<UploadInitResult> initUpload(Map<String, dynamic> body) {
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, dynamic>>> listFiles({
    required String deviceId,
    bool reconcile = true,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> moveFile(
    int serverId,
    Map<String, dynamic> body,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> reconcileStorage(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> updateFile(
    int serverId,
    Map<String, dynamic> body,
  ) {
    throw UnimplementedError();
  }
}
