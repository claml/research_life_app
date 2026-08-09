class SessionSnapshot {
  const SessionSnapshot({
    required this.snapshotVersion,
    required this.createdByAppVersion,
    required this.createdAt,
    required this.payload,
  });

  static const currentVersion = 1;
  static const defaultCreatedByAppVersion = '0.1.0+1';

  final int snapshotVersion;
  final String createdByAppVersion;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  factory SessionSnapshot.v1({
    required Map<String, dynamic> payload,
    DateTime? createdAt,
    String createdByAppVersion = defaultCreatedByAppVersion,
  }) {
    return SessionSnapshot(
      snapshotVersion: currentVersion,
      createdByAppVersion: createdByAppVersion,
      createdAt: createdAt ?? DateTime.now(),
      payload: payload,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'snapshotVersion': snapshotVersion,
      'createdByAppVersion': createdByAppVersion,
      'createdAt': createdAt.toIso8601String(),
      'payload': payload,
    };
  }
}

class SessionSnapshotWarning {
  const SessionSnapshotWarning({
    required this.message,
    this.sessionId,
    this.details,
  });

  final String message;
  final String? sessionId;
  final Object? details;

  @override
  String toString() {
    final idText = sessionId == null ? '' : ' session=$sessionId';
    final detailsText = details == null ? '' : ' details=$details';
    return '$message$idText$detailsText';
  }
}
