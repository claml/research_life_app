import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:xml/xml.dart';

import '../../core/models/app_models.dart';

typedef GbkDecoder = Future<String?> Function(Uint8List bytes);

Future<String?> _defaultGbkDecoder(Uint8List bytes) async {
  try {
    return await CharsetConverter.decode('gbk', bytes);
  } catch (_) {
    return null;
  }
}

class ImportResult {
  const ImportResult({
    required this.success,
    required this.message,
    this.input,
  });

  final bool success;
  final String message;
  final AnalysisInput? input;
}

class ImportService {
  const ImportService({GbkDecoder gbkDecoder = _defaultGbkDecoder})
    : _gbkDecoder = gbkDecoder;

  final GbkDecoder _gbkDecoder;

  Future<ImportResult> importFile(String path) async {
    final extension = _extensionOf(path);

    if (extension == 'xls' || extension == 'xlsx') {
      return const ImportResult(
        success: false,
        message: '当前不再支持 Excel 导入，请改用 TXT、Markdown 或 Word（.docx）。',
      );
    }

    if (extension == 'doc') {
      return const ImportResult(
        success: false,
        message: '暂不支持老式 .doc 文件，请先另存为 .docx 后再导入。',
      );
    }

    if (extension != 'txt' && extension != 'md' && extension != 'docx') {
      return const ImportResult(
        success: false,
        message: '当前仅支持导入 TXT、Markdown 和 Word（.docx）文件。',
      );
    }

    final file = File(path);
    if (!await file.exists()) {
      return const ImportResult(success: false, message: '文件不存在，无法导入。');
    }

    final rawText = switch (extension) {
      'txt' || 'md' => await _readTextFile(file),
      'docx' => await _readDocxFile(file),
      _ => null,
    };

    if (rawText == null) {
      return ImportResult(
        success: false,
        message: extension == 'docx'
            ? 'Word 文件读取失败，请确认文件没有损坏，并且格式为 .docx。'
            : '文件读取失败。请确认文件使用 UTF-8、UTF-16 或 GBK 编码。',
      );
    }

    if (rawText.trim().isEmpty) {
      return const ImportResult(success: false, message: '文件内容为空，无法进入分析。');
    }

    final sourceType = switch (extension) {
      'txt' => AnalysisSourceType.txt,
      'md' => AnalysisSourceType.md,
      'docx' => AnalysisSourceType.docx,
      _ => AnalysisSourceType.text,
    };

    return ImportResult(
      success: true,
      message: '已导入 ${file.uri.pathSegments.last}',
      input: AnalysisInput(
        rawText: rawText,
        sourceType: sourceType,
        sourcePath: path,
      ),
    );
  }

  String _extensionOf(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) {
      return '';
    }
    return path.substring(dotIndex + 1).toLowerCase();
  }

  Future<String?> _readTextFile(File file) async {
    try {
      final bytes = Uint8List.fromList(await file.readAsBytes());
      return _decodeTextBytes(bytes);
    } on FileSystemException {
      return null;
    }
  }

  Future<String?> _decodeTextBytes(Uint8List bytes) async {
    if (bytes.isEmpty) {
      return '';
    }

    final utf8WithBom = _decodeUtf8Bom(bytes);
    if (utf8WithBom != null) {
      return utf8WithBom;
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
      final gbk = await _gbkDecoder(bytes);
      return gbk?.replaceFirst('\ufeff', '');
    }
  }

  String? _decodeUtf8Bom(Uint8List bytes) {
    if (bytes.length < 3 ||
        bytes[0] != 0xEF ||
        bytes[1] != 0xBB ||
        bytes[2] != 0xBF) {
      return null;
    }

    try {
      return utf8.decode(bytes.sublist(3));
    } on FormatException {
      return null;
    }
  }

  String? _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final hasBom = littleEndian
        ? bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE
        : bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF;
    if (!hasBom) {
      return null;
    }

    final payloadLength = bytes.length - 2;
    if (payloadLength.isOdd) {
      return null;
    }

    final codeUnits = <int>[];
    for (var index = 2; index < bytes.length; index += 2) {
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

  Future<String?> _readDocxFile(File file) async {
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
              buffer.write('\n');
              break;
          }
        }

        final text = buffer.toString().trim();
        if (text.isNotEmpty) {
          paragraphs.add(text);
        }
      }

      if (paragraphs.isEmpty) {
        return null;
      }

      return paragraphs.join('\n');
    } on ArchiveException {
      return null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on XmlException {
      return null;
    }
  }
}
