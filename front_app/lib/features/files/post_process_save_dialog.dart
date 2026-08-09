import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import 'cloud_file_dialogs.dart';

enum ProcessSaveChoice { local, cloud, both }

/// 选择保存方式并返回云端目标文件夹（若选云端）。
Future<({ProcessSaveChoice? choice, int? cloudParentId})>
showPostProcessSaveSheet(
  BuildContext context, {
  required String fileName,
  required List<CloudFileEntry> entries,
}) async {
  CloudFileEntry? root;
  for (final entry in entries) {
    if (entry.systemRoot) {
      root = entry;
      break;
    }
  }

  final choice = await showModalBottomSheet<ProcessSaveChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('保存 $fileName', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('下载到本地'),
              subtitle: const Text('写入本机文件库，可在「我的文件」查看'),
              onTap: () => Navigator.pop(ctx, ProcessSaveChoice.local),
            ),
            if (root != null) ...[
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('上传到云端'),
                subtitle: const Text('选择云端文件夹后上传'),
                onTap: () => Navigator.pop(ctx, ProcessSaveChoice.cloud),
              ),
              ListTile(
                leading: const Icon(Icons.sync_alt_rounded),
                title: const Text('本地 + 云端'),
                subtitle: const Text('先保存本机，再上传到所选文件夹'),
                onTap: () => Navigator.pop(ctx, ProcessSaveChoice.both),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  if (choice == null || choice == ProcessSaveChoice.local || !context.mounted) {
    return (choice: choice, cloudParentId: null);
  }

  final folder = await showMoveTargetFolderDialog(
    context,
    entries: entries,
    movingEntry: CloudFileEntry(
      serverId: -1,
      clientId: 'picker',
      title: fileName,
      entryType: 'file',
    ),
  );
  if (folder == null) {
    return (choice: null, cloudParentId: null);
  }
  return (choice: choice, cloudParentId: folder.serverId);
}
