import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/json_parse.dart';

class PdfOperationApi {
  PdfOperationApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<PdfProcessOutput> process({
    required String operation,
    required List<File> localFiles,
    int? fileEntryId,
    Map<String, dynamic>? params,
    File? signatureImage,
  }) async {
    final form = FormData();
    form.fields.add(MapEntry('operation', operation));
    if (fileEntryId != null) {
      form.fields.add(MapEntry('fileEntryId', '$fileEntryId'));
    }
    if (params != null && params.isNotEmpty) {
      form.fields.add(MapEntry('params', _encodeParams(params)));
    }
    for (final file in localFiles) {
      form.files.add(
        MapEntry(
          'files',
          await MultipartFile.fromFile(
            file.path,
            filename: _basename(file.path),
          ),
        ),
      );
    }
    if (signatureImage != null) {
      form.files.add(
        MapEntry(
          'files',
          await MultipartFile.fromFile(
            signatureImage.path,
            filename: _basename(signatureImage.path),
          ),
        ),
      );
    }

    try {
      final response = await _client.dio.post<List<int>>(
        '/api/v1/pdf/process',
        data: form,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 5),
        ),
      );
      final bytes = Uint8List.fromList(response.data ?? const []);
      final disposition = response.headers.value('content-disposition') ?? '';
      final message = response.headers.value('x-process-message') ?? '';
      final contentType =
          response.headers.value('content-type') ?? 'application/octet-stream';
      return PdfProcessOutput(
        bytes: bytes,
        fileName: _fileNameFromDisposition(disposition) ?? 'output.bin',
        contentType: contentType,
        message: message,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<PdfAiOutput> ai({
    required String operation,
    File? localFile,
    int? fileEntryId,
    String? prompt,
  }) async {
    final form = FormData();
    form.fields.add(MapEntry('operation', operation));
    if (fileEntryId != null) {
      form.fields.add(MapEntry('fileEntryId', '$fileEntryId'));
    }
    if (prompt != null && prompt.trim().isNotEmpty) {
      form.fields.add(MapEntry('prompt', prompt.trim()));
    }
    if (localFile != null) {
      form.files.add(
        MapEntry(
          'file',
          await MultipartFile.fromFile(
            localFile.path,
            filename: _basename(localFile.path),
          ),
        ),
      );
    }

    final data = await _client.postData<Map<String, dynamic>>(
      '/api/v1/pdf/ai',
      data: form,
      fromJson: (json) => parseJsonMap(json, field: 'pdfAi'),
    );
    return PdfAiOutput(
      resultText: '${data['resultText'] ?? ''}',
      sourceExcerpt: data['sourceExcerpt'] as String?,
      pageCount: data['pageCount'] is int
          ? data['pageCount'] as int
          : int.tryParse('${data['pageCount']}') ?? 0,
    );
  }

  String _encodeParams(Map<String, dynamic> params) {
    final buffer = StringBuffer('{');
    var first = true;
    params.forEach((key, value) {
      if (!first) {
        buffer.write(',');
      }
      first = false;
      buffer.write('"$key":');
      if (value is String) {
        buffer.write('"${value.replaceAll('"', '\\"')}"');
      } else if (value is List) {
        buffer.write('[${value.join(',')}]');
      } else {
        buffer.write('$value');
      }
    });
    buffer.write('}');
    return buffer.toString();
  }

  ApiException _mapError(DioException error) {
    final raw = error.response?.data;
    if (raw != null) {
      try {
        final body = parseJsonMap(raw, field: '错误');
        final code = body['code'] is int ? body['code'] as int : 500;
        final msg = '${body['msg'] ?? error.message}';
        return ApiException(code, msg);
      } on FormatException {
        // fall through
      }
    }
    return ApiException(500, error.message ?? 'PDF 操作失败');
  }

  static String _basename(String path) {
    final sep = Platform.pathSeparator;
    final index = path.lastIndexOf(sep);
    return index == -1 ? path : path.substring(index + 1);
  }

  static String? _fileNameFromDisposition(String header) {
    final match = RegExp(r"filename\*=UTF-8''([^;]+)").firstMatch(header);
    if (match != null) {
      return Uri.decodeComponent(match.group(1)!);
    }
    final simple = RegExp(r'filename="?([^";]+)"?').firstMatch(header);
    return simple?.group(1);
  }
}

class PdfProcessOutput {
  const PdfProcessOutput({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    this.message = '',
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final String message;
}

class PdfAiOutput {
  const PdfAiOutput({
    required this.resultText,
    this.sourceExcerpt,
    this.pageCount = 0,
  });

  final String resultText;
  final String? sourceExcerpt;
  final int pageCount;
}
