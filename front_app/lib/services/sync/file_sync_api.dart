import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/json_parse.dart';
import 'sync_models.dart';

abstract interface class FileSyncRemoteApi {
  Future<Map<String, dynamic>> createFolder(Map<String, dynamic> body);

  Future<Map<String, dynamic>> moveFile(
    int serverId,
    Map<String, dynamic> body,
  );

  Future<Map<String, dynamic>> directUpload(FormData form);

  Future<List<Map<String, dynamic>>> listFiles({
    required String deviceId,
    bool reconcile = true,
  });

  Future<Map<String, dynamic>> reconcileStorage(String deviceId);

  Future<Map<String, dynamic>> createFile(Map<String, dynamic> body);

  Future<Map<String, dynamic>> updateFile(
    int serverId,
    Map<String, dynamic> body,
  );

  Future<void> deleteFile(int serverId, String deviceId);

  Future<UploadInitResult> initUpload(Map<String, dynamic> body);

  Future<Map<String, dynamic>> completeUpload(Map<String, dynamic> body);

  Future<String> downloadUrl(int serverId);

  Future<SyncPullResult> pullChanges({int cursor = 0});

  Future<List<SyncChange>> pushChanges({
    required String deviceId,
    required List<SyncChange> changes,
  });

  Future<List<Map<String, dynamic>>> listAnnotations(int documentServerId);

  Future<Map<String, dynamic>> createAnnotation(
    int documentServerId,
    Map<String, dynamic> body,
  );

  Future<Map<String, dynamic>> updateAnnotation(
    int documentServerId,
    int annotationServerId,
    Map<String, dynamic> body,
  );

  Future<void> deleteAnnotation(
    int documentServerId,
    int annotationServerId,
    String deviceId,
  );

  Future<List<Map<String, dynamic>>> listUserNotes();
}

class FileSyncApi implements FileSyncRemoteApi {
  FileSyncApi(this._client);

  final ApiClient _client;

  @override
  Future<Map<String, dynamic>> createFolder(Map<String, dynamic> body) {
    return _client.postData<Map<String, dynamic>>(
      '/api/v1/files/folders',
      data: body,
      fromJson: (json) => parseJsonMap(json, field: '文件夹'),
    );
  }

  @override
  Future<Map<String, dynamic>> moveFile(
    int serverId,
    Map<String, dynamic> body,
  ) {
    return _client.patchData<Map<String, dynamic>>(
      '/api/v1/files/$serverId/move',
      data: body,
      fromJson: (json) => parseJsonMap(json, field: '移动'),
    );
  }

  @override
  Future<Map<String, dynamic>> directUpload(FormData form) {
    return _client.postData<Map<String, dynamic>>(
      '/api/v1/file/upload/direct',
      data: form,
      fromJson: (json) => parseJsonMap(json, field: '直传'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listFiles({
    required String deviceId,
    bool reconcile = true,
  }) {
    return _client.getData<List<Map<String, dynamic>>>(
      '/api/v1/files',
      queryParameters: {'reconcile': reconcile, 'deviceId': deviceId},
      fromJson: parseJsonMapList,
    );
  }

  @override
  Future<Map<String, dynamic>> reconcileStorage(String deviceId) {
    return _client.postData<Map<String, dynamic>>(
      '/api/v1/files/reconcile',
      queryParameters: {'deviceId': deviceId},
      fromJson: (json) => parseJsonMap(json, field: '同步'),
    );
  }

  @override
  Future<Map<String, dynamic>> createFile(Map<String, dynamic> body) {
    return _client.postData<Map<String, dynamic>>(
      '/api/v1/files',
      data: body,
      fromJson: (json) => parseJsonMap(json, field: '文献'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateFile(
    int serverId,
    Map<String, dynamic> body,
  ) {
    return _client.patchData<Map<String, dynamic>>(
      '/api/v1/files/$serverId',
      data: body,
      fromJson: (json) => parseJsonMap(json, field: '文献'),
    );
  }

  @override
  Future<void> deleteFile(int serverId, String deviceId) {
    return _client.deleteVoid(
      '/api/v1/files/$serverId',
      queryParameters: {'deviceId': deviceId},
    );
  }

  @override
  Future<UploadInitResult> initUpload(Map<String, dynamic> body) {
    return _client.postData<UploadInitResult>(
      '/api/v1/file/upload/init',
      data: body,
      fromJson: (json) =>
          UploadInitResult.fromJson(parseJsonMap(json, field: '上传初始化')),
    );
  }

  @override
  Future<Map<String, dynamic>> completeUpload(Map<String, dynamic> body) {
    return _client.postData<Map<String, dynamic>>(
      '/api/v1/file/upload/complete',
      data: body,
      fromJson: (json) => parseJsonMap(json, field: '上传完成'),
    );
  }

  @override
  Future<String> downloadUrl(int serverId) async {
    final data = await _client.getData<Map<String, dynamic>>(
      '/api/v1/file/$serverId/download-url',
      fromJson: (json) => parseJsonMap(json, field: '下载地址'),
    );
    return '${data['downloadUrl'] ?? ''}';
  }

  @override
  Future<SyncPullResult> pullChanges({int cursor = 0}) {
    return _client.getData<SyncPullResult>(
      '/api/v1/files/changes',
      queryParameters: {'cursor': cursor},
      fromJson: (json) =>
          SyncPullResult.fromJson(parseJsonMap(json, field: '同步增量')),
    );
  }

  @override
  Future<List<SyncChange>> pushChanges({
    required String deviceId,
    required List<SyncChange> changes,
  }) {
    return _client.postData<List<SyncChange>>(
      '/api/v1/files/sync-push',
      data: {
        'deviceId': deviceId,
        'changes': changes.map((change) => change.toJson()).toList(),
      },
      allowNullData: true,
      fromJson: (json) {
        if (json == null) {
          return const <SyncChange>[];
        }
        if (json is! List) {
          return const <SyncChange>[];
        }
        return json
            .whereType<Map>()
            .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listAnnotations(int documentServerId) {
    return _client.getData<List<Map<String, dynamic>>>(
      '/api/v1/documents/$documentServerId/annotations',
      fromJson: parseJsonMapList,
    );
  }

  @override
  Future<Map<String, dynamic>> createAnnotation(
    int documentServerId,
    Map<String, dynamic> body,
  ) {
    return _client.postData<Map<String, dynamic>>(
      '/api/v1/documents/$documentServerId/annotations',
      data: body,
      fromJson: (json) => parseJsonMap(json, field: '批注'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateAnnotation(
    int documentServerId,
    int annotationServerId,
    Map<String, dynamic> body,
  ) {
    return _client.patchData<Map<String, dynamic>>(
      '/api/v1/documents/$documentServerId/annotations/$annotationServerId',
      data: body,
      fromJson: (json) => parseJsonMap(json, field: '批注'),
    );
  }

  @override
  Future<void> deleteAnnotation(
    int documentServerId,
    int annotationServerId,
    String deviceId,
  ) {
    return _client.deleteVoid(
      '/api/v1/documents/$documentServerId/annotations/$annotationServerId',
      queryParameters: {'deviceId': deviceId},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listUserNotes() {
    return _client.getData<List<Map<String, dynamic>>>(
      '/api/v1/notes',
      fromJson: parseJsonMapList,
    );
  }
}
