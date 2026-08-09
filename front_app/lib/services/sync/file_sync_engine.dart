import 'dart:convert';
import 'dart:io';

import '../../core/models/app_models.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../../core/network/api_client.dart';
import '../database/repositories/manual_events_repository.dart';
import '../database/repositories/notes_repository.dart';
import '../database/repositories/pdf_documents_repository.dart';
import '../database/repositories/sessions_repository.dart';
import '../database/repositories/sync_outbox_repository.dart';
import '../database/repositories/todo_status_repository.dart';
import '../storage/local_workspace_service.dart';
import 'cloud_file_service.dart';
import 'device_id_service.dart';
import 'file_sync_api.dart';
import 'sync_models.dart';

class FileSyncEngine {
  FileSyncEngine({
    required ApiClient apiClient,
    required PdfDocumentsRepository pdfRepository,
    required SyncOutboxRepository outboxRepository,
    required LocalWorkspaceService workspaceService,
    ManualEventsRepository? manualEventsRepository,
    TodoStatusRepository? todoStatusRepository,
    NotesRepository? notesRepository,
    SessionsRepository? sessionsRepository,
    DeviceIdService? deviceIdService,
    CloudFileService? cloudFileService,
    FileSyncRemoteApi? fileSyncApi,
  }) : _api = fileSyncApi ?? FileSyncApi(apiClient),
       _cloudFiles = cloudFileService ?? CloudFileService(apiClient: apiClient),
       _pdfRepository = pdfRepository,
       _outboxRepository = outboxRepository,
       _workspaceService = workspaceService,
       _manualEventsRepository = manualEventsRepository,
       _todoStatusRepository = todoStatusRepository,
       _notesRepository = notesRepository,
       _sessionsRepository = sessionsRepository,
       _deviceIdService = deviceIdService ?? DeviceIdService();

  static const filesCursorScope = 'files';

  final FileSyncRemoteApi _api;
  final CloudFileService _cloudFiles;
  final PdfDocumentsRepository _pdfRepository;
  final SyncOutboxRepository _outboxRepository;
  final LocalWorkspaceService _workspaceService;
  final ManualEventsRepository? _manualEventsRepository;
  final TodoStatusRepository? _todoStatusRepository;
  final NotesRepository? _notesRepository;
  final SessionsRepository? _sessionsRepository;
  final DeviceIdService _deviceIdService;
  bool _running = false;

  Future<CloudSyncReport> syncAll() async {
    if (_running) {
      return const CloudSyncReport();
    }
    _running = true;
    try {
      final uploadedFiles = await uploadPendingBinaries();
      await pushOutbox();
      await pullRemoteChanges();
      return CloudSyncReport(uploadedFileCount: uploadedFiles);
    } finally {
      _running = false;
    }
  }

  Future<List<CloudFileEntry>> fetchCloudFileTree({bool reconcile = true}) {
    return _cloudFiles.listCloudFiles(reconcile: reconcile);
  }

  Future<CloudSyncStatus> loadStatus() async {
    final outboxStats = await _outboxRepository.loadStats(
      cursorScope: filesCursorScope,
    );
    return CloudSyncStatus(
      pendingOutboxCount: outboxStats.pendingCount,
      retryingOutboxCount: outboxStats.retryingCount,
      pendingUploadCount: await _countPendingBinaries(),
      cursorValue: outboxStats.cursorValue,
      lastSyncedAt: outboxStats.cursorUpdatedAt,
    );
  }

  Future<int?> _resolveFolderParentId(
    String categoryPath,
    String deviceId,
  ) async {
    await _api.reconcileStorage(deviceId);
    final entries = await _api.listFiles(deviceId: deviceId, reconcile: false);
    CloudFileEntry? root;
    for (final raw in entries) {
      final entry = CloudFileEntry.fromJson(raw);
      if (entry.systemRoot) {
        root = entry;
        break;
      }
    }
    if (root == null) {
      return null;
    }
    final segments = categoryPath.split('/');
    var parentId = root.serverId;
    for (final segment in segments) {
      if (segment.trim().isEmpty) {
        continue;
      }
      CloudFileEntry? folder;
      for (final raw in entries) {
        final entry = CloudFileEntry.fromJson(raw);
        if (entry.isFolder &&
            entry.parentId == parentId &&
            entry.title == segment.trim()) {
          folder = entry;
          break;
        }
      }
      if (folder == null) {
        return parentId;
      }
      parentId = folder.serverId;
    }
    return parentId;
  }

