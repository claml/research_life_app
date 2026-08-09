import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../core/models/app_models.dart';
import '../../core/network/api_client.dart';
import 'device_id_service.dart';
import 'file_sync_api.dart';

class CloudFileService {
  CloudFileService({
    required ApiClient apiClient,
    DeviceIdService? deviceIdService,
  }) : _api = FileSyncApi(apiClient),
       _deviceIdService = deviceIdService ?? DeviceIdService();

  final FileSyncApi _api;
  final DeviceIdService _deviceIdService;

  Future<List<CloudFileEntry>> listCloudFiles({bool reconcile = true}) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final raw = await _api.listFiles(deviceId: deviceId, reconcile: reconcile);
    return raw.map(CloudFileEntry.fromJson).toList();
  }

  Future<CloudFileEntry> createFolder({
    required String title,
    int? parentId,
  }) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final response = await _api.createFolder({
      'title': title,
      'parentId': parentId,
      'deviceId': deviceId,
    });
    return CloudFileEntry.fromJson(response);
  }

  Future<CloudFileEntry> moveEntry({
    required int serverId,
    required int parentId,
  }) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final response = await _api.moveFile(serverId, {
      'parentId': parentId,
      'deviceId': deviceId,
    });
    return CloudFileEntry.fromJson(response);
  }

  Future<CloudFileEntry> renameEntry({
    required CloudFileEntry entry,
    required String title,
  }) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final response = await _api.updateFile(entry.serverId, {
      'title': title.trim(),
      'category': entry.category,
      'lastPage': entry.lastPage,
      'pageCount': entry.pageCount,
      'version': entry.version,
      'deviceId': deviceId,
    });
    return CloudFileEntry.fromJson(response);
  }

  Future<void> deleteEntry(int serverId) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    await _api.deleteFile(serverId, deviceId);
  }

  Future<CloudFileEntry> uploadFileToParent({
    required int parentId,
    required File file,
    List<CloudFileEntry>? knownEntries,
  }) async {
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final entries = knownEntries ?? await listCloudFiles(reconcile: false);
    CloudFileEntry? parent;
    for (final entry in entries) {
      if (entry.serverId == parentId) {
        parent = entry;
        break;
      }
    }
    final relativePath = parent?.relativePath;
    final fileName = _resolveFileName(file);
    final uploaded = await uploadFile(
      file: file,
      relativePath: relativePath,
      fileName: fileName,
    );
    if (uploaded.fileObjectId == null) {
      throw StateError('上传未完成：未获得云端文件对象');
    }
    final title = fileName;
    final response = await _api.createFile({
      'clientId': 'file_${DateTime.now().microsecondsSinceEpoch}',
      'parentId': parentId,
      'entryType': 'file',
      'title': title,
      'category': parent?.category ?? '未分类',
      'fileObjectId': uploaded.fileObjectId,
      'deviceId': deviceId,
    });
    return CloudFileEntry.fromJson(response);
  }

  String _resolveFileName(File file, [String? override]) {
    final raw = (override ?? p.basename(file.path)).trim();
    if (raw.isEmpty) {
      return 'upload.bin';
    }
    return _sanitizePathSegment(raw);
  }

  /// 与后端 UserStoragePathService 路径规则对齐，避免非法字符导致上传失败。
  String _sanitizePathSegment(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.runes) {
      final char = String.fromCharCode(codeUnit);
      if (_isSafePathChar(char)) {
        buffer.write(char);
      } else {
        buffer.write('_');
      }
    }
    final sanitized = buffer.toString().trim();
    return sanitized.isEmpty ? 'upload.bin' : sanitized;
  }

  bool _isSafePathChar(String char) {
    if (char == '.' || char == '-' || char == ' ') {
      return true;
    }
    final code = char.codeUnitAt(0);
    if (code >= 0x4e00 && code <= 0x9fff) {
      return true;
    }
    if (code >= 0x30 && code <= 0x39) {
      return true;
    }
    if ((code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a)) {
      return true;
    }
    return char == '_';
  }

  Future<UploadedCloudObject> uploadFile({
    required File file,
    String? relativePath,
    String? fileName,
  }) async {
    final fileSize = await file.length();
    if (fileSize <= 0) {
      throw StateError('无法上传空文件');
    }
    final hash = await _sha256File(file);
    final deviceId = await _deviceIdService.getOrCreateDeviceId();
    final resolvedName = _resolveFileName(file, fileName);
    final mimeType = _mimeTypeFor(resolvedName);

    // 优先走后端直传，避免客户端无法访问 MinIO 预签名内网地址导致失败。
    try {
      return await _directUpload(
        file: file,
        deviceId: deviceId,
        relativePath: relativePath,
        fileName: resolvedName,
      );
    } catch (_) {
      return _presignedUpload(
        file: file,
        fileSize: fileSize,
        hash: hash,
        deviceId: deviceId,
        relativePath: relativePath,
        fileName: resolvedName,
        mimeType: mimeType,
      );
    }
  }

  Future<UploadedCloudObject> _directUpload({
    required File file,
    required String deviceId,
    required String? relativePath,
    required String fileName,
  }) async {
    final fields = <String, dynamic>{
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
      'deviceId': deviceId,
      'fileName': fileName,
    };
    if (relativePath != null && relativePath.isNotEmpty) {
      fields['relativePath'] = relativePath;
    }
    final form = FormData.fromMap(fields);
    final data = await _api.directUpload(form);
    final uploaded = UploadedCloudObject.fromJson(data);
    if (uploaded.fileObjectId == null) {
      throw StateError('直传未完成：未获得云端文件对象');
    }
    return uploaded;
  }

  Future<String> downloadToCache({
    required int serverId,
    required String targetPath,
  }) async {
    final url = await _api.downloadUrl(serverId);
    final client = Dio();
    await client.download(url, targetPath);
    return targetPath;
  }

  Future<UploadedCloudObject> _presignedUpload({
    required File file,
    required int fileSize,
    required String hash,
    required String deviceId,
    required String? relativePath,
    required String fileName,
    required String mimeType,
  }) async {
    final init = await _api.initUpload({
      'contentHash': hash,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'deviceId': deviceId,
      'relativePath': ?relativePath,
      'fileName': fileName,
    });
    var storageKey = init.storageKey;
    if (!init.instantUpload && init.uploadUrl != null && storageKey != null) {
      final uploadClient = Dio();
      await uploadClient.put(
        init.uploadUrl!,
        data: file.openRead(),
        options: Options(
          headers: {'Content-Type': mimeType, 'Content-Length': fileSize},
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
      final completed = await _api.completeUpload({
        'contentHash': hash,
        'storageKey': storageKey,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'deviceId': deviceId,
      });
      storageKey = completed['storageKey'] as String? ?? storageKey;
      final fileObjectId = completed['fileObjectId'] is int
          ? completed['fileObjectId'] as int
          : int.tryParse('${completed['fileObjectId']}');
      if (fileObjectId == null) {
        throw StateError('分片上传未完成：未获得云端文件对象');
      }
      return UploadedCloudObject(
        fileObjectId: fileObjectId,
        storageKey: storageKey,
        contentHash: hash,
      );
    }
    if (init.fileObjectId == null) {
      throw StateError('上传初始化未返回文件对象');
    }
    return UploadedCloudObject(
      fileObjectId: init.fileObjectId,
      storageKey: storageKey,
      contentHash: hash,
    );
  }

  String _mimeTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md')) {
      return 'text/plain';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }

  Future<String> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}

class UploadedCloudObject {
  const UploadedCloudObject({
    this.fileObjectId,
    this.storageKey,
    required this.contentHash,
  });

  final int? fileObjectId;
  final String? storageKey;
  final String contentHash;

  factory UploadedCloudObject.fromJson(Map<String, dynamic> json) {
    return UploadedCloudObject(
      fileObjectId: json['fileObjectId'] is int
          ? json['fileObjectId'] as int
          : int.tryParse('${json['fileObjectId']}'),
      storageKey: json['storageKey'] as String?,
      contentHash: '${json['contentHash'] ?? ''}',
    );
  }
}
