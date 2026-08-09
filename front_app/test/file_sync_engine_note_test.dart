import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/core/network/api_client.dart';
import 'package:research_life/services/database/app_database.dart' as db;
import 'package:research_life/services/database/repositories/notes_repository.dart';
import 'package:research_life/services/database/repositories/pdf_documents_repository.dart';
import 'package:research_life/services/database/repositories/sync_outbox_repository.dart';
import 'package:research_life/services/storage/local_file_library_store.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/services/sync/device_id_service.dart';
import 'package:research_life/services/sync/file_sync_api.dart';
import 'package:research_life/services/sync/file_sync_engine.dart';
import 'package:research_life/services/sync/sync_models.dart';

class _NoteFakeApi implements FileSyncRemoteApi {
  final List<SyncChange> pushedChanges = [];
  List<SyncPullResult> pullResults = [];
  bool confirmPushed = true;

  @override
  Future<List<SyncChange>> pushChanges({
    required String deviceId,
    required List<SyncChange> changes,
  }) async {
    pushedChanges.addAll(changes);
    return confirmPushed ? changes : const [];
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

SyncChange _noteChange({
  required String clientId,
  bool isDeleted = false,
  Map<String, dynamic>? payload,
}) {
  return SyncChange(
    serverId: 7,
    clientId: clientId,
    entityType: 'user_note',
    version: 1,
    updatedAt: DateTime(2026, 4, 26, 12),
    deviceId: 'remote-device',
    isDeleted: isDeleted,
    payload: payload ??
        {
          'clientId': clientId,
          'title': '云端笔记',
          'contentMarkdown': '# 标题\n\n来自云端的正文',
          'updatedAt': DateTime(2026, 4, 26, 12).toIso8601String(),
        },
  );
}

void main() {
  late Directory tempDir;
  late db.AppDatabase database;
  late SyncOutboxRepository outboxRepository;
  late NotesRepository notesRepository;
  late _NoteFakeApi api;
  late FileSyncEngine engine;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_sync_engine_note_test');
    database = db.AppDatabase(NativeDatabase.memory());
    outboxRepository = SyncOutboxRepository(database);
    notesRepository = NotesRepository(database);
    final workspaceService = LocalWorkspaceService(
      storageDirectoryResolver: () async => tempDir,
    );
    final pdfRepository = PdfDocumentsRepository(
      database,
      localStore: LocalFileLibraryStore(workspaceService),
      outboxRepository: outboxRepository,
      deviceIdReader: () async => 'device_test',
    );
    api = _NoteFakeApi();
    engine = FileSyncEngine(
      apiClient: ApiClient(),
      pdfRepository: pdfRepository,
      outboxRepository: outboxRepository,
      workspaceService: workspaceService,
      notesRepository: notesRepository,
      deviceIdService: _FixedDeviceIdService(),
      fileSyncApi: api,
    );
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test('pushes notes to cloud and clears outbox', () async {
    final note = UserNote(
      id: 'note_1',
      title: '实验记录',
      contentMarkdown: '# 记录\n- 第一步\n- 第二步',
      createdAt: DateTime(2026, 4, 26),
      updatedAt: DateTime(2026, 4, 26),
    );

    await engine.enqueueNote(note);

    final report = await engine.syncAll();

    expect(api.pushedChanges, hasLength(1));
    final pushed = api.pushedChanges.single;
    expect(pushed.entityType, 'user_note');
    expect(pushed.clientId, 'note_1');
    expect(pushed.payload?['title'], '实验记录');
    expect(pushed.payload?['contentMarkdown'], contains('第一步'));
    expect(report.uploadedFileCount, 0);
  });

  test('applies remote note changes into local notes', () async {
    api.pullResults = [
      SyncPullResult(
        changes: [_noteChange(clientId: 'remote_note')],
        nextCursor: 1,
        hasMore: false,
      ),
    ];

    await engine.syncAll();

    final notes = await notesRepository.loadNotes();
    expect(notes, hasLength(1));
    expect(notes.single.id, 'remote_note');
    expect(notes.single.title, '云端笔记');
    expect(notes.single.contentMarkdown, contains('来自云端'));
  });

  test('removes local note when remote change is deleted', () async {
    await notesRepository.saveNote(
      UserNote(
        id: 'gone',
        title: '将删除',
        contentMarkdown: '内容',
        createdAt: DateTime(2026, 4, 26),
        updatedAt: DateTime(2026, 4, 26),
      ),
    );

    api.pullResults = [
      SyncPullResult(
        changes: [_noteChange(clientId: 'gone', isDeleted: true)],
        nextCursor: 1,
        hasMore: false,
      ),
    ];

    await engine.syncAll();

    expect(await notesRepository.loadNotes(), isEmpty);
  });

  test('skips remote note while local pending change exists', () async {
    final note = UserNote(
      id: 'pending_note',
      title: '本地新标题',
      contentMarkdown: '本地新内容',
      createdAt: DateTime(2026, 4, 26),
      updatedAt: DateTime(2026, 4, 26),
    );
    await notesRepository.saveNote(note);
    await engine.enqueueNote(note);
    api.confirmPushed = false;

    api.pullResults = [
      SyncPullResult(
        changes: [
          _noteChange(
            clientId: 'pending_note',
            payload: {
              'clientId': 'pending_note',
              'title': '旧远程标题',
              'contentMarkdown': '旧远程内容',
              'updatedAt': DateTime(2026, 4, 26, 9).toIso8601String(),
            },
          ),
        ],
        nextCursor: 1,
        hasMore: false,
      ),
    ];

    await engine.syncAll();

    final notes = await notesRepository.loadNotes();
    expect(notes.single.title, '本地新标题');
  });
}
