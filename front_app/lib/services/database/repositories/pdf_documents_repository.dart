import 'dart:convert';

import '../../../core/models/app_models.dart';
import '../../storage/local_file_library_store.dart';
import '../app_database.dart' as db;
import 'sync_outbox_repository.dart';

/// 文献库仓储：本地数据走 JSON 清单，云同步仍使用 outbox（SQLite）。
class PdfDocumentsRepository {
  PdfDocumentsRepository(
    this._database, {
    required LocalFileLibraryStore localStore,
    SyncOutboxRepository? outboxRepository,
    Future<String> Function()? deviceIdReader,
  }) : _localStore = localStore,
       _outboxRepository = outboxRepository,
       _deviceIdReader = deviceIdReader;

  final db.AppDatabase _database;
  final LocalFileLibraryStore _localStore;
  final SyncOutboxRepository? _outboxRepository;
  final Future<String> Function()? _deviceIdReader;
  bool _migratedFromSqlite = false;

  Future<void> _ensureMigrated() async {
    if (_migratedFromSqlite) {
      return;
    }
    _migratedFromSqlite = true;
    final existing = await _localStore.loadDocuments(includeDeleted: true);
    if (existing.isNotEmpty) {
      return;
    }
    try {
      final query = _database.select(_database.pdfLibraryDocuments);
      final rows = await query.get();
      if (rows.isEmpty) {
        return;
      }
      for (final row in rows) {
        await _localStore.saveDocument(_documentFromRow(row));
      }
      final annotationRows = await _database
          .select(_database.pdfLibraryAnnotations)
          .get();
      for (final row in annotationRows) {
        await _localStore.saveAnnotation(_annotationFromRow(row));
      }
    } catch (_) {
      // 旧表不存在时忽略
    }
  }

  Future<List<PdfLibraryDocument>> loadDocuments({
    bool includeDeleted = false,
  }) async {
    await _ensureMigrated();
    return _localStore.loadDocuments(includeDeleted: includeDeleted);
  }

  Future<PdfLibraryDocument?> findById(String id) async {
    await _ensureMigrated();
    return _localStore.findById(id);
  }

  Future<List<PdfTextAnnotation>> loadAnnotations(String documentId) async {
    await _ensureMigrated();
    return _localStore.loadAnnotations(documentId);
  }

  Future<void> saveDocument(
    PdfLibraryDocument document, {
    String operation = 'upsert',
  }) async {
    await _ensureMigrated();
    final stored = operation == 'sync_meta'
        ? document.copyWith(syncState: document.syncState)
        : document.copyWith(
            syncVersion: document.syncVersion + 1,
            syncState: 'pending',
            updatedAt: DateTime.now(),
          );
    await _localStore.saveDocument(
      stored,
      mergeMetadata: operation == 'metadata',
    );
    await _enqueueFileChange(stored, operation);
  }

  Future<void> saveAnnotation(
    PdfTextAnnotation annotation, {
    String operation = 'upsert',
  }) async {
    await _ensureMigrated();
    final nextVersion =
        annotation.syncVersion + (operation == 'upsert' ? 1 : 0);
    final stored = annotation.copyWith(
      syncVersion: operation == 'delete'
          ? annotation.syncVersion + 1
          : nextVersion,
      syncState: 'pending',
    );
    await _localStore.saveAnnotation(stored);
    await _enqueueAnnotationChange(stored, operation);
  }

  Future<void> deleteAnnotation(String id) async {
    await _ensureMigrated();
    final target = await _localStore.findAnnotationById(id);
    if (target == null) {
      return;
    }
    await saveAnnotation(
      target.copyWith(isDeleted: true, updatedAt: DateTime.now()),
      operation: 'delete',
    );
  }

  Future<void> deleteDocument(String id) async {
    await _ensureMigrated();
    final document = await findById(id);
    if (document == null) {
      return;
    }
    await saveDocument(
      document.copyWith(isDeleted: true, updatedAt: DateTime.now()),
      operation: 'delete',
    );
  }

  Future<void> markDeleted(String id) async {
    await _ensureMigrated();
    final document = await findById(id);
    if (document == null) {
      return;
    }
    await _localStore.saveDocument(
      document.copyWith(isDeleted: true, syncState: 'synced'),
    );
  }

  Future<void> updateSyncMetadata({
    required String documentId,
    int? serverId,
    int? syncVersion,
    String? syncState,
    String? deviceId,
    String? storageKey,
    String? contentHash,
  }) async {
    final existing = await findById(documentId);
    if (existing == null) {
      return;
    }
    await saveDocument(
      existing.copyWith(
        serverId: serverId ?? existing.serverId,
        syncVersion: syncVersion ?? existing.syncVersion,
        syncState: syncState ?? existing.syncState,
        deviceId: deviceId ?? existing.deviceId,
        storageKey: storageKey ?? existing.storageKey,
        contentHash: contentHash ?? existing.contentHash,
        updatedAt: DateTime.now(),
      ),
      operation: 'sync_meta',
    );
  }

