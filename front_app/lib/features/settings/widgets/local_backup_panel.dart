import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/local_services_scope.dart';
import '../../../services/storage/backup_manifest.dart';
import '../../../state/local_backup_controller.dart';

class LocalBackupPanel extends StatelessWidget {
  const LocalBackupPanel({super.key, this.showHeading = true});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final controller = LocalServicesScope.of(context).backupController;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final latest = controller.latestBackup;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeading) ...[
              Text(
                '备份与恢复',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
            ],
            _BackupInfoRow(
              label: '最近备份',
              value: latest == null
                  ? '尚无已验证备份'
                  : _formatDateTime(latest.manifest.createdAt),
            ),
            const SizedBox(height: 8),
            _BackupInfoRow(
              label: '备份目录',
              value: controller.backupDirectoryPath ?? '尚未生成',
            ),
            if (controller.message != null) ...[
              const SizedBox(height: 10),
              Text(
                controller.message!,
                style: TextStyle(
                  color: controller.messageIsError
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => _createBackup(context, controller),
                  icon: const Icon(Icons.backup_rounded),
                  label: const Text('立即备份'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      controller.busy || controller.backupDirectoryPath == null
                      ? null
                      : () => _run(context, controller.openBackupDirectory),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('打开备份目录'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => _chooseAndRestore(context, controller),
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('恢复备份'),
                ),
              ],
            ),
            if (controller.busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        );
      },
    );
  }

  Future<void> _createBackup(
    BuildContext context,
    LocalBackupController controller,
  ) async {
    await _run(context, controller.createManualBackup);
  }

  Future<void> _chooseAndRestore(
    BuildContext context,
    LocalBackupController controller,
  ) async {
    final path = await getDirectoryPath(confirmButtonText: '选择备份');
    if (path == null || !context.mounted) return;
    final directory = Directory(path);
    BackupManifest manifest;
    try {
      manifest = await controller.inspectBackup(directory);
    } catch (error) {
      if (context.mounted) _showMessage(context, '$error');
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认恢复'),
        content: Text(
          '恢复 ${_formatDateTime(manifest.createdAt)} 的备份？'
          '当前状态会先自动保护。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.restore(directory);
    } catch (error) {
      if (context.mounted) _showMessage(context, '$error');
    }
  }

  Future<void> _run(
    BuildContext context,
    Future<Object?> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error) {
      if (context.mounted) _showMessage(context, '$error');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BackupInfoRow extends StatelessWidget {
  const _BackupInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
