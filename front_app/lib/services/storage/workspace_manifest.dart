class WorkspaceManifest {
  const WorkspaceManifest({
    this.manifestVersion = currentManifestVersion,
    required this.appVersion,
    required this.createdAt,
    required this.workspacePath,
    this.databasePath = 'research_life.sqlite',
    this.preferencesPath = 'preferences.json',
  });

  static const currentManifestVersion = 1;

  final int manifestVersion;
  final String appVersion;
  final DateTime createdAt;
  final String workspacePath;
  final String databasePath;
  final String preferencesPath;

  factory WorkspaceManifest.fromJson(Map<String, Object?> json) {
    return WorkspaceManifest(
      manifestVersion: _intValue(json['manifestVersion']) ?? 0,
      appVersion: _stringValue(json['appVersion']) ?? '',
      createdAt:
          DateTime.tryParse(_stringValue(json['createdAt']) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      workspacePath: _stringValue(json['workspacePath']) ?? '',
      databasePath:
          _stringValue(json['databasePath']) ?? 'research_life.sqlite',
      preferencesPath:
          _stringValue(json['preferencesPath']) ?? 'preferences.json',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'manifestVersion': manifestVersion,
      'appVersion': appVersion,
      'createdAt': createdAt.toIso8601String(),
      'workspacePath': workspacePath,
      'databasePath': databasePath,
      'preferencesPath': preferencesPath,
    };
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
