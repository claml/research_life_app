import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/core/network/api_client.dart';
import 'package:research_life/services/database/app_database.dart' as db;
import 'package:research_life/services/database/repositories/manual_events_repository.dart';
import 'package:research_life/services/database/repositories/pdf_documents_repository.dart';
import 'package:research_life/services/database/repositories/sync_outbox_repository.dart';
import 'package:research_life/services/database/repositories/todo_status_repository.dart';
import 'package:research_life/services/storage/local_file_library_store.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/services/sync/device_id_service.dart';
import 'package:research_life/services/sync/file_sync_api.dart';
import 'package:research_life/services/sync/file_sync_engine.dart';
import 'package:research_life/services/sync/sync_models.dart';

class _EventFakeApi implements FileSyncRemoteApi {
  final List<SyncChange> pushedChanges = [];
  List<SyncPullResult> pullResults = [];
  bool confirmPushed = true;

  @override
  Future<List<SyncChange>> pushChanges({
    required String deviceId,
    required List<SyncChange> changes,
  }) async {
    pushedChanges.addAll(changes);
    // 模拟服务端确认：原样返回以便引擎清空 Outbox；confirmPushed=false 时不确认。
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

SyncChange _eventChange({
  required String clientId,
  bool isDeleted = false,
  Map<String, dynamic>? payload,
  int version = 1,
}) {
  return SyncChange(
    serverId: 5,
    clientId: clientId,
    entityType: 'user_event',
    version: version,
    updatedAt: DateTime(2026, 4, 26, 12),
    deviceId: 'remote-device',
    isDeleted: isDeleted,
    payload: payload ??
        {
          'clientId': clientId,
          'title': '远程导入的计划',
          'category': 'work',
          'type': 'plan',
          'origin': 'manual',
          'startAt': DateTime(2026, 4, 26).toIso8601String(),
          'sourceLabel': '云同步',
          'isDone': true,
          'priority': 'high',
          'completedAt': DateTime(2026, 4, 26, 10).toIso8601String(),
        },
  );
}

void main() {
  late Directory tempDir;
  late db.AppDatabase database;
  late SyncOutboxRepository outboxRepository;
  late ManualEventsRepository manualEventsRepository;
  late TodoStatusRepository todoStatusRepository;
  late _EventFakeApi api;
  late FileSyncEngine engine;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'file_sync_engine_event_test',
    );
    database = db.AppDatabase(NativeDatabase.memory());
    outboxRepository = SyncOutboxRepository(database);
    manualEventsRepository = ManualEventsRepository(database);
    todoStatusRepository = TodoStatusRepository(database);
    final workspaceService = LocalWorkspaceService(
      storageDirectoryResolver: () async => tempDir,
    );
    final pdfRepository = PdfDocumentsRepository(
      database,
      localStore: LocalFileLibraryStore(workspaceService),
      outboxRepository: outboxRepository,
      deviceIdReader: () async => 'device_test',
    );
    api = _EventFakeApi();
    engine = FileSyncEngine(
      apiClient: ApiClient(),
      pdfRepository: pdfRepository,
      outboxRepository: outboxRepository,
      workspaceService: workspaceService,
      manualEventsRepository: manualEventsRepository,
      todoStatusRepository: todoStatusRepository,
      deviceIdService: _FixedDeviceIdService(),
      fileSyncApi: api,
    );
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test('pushes enqueued events to cloud and clears outbox', () async {
    final event = EventItem(
      id: 'manual_1',
      title: '准备组会',
      category: ItemCategory.work,
      type: EventType.plan,
      startAt: DateTime(2026, 4, 26),
      origin: EventOrigin.manual,
      sourceLabel: '手动添加',
    );

    await engine.enqueueEvent(
      event: event,
      isDone: true,
      priority: TodoPriority.high.name,
      completedAt: DateTime(2026, 4, 26, 10),
    );
    expect(await outboxRepository.loadStats(cursorScope: 'files'), isNotNull);

    final report = await engine.syncAll();

    expect(api.pushedChanges, hasLength(1));
    final pushed = api.pushedChanges.single;
    expect(pushed.entityType, 'user_event');
    expect(pushed.clientId, 'manual_1');
    expect(pushed.payload?['title'], '准备组会');
    expect(pushed.payload?['isDone'], isTrue);
    expect(pushed.payload?['priority'], 'high');
    expect(await outboxRepository.loadStats(cursorScope: 'files'), isNotNull);
    expect(report.uploadedFileCount, 0);
  });

  test('applies remote event changes into local events and todo status',
      () async {
    api.pullResults = [
      SyncPullResult(
        changes: [_eventChange(clientId: 'remote_evt')],
        nextCursor: 1,
        hasMore: false,
      ),
    ];

    await engine.syncAll();

    final events = await manualEventsRepository.loadManualEvents();
    expect(events, hasLength(1));
    expect(events.single.id, 'remote_evt');
    expect(events.single.title, '远程导入的计划');
    expect(events.single.category, ItemCategory.work);

    final status = await todoStatusRepository.loadAll();
    expect(status['remote_evt']?.isDone, isTrue);
    expect(status['remote_evt']?.priority, TodoPriority.high);
  });

  test('removes local event when remote change is deleted', () async {
    await manualEventsRepository.saveManualEvent(
      EventItem(
        id: 'gone',
        title: '将被删除',
        category: ItemCategory.study,
        type: EventType.plan,
        startAt: DateTime(2026, 4, 26),
        origin: EventOrigin.manual,
      ),
    );
    await todoStatusRepository.upsert(
      const EventTodoState(
        eventId: 'gone',
        isDone: true,
        priority: TodoPriority.none,
      ),
    );

    api.pullResults = [
      SyncPullResult(
        changes: [_eventChange(clientId: 'gone', isDeleted: true)],
        nextCursor: 1,
        hasMore: false,
      ),
    ];

    await engine.syncAll();

    expect(await manualEventsRepository.loadManualEvents(), isEmpty);
    expect(await todoStatusRepository.loadAll(), isEmpty);
  });

  test('skips remote event while local pending change exists', () async {
    final event = EventItem(
      id: 'pending_evt',
      title: '本地新值',
      category: ItemCategory.study,
      type: EventType.plan,
      startAt: DateTime(2026, 4, 26),
      origin: EventOrigin.manual,
    );
    // 真实流程：先写本地库，再入同步 Outbox。
    await manualEventsRepository.saveManualEvent(event);
    await engine.enqueueEvent(
      event: event,
      isDone: false,
      priority: TodoPriority.none.name,
    );
    // 服务端未确认推送（模拟 push 失败），Outbox 仍保留本地变更。
    api.confirmPushed = false;

    api.pullResults = [
      SyncPullResult(
        changes: [_eventChange(clientId: 'pending_evt', payload: {
          'clientId': 'pending_evt',
          'title': '旧远程值',
          'category': 'study',
          'type': 'plan',
          'origin': 'manual',
          'startAt': DateTime(2026, 4, 26).toIso8601String(),
          'isDone': false,
          'priority': 'none',
        })],
        nextCursor: 1,
        hasMore: false,
      ),
    ];

    await engine.syncAll();

    final events = await manualEventsRepository.loadManualEvents();
    expect(events.single.title, '本地新值');
  });
}
