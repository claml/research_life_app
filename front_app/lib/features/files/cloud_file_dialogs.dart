import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';

Future<String?> showCloudNameDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
  String hint = '名称',
}) {
  final controller = TextEditingController(text: initialValue ?? '');
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Future<bool> showCloudDeleteConfirm(
  BuildContext context, {
  required String name,
  required bool isFolder,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isFolder ? '删除文件夹' : '删除文件'),
      content: Text(isFolder ? '确定删除文件夹「$name」吗？其中文件将一并删除。' : '确定删除「$name」吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('删除'),
        ),
      ],
    ),
  ).then((value) => value == true);
}

Future<CloudFileEntry?> showMoveTargetFolderDialog(
  BuildContext context, {
  required List<CloudFileEntry> entries,
  required CloudFileEntry movingEntry,
}) {
  final folders =
      entries.where((entry) => entry.isFolder && !entry.systemRoot).toList()
        ..sort((a, b) => a.title.compareTo(b.title));
  CloudFileEntry? root;
  for (final entry in entries) {
    if (entry.systemRoot) {
      root = entry;
      break;
    }
  }

  return showDialog<CloudFileEntry>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('移动到'),
      children: [
        if (root != null)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, root),
            child: Text('${root.title}（根目录）'),
          ),
        for (final folder in folders)
          if (folder.serverId != movingEntry.serverId)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, folder),
              child: Text(folder.relativePath ?? folder.title),
            ),
      ],
    ),
  );
}
