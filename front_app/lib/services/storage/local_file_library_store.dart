import 'dart:convert';
import 'dart:io';

import '../../core/models/app_models.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../storage/local_workspace_service.dart';

/// 本地文献库：使用 JSON 清单持久化，不依赖 SQLite。
class LocalFileLibraryStore {
  LocalFileLibraryStore(this._workspaceService);

  final LocalWorkspaceService _workspaceService;
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
  }) async {
    final manifest = await _readManifest();
    final documents = manifest.documents
        .map(_documentFromJson)
        .where((document) => includeDeleted || !document.isDeleted)
        .toList();
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

  Future<List<PdfTextAnnotation>> loadAnnotations(String documentId) async {
    final all = await _readAnnotations();
    return all
        .where((item) => item.documentId == documentId && !item.isDeleted)
        .toList()
      ..sort(_compareAnnotations);
  }

  Future<void> saveDocument(PdfLibraryDocument document) async {
    final manifest = await _readManifest();
    final next = manifest.documents
        .where((item) => item['id'] != document.id)
        .toList();
    next.add(_documentToJson(document));
    await _writeManifest(_LibraryManifest(documents: next));
  }

  Future<void> deleteDocument(String id) async {
    final existing = await findById(id);
    if (existing == null) {
      return;
    }
    await saveDocument(
      existing.copyWith(isDeleted: true, updatedAt: DateTime.now()),
    );
  }

  Future<void> saveAnnotation(PdfTextAnnotation annotation) async {
    final all = await _readAnnotations();
    final next = all.where((item) => item.id != annotation.id).toList()
      ..add(annotation);
    await _writeAnnotations(next);
  }

  Future<PdfTextAnnotation?> findAnnotationById(String id) async {
    final all = await _readAnnotations();
    for (final item in all) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Future<void> deleteAnnotation(String id) async {
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

  Future<_LibraryManifest> _readManifest() async {
    final file = await _manifestFile();
    if (!file.existsSync()) {
      return const _LibraryManifest(documents: []);
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const _LibraryManifest(documents: []);
      }
      final rawDocs = decoded['documents'];
      if (rawDocs is! List) {
        return const _LibraryManifest(documents: []);
      }
      return _LibraryManifest(
        documents: rawDocs
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList(),
      );
    } on FormatException {
      return const _LibraryManifest(documents: []);
    }
  }

  Future<void> _writeManifest(_LibraryManifest manifest) async {
    final file = await _manifestFile();
    await file.writeAsString(
      jsonEncode({'version': 1, 'documents': manifest.documents}),
      flush: true,
    );
  }

  Future<List<PdfTextAnnotation>> _readAnnotations() async {
    final file = await _annotationsFile();
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
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'items': annotations.map(_annotationToJson).toList(),
      }),
      flush: true,
    );
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

  Map<String, dynamic> _documentToJson(PdfLibraryDocument document) {
    return {
      'id': document.id,
      'title': document.title,
      'path': document.path,
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
