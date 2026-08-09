class SyncChange {
  const SyncChange({
    required this.clientId,
    this.serverId,
    required this.entityType,
    required this.version,
    required this.updatedAt,
    required this.deviceId,
    required this.isDeleted,
    this.payload,
  });

  final String clientId;
  final int? serverId;
  final String entityType;
  final int version;
  final DateTime updatedAt;
  final String deviceId;
  final bool isDeleted;
  final Map<String, dynamic>? payload;

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    final updatedAtRaw = json['updatedAt'];
    DateTime updatedAt = DateTime.now().toUtc();
    if (updatedAtRaw is String) {
      updatedAt = DateTime.tryParse(updatedAtRaw) ?? updatedAt;
    }
    return SyncChange(
      clientId: '${json['clientId'] ?? ''}',
      serverId: json['serverId'] is int
          ? json['serverId'] as int
          : int.tryParse('${json['serverId']}'),
      entityType: '${json['entityType'] ?? ''}',
      version: json['version'] is int
          ? json['version'] as int
          : int.tryParse('${json['version']}') ?? 1,
      updatedAt: updatedAt,
      deviceId: '${json['deviceId'] ?? ''}',
      isDeleted: json['isDeleted'] == true,
      payload: json['payload'] is Map<String, dynamic>
          ? json['payload'] as Map<String, dynamic>
          : json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clientId': clientId,
      if (serverId != null) 'serverId': serverId,
      'entityType': entityType,
      'version': version,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'deviceId': deviceId,
      'isDeleted': isDeleted,
      if (payload != null) 'payload': payload,
    };
  }
}

class SyncPullResult {
  const SyncPullResult({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<SyncChange> changes;
  final int nextCursor;
  final bool hasMore;

  factory SyncPullResult.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'];
    final changes = rawChanges is List
        ? rawChanges
              .whereType<Map>()
              .map(
                (item) => SyncChange.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <SyncChange>[];
    return SyncPullResult(
      changes: changes,
      nextCursor: json['nextCursor'] is int
          ? json['nextCursor'] as int
          : int.tryParse('${json['nextCursor']}') ?? 0,
      hasMore: json['hasMore'] == true,
    );
  }
}

class CloudSyncStatus {
  const CloudSyncStatus({
    required this.pendingOutboxCount,
    required this.retryingOutboxCount,
    required this.pendingUploadCount,
    required this.cursorValue,
    this.lastSyncedAt,
  });

  const CloudSyncStatus.empty()
    : pendingOutboxCount = 0,
      retryingOutboxCount = 0,
      pendingUploadCount = 0,
      cursorValue = 0,
      lastSyncedAt = null;

  final int pendingOutboxCount;
  final int retryingOutboxCount;
  final int pendingUploadCount;
  final int cursorValue;
  final DateTime? lastSyncedAt;

  int get totalPendingCount => pendingOutboxCount + pendingUploadCount;
  bool get hasRetryingItems => retryingOutboxCount > 0;
}

class UploadInitResult {
  const UploadInitResult({
    required this.instantUpload,
    this.fileObjectId,
    this.storageKey,
    this.uploadUrl,
    this.method = 'PUT',
  });

  final bool instantUpload;
  final int? fileObjectId;
  final String? storageKey;
  final String? uploadUrl;
  final String method;

  factory UploadInitResult.fromJson(Map<String, dynamic> json) {
    return UploadInitResult(
      instantUpload: json['instantUpload'] == true,
      fileObjectId: json['fileObjectId'] is int
          ? json['fileObjectId'] as int
          : int.tryParse('${json['fileObjectId']}'),
      storageKey: json['storageKey'] as String?,
      uploadUrl: json['uploadUrl'] as String?,
      method: '${json['method'] ?? 'PUT'}',
    );
  }
}
