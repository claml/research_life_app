import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../app/workbench_destination.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/search/global_search_service.dart';
import '../../state/research_life_controller.dart';

const Map<SearchKind, String> _kindLabels = {
  SearchKind.document: '科研文献',
  SearchKind.event: '记录与计划',
  SearchKind.person: '人物',
  SearchKind.session: '分析会话',
  SearchKind.place: '校园地点',
};

class SearchPage extends StatefulWidget {
  const SearchPage({required this.onNavigate, super.key});

  final ValueChanged<WorkbenchTab> onNavigate;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _handleTap(
    BuildContext context,
    ResearchLifeController controller,
    GlobalSearchResult result,
  ) {
    switch (result.kind) {
      case SearchKind.document:
        final document = result.target as PdfLibraryDocument;
        if (document.fileKind.isPdf) {
          controller.requestOpenReading(documentId: document.id);
          widget.onNavigate(WorkbenchTab.researchReading);
        } else {
          controller.requestOpenDocumentView(documentId: document.id);
          widget.onNavigate(WorkbenchTab.materialsDocumentView);
        }
      case SearchKind.event:
        widget.onNavigate(WorkbenchTab.todayCalendar);
      case SearchKind.person:
        widget.onNavigate(WorkbenchTab.researchPersons);
      case SearchKind.session:
        widget.onNavigate(WorkbenchTab.researchAnalysis);
      case SearchKind.place:
        widget.onNavigate(WorkbenchTab.lifeCampus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final query = _queryController.text;
        final results = query.trim().isEmpty
            ? const <GlobalSearchResult>[]
            : GlobalSearchService.search(
                query: query,
                documents: controller.pdfDocuments,
                events: controller.calendarEvents,
                sessions: controller.sessionHistory,
                places: controller.campusPlaces,
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '全局搜索',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '跨文献、记录与计划、人物、分析会话和校园地点搜索。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _queryController,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '搜索文献、事项、人物、会话、地点…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空',
                              onPressed: () {
                                _queryController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: tokens.panelSubtle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusLarge),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusLarge),
                        borderSide: BorderSide(color: tokens.borderFaint),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: query.trim().isEmpty
                  ? const _SearchEmpty(
                      icon: Icons.manage_search_rounded,
                      title: '输入关键词开始搜索',
                      description: '可以搜索 PDF 文献、日历记录与计划、人物、分析会话和校园地点。',
                    )
                  : results.isEmpty
                  ? _SearchEmpty(
                      icon: Icons.search_off_rounded,
                      title: '没有找到相关结果',
                      description: '换个关键词试试，比如文献标题、人名或地点名称。',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      children: [
                        Text(
                          '找到 ${results.length} 条结果',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final group in _groupResults(results)) ...[
                          _GroupHeader(label: _kindLabels[group.kind]!),
                          for (final result in group.results)
                            _SearchResultTile(
                              result: result,
                              onTap: () =>
                                  _handleTap(context, controller, result),
                            ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  List<_ResultGroup> _groupResults(List<GlobalSearchResult> results) {
    final groups = <_ResultGroup>[];
    for (final result in results) {
      final last = groups.isEmpty ? null : groups.last;
      if (last == null || last.kind != result.kind) {
        groups.add(_ResultGroup(kind: result.kind, results: [result]));
      } else {
        last.results.add(result);
      }
    }
    return groups;
  }
}

class _ResultGroup {
  _ResultGroup({required this.kind, required this.results});

  final SearchKind kind;
  final List<GlobalSearchResult> results;
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: tokens.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.result, required this.onTap});

  final GlobalSearchResult result;
  final VoidCallback onTap;

  IconData _kindIcon(GlobalSearchResult result) => switch (result.kind) {
    SearchKind.document => Icons.description_rounded,
    SearchKind.event => Icons.event_rounded,
    SearchKind.person => Icons.person_rounded,
    SearchKind.session => Icons.library_books_rounded,
    SearchKind.place => Icons.place_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tokens.accentSoft.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(_kindIcon(result), size: 19, color: tokens.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    result.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: tokens.accentSoft.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 26, color: tokens.accent),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
