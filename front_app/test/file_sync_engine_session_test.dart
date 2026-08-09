import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/core/network/api_client.dart';
import 'package:research_life/services/database/app_database.dart' as db;
import 'package:research_life/services/database/repositories/pdf_documents_repository.dart';
import 'package:research_life/services/database/repositories/sessions_repository.dart';
import 'package:research_life/services/database/repositories/sync_outbox_repository.dart';
import 'package:research_life/services/storage/local_file_library_store.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/services/sync/device_id_service.dart';
import 'package:research_life/services/sync/file_sync_api.dart';
import 'package:research_life/services/sync/file_sync_engine.dart';
import 'package:research_life/services/sync/sync_models.dart';

class _SessionFakeApi implements FileSyncRemoteApi {
  final List<SyncChange> pushedChanges = [];
  List<SyncPullResult> pullResults = [];

  @override
  Future<List<SyncChange>> pushChanges({
    required String deviceId,
    required List<SyncChange> changes,
  }) async {
    pushedChanges.addAll(changes);
    return changes;
  }

  @override
  Future<SyncPullResult> pullChanges({int cursor = 0}) async {
    if (pullResults.isEmpty) {
      return const SyncPullResult(changes: [], nextCursor: 0, hasMore: false);
    }
    return pullResults.removeAt(0);
  }

  @override
  Future<Map<String, dynamic>> createAnnotation(
    int documentServerId,
    Map<String, dynamic> body,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteAnnotation(
    int documentServerId,
    int annotationServerId,
    String deviceId,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, dynamic>>> listAnnotations(int documentServerId) {
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, dynamic>>> listUserNotes() {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> updateAnnotation(
    int documentServerId,
    int annotationServerId,
    Map<String, dynamic> body,
  ) {
    throw UnimplementedError();
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

class _FixedDeviceIdService extends DeviceIdService {
  @override
  Future<String> getOrCreateDeviceId() async => 'device_test';
}

void main() {
  late Directory tempDir;
  late db.AppDatabase database;
  late SyncOutboxRepository outboxRepository;
  late SessionsRepository sessionsRepository;
  late _SessionFakeApi api;
  late FileSyncEngine engine;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'file_sync_engine_session_test',
    );
    database = db.AppDatabase(NativeDatabase.memory());
    outboxRepository = SyncOutboxRepository(database);
    sessionsRepository = SessionsRepository(database);
    final workspaceService = LocalWorkspaceService(
      storageDirectoryResolver: () async => tempDir,
    );
    final pdfRepository = PdfDocumentsRepository(
      database,
      localStore: LocalFileLibraryStore(workspaceService),
      outboxRepository: outboxRepository,
      deviceIdReader: () async => 'device_test',
    );
    api = _SessionFakeApi();
    engine = FileSyncEngine(
      apiClient: ApiClient(),
      pdfRepository: pdfRepository,
      outboxRepository: outboxRepository,
      workspaceService: workspaceService,
      sessionsRepository: sessionsRepository,
      deviceIdService: _FixedDeviceIdService(),
      fileSyncApi: api,
    );
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  SessionRecord _session(String id) {
    return SessionRecord(
      id: id,
      title: '$id 周分析',
      input: AnalysisInput(
        rawText: '这周完成了文献阅读。',
        sourceType: AnalysisSourceType.text,
      ),
      draft: AnalysisDraft(
        id: 'draft_$id',
        tasks: const [],
        persons: const [],
        summary: '',
        warnings: const [],
        createdAt: DateTime(2026, 4, 26),
      ),
      preview: ReviewPreview(
        id: 'preview_$id',
        completedTasks: const [],
        plannedTasks: const [],
        persons: const [],
        summary: '',
        warnings: const [],
        relationLabels: const [],
      ),
      events: const [],
      people: const [],
      confirmedAt: DateTime(2026, 4, 26),
    );
  }

  test('pushes session snapshots to cloud', () async {
    final session = _session('s1');

    await engine.enqueueSession(session);

    final report = await engine.syncAll();

    expect(api.pushedChanges, hasLength(1));
    final pushed = api.pushedChanges.single;
    expect(pushed.entityType, 'user_session');
    expect(pushed.clientId, 's1');
    final snapshot = pushed.payload?['snapshotJson'] as String;
    expect(snapshot, contains('s1'));
    expect(snapshot, contains('周分析'));
    expect(report.uploadedFileCount, 0);
  });

  test('applies remote session snapshots into local sessions', () async {
    final session = _session('remote_s');
    final snapshot = await sessionsRepository.snapshotJsonFor(session);

    api.pullResults = [
      SyncPullResult(
        changes: [
          SyncChange(
            serverId: 9,
            clientId: 'remote_s',
            entityType: 'user_session',
            version: 1,
            updatedAt: DateTime(2026, 4, 26, 12),
            deviceId: 'remote',
            isDeleted: false,
            payload: {
              'clientId': 'remote_s',
              'title': 'remote_s 周分析',
              'snapshotJson': snapshot,
              'updatedAt': DateTime(2026, 4, 26, 12).toIso8601String(),
            },
          ),
        ],
        nextCursor: 1,
        hasMore: false,
      ),
    ];

    await engine.syncAll();

    final sessions = await sessionsRepository.loadSessions();
    expect(sessions, hasLength(1));
    expect(sessions.single.id, 'remote_s');
    expect(sessions.single.title, contains('周分析'));
  });
}
