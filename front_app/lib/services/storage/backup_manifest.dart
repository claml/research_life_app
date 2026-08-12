class BackupManifest {
  const BackupManifest({
    this.manifestVersion = currentManifestVersion,
    this.purpose = BackupPurpose.manual,
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
  final BackupPurpose purpose;
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

    final manifestVersion = _intValue(json['manifestVersion']);
    final appVersion = _stringValue(json['appVersion']);
    final createdAtText = _stringValue(json['createdAt']);
    final createdAt = createdAtText == null
        ? null
        : DateTime.tryParse(createdAtText);
    final schemaVersion = _intValue(json['schemaVersion']);
    final workspacePath = _stringValue(json['workspacePath']);
    if (manifestVersion == null || manifestVersion < 1) {
      throw const FormatException(
        'backup_manifest.json has invalid manifestVersion.',
      );
    }
    if (appVersion == null || appVersion.trim().isEmpty) {
      throw const FormatException(
        'backup_manifest.json has invalid appVersion.',
      );
    }
    if (createdAt == null) {
      throw const FormatException(
        'backup_manifest.json has invalid createdAt.',
      );
    }
    if (schemaVersion == null || schemaVersion < 1) {
      throw const FormatException(
        'backup_manifest.json has invalid schemaVersion.',
      );
    }
    if (workspacePath == null || workspacePath.trim().isEmpty) {
      throw const FormatException(
        'backup_manifest.json has invalid workspacePath.',
      );
    }
    if (json.containsKey('workspaceManifestFile') &&
        workspaceManifestFile is! Map) {
      throw const FormatException(
        'backup_manifest.json has invalid workspaceManifestFile.',
      );
    }
    List<BackupFileInfo>? parsedLocalFileLibraryFiles;
    if (json.containsKey('localFileLibraryFiles')) {
      if (localFileLibraryFiles is! List) {
        throw const FormatException(
          'backup_manifest.json has invalid localFileLibraryFiles.',
        );
      }
      parsedLocalFileLibraryFiles = <BackupFileInfo>[];
      for (final item in localFileLibraryFiles) {
        if (item is! Map) {
          throw const FormatException(
            'backup_manifest.json has invalid localFileLibraryFiles item.',
          );
        }
        parsedLocalFileLibraryFiles.add(
          BackupFileInfo.fromJson(item.cast<String, Object?>()),
        );
      }
    }

    return BackupManifest(
      manifestVersion: manifestVersion,
      purpose: json.containsKey('purpose')
          ? _backupPurposeValue(json['purpose'])
          : BackupPurpose.manual,
      appVersion: appVersion,
      createdAt: createdAt,
      schemaVersion: schemaVersion,
      workspacePath: workspacePath,
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
      localFileLibraryFiles: parsedLocalFileLibraryFiles,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'manifestVersion': manifestVersion,
      'purpose': purpose.name,
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

enum BackupPurpose { manual, safety, migration }

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
  if (value is! String) {
    return null;
  }
  return value.isEmpty ? null : value;
}

int? _intValue(Object? value) {
  return value is int ? value : null;
}

BackupPurpose _backupPurposeValue(Object? value) {
  final name = _stringValue(value);
  for (final purpose in BackupPurpose.values) {
    if (purpose.name == name) {
      return purpose;
    }
  }
  throw FormatException('Unsupported backup purpose: $value');
}