  Future<void> replaceAllDocuments(List<PdfLibraryDocument> documents) async {
    await _ensureMigrated();
    for (final document in documents) {
      await _localStore.saveDocument(document);
    }
  }

  Future<void> _enqueueFileChange(
    PdfLibraryDocument document,
    String operation,
  ) async {
    if (_outboxRepository == null || operation == 'sync_meta') {
      return;
    }
    final deviceId = await _resolveDeviceId(document.deviceId);
    final payload = {
      'clientId': document.id,
      'entryType': 'file',
      'title': document.title,
      'category': document.category,
      'lastPage': document.lastPage,
      'pageCount': document.pageCount,
      if (document.contentHash != null) 'contentHash': document.contentHash,
      if (document.parentServerId != null) 'parentId': document.parentServerId,
      'deviceId': deviceId,
    };
    await _outboxRepository.enqueue(
      entityType: 'file_entry',
      entityId: document.id,
      operation: operation == 'delete' ? 'delete' : 'upsert',
      payload: payload,
      syncVersion: document.syncVersion,
      deviceId: deviceId,
    );
  }

  Future<void> _enqueueAnnotationChange(
    PdfTextAnnotation annotation,
    String operation,
  ) async {
    if (_outboxRepository == null) {
      return;
    }
    final deviceId = await _resolveDeviceId(annotation.deviceId);
    await _outboxRepository.enqueue(
      entityType: 'document_annotation',
      entityId: annotation.id,
      operation: operation == 'delete' ? 'delete' : 'upsert',
      payload: {
        'clientId': annotation.id,
        'documentClientId': annotation.documentId,
        'pageNumber': annotation.pageNumber,
        'type': annotation.kind.name,
        'colorValue': annotation.colorValue,
        'opacity': annotation.opacity,
        'selectedText': annotation.selectedText,
        'note': annotation.note,
        'contentType': annotation.contentType.wireValue,
        if (annotation.latexContent != null)
          'latexContent': annotation.latexContent,
        'rectsJson': jsonEncode(annotation.rects.map(_rectToJson).toList()),
        'deviceId': deviceId,
      },
      syncVersion: annotation.syncVersion,
      deviceId: deviceId,
    );
  }

  Future<String> _resolveDeviceId(String? existing) async {
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    if (_deviceIdReader != null) {
      return _deviceIdReader();
    }
    return 'unknown_device';
  }

  PdfLibraryDocument _documentFromRow(db.PdfLibraryDocument row) {
    return PdfLibraryDocument(
      id: row.id,
      title: row.title,
      path: row.path,
      category: row.category,
      lastPage: row.lastPage,
      pageCount: row.pageCount,
      lastOpenedAt: _nullableDateTimeValue(row.lastOpenedAt),
      createdAt: _dateTimeValue(row.createdAt),
      updatedAt: _dateTimeValue(row.updatedAt),
      serverId: row.serverId,
      syncVersion: row.syncVersion,
      syncState: row.syncState,
      deviceId: row.deviceId,
      isDeleted: row.isDeleted,
      storageKey: row.storageKey,
      contentHash: row.contentHash,
    );
  }

  PdfTextAnnotation _annotationFromRow(db.PdfLibraryAnnotation row) {
    return PdfTextAnnotation(
      id: row.id,
      documentId: row.documentId,
      pageNumber: row.pageNumber,
      kind: _enumValue(
        PdfAnnotationKind.values,
        row.type,
        PdfAnnotationKind.highlight,
      ),
      colorValue: row.colorValue,
      opacity: row.opacity,
      selectedText: row.selectedText,
      note: row.note,
      rects: _rectsFromJson(row.rectsJson),
      createdAt: _dateTimeValue(row.createdAt),
      updatedAt: _dateTimeValue(row.updatedAt),
      serverId: row.serverId,
      syncVersion: row.syncVersion,
      syncState: row.syncState,
      deviceId: row.deviceId,
      isDeleted: row.isDeleted,
    );
  }

  Map<String, double> _rectToJson(PdfAnnotationRect rect) {
    return {
      'left': rect.left,
      'top': rect.top,
      'right': rect.right,
      'bottom': rect.bottom,
    };
  }

  List<PdfAnnotationRect> _rectsFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) {
        return const [];
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
      return const [];
    }
  }

  T _enumValue<T extends Enum>(List<T> values, String value, T fallback) {
    for (final enumValue in values) {
      if (enumValue.name == value) {
        return enumValue;
      }
    }
    return fallback;
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

  DateTime _dateTimeValue(int value) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  DateTime? _nullableDateTimeValue(int? value) {
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}
