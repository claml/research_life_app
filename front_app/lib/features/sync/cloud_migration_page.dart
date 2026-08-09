import 'package:flutter/material.dart';

import '../../app/auth_scope.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/sync/file_sync_engine.dart';

class CloudMigrationPage extends StatefulWidget {
  const CloudMigrationPage({super.key, required this.syncEngine});

  final FileSyncEngine syncEngine;

  @override
  State<CloudMigrationPage> createState() => _CloudMigrationPageState();
}

class _CloudMigrationPageState extends State<CloudMigrationPage> {
  bool _running = false;
  CloudMigrationReport? _report;
  String? _error;

  Future<void> _runMigration() async {
    final auth = AuthScope.of(context);
    if (!auth.isAuthenticated) {
      setState(() => _error = '请先登录云端账号');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _report = null;
    });
    try {
      final report = await widget.syncEngine.migrateLocalLibraryToCloud();
      if (!mounted) {
        return;
      }
      setState(() => _report = report);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final report = _report;

    return Scaffold(
      appBar: AppBar(title: const Text('迁移到云端')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '迁移前会自动备份本地 SQLite。上传失败不会删除本地 PDF，可对失败项重试。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _running ? null : _runMigration,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_running ? '正在迁移…' : '开始迁移'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (report != null) ...[
            const SizedBox(height: 24),
            Text(
              '完成：${report.successCount}/${report.totalCount}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText('备份：${report.backupPath}'),
            if (report.failures.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('失败项', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final failure in report.failures)
                ListTile(
                  title: Text(failure.title),
                  subtitle: Text(failure.message),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
