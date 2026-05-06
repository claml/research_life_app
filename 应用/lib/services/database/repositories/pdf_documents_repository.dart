import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/models/app_models.dart';
import '../app_database.dart' as db;

class PdfDocumentsRepository {
  const PdfDocumentsRepository(this._database);

  final db.AppDatabase _database;

  Future<List<PdfLibraryDocument>> loadDocuments() async {
    final rows =
        await (_database.select(_database.pdfLibraryDocuments)..orderBy([
              (document) => OrderingTerm(
                expression: document.updatedAt,
                mode: OrderingMode.desc,
              ),
            ]))
            .get();

    return rows.map(_documentFromRow).toList();
  }

  Future<List<PdfTextAnnotation>> loadAnnotations(String documentId) async {
    final rows =
        await (_database.select(_database.pdfLibraryAnnotations)
              ..where((annotation) => annotation.documentId.equals(documentId))
              ..orderBy([
                (annotation) => OrderingTerm(
                  expression: annotation.pageNumber,
                  mode: OrderingMode.asc,
                ),
                (annotation) => OrderingTerm(
                  expression: annotation.createdAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();

    return rows.map(_annotationFromRow).toList();
  }

  Future<void> saveDocument(PdfLibraryDocument document) async {
    await _database
        .into(_database.pdfLibraryDocuments)
        .insertOnConflictUpdate(
          db.PdfLibraryDocumentsCompanion.insert(
            id: document.id,
            title: document.title,
            path: document.path,
            category: Value(document.category),
            lastPage: Value(document.lastPage),
            pageCount: Value(document.pageCount),
            lastOpenedAt: Value(_nullableDateTimeToInt(document.lastOpenedAt)),
            createdAt: _dateTimeToInt(document.createdAt),
            updatedAt: _dateTimeToInt(document.updatedAt),
          ),
        );
  }

  Future<void> saveAnnotation(PdfTextAnnotation annotation) async {
    await _database
        .into(_database.pdfLibraryAnnotations)
        .insertOnConflictUpdate(
          db.PdfLibraryAnnotationsCompanion.insert(
            id: annotation.id,
            documentId: annotation.documentId,
            pageNumber: annotation.pageNumber,
            type: annotation.kind.name,
            colorValue: annotation.colorValue,
            opacity: annotation.opacity,
            selectedText: annotation.selectedText,
            note: Value(annotation.note),
            rectsJson: jsonEncode(annotation.rects.map(_rectToJson).toList()),
            createdAt: _dateTimeToInt(annotation.createdAt),
            updatedAt: _dateTimeToInt(annotation.updatedAt),
          ),
        );
  }

  Future<void> deleteAnnotation(String id) async {
    await (_database.delete(
      _database.pdfLibraryAnnotations,
    )..where((annotation) => annotation.id.equals(id))).go();
  }

  Future<void> deleteDocument(String id) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.pdfLibraryAnnotations,
      )..where((annotation) => annotation.documentId.equals(id))).go();
      await (_database.delete(
        _database.pdfLibraryDocuments,
      )..where((document) => document.id.equals(id))).go();
    });
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
    } on TypeError {
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

  int _dateTimeToInt(DateTime value) {
    return value.millisecondsSinceEpoch;
  }

  int? _nullableDateTimeToInt(DateTime? value) {
    return value?.millisecondsSinceEpoch;
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
