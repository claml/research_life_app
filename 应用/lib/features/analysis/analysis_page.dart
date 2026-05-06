import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/section_card.dart';
import 'state/analysis_controller.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.of(context);
    final analysisController = controller.analysisController;
    final tokens = context.tokens;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final preview = analysisController.preview;
        final latestSession = controller.latestSession;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WorkspaceHeader(
                sourceLabel: analysisController.sourceLabel,
                editingLabel: controller.editingSessionLabel,
                isBusy: analysisController.isBusy,
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 980;
                  final sidebarWidth = _resolveResultsWidth(
                    constraints.maxWidth,
                  );

                  final composer = _buildComposerPanel(
                    context,
                    controller,
                    analysisController,
                    preview,
                    tokens,
                  );
                  final results = _buildResultsPanel(
                    context,
                    preview,
                    latestSession,
                    controller,
                    analysisController,
                    tokens,
                  );

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [composer, const SizedBox(height: 18), results],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: composer),
                      const SizedBox(width: 18),
                      SizedBox(width: sidebarWidth, child: results),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  double _resolveResultsWidth(double maxWidth) {
    if (maxWidth >= 1600) {
      return 450;
    }
    if (maxWidth >= 1360) {
      return 420;
    }
    if (maxWidth >= 1160) {
      return 390;
    }
    return 360;
  }

  Widget _buildComposerPanel(
    BuildContext context,
    dynamic controller,
    AnalysisController analysisController,
    ReviewPreview? preview,
    AppTokens tokens,
  ) {
    final editingLabel = controller.editingSessionLabel as String?;
    final isEditing = editingLabel != null;
    final toolbarLabel = _dragging ? '松开即可导入文件' : '粘贴周记或拖入文件';
    final toolbarHint = analysisController.sourceLabel == null
        ? '支持 TXT / MD / DOCX'
        : analysisController.sourceLabel as String;

    return SectionCard(
      title: isEditing ? '编辑周分析记录' : '周记输入',
      subtitle: isEditing
          ? '正在修改 $editingLabel 的上传记录，保存后会覆盖原记录。'
          : '输入本周记录，生成事项草稿与人物关系。',
      trailing: FilledButton.icon(
        onPressed: analysisController.isBusy
            ? null
            : () => _runAction(context, analysisController.analyzeCurrentInput),
        icon: const Icon(Icons.auto_awesome_rounded),
        label: Text(analysisController.isBusy ? '分析中...' : '开始分析'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                _dragging
                    ? Icons.file_download_done_rounded
                    : Icons.notes_rounded,
                size: 18,
                color: tokens.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      toolbarLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      toolbarHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: analysisController.isBusy
                    ? null
                    : () => _runAsyncAction(
                        context,
                        analysisController.importFile,
                        analyzeAfterSuccess: true,
                      ),
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('导入文件'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) async {
              setState(() => _dragging = false);
              if (details.files.isEmpty) {
                return;
              }
              if (details.files.length > 1) {
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('目前仅支持单文件导入，请一次只拖入一个文件。')),
                );
                return;
              }
              await _handleImport(context, details.files.first.path);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              decoration: BoxDecoration(
                color: tokens.panelSurface,
                borderRadius: BorderRadius.circular(tokens.radiusLarge),
                border: Border.all(
                  color: _dragging ? tokens.accent : tokens.borderFaint,
                  width: _dragging ? 1.6 : 1,
                ),
                boxShadow: _dragging ? tokens.shadowSm : const [],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: TextField(
                      controller: analysisController.inputController,
                      onChanged: analysisController.updateInputText,
                      minLines: 16,
                      maxLines: 20,
                      decoration: const InputDecoration(
                        hintText:
                            '例如：这周我完成了论文第二章资料整理，周三和王老师同步实验计划，周末准备和朋友见面聊天。',
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                  if (_dragging)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            color: tokens.accentSoft.withValues(alpha: 0.82),
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.file_download_done_rounded,
                                size: 28,
                                color: tokens.accent,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '松开鼠标导入文件',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: tokens.textPrimary,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '支持 TXT / MD / DOCX',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: () =>
                    _runAction(context, controller.fillSampleAndAnalyze),
                icon: const Icon(Icons.lightbulb_outline_rounded),
                label: const Text('示例'),
              ),
              TextButton.icon(
                onPressed: controller.clearComposer,
                icon: const Icon(Icons.cleaning_services_rounded),
                label: const Text('清空'),
              ),
              if (preview != null)
                TextButton.icon(
                  onPressed: analysisController.clearDraft,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重置草稿'),
                ),
              if (isEditing)
                TextButton.icon(
                  onPressed: () =>
                      _runAction(context, controller.cancelSessionEditing),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('退出编辑'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel(
    BuildContext context,
    ReviewPreview? preview,
    SessionRecord? latestSession,
    dynamic controller,
    AnalysisController analysisController,
    AppTokens tokens,
  ) {
    if (preview == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionCard(
            title: '结果预览',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CompactEmptyState(
                  icon: Icons.auto_awesome_rounded,
                  title: '等待分析',
                  description: '开始分析后，这里会显示摘要、事项和人物。',
                ),
                const SizedBox(height: 14),
                Row(
                  children: const [
                    Expanded(
                      child: _OverviewMetric(label: '事项', value: '--'),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _OverviewMetric(label: '人物', value: '--'),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _OverviewMetric(label: '提醒', value: '--'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: '分析后会生成',
            child: const Column(
              children: [
                _ResultIntroTile(
                  icon: Icons.task_alt_rounded,
                  title: '事项草稿',
                  description: '拆分已完成事项和后续计划。',
                ),
                SizedBox(height: 10),
                _ResultIntroTile(
                  icon: Icons.people_alt_rounded,
                  title: '人物关系',
                  description: '提取人物并关联相关事项。',
                ),
                SizedBox(height: 10),
                _ResultIntroTile(
                  icon: Icons.notes_rounded,
                  title: '总结提醒',
                  description: '生成简短总结和待补充提醒。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          latestSession != null
              ? SectionCard(
                  title: '最近一次分析',
                  subtitle: latestSession.title,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        latestSession.preview.summary,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _CountTag(
                            label:
                                '${latestSession.preview.completedTasks.length} 条完成',
                          ),
                          _CountTag(
                            label:
                                '${latestSession.preview.plannedTasks.length} 条计划',
                          ),
                          _CountTag(
                            label:
                                '${latestSession.preview.persons.length} 位人物',
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : const SectionCard(
                  title: '示例结果',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('本周共识别出 4 条事项，涉及 3 位人物，包含 1 条后续计划。'),
                      SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _CountTag(label: '3 条完成'),
                          _CountTag(label: '1 条计划'),
                          _CountTag(label: '3 位人物'),
                        ],
                      ),
                    ],
                  ),
                ),
        ],
      );
    }

    final isEditing = controller.editingSessionLabel != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          title: '分析结果',
          trailing: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    _runAction(context, analysisController.confirmDraft),
                icon: const Icon(Icons.check_circle_rounded),
                label: Text(isEditing ? '保存修改' : '确认结果'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _runAction(context, analysisController.analyzeCurrentInput),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('重新分析'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.summary,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _OverviewMetric(
                      label: '已完成',
                      value: '${preview.completedTasks.length}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OverviewMetric(
                      label: '待计划',
                      value: '${preview.plannedTasks.length}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OverviewMetric(
                      label: '人物',
                      value: '${preview.persons.length}',
                    ),
                  ),
                ],
              ),
              if (preview.warnings.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final warning in preview.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.panelSubtle,
                        borderRadius: BorderRadius.circular(
                          tokens.radiusMedium,
                        ),
                        border: Border.all(color: tokens.borderFaint),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: tokens.warmAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              warning,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: tokens.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '事项',
          trailing: _CountTag(
            label:
                '${preview.completedTasks.length + preview.plannedTasks.length} 条',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preview.completedTasks.isNotEmpty) ...[
                _SectionLabel(label: '已完成'),
                const SizedBox(height: 10),
                for (final task in preview.completedTasks) ...[
                  _TaskTile(task: task),
                  if (task != preview.completedTasks.last)
                    const SizedBox(height: 10),
                ],
              ],
              if (preview.completedTasks.isNotEmpty &&
                  preview.plannedTasks.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1),
                ),
              if (preview.plannedTasks.isNotEmpty) ...[
                _SectionLabel(label: '待执行'),
                const SizedBox(height: 10),
                for (final task in preview.plannedTasks) ...[
                  _TaskTile(task: task),
                  if (task != preview.plannedTasks.last)
                    const SizedBox(height: 10),
                ],
              ],
              if (preview.completedTasks.isEmpty &&
                  preview.plannedTasks.isEmpty)
                const _CompactEmptyState(
                  icon: Icons.task_alt_rounded,
                  title: '没有事项',
                  description: '当前文本没有提取到可展示的事项。',
                ),
            ],
          ),
        ),
        if (latestSession != null) ...[
          const SizedBox(height: 18),
          SectionCard(
            title: '最近同步',
            subtitle: latestSession.title,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latestSession.preview.summary,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CountTag(
                      label:
                          '${latestSession.preview.completedTasks.length} 条完成',
                    ),
                    _CountTag(
                      label: '${latestSession.preview.plannedTasks.length} 条计划',
                    ),
                    _CountTag(
                      label: '${latestSession.preview.persons.length} 位人物',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _handleImport(BuildContext context, String path) async {
    final analysisController = ResearchLifeScope.of(context).analysisController;
    await _runAsyncAction(
      context,
      () => analysisController.importFileFromPath(path),
      analyzeAfterSuccess: true,
    );
  }

  Future<void> _runAction(
    BuildContext context,
    FutureOr<String?> Function() action,
  ) async {
    try {
      final message = await Future<String?>.value(action());
      if (!context.mounted || message == null) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分析失败：$error')));
    }
  }

  Future<void> _runAsyncAction(
    BuildContext context,
    Future<String?> Function() action, {
    bool analyzeAfterSuccess = false,
  }) async {
    try {
      final analysisController = ResearchLifeScope.of(
        context,
      ).analysisController;
      final message = await action();
      if (!context.mounted || message == null) {
        return;
      }

      if (analyzeAfterSuccess &&
          analysisController.lastImportSucceeded &&
          analysisController.currentInputText.trim().isNotEmpty) {
        final analyzeMessage = analysisController.analyzeCurrentInput();
        final mergedMessage = analyzeMessage == null
            ? message
            : '$message\n$analyzeMessage';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mergedMessage)));
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入或分析失败：$error')));
    }
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final ExtractedTaskDraft task;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isPlan = task.type == EventType.plan;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isPlan ? tokens.accentSoft : tokens.panelSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.borderFaint),
            ),
            child: Icon(
              isPlan ? Icons.schedule_rounded : Icons.task_alt_rounded,
              size: 18,
              color: isPlan ? tokens.warmAccent : tokens.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.content,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CountTag(label: task.category.label),
                    _CountTag(label: task.type.label),
                    _CountTag(label: '${(task.confidence * 100).round()}%'),
                  ],
                ),
                if (task.relatedPersonNames.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    task.relatedPersonNames.join('、'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.sourceLabel,
    required this.editingLabel,
    required this.isBusy,
  });

  final String? sourceLabel;
  final String? editingLabel;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tokens.panelSurface, tokens.panelSubtle],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(tokens.radiusXLarge),
        border: Border.all(color: tokens.borderFaint),
        boxShadow: tokens.shadowSm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final meta = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _CountTag(label: '周分析'),
              const _CountTag(label: '文本 / 文件'),
              if (editingLabel != null) _CountTag(label: '编辑 $editingLabel'),
              if (sourceLabel != null) _CountTag(label: sourceLabel!),
              if (isBusy) const _CountTag(label: '分析中'),
            ],
          );

          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '周分析工作台',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                editingLabel == null
                    ? '输入周记，生成事项草稿与人物关系。'
                    : '编辑已有上传记录，保存后同步更新历史、主页与人物关系。',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: tokens.textSecondary),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleBlock, const SizedBox(height: 14), meta],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Align(alignment: Alignment.topRight, child: meta),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _CountTag extends StatelessWidget {
  const _CountTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.insetSurface,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: tokens.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ResultIntroTile extends StatelessWidget {
  const _ResultIntroTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tokens.panelSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.borderFaint),
            ),
            child: Icon(icon, size: 18, color: tokens.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactEmptyState extends StatelessWidget {
  const _CompactEmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.panelSurface,
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
              border: Border.all(color: tokens.borderFaint),
            ),
            child: Icon(icon, size: 20, color: tokens.accent),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
