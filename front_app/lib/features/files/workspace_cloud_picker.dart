import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/auth_scope.dart';
import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../../state/research_life_controller.dart';

/// 云端文件选择条：PDF 操作 / 文档查阅共用，无需先导入本地。
class WorkspaceCloudPicker extends StatefulWidget {
  const WorkspaceCloudPicker({
    super.key,
    required this.filter,
    this.multiSelect = false,
    this.selectedServerIds = const {},
    this.onSelectionChanged,
    this.height = 140,
  });

  final WorkspaceCloudFilter filter;
  final bool multiSelect;
  final Set<int> selectedServerIds;
  final ValueChanged<Set<int>>? onSelectionChanged;
  final double height;

  @override
  State<WorkspaceCloudPicker> createState() => _WorkspaceCloudPickerState();
}

enum WorkspaceCloudFilter { pdfOnly, viewableOnly }

class _WorkspaceCloudPickerState extends State<WorkspaceCloudPicker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final auth = AuthScope.read(context);
    if (auth.isGuest || !auth.cloudSyncEnabled) {
      return;
    }
    final controller = ResearchLifeScope.read(context);
    await controller.refreshCloudFiles(reconcile: false);
  }

  List<CloudFileEntry> _filtered(ResearchLifeController controller) {
    final all = controller.cloudFileEntries;
    return [
      for (final entry in all)
        if (!entry.isFolder && !entry.systemRoot && _matches(entry)) entry,
    ];
  }

  bool _matches(CloudFileEntry entry) {
    final kind = WorkspaceFileKind.fromPath(entry.title);
    return switch (widget.filter) {
      WorkspaceCloudFilter.pdfOnly => kind.isPdf,
      WorkspaceCloudFilter.viewableOnly => kind.isViewable,
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.read(context);
    final controller = ResearchLifeScope.read(context);
    final tokens = context.tokens;

    if (auth.isGuest) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.shellBorder),
        ),
        child: const Center(child: Text('登录后可直选云端文件')),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([controller, auth]),
      builder: (context, _) {
        final files = _filtered(controller);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.shellBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text('云端文件', style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    Text(
                      '已选 ${widget.selectedServerIds.length}/${files.length}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
                    ),
                    IconButton(
                      tooltip: '刷新云端',
                      icon: controller.cloudFilesBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 20),
                      onPressed: controller.cloudFilesBusy ? null : _refresh,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: widget.height,
                child: files.isEmpty
                    ? Center(
                        child: Text(
                          controller.cloudFilesBusy
                              ? '加载中…'
                              : '云端暂无匹配文件，可在「我的文件」上传',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        scrollDirection: Axis.horizontal,
                        itemCount: files.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final entry = files[index];
                          final selected = widget.selectedServerIds.contains(
                            entry.serverId,
                          );
                          final kind = WorkspaceFileKind.fromPath(entry.title);
                          return InkWell(
                            onTap: () => _toggle(entry.serverId),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 148,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? tokens.accent
                                      : tokens.shellBorder,
                                ),
                                color: selected
                                    ? tokens.accent.withValues(alpha: 0.08)
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(kind.icon, size: 22),
                                  const Spacer(),
                                  Text(
                                    entry.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  Text(
                                    kind.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: tokens.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggle(int serverId) {
    final next = Set<int>.from(widget.selectedServerIds);
    if (widget.multiSelect) {
      if (next.contains(serverId)) {
        next.remove(serverId);
      } else {
        next.add(serverId);
      }
    } else {
      next.clear();
      next.add(serverId);
    }
    widget.onSelectionChanged?.call(next);
  }
}
