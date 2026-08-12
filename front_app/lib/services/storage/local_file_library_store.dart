import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/models/app_models.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../storage/local_workspace_service.dart';
import 'local_data_operation_coordinator.dart';

/// 本地文献库：使用 JSON 清单持久化，不依赖 SQLite。
class LocalFileLibraryStore {
  LocalFileLibraryStore(
    this._workspaceService, {
    LocalDataOperationCoordinator? operationCoordinator,
  }) : _operationCoordinator =
           operationCoordinator ?? LocalDataOperationCoordinator();

  final LocalWorkspaceService _workspaceService;
  final LocalDataOperationCoordinator _operationCoordinator;
  bool _managedOperationRecoveryCompleted = false;
  static const _manifestFileName = 'library_manifest.json';
  static const _annotationsFileName = 'annotations.json';

  Future<File> _manifestFile() async {
    final dir = await _workspaceService.resolveLocalFileLibraryDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_manifestFileName');
  }

  Future<File> _annotationsFile() async {
    final dir = await _workspaceService.resolveLocalFileLibraryDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_annotationsFileName');
  }

  Future<List<PdfLibraryDocument>> loadDocuments({
    bool includeDeleted = false,
  }) {
    return _operationCoordinator.runExclusive(
      () => _loadDocuments(includeDeleted: includeDeleted),
    );
  }

  Future<List<PdfLibraryDocument>> _loadDocuments({
    required bool includeDeleted,
  }) async {
    final shouldRecover = !_managedOperationRecoveryCompleted;
    final manifest = await _readManifest(
      recoverManagedOperation: shouldRecover,
    );
    _managedOperationRecoveryCompleted = true;
    final normalizedItems = <Map<String, dynamic>>[];
    final documents = <PdfLibraryDocument>[];
    var migratedLegacyPath = false;
    for (final item in manifest.documents) {
      final normalized = Map<String, dynamic>.from(item);
      final storedPath = '${normalized['path'] ?? ''}';
      final portablePath = await _resolvePortablePath(storedPath);
      if (portablePath != null) {
        normalizedItems.add(normalized);
        final document = _documentFromJson({
          ...normalized,
          'path': portablePath,
        });
        if (includeDeleted || !document.isDeleted) {
          documents.add(document);
        }
        continue;
      }

      final legacyDocument = _documentFromJson(normalized);
      if (!legacyDocument.isDeleted &&
          !legacyDocument.cloudOnly &&
          storedPath.isNotEmpty &&
          await File(storedPath).exists()) {
        final managed = await _workspaceService.copyFileIntoMaterials(
          File(storedPath),
          category: legacyDocument.category,
          reuseIdenticalFile: false,
        );
        normalized['path'] = await _portableStoredPath(managed.path);
        normalizedItems.add(normalized);
        migratedLegacyPath = true;
        final migrated = legacyDocument.copyWith(path: managed.path);
        if (includeDeleted || !migrated.isDeleted) {
          documents.add(migrated);
        }
      } else {
        normalizedItems.add(normalized);
        if (includeDeleted || !legacyDocument.isDeleted) {
          documents.add(legacyDocument);
        }
      }
    }
    if (migratedLegacyPath) {
      await _writeManifest(_LibraryManifest(documents: normalizedItems));
    }
    documents.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return documents;
  }

  Future<PdfLibraryDocument?> findById(String id) async {
    final documents = await loadDocuments(includeDeleted: true);
    for (final document in documents) {
      if (document.id == id) {
        return document;
      }
    }
    return null;
  }

  Future<void> replaceDocumentPaths(Map<String, String> paths) {
    if (paths.isEmpty) {
      return Future<void>.value();
    }
    return _operationCoordinator.runExclusive(
      () => _replaceDocumentPaths(paths),
    );
  }

  Future<void> _replaceDocumentPaths(Map<String, String> paths) async {
    final manifest = await _readManifest();
    final next = <Map<String, dynamic>>[];
    var changed = false;
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    for (final item in manifest.documents) {
      final copy = Map<String, dynamic>.from(item);
      final id = '${copy['id'] ?? ''}';
      final replacement = paths[id];
      if (replacement != null) {
        copy['path'] = await _portableStoredPath(replacement);
        copy['updatedAt'] = updatedAt;
        changed = true;
      }
      next.add(copy);
    }
    if (changed) {
      await _writeManifest(_LibraryManifest(documents: next));
    }
  }

