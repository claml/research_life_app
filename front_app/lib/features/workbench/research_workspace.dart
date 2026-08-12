import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../app/workbench_destination.dart';
import '../../app/workbench_navigation_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../agent/agent_page.dart';
import '../analysis/analysis_page.dart';
import '../notes/my_notes_page.dart';
import '../persons/persons_page.dart';
import '../reading/reading_page.dart';
import '../stats/stats_page.dart';
import 'workbench_workspace_frame.dart';

class ResearchWorkspace extends StatelessWidget {
  const ResearchWorkspace({
    required this.navigation,
    this.pages,
    this.onOpenAi,
    super.key,
  });

  final WorkbenchNavigationController navigation;
  final Map<WorkbenchTab, Widget>? pages;
  final VoidCallback? onOpenAi;

  @override
  Widget build(BuildContext context) {
    final resolvedPages =
        pages ??
        {
          WorkbenchTab.researchOverview: _ResearchOverview(
            navigation: navigation,
          ),
          WorkbenchTab.researchReading: const ReadingPage(),
          WorkbenchTab.researchNotes: const MyNotesPage(),
          WorkbenchTab.researchAnalysis: const AnalysisPage(),
          WorkbenchTab.researchPersons: const PersonsPage(),
          WorkbenchTab.researchStats: const StatsPage(),
        };
    return WorkbenchWorkspaceFrame(
      key: const Key('research-workspace'),
      workspace: WorkbenchWorkspace.research,
      navigation: navigation,
      title: '科研',
      description: '阅读、整理与复盘。',
      pages: resolvedPages,
      primaryAction: FilledButton.icon(
        onPressed: onOpenAi ?? () => _showAgent(context),
        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
        label: const Text('AI 助手'),
      ),
    );
  }

  void _showAgent(BuildContext context) {
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) => const Dialog.fullscreen(child: AgentPage()),
    );
  }
}

class _ResearchOverview extends StatefulWidget {
  const _ResearchOverview({required this.navigation});

  final WorkbenchNavigationController navigation;

  @override
  State<_ResearchOverview> createState() => _ResearchOverviewState();
}

class _ResearchOverviewState extends State<_ResearchOverview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ResearchLifeScope.of(context);
      unawaited(controller.ensurePdfLibraryLoaded());
      unawaited(controller.ensureNotesLoaded());
      unawaited(controller.ensureSessionHistoryLoaded());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final reading = controller.pdfReadingDocuments;
        final notes = controller.notes;
        final latest = controller.latestSession;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppLayout.pageHorizontalPadding),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 850;
              final cards = [
                _ResearchCard(
                  icon: Icons.menu_book_rounded,
                  title: '最近文献',
                  emptyLabel: '还没有加入阅读的文献',
                  entries: [for (final doc in reading.take(4)) doc.title],
                  onOpen: () =>
                      widget.navigation.selectTab(WorkbenchTab.researchReading),
                ),
                _ResearchCard(
                  icon: Icons.edit_note_rounded,
                  title: '待整理笔记',
                  emptyLabel: '暂无笔记',
                  entries: [for (final note in notes.take(4)) note.title],
                  onOpen: () =>
                      widget.navigation.selectTab(WorkbenchTab.researchNotes),
                ),
                _ResearchCard(
                  icon: Icons.insights_rounded,
                  title: '本周复盘',
                  emptyLabel: '本周还没有复盘',
                  entries: latest == null
                      ? const []
                      : [
                          latest.title,
                          latest.preview.summary.trim().isEmpty
                              ? '已保存分析结果'
                              : latest.preview.summary,
                        ],
                  onOpen: () => widget.navigation.selectTab(
                    WorkbenchTab.researchAnalysis,
                  ),
                ),
              ];
              if (compact) {
                return Column(
                  children: [
                    for (var index = 0; index < cards.length; index++) ...[
                      cards[index],
                      if (index < cards.length - 1) const SizedBox(height: 18),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < cards.length; index++) ...[
                    Expanded(child: cards[index]),
                    if (index < cards.length - 1) const SizedBox(width: 18),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ResearchCard extends StatelessWidget {
  const _ResearchCard({
    required this.icon,
    required this.title,
    required this.emptyLabel,
    required this.entries,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String emptyLabel;
  final List<String> entries;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      constraints: const BoxConstraints(minHeight: 260),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.borderFaint),
        boxShadow: tokens.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(tokens.radiusSmall),
                ),
                child: Icon(icon, color: tokens.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Text(
                emptyLabel,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
              ),
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  entry,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onOpen, child: const Text('打开')),
          ),
        ],
      ),
    );
  }
}
