import 'dart:io';
import 'dart:typed_data';

Future<File> writePdfOutputCollisionSafe({
  required Directory directory,
  required String preferredFileName,
  required Uint8List bytes,
}) {
  return _writePdfOutputCollisionSafe(
    directory: directory,
    preferredFileName: preferredFileName,
    bytes: bytes,
  );
}

Future<File> _writePdfOutputCollisionSafe({
  required Directory directory,
  required String preferredFileName,
  required Uint8List bytes,
}) async {
  await directory.create(recursive: true);
  final safeName = preferredFileName
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .trim();
  final resolvedName = safeName.isEmpty ? 'output.pdf' : safeName;
  final dot = resolvedName.lastIndexOf('.');
  final baseName = dot > 0 ? resolvedName.substring(0, dot) : resolvedName;
  final extension = dot > 0 ? resolvedName.substring(dot) : '';
  for (var index = 0; index < 10000; index += 1) {
    final fileName = index == 0 ? resolvedName : '$baseName ($index)$extension';
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    try {
      await candidate.create(exclusive: true);
    } on FileSystemException {
      if (await candidate.exists()) {
        continue;
      }
      rethrow;
    }
    RandomAccessFile? output;
    try {
      output = await candidate.open(mode: FileMode.writeOnly);
      await output.writeFrom(bytes);
      await output.flush();
    } catch (_) {
      await output?.close();
      output = null;
      if (await candidate.exists()) {
        await candidate.delete();
      }
      rethrow;
    } finally {
      await output?.close();
    }
    return candidate;
  }
  throw FileSystemException('无法生成可用输出文件名', directory.path);
}
