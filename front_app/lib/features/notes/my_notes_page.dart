import 'package:flutter/material.dart';
import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../state/research_life_controller.dart';
import '../reading/reading_latex_utils.dart';
import 'note_editor_page.dart';
import 'notes_export.dart';
import 'notes_preview.dart';

class MyNotesPage extends StatefulWidget {
  const MyNotesPage({super.key});

  @override
  State<MyNotesPage> createState() => _MyNotesPageState();
}

class _MyNotesPageState extends State<MyNotesPage> {
  String _query = '';
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final controller = ResearchLifeScope.of(context);
    setState(() => _refreshing = true);
    await controller.ensurePdfLibraryLoaded();
    await controller.refreshCloudUserNotes();
    if (mounted) {
      setState(() => _refreshing = false);
    }
  }

  List<PdfNoteDocumentGroup> _filteredGroups(
    ResearchLifeController controller,
  ) {
    final needle = _query.trim().toLowerCase();
    final groups = controller.pdfNoteDocumentGroups();
    if (needle.isEmpty) {
      return groups;
    }
    return [
      for (final group in groups)
        if (group.document.title.toLowerCase().contains(needle) ||
            group.notes.any(
              (note) =>
                  note.selectedText.toLowerCase().contains(needle) ||
                  (note.note?.toLowerCase().contains(needle) ?? false),
            ))
          PdfNoteDocumentGroup(
            document: group.document,
            notes: [
              for (final note in group.notes)
                if (group.document.title.toLowerCase().contains(needle) ||
                    note.selectedText.toLowerCase().contains(needle) ||
                    (note.note?.toLowerCase().contains(needle) ?? false))
                  note,
            ],
          ),
    ];
  }

  void _openInReader(PdfTextAnnotation note) {
    ResearchLifeScope.of(context).requestOpenReading(
      documentId: note.documentId,
      pageNumber: note.pageNumber,
      annotationId: note.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    final tokens = context.tokens;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return DefaultTabController(
          length: 2,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '我的笔记',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '「独立笔记」保存自己的 Markdown 随笔；「文献笔记」聚合 PDF 批注感悟。',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: tokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: _refreshing ? null : _refresh,
                      icon: _refreshing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<NotesExportFormat>(
                      tooltip: '导出（预览）',
                      onSelected: (format) async {
                        final markdown = NotesExport.build(
                          groups: controller.pdfNoteDocumentGroups(),
                          format: format,
                        );
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('导出 ${format.label} 预览'),
                            content: SizedBox(
                              width: 560,
                              height: 420,
                              child: SingleChildScrollView(
                                child: SelectableText(markdown),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        );
                      },
                      itemBuilder: (context) => [
                        for (final format in NotesExportFormat.values)
                          PopupMenuItem(
                            value: format,
                            child: Text(format.label),
                          ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.download_rounded, size: 18),
                            SizedBox(width: 6),
                            Text('导出'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const TabBar(
                  tabs: [
                    Tab(text: '独立笔记'),
                    Tab(text: '文献笔记'),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      _IndependentNotesTab(
                        notes: controller.notes,
                        onOpenNote: (note) => _openNoteEditor(context, note),
                        onCreateNote: () => _openNoteEditor(context, null),
                      ),
                      _buildDocumentNotesTab(controller, tokens),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openNoteEditor(BuildContext context, UserNote? note) async {
    final controller = ResearchLifeScope.of(context);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => NoteEditorPage(
          note: note,
          onCreate: (title, content) =>
              controller.createNote(title: title, contentMarkdown: content),
          onUpdate: (id, title, content) =>
              controller.updateNote(id, title: title, contentMarkdown: content),
          onDelete: (id) => controller.deleteNote(id),
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildDocumentNotesTab(
    ResearchLifeController controller,
    AppTokens tokens,
  ) {
    final groups = _filteredGroups(controller);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: '搜索文献标题、摘录或感悟…',
            prefixIcon: const Icon(Icons.search_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
            ),
            isDense: true,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty ? '还没有笔记，在阅读 PDF 时选中文字即可添加。' : '没有匹配的笔记。',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: groups.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return _DocumentNoteCard(
                      group: group,
                      onOpenNote: _openInReader,
                      onOpenDocument: () {
                        final first = group.notes.first;
                        _openInReader(first);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 独立 Markdown 笔记列表。
class _IndependentNotesTab extends StatelessWidget {
  const _IndependentNotesTab({
    required this.notes,
    required this.onOpenNote,
    required this.onCreateNote,
  });

  final List<UserNote> notes;
  final ValueChanged<UserNote> onOpenNote;
  final VoidCallback onCreateNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_rounded, size: 42, color: tokens.textMuted),
            const SizedBox(height: 12),
            Text(
              '还没有独立笔记',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '用 Markdown 记录想法、随笔或项目笔记。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onCreateNote,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建笔记'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onCreateNote,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新建笔记'),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: notes.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final note = notes[index];
              return _NoteCard(note: note, onTap: () => onOpenNote(note));
            },
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onTap});

  final UserNote note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final preview = stripMarkdownForPreview(note.contentMarkdown);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.panelSubtle,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.borderFaint),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.accentSoft.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.sticky_note_2_rounded,
                size: 18,
                color: tokens.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview.isEmpty ? '（空白笔记）' : preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatNoteTime(note.updatedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatNoteTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _DocumentNoteCard extends StatelessWidget {
  const _DocumentNoteCard({
    required this.group,
    required this.onOpenNote,
    required this.onOpenDocument,
  });

  final PdfNoteDocumentGroup group;
  final ValueChanged<PdfTextAnnotation> onOpenNote;
  final VoidCallback onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return Material(
      color: tokens.panelSurface,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
              onTap: onOpenDocument,
              child: Row(
                children: [
                  Icon(Icons.menu_book_rounded, color: tokens.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      group.document.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${group.notes.length} 条',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final note in group.notes) ...[
              InkWell(
                borderRadius: BorderRadius.circular(tokens.radiusSmall),
                onTap: () => onOpenNote(note),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        alignment: Alignment.topCenter,
                        child: Text(
                          'P${note.pageNumber}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: tokens.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              note.selectedText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (note.note?.isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              Text(
                                note.note!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                            if (note.hasLatex) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.functions_rounded,
                                    size: 14,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      note.latexContent ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(fontFamily: 'Consolas'),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '复制公式到 Word',
                                    visualDensity: VisualDensity.compact,
                                    iconSize: 16,
                                    onPressed: note.latexContent == null
                                        ? null
                                        : () => ReadingLatexUtils.copyForWord(
                                            note.latexContent!,
                                          ),
                                    icon: const Icon(Icons.copy_rounded),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              _formatNoteTime(note.updatedAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: tokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: tokens.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              if (note != group.notes.last)
                Divider(height: 1, color: tokens.borderFaint),
            ],
          ],
        ),
      ),
    );
  }
}