  Future<void> uploadDocument(PdfLibraryDocument document) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    await _migrateSingleDocument(document, deviceId);
  }

  Future<int> uploadPendingBinaries() async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final documents = await _pdfRepository.loadDocuments(includeDeleted: false);
    var uploaded = 0;
    for (final document in documents) {
      if (document.cloudOnly) {
        continue;
      }
      if (document.storageKey != null && document.contentHash != null) {
        continue;
      }
      if (document.path.isEmpty || !File(document.path).existsSync()) {
        continue;
      }
      try {
        await _migrateSingleDocument(document, deviceId);
        uploaded++;
      } catch (_) {
        // 单篇失败不阻断其余文献
      }
    }
    return uploaded;
  }

  Future<int> _countPendingBinaries() async {
    final documents = await _pdfRepository.loadDocuments(includeDeleted: false);
    var pending = 0;
    for (final document in documents) {
      if (document.cloudOnly) {
        continue;
      }
      if (document.storageKey != null && document.contentHash != null) {
        continue;
      }
      if (document.path.isEmpty || !File(document.path).existsSync()) {
        continue;
      }
      pending++;
    }
    return pending;
  }

  Future<void> pushOutbox() async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final pending = await _outboxRepository.pending();
    if (pending.isEmpty) {
      return;
    }
    final changes = <SyncChange>[];
    for (final row in pending) {
      changes.add(
        SyncChange(
          clientId: row.entityId,
          entityType: row.entityType,
          version: row.syncVersion,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
          deviceId: deviceId,
          isDeleted: row.operation == 'delete',
          payload: _decodePayload(row.payloadJson),
        ),
      );
    }
    final applied = await _api.pushChanges(
      deviceId: deviceId,
      changes: changes,
    );
    final appliedKeys = applied
        .map((change) => _changeKey(change.entityType, change.clientId))
        .where((key) => key != null)
        .cast<String>()
        .toSet();
    if (appliedKeys.isEmpty) {
      for (final row in pending) {
        await _outboxRepository.incrementRetry(row.id);
      }
      return;
    }
    for (final row in pending) {
      final key = _changeKey(row.entityType, row.entityId);
      if (key != null && appliedKeys.contains(key)) {
        await _outboxRepository.remove(row.id);
      } else {
        await _outboxRepository.incrementRetry(row.id);
      }
    }
  }

  Future<void> pullRemoteChanges() async {
    var cursor = await _outboxRepository.readCursor(filesCursorScope);
    var hasMore = true;
    while (hasMore) {
      final result = await _api.pullChanges(cursor: cursor);
      for (final change in result.changes) {
        await _applyRemoteChange(change);
      }
      cursor = result.nextCursor;
      hasMore = result.hasMore;
    }
    await _outboxRepository.writeCursor(filesCursorScope, cursor);
  }

  Future<CloudMigrationReport> migrateLocalLibraryToCloud() async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final backupFile = await _workspaceService.createDatabaseBackup();
    final backupPath = backupFile.path;
    final documents = await _pdfRepository.loadDocuments(includeDeleted: false);
    final failures = <CloudMigrationFailure>[];
    var successCount = 0;

    for (final document in documents) {
      try {
        await _migrateSingleDocument(document, deviceId);
        successCount++;
      } catch (error) {
        failures.add(
          CloudMigrationFailure(
            documentId: document.id,
            title: document.title,
            message: '$error',
          ),
        );
      }
    }

    await syncAll();
    return CloudMigrationReport(
      backupPath: backupPath,
      totalCount: documents.length,
      successCount: successCount,
      failures: failures,
    );
  }

  Future<PdfLibraryDocument> importCloudFileToLocal(
    CloudFileEntry entry, {
    bool persist = true,
    bool cloudOnly = false,
  }) async {
    if (entry.isFolder) {
      throw StateError('文件夹无法直接打开阅读');
    }
    final cacheDir = await _workspaceService.resolveMaterialsDirectory();
    final safeName = entry.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final target = File(
      '${cacheDir.path}${Platform.pathSeparator}cloud_${entry.serverId}_$safeName',
    );
    await _cloudFiles.downloadToCache(
      serverId: entry.serverId,
      targetPath: target.path,
    );
    final now = DateTime.now();
    final kind = WorkspaceFileKind.fromPath(target.path);
    final document = PdfLibraryDocument(
      id: entry.clientId.isNotEmpty
          ? entry.clientId
          : 'cloud_${entry.serverId}',
      title: entry.title,
      path: target.path,
      fileKind: kind,
      category: entry.category,
      inReadingList: false,
      lastPage: entry.lastPage,
      pageCount: entry.pageCount,
      createdAt: now,
      updatedAt: now,
      serverId: entry.serverId,
      syncVersion: entry.version,
      syncState: 'synced',
      storageKey: entry.storageKey,
      contentHash: entry.contentHash,
      cloudOnly: cloudOnly,
      parentServerId: entry.parentId,
    );
    if (persist) {
      await _pdfRepository.saveDocument(document, operation: 'sync_meta');
    }
    return document;
  }

  Future<PdfLibraryDocument> uploadDocumentAsNew({
    required PdfLibraryDocument document,
    required String newTitle,
  }) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final file = File(document.path);
    if (!file.existsSync()) {
      throw StateError('本地文件不存在：${document.path}');
    }
    final categoryPath = document.category == '未分类' ? '资料' : document.category;
    final uploaded = await _cloudFiles.uploadFile(
      file: file,
      relativePath: categoryPath,
      fileName: '$newTitle.pdf',
    );
    final folderId = await _resolveFolderParentId(categoryPath, deviceId);
    final now = DateTime.now();
    final body = {
      'clientId': 'pdf_${now.microsecondsSinceEpoch}',
      'entryType': 'file',
      'title': newTitle,
      'category': document.category,
      'lastPage': document.lastPage,
      'pageCount': document.pageCount,
      'fileObjectId': uploaded.fileObjectId,
      'parentId': ?folderId,
      'deviceId': deviceId,
    };
    final remote = await _api.createFile(body);
    final serverId = remote['serverId'] is int
        ? remote['serverId'] as int
        : int.tryParse('${remote['serverId']}');
    final version = remote['version'] is int
        ? remote['version'] as int
        : int.tryParse('${remote['version']}') ?? 1;
    return document.copyWith(
      id: body['clientId'] as String,
      title: newTitle,
      serverId: serverId,
      syncVersion: version,
      syncState: 'synced',
      storageKey: uploaded.storageKey ?? remote['storageKey'] as String?,
      contentHash: uploaded.contentHash,
      cloudOnly: false,
      updatedAt: now,
    );
  }

  Future<void> _migrateSingleDocument(
    PdfLibraryDocument document,
    String deviceId,
  ) async {
    final file = File(document.path);
    if (!file.existsSync()) {
      throw StateError('本地文件不存在：${document.path}');
    }

    final categoryPath = document.category == '未分类' ? '资料' : document.category;
    final uploaded = await _cloudFiles.uploadFile(
      file: file,
      relativePath: categoryPath,
      fileName: file.uri.pathSegments.last,
    );

    final folderId = await _resolveFolderParentId(categoryPath, deviceId);

    final body = {
      'clientId': document.id,
      'entryType': 'file',
      'title': document.title,
      'category': document.category,
      'lastPage': document.lastPage,
      'pageCount': document.pageCount,
      'fileObjectId': uploaded.fileObjectId,
      'parentId': ?folderId,
      'deviceId': deviceId,
    };
    final remote = document.serverId == null
        ? await _api.createFile(body)
        : await _api.updateFile(document.serverId!, {
            ...body,
            'version': document.syncVersion,
          });

    final serverId = remote['serverId'] is int
        ? remote['serverId'] as int
        : int.tryParse('${remote['serverId']}');
    final version = remote['version'] is int
        ? remote['version'] as int
        : int.tryParse('${remote['version']}') ?? document.syncVersion;

    await _pdfRepository.updateSyncMetadata(
      documentId: document.id,
      serverId: serverId,
      syncVersion: version,
      syncState: 'synced',
      deviceId: deviceId,
      storageKey: uploaded.storageKey ?? remote['storageKey'] as String?,
      contentHash: uploaded.contentHash,
    );

    if (serverId != null) {
      final annotations = await _pdfRepository.loadAnnotations(document.id);
      await syncDocumentAnnotations(
        serverId: serverId,
        documentClientId: document.id,
        annotations: annotations,
        deviceId: deviceId,
      );
    }
  }

  Future<void> syncDocumentMetadata(PdfLibraryDocument document) async {
    final serverId = document.serverId;
    if (serverId == null) {
      return;
    }
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final remote = await _api.updateFile(serverId, {
      'clientId': document.id,
      'entryType': 'file',
      'title': document.title,
      'category': document.category,
      'lastPage': document.lastPage,
      'pageCount': document.pageCount,
      'deviceId': deviceId,
      'version': document.syncVersion,
    });
    final version = remote['version'] is int
        ? remote['version'] as int
        : int.tryParse('${remote['version']}') ?? document.syncVersion;
    await _pdfRepository.updateSyncMetadata(
      documentId: document.id,
      serverId: serverId,
      syncVersion: version,
      syncState: 'synced',
      deviceId: deviceId,
    );
  }

  Future<List<PdfTextAnnotation>> fetchUserNotes() async {
    final remote = await _api.listUserNotes();
    return remote
        .map((item) => _userNoteFromRemote(item))
        .where((item) => !item.isDeleted)
        .toList();
  }

  PdfTextAnnotation _userNoteFromRemote(Map<String, dynamic> json) {
    final documentClientId = '${json['documentClientId'] ?? ''}';
    final clientId = '${json['clientId'] ?? ''}';
    return PdfTextAnnotation(
      id: clientId.isEmpty ? 'pdf_note_unknown' : clientId,
      documentId: documentClientId.isEmpty ? 'unknown_doc' : documentClientId,
      pageNumber: json['pageNumber'] is int
          ? json['pageNumber'] as int
          : int.tryParse('${json['pageNumber']}') ?? 1,
      kind: PdfAnnotationKind.note,
      colorValue: 0xFFFFB74D,
      opacity: 0.72,
      selectedText: '${json['selectedText'] ?? ''}',
      note: json['note'] as String?,
      contentType: PdfAnnotationContentType.parse(
        json['contentType'] as String?,
      ),
      latexContent: json['latexContent'] as String?,
      rects: const [],
      createdAt: _parseRemoteTime(json['updatedAt']) ?? DateTime.now(),
      updatedAt: _parseRemoteTime(json['updatedAt']) ?? DateTime.now(),
      serverId: json['serverId'] is int
          ? json['serverId'] as int
          : int.tryParse('${json['serverId']}'),
      syncVersion: json['version'] is int
          ? json['version'] as int
          : int.tryParse('${json['version']}') ?? 1,
      syncState: 'synced',
    );
  }

  Future<List<PdfTextAnnotation>> fetchDocumentAnnotations({
    required int fileServerId,
    required String documentClientId,
  }) async {
    final remote = await _api.listAnnotations(fileServerId);
    return remote
        .map(
          (item) =>
              _annotationFromRemote(item, documentClientId: documentClientId),
        )
        .where((item) => !item.isDeleted)
        .toList();
  }

  Future<List<PdfTextAnnotation>> syncDocumentAnnotations({
    required int serverId,
    required String documentClientId,
    required List<PdfTextAnnotation> annotations,
    String? deviceId,
  }) async {
    final resolvedDeviceId =
        deviceId ?? await _deviceIdService.getOrCreateDeviceId();
    final remote = await _api.listAnnotations(serverId);
    final remoteByClientId = <String, Map<String, dynamic>>{};
    for (final item in remote) {
      final clientId = '${item['clientId'] ?? ''}';
      if (clientId.isNotEmpty) {
        remoteByClientId[clientId] = item;
      }
    }

    final synced = <PdfTextAnnotation>[];
    final handledClientIds = <String>{};

    for (final annotation in annotations) {
      handledClientIds.add(annotation.id);
      if (annotation.isDeleted) {
        final existing = remoteByClientId[annotation.id];
        final annotationServerId = existing == null
            ? annotation.serverId
            : existing['serverId'] is int
            ? existing['serverId'] as int
            : int.tryParse('${existing['serverId']}');
        if (annotationServerId != null) {
          await _api.deleteAnnotation(
            serverId,
            annotationServerId,
            resolvedDeviceId,
          );
        }
        continue;
      }
      final payload = _annotationPayload(annotation, resolvedDeviceId);
      final existing = remoteByClientId[annotation.id];
      Map<String, dynamic> response;
      if (existing != null) {
        final annotationServerId = existing['serverId'] is int
            ? existing['serverId'] as int
            : int.tryParse('${existing['serverId']}');
        if (annotationServerId == null) {
          response = await _api.createAnnotation(serverId, payload);
        } else {
          final remoteVersion = existing['version'] is int
              ? existing['version'] as int
              : int.tryParse('${existing['version']}') ?? 1;
          response = await _api.updateAnnotation(serverId, annotationServerId, {
            ...payload,
            'version': remoteVersion,
          });
        }
      } else {
        response = await _api.createAnnotation(serverId, payload);
      }
      synced.add(
        _annotationFromRemote(
          response,
          documentClientId: documentClientId,
          fallback: annotation,
        ),
      );
    }

    for (final item in remote) {
      final clientId = '${item['clientId'] ?? ''}';
      if (clientId.isEmpty ||
          handledClientIds.contains(clientId) ||
          item['isDeleted'] == true) {
        continue;
      }
      synced.add(
        _annotationFromRemote(item, documentClientId: documentClientId),
      );
    }

    return synced;
  }

  Map<String, dynamic> _annotationPayload(
    PdfTextAnnotation annotation,
    String deviceId,
  ) {
    return {
      'clientId': annotation.id,
      'pageNumber': annotation.pageNumber,
      'type': annotation.kind.name,
      'colorValue': annotation.colorValue,
      'opacity': annotation.opacity,
      'selectedText': annotation.selectedText,
      'note': annotation.note,
      'contentType': annotation.contentType.wireValue,
      if (annotation.latexContent != null)
        'latexContent': annotation.latexContent,
      'rectsJson': jsonEncode(
        annotation.rects
            .map(
              (rect) => {
                'left': rect.left,
                'top': rect.top,
                'right': rect.right,
                'bottom': rect.bottom,
              },
            )
            .toList(),
      ),
      'deviceId': deviceId,
    };
  }

  PdfTextAnnotation _annotationFromRemote(
    Map<String, dynamic> json, {
    required String documentClientId,
    PdfTextAnnotation? fallback,
  }) {
    final clientId = '${json['clientId'] ?? fallback?.id ?? ''}';
    final serverId = json['serverId'] is int
        ? json['serverId'] as int
        : int.tryParse('${json['serverId']}');
    final version = json['version'] is int
        ? json['version'] as int
        : int.tryParse('${json['version']}') ?? fallback?.syncVersion ?? 1;
    return PdfTextAnnotation(
      id: clientId.isEmpty ? 'pdf_note_unknown' : clientId,
      documentId: documentClientId,
      pageNumber: json['pageNumber'] is int
          ? json['pageNumber'] as int
          : int.tryParse('${json['pageNumber']}') ?? fallback?.pageNumber ?? 1,
      kind: _annotationKind(
        '${json['type'] ?? fallback?.kind.name ?? 'highlight'}',
      ),
      colorValue: json['colorValue'] is int
          ? json['colorValue'] as int
          : int.tryParse('${json['colorValue']}') ??
                fallback?.colorValue ??
                0xFFFFFF00,
      opacity: json['opacity'] is num
          ? (json['opacity'] as num).toDouble()
          : double.tryParse('${json['opacity']}') ?? fallback?.opacity ?? 0.35,
      selectedText: '${json['selectedText'] ?? fallback?.selectedText ?? ''}',
      note: json['note'] as String? ?? fallback?.note,
      contentType: PdfAnnotationContentType.parse(
        json['contentType'] as String? ?? fallback?.contentType.wireValue,
      ),
      latexContent: json['latexContent'] as String? ?? fallback?.latexContent,
      rects: _rectsFromJson(
        json['rectsJson'] as String? ?? '',
        fallback: fallback,
      ),
      createdAt:
          _parseRemoteTime(json['createdAt']) ??
          fallback?.createdAt ??
          DateTime.now(),
      updatedAt: _parseRemoteTime(json['updatedAt']) ?? DateTime.now(),
      serverId: serverId,
      syncVersion: version,
      syncState: 'synced',
      deviceId: '${json['deviceId'] ?? fallback?.deviceId ?? ''}',
      isDeleted: json['isDeleted'] == true,
    );
  }

  List<PdfAnnotationRect> _rectsFromJson(
    String raw, {
    PdfTextAnnotation? fallback,
  }) {
    if (raw.isEmpty) {
      return fallback?.rects ?? const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return fallback?.rects ?? const [];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) => PdfAnnotationRect(
              left: _doubleValue(item['left']),
              top: _doubleValue(item['top']),
              right: _doubleValue(item['right']),
              bottom: _doubleValue(item['bottom']),
            ),
          )
          .where((rect) => rect.width > 0 && rect.height > 0)
          .toList();
    } on FormatException {
      return fallback?.rects ?? const [];
    }
  }

  double _doubleValue(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }

  DateTime? _parseRemoteTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  Future<void> _applyRemoteChange(SyncChange change) async {
    if (change.entityType == 'file_entry') {
      await _applyRemoteFile(change);
      return;
    }
    if (change.entityType == 'document_annotation') {
      await _applyRemoteAnnotation(change);
      return;
    }
    if (change.entityType == 'user_event') {
      await _applyRemoteEvent(change);
      return;
    }
    if (change.entityType == 'user_note') {
      await _applyRemoteNote(change);
      return;
    }
    if (change.entityType == 'user_session') {
      await _applyRemoteSession(change);
    }
  }

  /// 将一条周分析会话快照写入同步 Outbox。
  Future<void> enqueueSession(SessionRecord session) async {
    final sessionsRepository = _sessionsRepository;
    if (sessionsRepository == null) {
      return;
    }
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final snapshotJson = await sessionsRepository.snapshotJsonFor(session);
    final payload = <String, Object?>{
      'clientId': session.id,
      'title': session.title,
      'snapshotJson': snapshotJson,
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _outboxRepository.enqueue(
      entityType: 'user_session',
      entityId: session.id,
      operation: 'update',
      payload: payload,
      syncVersion: 1,
      deviceId: deviceId,
    );
  }

  /// 将一条周分析会话的删除标记写入同步 Outbox。
  Future<void> enqueueSessionDelete(String id) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    await _outboxRepository.enqueue(
      entityType: 'user_session',
      entityId: id,
      operation: 'delete',
      payload: {
        'clientId': id,
        'isDeleted': true,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      syncVersion: 1,
      deviceId: deviceId,
    );
  }

  Future<void> _applyRemoteSession(SyncChange change) async {
    final sessionsRepository = _sessionsRepository;
    if (sessionsRepository == null) {
      return;
    }

    final clientId = change.clientId;
    if (clientId.isEmpty) {
      return;
    }

    // 本地存在未推送的变更时跳过，避免用旧远程值覆盖本地新值。
    final pending = await _outboxRepository.pending();
    final pendingIds = {for (final row in pending) row.entityId};
    if (pendingIds.contains(clientId)) {
      return;
    }

    if (change.isDeleted) {
      await sessionsRepository.deleteSession(clientId);
      return;
    }

    final payload = change.payload ?? {};
    final snapshotJson = payload['snapshotJson'];
    if (snapshotJson is! String || snapshotJson.isEmpty) {
      return;
    }
    await sessionsRepository.saveSessionFromSnapshotJson(snapshotJson);
  }

  /// 将一条独立笔记写入同步 Outbox，等待下次 push 上云。
  Future<void> enqueueNote(UserNote note) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final payload = <String, Object?>{
      'clientId': note.id,
      'title': note.title,
      'contentMarkdown': note.contentMarkdown,
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _outboxRepository.enqueue(
      entityType: 'user_note',
      entityId: note.id,
      operation: 'update',
      payload: payload,
      syncVersion: 1,
      deviceId: deviceId,
    );
  }

  /// 将一条独立笔记的删除标记写入同步 Outbox。
  Future<void> enqueueNoteDelete(String id) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    await _outboxRepository.enqueue(
      entityType: 'user_note',
      entityId: id,
      operation: 'delete',
      payload: {
        'clientId': id,
        'isDeleted': true,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      syncVersion: 1,
      deviceId: deviceId,
    );
  }

  Future<void> _applyRemoteNote(SyncChange change) async {
    final notesRepository = _notesRepository;
    if (notesRepository == null) {
      return;
    }

    final clientId = change.clientId;
    if (clientId.isEmpty) {
      return;
    }

    // 本地存在未推送的变更时跳过，避免用旧远程值覆盖本地新值。
    final pending = await _outboxRepository.pending();
    final pendingIds = {for (final row in pending) row.entityId};
    if (pendingIds.contains(clientId)) {
      return;
    }

    if (change.isDeleted) {
      await notesRepository.deleteById(clientId);
      return;
    }

    final payload = change.payload ?? {};
    final existing = await notesRepository.findById(clientId);
    final updatedAt =
        _parseRemoteTime(payload['updatedAt']) ?? change.updatedAt;
    await notesRepository.saveNote(
      UserNote(
        id: clientId,
        title: '${payload['title'] ?? existing?.title ?? '未命名笔记'}',
        contentMarkdown:
            '${payload['contentMarkdown'] ?? existing?.contentMarkdown ?? ''}',
        createdAt: existing?.createdAt ?? updatedAt,
        updatedAt: updatedAt,
      ),
    );
  }

  /// 将一条事件（含待办状态）写入同步 Outbox，等待下次 push 上云。
  Future<void> enqueueEvent({
    required EventItem event,
    required bool isDone,
    required String priority,
    DateTime? completedAt,
  }) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final payload = <String, Object?>{
      'clientId': event.id,
      'title': event.title,
      'category': event.category.name,
      'type': event.type.name,
      'origin': event.origin.name,
      'startAt': event.startAt.toIso8601String(),
      'endAt': event.endAt?.toIso8601String(),
      'sourceLabel': event.sourceLabel,
      'isDone': isDone,
      'priority': priority,
      'completedAt': completedAt?.toIso8601String(),
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _outboxRepository.enqueue(
      entityType: 'user_event',
      entityId: event.id,
      operation: 'update',
      payload: payload,
      syncVersion: 1,
      deviceId: deviceId,
    );
  }

  Future<void> _applyRemoteEvent(SyncChange change) async {
    final eventsRepository = _manualEventsRepository;
    final todoRepository = _todoStatusRepository;
    if (eventsRepository == null || todoRepository == null) {
      return;
    }

    final clientId = change.clientId;
    if (clientId.isEmpty) {
      return;
    }

    // 本地存在未推送的变更时跳过，避免用旧远程值覆盖本地新值。
    final pending = await _outboxRepository.pending();
    final pendingIds = {for (final row in pending) row.entityId};
    if (pendingIds.contains(clientId)) {
      return;
    }

    if (change.isDeleted) {
      await eventsRepository.deleteById(clientId);
      await todoRepository.deleteForEvents([clientId]);
      return;
    }

    final payload = change.payload ?? {};
    final existingList = await eventsRepository.loadManualEvents();
    EventItem? existing;
    for (final event in existingList) {
      if (event.id == clientId) {
        existing = event;
        break;
      }
    }

    final startAt = _parseRemoteTime(payload['startAt']);
    if (startAt == null) {
      return;
    }

    final event = EventItem(
      id: clientId,
      title: '${payload['title'] ?? existing?.title ?? '未命名事项'}',
      category: _eventCategoryByName(
        '${payload['category']}',
        existing?.category ?? ItemCategory.other,
      ),
      type: _eventTypeByName(
        '${payload['type']}',
        existing?.type ?? EventType.plan,
      ),
      startAt: startAt,
      endAt: _parseRemoteTime(payload['endAt']) ?? existing?.endAt,
      origin: existing?.origin ?? EventOrigin.manual,
      sourceLabel: '${payload['sourceLabel'] ?? existing?.sourceLabel ?? ''}',
    );
    await eventsRepository.saveManualEvent(event);

    final isDone = payload['isDone'] == true;
    final priority = _todoPriorityByName('${payload['priority']}');
    if (isDone ||
        priority != TodoPriority.none ||
        payload['completedAt'] != null) {
      await todoRepository.upsert(
        EventTodoState(
          eventId: clientId,
          isDone: isDone,
          priority: priority,
          completedAt: _parseRemoteTime(payload['completedAt']),
        ),
      );
    }
  }

  ItemCategory _eventCategoryByName(String name, ItemCategory fallback) {
    for (final value in ItemCategory.values) {
      if (value.name == name) {
        return value;
      }
    }
    return fallback;
  }

  EventType _eventTypeByName(String name, EventType fallback) {
    for (final value in EventType.values) {
      if (value.name == name) {
        return value;
      }
    }
    return fallback;
  }

  TodoPriority _todoPriorityByName(String name) {
    for (final value in TodoPriority.values) {
      if (value.name == name) {
        return value;
      }
    }
    return TodoPriority.none;
  }

  Future<void> _applyRemoteFile(SyncChange change) async {
    final payload = change.payload ?? {};
    if (change.isDeleted) {
      await _pdfRepository.markDeleted(change.clientId);
      return;
    }
    final existing = await _pdfRepository.findById(change.clientId);
    final remoteUpdatedAt = change.updatedAt;
    if (existing != null &&
        existing.updatedAt.isAfter(remoteUpdatedAt) &&
        existing.syncVersion >= change.version) {
      return;
    }
    final document = PdfLibraryDocument(
      id: change.clientId,
      title: '${payload['title'] ?? existing?.title ?? '未命名文献'}',
      path: existing?.path ?? '',
      category: '${payload['category'] ?? existing?.category ?? '未分类'}',
      lastPage: payload['lastPage'] is int
          ? payload['lastPage'] as int
          : int.tryParse('${payload['lastPage']}') ?? existing?.lastPage ?? 1,
      pageCount: payload['pageCount'] is int
          ? payload['pageCount'] as int
          : int.tryParse('${payload['pageCount']}'),
      lastOpenedAt: existing?.lastOpenedAt,
      createdAt: existing?.createdAt ?? remoteUpdatedAt,
      updatedAt: remoteUpdatedAt,
      serverId: change.serverId ?? payload['serverId'] as int?,
      syncVersion: change.version,
      syncState: 'synced',
      deviceId: change.deviceId,
      storageKey: payload['storageKey'] as String? ?? existing?.storageKey,
      contentHash: payload['contentHash'] as String? ?? existing?.contentHash,
      cloudOnly: existing?.path.isEmpty ?? true,
    );
    await _pdfRepository.saveDocument(document, operation: 'sync_meta');
  }

  Future<void> _applyRemoteAnnotation(SyncChange change) async {
    final payload = change.payload ?? {};
    if (change.isDeleted) {
      await _pdfRepository.deleteAnnotation(change.clientId);
      return;
    }
    final documentClientId =
        '${payload['documentClientId'] ?? payload['documentId'] ?? ''}';
    if (documentClientId.isEmpty) {
      return;
    }
    final annotation = PdfTextAnnotation(
      id: change.clientId,
      documentId: documentClientId,
      pageNumber: payload['pageNumber'] is int
          ? payload['pageNumber'] as int
          : int.tryParse('${payload['pageNumber']}') ?? 1,
      kind: _annotationKind('${payload['type'] ?? 'highlight'}'),
      colorValue: payload['colorValue'] is int
          ? payload['colorValue'] as int
          : int.tryParse('${payload['colorValue']}') ?? 0xFFFFFF00,
      opacity: payload['opacity'] is num
          ? (payload['opacity'] as num).toDouble()
          : double.tryParse('${payload['opacity']}') ?? 0.35,
      selectedText: '${payload['selectedText'] ?? ''}',
      note: payload['note'] as String?,
      contentType: PdfAnnotationContentType.parse(
        payload['contentType'] as String?,
      ),
      latexContent: payload['latexContent'] as String?,
      rects: _rectsFromJson('${payload['rectsJson'] ?? ''}'),
      createdAt: change.updatedAt,
      updatedAt: change.updatedAt,
      serverId: change.serverId,
      syncVersion: change.version,
      syncState: 'synced',
      deviceId: change.deviceId,
    );
    await _pdfRepository.saveAnnotation(annotation, operation: 'sync_meta');
  }

  Map<String, dynamic>? _decodePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String? _changeKey(String entityType, String clientId) {
    if (entityType.isEmpty || clientId.isEmpty) {
      return null;
    }
    return '$entityType:$clientId';
  }

  PdfAnnotationKind _annotationKind(String raw) {
    for (final kind in PdfAnnotationKind.values) {
      if (kind.name == raw) {
        return kind;
      }
    }
    return PdfAnnotationKind.highlight;
  }
}

class CloudSyncReport {
  const CloudSyncReport({this.uploadedFileCount = 0});

  final int uploadedFileCount;
}

class CloudMigrationReport {
  const CloudMigrationReport({
    required this.backupPath,
    required this.totalCount,
    required this.successCount,
    required this.failures,
  });

  final String backupPath;
  final int totalCount;
  final int successCount;
  final List<CloudMigrationFailure> failures;
}

class CloudMigrationFailure {
  const CloudMigrationFailure({
    required this.documentId,
    required this.title,
    required this.message,
  });

  final String documentId;
  final String title;
  final String message;
}
