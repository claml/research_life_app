import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../state/research_life_controller.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/status_badge.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({this.onEditSession, super.key});

  final ValueChanged<SessionRecord>? onEditSession;

  void _startEditingSession(
    BuildContext context,
    ResearchLifeController controller,
    SessionRecord session,
  ) {
    final message = session.isInstitutionCalendar
        ? controller.loadInstitutionCalendarForEditing(session.id)
        : controller.loadSessionForEditing(session.id);
    final loaded = session.isInstitutionCalendar
        ? controller.editingInstitutionCalendarSessionId == session.id
        : controller.editingSession?.id == session.id;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    if (loaded) {
      onEditSession?.call(session);
    }
  }

  Future<void> _confirmDeleteSession(
    BuildContext context,
    ResearchLifeController controller,
    SessionRecord session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除历史记录'),
        content: Text(
          session.isInstitutionCalendar
              ? '确定删除“${session.title}”吗？对应校历事件也会从主页日历移除。'
              : '确定删除“${session.title}”吗？相关人物、待办和规划事件也会一起移除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除'),
          ),
        ],
      ),
    );

    if (!context.mounted || confirmed != true) {
      return;
    }

    final message = controller.deleteSessionRecord(session.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final sessions = controller.sessionHistory;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  const StatusBadge(label: '会话内历史记录', color: Color(0xFF24483C)),
                  StatusBadge(
                    label: '已保存 ${sessions.length} 条',
                    color: const Color(0xFF7D8F63),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('历史记录', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                '周分析上传记录和校历导入记录都可以从这里重新编辑，保存后会覆盖原记录。',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF576057)),
              ),
              const SizedBox(height: 24),
              if (sessions.isEmpty)
                const EmptyState(
                  title: '还没有确认过的分析记录',
                  description: '完成一次周分析或导入校历后，这里会生成一条历史卡片。',
                  icon: Icons.history_rounded,
                )
              else
                SectionCard(
                  title: '保存记录',
                  subtitle: '按保存时间倒序展示。',
                  child: Column(
                    children: [
                      for (final session in sessions)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9F7F2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFECE3D5)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: session.isInstitutionCalendar
                                      ? const Color(0xFF536D7A)
                                      : const Color(0xFF16342D),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                alignment: Alignment.center,
                                child: session.isInstitutionCalendar
                                    ? const Icon(
                                        Icons.calendar_month_rounded,
                                        color: Colors.white,
                                      )
                                    : Text(
                                        '${session.confirmedAt.day}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(color: Colors.white),
                                      ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      session.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      session.preview.summary,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: const Color(0xFF5F665F),
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        if (session.isInstitutionCalendar) ...[
                                          Chip(
                                            label: Text(
                                              '${session.events.length} 条校历事件',
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              session.input.sourceType.label,
                                            ),
                                          ),
                                        ] else ...[
                                          Chip(
                                            label: Text(
                                              '${session.preview.completedTasks.length} 条完成事项',
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              '${session.preview.plannedTasks.length} 条未来计划',
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              '${session.preview.persons.length} 位人物',
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              session.input.sourceType.label,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (onEditSession != null) ...[
                                const SizedBox(width: 12),
                                IconButton(
                                  tooltip: session.isInstitutionCalendar
                                      ? '编辑校历文本'
                                      : '编辑上传记录',
                                  onPressed: () => _startEditingSession(
                                    context,
                                    controller,
                                    session,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: '删除历史记录',
                                  onPressed: () => _confirmDeleteSession(
                                    context,
                                    controller,
                                    session,
                                  ),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