  Future<List<PdfTextAnnotation>> loadAnnotations(String documentId) {
    return _operationCoordinator.runExclusive(
      () => _loadAnnotations(documentId),
    );
  }

  Future<List<PdfTextAnnotation>> _loadAnnotations(String documentId) async {
    final all = await _readAnnotations();
    return all
        .where((item) => item.documentId == documentId && !item.isDeleted)
        .toList()
      ..sort(_compareAnnotations);
  }

  Future<void> saveDocument(
    PdfLibraryDocument document, {
    bool mergeMetadata = false,
  }) {
    return _operationCoordinator.runExclusive(
      () => _saveDocument(document, mergeMetadata: mergeMetadata),
    );
  }

  Future<void> _saveDocument(
    PdfLibraryDocument document, {
    required bool mergeMetadata,
  }) async {
    final manifest = await _readManifest();
    var documentToSave = document;
    if (mergeMetadata) {
      final existingJson = manifest.documents
          .where((item) => item['id'] == document.id)
          .firstOrNull;
      if (existingJson != null) {
        final storedPath = '${existingJson['path'] ?? ''}';
        final resolvedPath = await _resolvePortablePath(storedPath);
        final current = _documentFromJson({
          ...existingJson,
          'path': resolvedPath ?? storedPath,
        });
        documentToSave = current.copyWith(
          lastPage: document.lastPage,
          pageCount: document.pageCount,
          lastOpenedAt: document.lastOpenedAt,
          updatedAt: document.updatedAt,
          serverId: document.serverId,
          syncVersion: document.syncVersion,
          syncState: document.syncState,
          deviceId: document.deviceId,
          storageKey: document.storageKey,
          contentHash: document.contentHash,
          cloudOnly: document.cloudOnly,
          parentServerId: document.parentServerId,
          inReadingList: document.inReadingList,
        );
      }
    }
    final next = manifest.documents
        .where((item) => item['id'] != document.id)
        .toList();
    next.add(await _documentToJson(documentToSave));
    await _writeManifest(_LibraryManifest(documents: next));
  }

  Future<void> deleteDocument(String id) {
    return _operationCoordinator.runExclusive(() => _deleteDocument(id));
  }

  Future<void> _deleteDocument(String id) async {
    final manifest = await _readManifest();
    final index = manifest.documents.indexWhere((item) => item['id'] == id);
    if (index == -1) {
      return;
    }
    final next = manifest.documents.map(Map<String, dynamic>.from).toList();
    next[index]
      ..['isDeleted'] = true
      ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _writeManifest(_LibraryManifest(documents: next));
  }

  Future<void> saveAnnotation(PdfTextAnnotation annotation) {
    return _operationCoordinator.runExclusive(
      () => _saveAnnotation(annotation),
    );
  }

  Future<void> _saveAnnotation(PdfTextAnnotation annotation) async {
    final all = await _readAnnotations();
    final next = all.where((item) => item.id != annotation.id).toList()
      ..add(annotation);
    await _writeAnnotations(next);
  }

  Future<PdfTextAnnotation?> findAnnotationById(String id) {
    return _operationCoordinator.runExclusive(() => _findAnnotationById(id));
  }

