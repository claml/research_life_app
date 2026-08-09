import 'dart:convert';

import 'local_workspace_service.dart';
import 'workspace_manifest.dart';

class WorkspaceManifestService {
  const WorkspaceManifestService({
    required LocalWorkspaceService workspaceService,
    this.appVersion = '0.1.0+1',
  }) : _workspaceService = workspaceService;

  final LocalWorkspaceService _workspaceService;
  final String appVersion;

  Future<WorkspaceManifest?> loadManifest() async {
    final file = await _workspaceService.resolveWorkspaceManifestFile();
    if (!await file.exists()) {
      return null;
    }

    final rawContent = await file.readAsString();
    final decoded = jsonDecode(rawContent);
    if (decoded is Map<String, dynamic>) {
      return WorkspaceManifest.fromJson(decoded);
    }
    if (decoded is Map) {
      return WorkspaceManifest.fromJson(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    }
    throw const FormatException('workspace_manifest.json 不是 JSON object。');
  }

  Future<WorkspaceManifest> writeManifest({DateTime? createdAt}) async {
    final workspaceDirectory = await _workspaceService
        .resolveStorageDirectory();
    final manifest = WorkspaceManifest(
      appVersion: appVersion,
      createdAt: createdAt ?? DateTime.now(),
      workspacePath: workspaceDirectory.path,
    );
    await saveManifest(manifest);
    return manifest;
  }

  Future<void> saveManifest(WorkspaceManifest manifest) async {
    final file = await _workspaceService.resolveWorkspaceManifestFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );
  }
}
