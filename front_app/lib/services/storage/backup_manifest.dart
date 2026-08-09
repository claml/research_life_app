class BackupManifest {
  const BackupManifest({
    this.manifestVersion = currentManifestVersion,
    required this.appVersion,
    required this.createdAt,
    required this.schemaVersion,
    required this.workspacePath,
    required this.databaseFile,
    required this.preferencesFile,
    this.workspaceManifestFile,
    this.localFileLibraryFiles,
  });

  static const currentManifestVersion = 1;

  final int manifestVersion;
  final String appVersion;
  final DateTime createdAt;
  final int schemaVersion;
  final String workspacePath;
  final BackupFileInfo databaseFile;
  final BackupFileInfo preferencesFile;
  final BackupFileInfo? workspaceManifestFile;
  final List<BackupFileInfo>? localFileLibraryFiles;

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    final databaseFile = json['databaseFile'];
    final preferencesFile = json['preferencesFile'];
    final workspaceManifestFile = json['workspaceManifestFile'];
    final localFileLibraryFiles = json['localFileLibraryFiles'];

    if (databaseFile is! Map) {
      throw const FormatException('backup_manifest.json 缺少 databaseFile。');
    }
    if (preferencesFile is! Map) {
      throw const FormatException('backup_manifest.json 缺少 preferencesFile。');
    }

    return BackupManifest(
      manifestVersion: _intValue(json['manifestVersion']) ?? 0,
      appVersion: _stringValue(json['appVersion']) ?? '',
      createdAt:
          DateTime.tryParse(_stringValue(json['createdAt']) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      schemaVersion: _intValue(json['schemaVersion']) ?? 0,
      workspacePath: _stringValue(json['workspacePath']) ?? '',
      databaseFile: BackupFileInfo.fromJson(
        databaseFile.cast<String, Object?>(),
      ),
      preferencesFile: BackupFileInfo.fromJson(
        preferencesFile.cast<String, Object?>(),
      ),
      workspaceManifestFile: workspaceManifestFile is Map
          ? BackupFileInfo.fromJson(
              workspaceManifestFile.cast<String, Object?>(),
            )
          : null,
      localFileLibraryFiles: localFileLibraryFiles is List
          ? localFileLibraryFiles
                .whereType<Map>()
                .map(
                  (item) =>
                      BackupFileInfo.fromJson(item.cast<String, Object?>()),
                )
                .toList()
          : null,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'manifestVersion': manifestVersion,
      'appVersion': appVersion,
      'createdAt': createdAt.toIso8601String(),
      'schemaVersion': schemaVersion,
      'workspacePath': workspacePath,
      'databaseFile': databaseFile.toJson(),
      'preferencesFile': preferencesFile.toJson(),
      if (workspaceManifestFile != null)
        'workspaceManifestFile': workspaceManifestFile!.toJson(),
      if (localFileLibraryFiles != null)
        'localFileLibraryFiles': localFileLibraryFiles!
            .map((file) => file.toJson())
            .toList(),
    };
  }
}

class BackupFileInfo {
  const BackupFileInfo({
    required this.path,
    required this.sha256,
    required this.sizeBytes,
  });

  final String path;
  final String sha256;
  final int sizeBytes;

  factory BackupFileInfo.fromJson(Map<String, Object?> json) {
    final path = _stringValue(json['path']);
    final sha256 = _stringValue(json['sha256']);
    final sizeBytes = _intValue(json['sizeBytes']);

    if (path == null || path.trim().isEmpty) {
      throw const FormatException('backup file info 缺少 path。');
    }
    if (sha256 == null || sha256.trim().isEmpty) {
      throw const FormatException('backup file info 缺少 sha256。');
    }
    if (sizeBytes == null || sizeBytes < 0) {
      throw const FormatException('backup file info 缺少有效 sizeBytes。');
    }

    return BackupFileInfo(path: path, sha256: sha256, sizeBytes: sizeBytes);
  }

  Map<String, Object?> toJson() {
    return {'path': path, 'sha256': sha256, 'sizeBytes': sizeBytes};
  }
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final text = '$value';
  return text.isEmpty ? null : text;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
