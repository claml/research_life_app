import 'session_snapshot.dart';

class SessionSnapshotMigrator {
  const SessionSnapshotMigrator();

  SessionSnapshotMigrationResult migrate(
    Map<String, dynamic> json, {
    DateTime? createdAt,
    String createdByAppVersion = SessionSnapshot.defaultCreatedByAppVersion,
  }) {
    final rawVersion = json['snapshotVersion'];
    if (rawVersion == null) {
      return SessionSnapshotMigrationResult(
        snapshot: SessionSnapshot.v1(
          payload: json,
          createdAt: createdAt,
          createdByAppVersion: createdByAppVersion,
        ),
        migratedFromVersion: 0,
      );
    }

    final version = _intValue(rawVersion);
    if (version != SessionSnapshot.currentVersion) {
      throw SessionSnapshotMigrationException(
        'Unsupported session snapshot version: $rawVersion',
      );
    }

    final payload = json['payload'];
    if (payload is Map<String, dynamic>) {
      return SessionSnapshotMigrationResult(
        snapshot: SessionSnapshot(
          snapshotVersion: version,
          createdByAppVersion:
              _stringValue(json['createdByAppVersion']) ?? createdByAppVersion,
          createdAt:
              _dateTimeValue(json['createdAt']) ?? createdAt ?? DateTime.now(),
          payload: payload,
        ),
      );
    }
    if (payload is Map) {
      return SessionSnapshotMigrationResult(
        snapshot: SessionSnapshot(
          snapshotVersion: version,
          createdByAppVersion:
              _stringValue(json['createdByAppVersion']) ?? createdByAppVersion,
          createdAt:
              _dateTimeValue(json['createdAt']) ?? createdAt ?? DateTime.now(),
          payload: payload.map((key, value) => MapEntry('$key', value)),
        ),
      );
    }

    throw const SessionSnapshotMigrationException(
      'Session snapshot v1 payload is missing or invalid.',
    );
  }

  int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.parse('$value');
  }

  String? _stringValue(Object? value) {
    if (value == null) {
      return null;
    }
    final text = '$value';
    return text.isEmpty ? null : text;
  }

  DateTime? _dateTimeValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.tryParse('$value');
  }
}

class SessionSnapshotMigrationResult {
  const SessionSnapshotMigrationResult({
    required this.snapshot,
    this.migratedFromVersion,
  });

  final SessionSnapshot snapshot;
  final int? migratedFromVersion;

  bool get wasMigrated => migratedFromVersion != null;
}

class SessionSnapshotMigrationException implements Exception {
  const SessionSnapshotMigrationException(this.message);

  final String message;

  @override
  String toString() => message;
}
