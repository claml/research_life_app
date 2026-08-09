import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../services/sync/sync_models.dart';

class SyncStatusPanel extends StatelessWidget {
  const SyncStatusPanel({
    super.key,
    required this.enabled,
    required this.status,
    required this.statusBusy,
    required this.syncBusy,
    required this.syncMessageIsError,
    this.statusMessage,
    this.syncMessage,
    this.cloudFilesMessage,
  });

  final bool enabled;
  final CloudSyncStatus status;
  final bool statusBusy;
  final bool syncBusy;
  final String? statusMessage;
  final String? syncMessage;
  final bool syncMessageIsError;
  final String? cloudFilesMessage;

  @override
  Widget build(BuildContext context) {
    final messages = <Widget>[
      if (statusMessage != null && statusMessage!.isNotEmpty)
        _SyncInfoBanner(title: '状态读取', body: statusMessage!),
      if (syncMessage != null && syncMessage!.isNotEmpty)
        _SyncInfoBanner(
          title: syncMessageIsError ? '同步失败' : '同步结果',
          body: syncMessage!,
        ),
      if (cloudFilesMessage != null && cloudFilesMessage!.isNotEmpty)
        _SyncInfoBanner(title: '云端文件', body: cloudFilesMessage!),
    ];

    if (!enabled) {
      return const _SyncInfoBanner(
        title: '本地模式',
        body: '当前不会连接云端。登录后可以同步文献文件、PDF 批注和云端文件树。',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (statusBusy || syncBusy) ...[
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 14),
        ],
        _SyncMetricGrid(
          metrics: [
            _SyncMetricData(
              icon: Icons.upload_file_rounded,
              label: '待上传文件',
              value: '${status.pendingUploadCount}',
              helper: '本地 PDF 原文件',
            ),
            _SyncMetricData(
              icon: Icons.outbox_rounded,
              label: '待推送变更',
              value: '${status.pendingOutboxCount}',
              helper: '元数据与批注',
            ),
            _SyncMetricData(
              icon: Icons.replay_circle_filled_rounded,
              label: '重试项',
              value: '${status.retryingOutboxCount}',
              helper: '上次推送未确认',
            ),
            _SyncMetricData(
              icon: Icons.schedule_rounded,
              label: '上次同步',
              value: status.lastSyncedAt == null
                  ? '未记录'
                  : _formatDateTime(status.lastSyncedAt!),
              helper: '增量游标 ${status.cursorValue}',
            ),
          ],
        ),
        if (messages.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...messages.expand((widget) => [widget, const SizedBox(height: 10)]),
        ],
      ],
    );
  }
}

class _SyncMetricData {
  const _SyncMetricData({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;
}

class _SyncMetricGrid extends StatelessWidget {
  const _SyncMetricGrid({required this.metrics});

  final List<_SyncMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 4 : 2;
        final spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _SyncMetricTile(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _SyncMetricTile extends StatelessWidget {
  const _SyncMetricTile({required this.metric});

  final _SyncMetricData metric;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      constraints: const BoxConstraints(minHeight: 122),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, size: 20, color: tokens.accent),
          const SizedBox(height: 10),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            metric.label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            metric.helper,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SyncInfoBanner extends StatelessWidget {
  const _SyncInfoBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.accentSoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
