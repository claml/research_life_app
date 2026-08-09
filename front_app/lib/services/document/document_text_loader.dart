import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:xml/xml.dart';

import '../../core/utils/workspace_file_kind.dart';

/// 从本地路径读取可查阅文档正文（文本 / docx / pptx）。
class DocumentTextLoader {
  const DocumentTextLoader._();

  static Future<String> loadFromPath(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('文件不存在');
    }
    final kind = WorkspaceFileKind.fromPath(path);
    if (kind == WorkspaceFileKind.presentation) {
      return _loadPptxOutline(file);
    }
    if (kind == WorkspaceFileKind.office &&
        path.toLowerCase().endsWith('.docx')) {
      final docx = await _readDocxFile(file);
      if (docx != null && docx.trim().isNotEmpty) {
        return docx;
      }
      throw StateError('无法读取 Word 文档内容');
    }
    return _loadPlainText(file);
  }

  static Future<String> _loadPlainText(File file) async {
    final bytes = await file.readAsBytes();
    final decoded = await _decodeTextBytes(bytes);
    if (decoded.trim().isEmpty) {
      return '（文件为空或无法识别编码）';
    }
    return decoded;
  }

  static Future<String> _decodeTextBytes(Uint8List bytes) async {
    if (bytes.isEmpty) {
      return '';
    }

    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      try {
        return utf8.decode(bytes.sublist(3));
      } on FormatException {
        // continue
      }
    }

    final utf16Le = _decodeUtf16(bytes, littleEndian: true);
    if (utf16Le != null) {
      return utf16Le;
    }
    final utf16Be = _decodeUtf16(bytes, littleEndian: false);
    if (utf16Be != null) {
      return utf16Be;
    }

    try {
      return utf8.decode(bytes);
    } on FormatException {
      final gbk = await CharsetConverter.decode('gbk', bytes);
      if (gbk.isNotEmpty) {
        return gbk.replaceFirst('\ufeff', '');
      }
      return latin1.decode(bytes);
    }
  }

  static String? _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final hasBom = littleEndian
        ? bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE
        : bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF;
    if (!hasBom) {
      return null;
    }
    final codeUnits = <int>[];
    for (var index = 2; index < bytes.length; index += 2) {
      if (index + 1 >= bytes.length) {
        break;
      }
      final value = littleEndian
          ? bytes[index] | (bytes[index + 1] << 8)
          : (bytes[index] << 8) | bytes[index + 1];
      codeUnits.add(value);
    }
    try {
      return String.fromCharCodes(codeUnits).replaceFirst('\ufeff', '');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readDocxFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? documentEntry;
      for (final entry in archive.files) {
        if (entry.name == 'word/document.xml') {
          documentEntry = entry;
          break;
        }
      }
      if (documentEntry == null) {
        return null;
      }
      final xmlString = utf8.decode(documentEntry.content);
      final document = XmlDocument.parse(xmlString);
      final paragraphs = <String>[];
      for (final paragraph in document.descendants.whereType<XmlElement>()) {
        if (paragraph.name.local != 'p') {
          continue;
        }
        final buffer = StringBuffer();
        for (final node in paragraph.descendants.whereType<XmlElement>()) {
          switch (node.name.local) {
            case 't':
              buffer.write(node.innerText);
              break;
            case 'tab':
              buffer.write('\t');
              break;
            case 'br':
            case 'cr':
              buffer.writeln();
              break;
          }
        }
        final line = buffer.toString().trim();
        if (line.isNotEmpty) {
          paragraphs.add(line);
        }
      }
      return paragraphs.join('\n\n');
    } catch (_) {
      return null;
    }
  }

  static Future<String> _loadPptxOutline(File file) async {
    final lower = file.path.toLowerCase();
    if (lower.endsWith('.ppt')) {
      return '旧版 .ppt 请另存为 .pptx 后再查阅。';
    }
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final slides = <String>[];
    var slideIndex = 1;
    for (final entry in archive.files) {
      if (!entry.isFile || !entry.name.startsWith('ppt/slides/slide')) {
        continue;
      }
      final xml = utf8.decode(entry.content as List<int>);
      final document = XmlDocument.parse(xml);
      final buffer = StringBuffer('--- 幻灯片 $slideIndex ---\n');
      for (final node in document.findAllElements('t')) {
        final text = node.innerText.trim();
        if (text.isNotEmpty) {
          buffer.writeln(text);
        }
      }
      slides.add(buffer.toString());
      slideIndex++;
    }
    if (slides.isEmpty) {
      return '未能从 PPT 中提取文字，可能为纯图片幻灯片。';
    }
    return slides.join('\n');
  }
}