  Future<PdfTextAnnotation?> _findAnnotationById(String id) async {
    final all = await _readAnnotations();
    for (final item in all) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Future<void> deleteAnnotation(String id) {
    return _operationCoordinator.runExclusive(() => _deleteAnnotation(id));
  }

  Future<void> _deleteAnnotation(String id) async {
    final all = await _readAnnotations();
    final updated = <PdfTextAnnotation>[];
    for (final annotation in all) {
      if (annotation.id == id) {
        updated.add(
          annotation.copyWith(isDeleted: true, updatedAt: DateTime.now()),
        );
      } else {
        updated.add(annotation);
      }
    }
    await _writeAnnotations(updated);
  }

  Future<_LibraryManifest> _readManifest({
    bool recoverManagedOperation = false,
  }) async {
    final file = await _manifestFile();
    await _recoverInterruptedReplacement(file);
    if (!file.existsSync()) {
      return const _LibraryManifest(documents: []);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException {
      return const _LibraryManifest(documents: []);
    }
    if (decoded is! Map) {
      return const _LibraryManifest(documents: []);
    }
    final rawDocs = decoded['documents'];
    if (rawDocs is! List) {
      return const _LibraryManifest(documents: []);
    }
    final documents = rawDocs
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
    if (recoverManagedOperation) {
      await _recoverManagedFileOperation(documents);
    }
    return _LibraryManifest(documents: documents);
  }

  Future<void> _recoverManagedFileOperation(
    List<Map<String, dynamic>> documents,
  ) async {
    final journal = await _workspaceService
        .resolveManagedFileOperationJournalFile();
    final pending = File('${journal.path}.pending');
    if (!await journal.exists()) {
      if (await pending.exists()) {
        await pending.delete();
      }
      return;
    }

    final decoded = jsonDecode(await journal.readAsString());
    if (decoded is! Map) {
      throw const FormatException('managed-file journal is not an object');
    }
    final operation = Map<String, dynamic>.from(decoded);
    if (operation['version'] != 1) {
      throw const FormatException('unsupported managed-file journal version');
    }
    final type = operation['type'];
    final documentId = '${operation['documentId'] ?? ''}';
    if (type != 'rename' && type != 'delete') {
      throw FormatException('unsupported managed-file operation: $type');
    }
    if (documentId.isEmpty) {
      throw const FormatException('managed-file document id is empty');
    }
    final original = await _workspaceService.resolveManagedPortableFile(
      '${operation['originalPath'] ?? ''}',
    );
    final target = await _workspaceService.resolveManagedPortableFile(
      '${operation['targetPath'] ?? ''}',
    );
    Map<String, dynamic>? document;
    for (final candidate in documents) {
      if ('${candidate['id'] ?? ''}' == documentId) {
        document = candidate;
        break;
      }
    }
    final storedPath = document?['path']?.toString() ?? '';
    final normalizedStored = p.posix.normalize(
      storedPath.replaceAll('\\', '/'),
    );
    final normalizedTarget = p.posix.normalize(
      '${operation['targetPath'] ?? ''}'.replaceAll('\\', '/'),
    );
    final manifestCommitted = type == 'delete'
        ? document != null && document['isDeleted'] == true
        : normalizedStored == normalizedTarget;

    if (manifestCommitted) {
      if (type == 'delete' && await target.exists()) {
        await target.delete();
      }
      if (type == 'rename' && !await target.exists()) {
        throw FileSystemException('已提交的文件改名缺少目标文件', target.path);
      }
      await _workspaceService.clearManagedFileOperationJournal();
      return;
    }

    if (await target.exists() && !await original.exists()) {
      await target.rename(original.path);
    }
    if (!await original.exists()) {
      throw FileSystemException('无法恢复中断的文件操作', original.path);
    }
    await _workspaceService.clearManagedFileOperationJournal();
  }

  Future<void> _writeManifest(_LibraryManifest manifest) async {
    final file = await _manifestFile();
    await _replaceTextAtomically(
      file,
      jsonEncode({'version': 1, 'documents': manifest.documents}),
    );
  }

  Future<List<PdfTextAnnotation>> _readAnnotations() async {
    final file = await _annotationsFile();
    await _recoverInterruptedReplacement(file);
    if (!file.existsSync()) {
      return const [];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const [];
      }
      final raw = decoded['items'];
      if (raw is! List) {
        return const [];
      }
      return raw
          .whereType<Map>()
          .map((item) => _annotationFromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> _writeAnnotations(List<PdfTextAnnotation> annotations) async {
    final file = await _annotationsFile();
    await _replaceTextAtomically(
      file,
      jsonEncode({
        'version': 1,
        'items': annotations.map(_annotationToJson).toList(),
      }),
    );
  }

  Future<void> _replaceTextAtomically(File target, String content) async {
    final pending = File('${target.path}.pending');
    final previous = File('${target.path}.previous');
    await pending.parent.create(recursive: true);
    if (await pending.exists()) {
      await pending.delete();
    }
    await pending.writeAsString(content, flush: true);
    if (await previous.exists()) {
      await previous.delete();
    }
    if (await target.exists()) {
      await target.rename(previous.path);
    }
    try {
      await pending.rename(target.path);
    } catch (_) {
      if (!await target.exists() && await previous.exists()) {
        await previous.rename(target.path);
      }
      rethrow;
    }
    if (await previous.exists()) {
      try {
        await previous.delete();
      } on FileSystemException {
        // The new target is committed; stale rollback cleanup is recoverable.
      }
    }
  }

  Future<void> _recoverInterruptedReplacement(File target) async {
    final pending = File('${target.path}.pending');
    final previous = File('${target.path}.previous');
    if (!await target.exists() && await previous.exists()) {
      await previous.rename(target.path);
    }
    if (await pending.exists()) {
      await pending.delete();
    }
    if (await target.exists() && await previous.exists()) {
      try {
        await previous.delete();
      } on FileSystemException {
        // A later read can retry stale rollback cleanup.
      }
    }
  }

  int _compareAnnotations(PdfTextAnnotation a, PdfTextAnnotation b) {
    final page = a.pageNumber.compareTo(b.pageNumber);
    if (page != 0) {
      return page;
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  PdfLibraryDocument _documentFromJson(Map<String, dynamic> json) {
    return PdfLibraryDocument(
      id: '${json['id']}',
      title: '${json['title'] ?? '未命名文献'}',
      path: '${json['path'] ?? ''}',
      fileKind: _fileKindFromJson(json['fileKind'], '${json['path'] ?? ''}'),
      category: '${json['category'] ?? '未分类'}',
      lastPage: json['lastPage'] is int
          ? json['lastPage'] as int
          : int.tryParse('${json['lastPage']}') ?? 1,
      pageCount: json['pageCount'] is int
          ? json['pageCount'] as int
          : int.tryParse('${json['pageCount']}'),
      lastOpenedAt: _dateFromJson(json['lastOpenedAt']),
      createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
      updatedAt: _dateFromJson(json['updatedAt']) ?? DateTime.now(),
      serverId: json['serverId'] is int
          ? json['serverId'] as int
          : int.tryParse('${json['serverId']}'),
      syncVersion: json['syncVersion'] is int
          ? json['syncVersion'] as int
          : int.tryParse('${json['syncVersion']}') ?? 1,
      syncState: '${json['syncState'] ?? 'local'}',
      deviceId: json['deviceId'] as String?,
      isDeleted: json['isDeleted'] == true,
      storageKey: json['storageKey'] as String?,
      contentHash: json['contentHash'] as String?,
      cloudOnly: json['cloudOnly'] == true,
      parentServerId: json['parentServerId'] is int
          ? json['parentServerId'] as int
          : int.tryParse('${json['parentServerId']}'),
      inReadingList: json['inReadingList'] != false,
    );
  }

  Future<Map<String, dynamic>> _documentToJson(
    PdfLibraryDocument document,
  ) async {
    return {
      'id': document.id,
      'title': document.title,
      'path': await _portableStoredPath(document.path),
      'fileKind': document.fileKind.name,
      'category': document.category,
      'lastPage': document.lastPage,
      'pageCount': document.pageCount,
      'lastOpenedAt': document.lastOpenedAt?.millisecondsSinceEpoch,
      'createdAt': document.createdAt.millisecondsSinceEpoch,
      'updatedAt': document.updatedAt.millisecondsSinceEpoch,
      'serverId': document.serverId,
      'syncVersion': document.syncVersion,
      'syncState': document.syncState,
      'deviceId': document.deviceId,
      'isDeleted': document.isDeleted,
      'storageKey': document.storageKey,
      'contentHash': document.contentHash,
      'cloudOnly': document.cloudOnly,
      'parentServerId': document.parentServerId,
      'inReadingList': document.inReadingList,
    };
  }

  Future<String> _portableStoredPath(String path) async {
    if (path.isEmpty) {
      return path;
    }
    final payloads = await _workspaceService
        .resolveManagedFilePayloadsDirectory(create: false);
    final absolutePayloads = p.normalize(p.absolute(payloads.path));
    final absolutePath = p.normalize(p.absolute(path));
    if (absolutePath != absolutePayloads &&
        !p.isWithin(absolutePayloads, absolutePath)) {
      return path;
    }
    final library = await _workspaceService.resolveLocalFileLibraryDirectory(
      create: false,
    );
    final relative = p.relative(absolutePath, from: p.absolute(library.path));
    return p.posix.joinAll(p.split(relative));
  }

  Future<String?> _resolvePortablePath(String storedPath) async {
    final normalized = p.posix.normalize(storedPath.replaceAll('\\', '/'));
    if (normalized == 'payloads' ||
        !normalized.startsWith('payloads/') ||
        normalized.split('/').any((segment) => segment == '..')) {
      return null;
    }
    final library = await _workspaceService.resolveLocalFileLibraryDirectory(
      create: false,
    );
    return p.joinAll([library.path, ...normalized.split('/')]);
  }

  PdfTextAnnotation _annotationFromJson(Map<String, dynamic> json) {
    return PdfTextAnnotation(
      id: '${json['id']}',
      documentId: '${json['documentId']}',
      pageNumber: json['pageNumber'] is int
          ? json['pageNumber'] as int
          : int.tryParse('${json['pageNumber']}') ?? 1,
      kind: _annotationKind('${json['type'] ?? 'highlight'}'),
      colorValue: json['colorValue'] is int
          ? json['colorValue'] as int
          : int.tryParse('${json['colorValue']}') ?? 0xFFFFFF00,
      opacity: json['opacity'] is num
          ? (json['opacity'] as num).toDouble()
          : double.tryParse('${json['opacity']}') ?? 0.35,
      selectedText: '${json['selectedText'] ?? ''}',
      note: json['note'] as String?,
      contentType: PdfAnnotationContentType.parse(
        json['contentType'] as String?,
      ),
      latexContent: json['latexContent'] as String?,
      rects: _rectsFromJson('${json['rectsJson'] ?? '[]'}'),
      createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
      updatedAt: _dateFromJson(json['updatedAt']) ?? DateTime.now(),
      serverId: json['serverId'] is int
          ? json['serverId'] as int
          : int.tryParse('${json['serverId']}'),
      syncVersion: json['syncVersion'] is int
          ? json['syncVersion'] as int
          : int.tryParse('${json['syncVersion']}') ?? 1,
      syncState: '${json['syncState'] ?? 'local'}',
      deviceId: json['deviceId'] as String?,
      isDeleted: json['isDeleted'] == true,
    );
  }

  Map<String, dynamic> _annotationToJson(PdfTextAnnotation annotation) {
    return {
      'id': annotation.id,
      'documentId': annotation.documentId,
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
      'createdAt': annotation.createdAt.millisecondsSinceEpoch,
      'updatedAt': annotation.updatedAt.millisecondsSinceEpoch,
      'serverId': annotation.serverId,
      'syncVersion': annotation.syncVersion,
      'syncState': annotation.syncState,
      'deviceId': annotation.deviceId,
      'isDeleted': annotation.isDeleted,
    };
  }

  PdfAnnotationKind _annotationKind(String raw) {
    for (final kind in PdfAnnotationKind.values) {
      if (kind.name == raw) {
        return kind;
      }
    }
    return PdfAnnotationKind.highlight;
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

  double _doubleValue(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }

  WorkspaceFileKind _fileKindFromJson(Object? raw, String path) {
    if (raw is String && raw.isNotEmpty) {
      for (final kind in WorkspaceFileKind.values) {
        if (kind.name == raw) {
          return kind;
        }
      }
    }
    return WorkspaceFileKind.fromPath(path);
  }

  DateTime? _dateFromJson(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }
}

class _LibraryManifest {
  const _LibraryManifest({required this.documents});

  final List<Map<String, dynamic>> documents;
}
