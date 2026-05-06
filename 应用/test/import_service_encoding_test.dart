import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/import/import_service.dart';

void main() {
  group('ImportService encoding support', () {
    test('reads utf8 bom text files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_utf8_bom_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsBytes([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('本周完成论文整理'),
      ]);

      const service = ImportService();
      final result = await service.importFile(file.path);

      expect(result.success, isTrue);
      expect(result.input?.rawText, contains('本周完成论文整理'));
    });

    test('reads utf16 little endian text files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_utf16le_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsBytes(_utf16LeBytes('下周和导师开会'));

      const service = ImportService();
      final result = await service.importFile(file.path);

      expect(result.success, isTrue);
      expect(result.input?.rawText, contains('下周和导师开会'));
    });

    test('reads gbk text files via fallback decoder', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_gbk_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final file = File('${tempDir.path}/sample.txt');
      final gbkBytes = Uint8List.fromList([0xD6, 0xD0, 0xCE, 0xC4]);
      await file.writeAsBytes(gbkBytes);

      final service = ImportService(
        gbkDecoder: (bytes) async {
          expect(bytes, gbkBytes);
          return '中文';
        },
      );
      final result = await service.importFile(file.path);

      expect(result.success, isTrue);
      expect(result.input?.rawText, '中文');
    });

    test('returns clear error message for unsupported text encoding', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_invalid_encoding_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsBytes([0xFF]);

      final service = ImportService(
        gbkDecoder: (_) async => null,
      );
      final result = await service.importFile(file.path);

      expect(result.success, isFalse);
      expect(result.message, contains('UTF-8、UTF-16 或 GBK'));
    });
  });
}

Uint8List _utf16LeBytes(String text) {
  final bytes = <int>[0xFF, 0xFE];
  for (final codeUnit in text.codeUnits) {
    bytes.add(codeUnit & 0xFF);
    bytes.add((codeUnit >> 8) & 0xFF);
  }
  return Uint8List.fromList(bytes);
}
