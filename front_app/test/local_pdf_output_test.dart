import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/features/pdf_tools/local_pdf_output.dart';

void main() {
  test('saving a PDF output never overwrites an existing file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'research_life_pdf_output',
    );
    addTearDown(() => directory.delete(recursive: true));
    final existing = File(
      '${directory.path}${Platform.pathSeparator}result.pdf',
    );
    await existing.writeAsBytes([1, 2, 3]);

    final saved = await writePdfOutputCollisionSafe(
      directory: directory,
      preferredFileName: 'result.pdf',
      bytes: Uint8List.fromList([9, 8, 7]),
    );

    expect(await existing.readAsBytes(), [1, 2, 3]);
    expect(saved.path, endsWith('result (1).pdf'));
    expect(await saved.readAsBytes(), [9, 8, 7]);
  });

  test('concurrent PDF saves claim distinct output paths atomically', () async {
    final directory = await Directory.systemTemp.createTemp(
      'research_life_pdf_output_concurrent',
    );
    addTearDown(() => directory.delete(recursive: true));

    final saved = await Future.wait([
      writePdfOutputCollisionSafe(
        directory: directory,
        preferredFileName: 'result.pdf',
        bytes: Uint8List.fromList([1]),
      ),
      writePdfOutputCollisionSafe(
        directory: directory,
        preferredFileName: 'result.pdf',
        bytes: Uint8List.fromList([2]),
      ),
    ]);

    expect(saved.map((file) => file.path).toSet(), hasLength(2));
    expect(
      {for (final file in saved) (await file.readAsBytes()).single},
      {1, 2},
    );
  });
}
