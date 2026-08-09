import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/auth_scope.dart';
import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../../state/research_life_controller.dart';
import '../../shared/widgets/empty_state.dart';
import '../files/cloud_file_explorer.dart';
import 'reading_note_dialog.dart';
import 'reading_save_dialog.dart';

/// PDF 全文搜索匹配高亮色（半透明黄 / 当前匹配橙）。
/// PDF 页面本身是白底，与主题无关。
const Color _searchMatchColor = Color(0x66FFE082);
const Color _searchActiveMatchColor = Color(0x80FF8F00);

class ReadingPage extends StatefulWidget {
  const ReadingPage({super.key});

  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage> {
  static const _categoryOptions = ['未分类', '论文', '课程', '项目', '书籍', '资料'];

  String? _selectedDocumentId;
  int? _pendingPageNumber;
  String? _pendingAnnotationId;
  bool _pendingOpenFullscreen = false;
  String _selectedCategory = _categoryOptions.first;
  bool _dragging = false;
  int _readerRefreshTick = 0;
  bool _cloudPickerExpanded = true;
  ResearchLifeController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapReadingPage();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ResearchLifeScope.of(context);
    if (!identical(_controller, controller)) {
      _controller?.removeListener(_handleReadingNavigation);
      _controller = controller;
      controller.addListener(_handleReadingNavigation);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleReadingNavigation);
    super.dispose();
  }

  void _handleReadingNavigation() {
    if (_controller?.hasPendingReadingOpen == true) {
      unawaited(_consumeReadingOpenRequest());
    }
  }

  Future<void> _bootstrapReadingPage() async {
    final controller = ResearchLifeScope.of(context);
    final auth = AuthScope.of(context);
    if (auth.cloudSyncEnabled) {
      await controller.refreshCloudFiles(reconcile: false);
    }
    await _consumeReadingOpenRequest();
  }

  Future<void> _consumeReadingOpenRequest() async {
    final controller = ResearchLifeScope.of(context);
    final request = controller.consumeReadingOpenRequest();
    if (request == null || request.isEmpty || !mounted) {
      return;
    }
    if (request.documentId != null) {
      final document = controller.pdfDocumentById(request.documentId!);
      setState(() {
        _selectedDocumentId = request.documentId;
        _pendingPageNumber = request.pageNumber;
        _pendingAnnotationId = request.annotationId;
        _pendingOpenFullscreen = request.openFullscreen;
        _readerRefreshTick++;
      });
      if (request.openFullscreen && document != null && mounted) {
        await _openFullscreenReader(
          context,
          controller,
          document,
          initialPageNumber: request.pageNumber,
          focusAnnotationId: request.annotationId,
        );
        if (mounted) {
          setState(() {
            _pendingPageNumber = null;
            _pendingAnnotationId = null;
            _pendingOpenFullscreen = false;
          });
        }
      }
      return;
    }
    if (request.cloudServerId != null) {
      final entry = controller.cloudFileEntryByServerId(request.cloudServerId!);
      if (entry != null) {
        await _openCloudEntry(entry);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final documents = controller.pdfReadingDocuments;
        final selectedDocument = _selectedDocument(documents);

        final auth = AuthScope.read(context);
        final tokens = context.tokens;

        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReadingHeader(
                busy: controller.pdfLibraryBusy,
                category: _selectedCategory,
                categories: _categoryOptions,
                onCategoryChanged: (category) =>
                    setState(() => _selectedCategory = category),
                onImport: () => _pickPdf(context, controller),
              ),
              if (auth.cloudSyncEnabled) ...[
                const SizedBox(height: 12),
                Material(
                  color: tokens.panelSurface,
                  borderRadius: BorderRadius.circular(tokens.radiusMedium),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(tokens.radiusMedium),
                    onTap: () => setState(
                      () => _cloudPickerExpanded = !_cloudPickerExpanded,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _cloudPickerExpanded
                                ? Icons.folder_open_rounded
                                : Icons.folder_rounded,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '云端文献库',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Icon(
                            _cloudPickerExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_cloudPickerExpanded) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: selectedDocument == null ? 280 : 220,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.panelSurface,
                        borderRadius: BorderRadius.circular(
                          tokens.radiusMedium,
                        ),
                        border: Border.all(color: tokens.borderFaint),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: CloudFileExplorer(
                          compact: true,
                          entries: controller.cloudFileEntries,
                          busy: controller.cloudFilesBusy,
                          controller: controller,
                          mode: CloudFileExplorerMode.readingPicker,
                          fileFilter: (entry) =>
                              WorkspaceFileKind.fromPath(entry.title).isPdf,
                          onOpenFile: _openCloudEntry,
                          onSaveAs: (entry) =>
                              _saveCloudEntryAs(context, controller, entry),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Expanded(
                child: selectedDocument == null
                    ? Row(
                        children: [
                          SizedBox(
                            width: 280,
                            child: _DocumentLibraryPanel(
                              documents: documents,
                              selectedDocumentId: selectedDocument?.id,
                              dragging: _dragging,
                              annotationCountFor: (documentId) => controller
                                  .pdfAnnotationsFor(documentId)
                                  .length,
                              onSelect: (document) => setState(
                                () => _selectedDocumentId = document.id,
                              ),
                              onDelete: (document) => _confirmDeleteDocument(
                                context,
                                controller,
                                document,
                              ),
                              onDragEntered: () =>
                                  setState(() => _dragging = true),
                              onDragExited: () =>
                                  setState(() => _dragging = false),
                              onDragDone: (path) =>
                                  _addDroppedPdf(context, controller, path),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _EmptyReader(
                              dragging: _dragging,
                              onDragEntered: () =>
                                  setState(() => _dragging = true),
                              onDragExited: () =>
                                  setState(() => _dragging = false),
                              onDragDone: (path) =>
                                  _addDroppedPdf(context, controller, path),
                            ),
                          ),
                        ],
                      )
                    : _PdfReader(
                        key: ValueKey(
                          '${selectedDocument.id}-$_readerRefreshTick',
                        ),
                        document: selectedDocument,
                        controller: controller,
                        initialPageNumber: _pendingPageNumber,
                        focusAnnotationId: _pendingAnnotationId,
                        onNavigationConsumed: () {
                          if (_pendingPageNumber != null ||
                              _pendingAnnotationId != null ||
                              _pendingOpenFullscreen) {
                            setState(() {
                              _pendingPageNumber = null;
                              _pendingAnnotationId = null;
                              _pendingOpenFullscreen = false;
                            });
                          }
                        },
                        documents: documents,
                        selectedDocumentId: selectedDocument.id,
                        dragging: _dragging,
                        annotationCountFor: (documentId) =>
                            controller.pdfAnnotationsFor(documentId).length,
                        onSelectDocument: (document) =>
                            setState(() => _selectedDocumentId = document.id),
                        onDeleteDocument: (document) => _confirmDeleteDocument(
                          context,
                          controller,
                          document,
                        ),
                        onDragEntered: () => setState(() => _dragging = true),
                        onDragExited: () => setState(() => _dragging = false),
                        onDragDone: (path) =>
                            _addDroppedPdf(context, controller, path),
                        onOpenFullscreen: () => _openFullscreenReader(
                          context,
                          controller,
                          selectedDocument,
                        ),
                        onCloseReading: () =>
                            setState(() => _selectedDocumentId = null),
                        onSaveReading: () => _saveReadingSession(
                          context,
                          controller,
                          selectedDocument,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  PdfLibraryDocument? _selectedDocument(List<PdfLibraryDocument> documents) {
    if (documents.isEmpty) {
      return null;
    }
    final selectedId = _selectedDocumentId;
    if (selectedId != null) {
      for (final document in documents) {
        if (document.id == selectedId) {
          return document;
        }
      }
    }
    return documents.first;
  }

  Future<void> _openFullscreenReader(
    BuildContext context,
    ResearchLifeController controller,
    PdfLibraryDocument document, {
    int? initialPageNumber,
    String? focusAnnotationId,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenReadingRoute(
          document: document,
          controller: controller,
          initialPageNumber: initialPageNumber,
          focusAnnotationId: focusAnnotationId,
        ),
      ),
    );
  }

  Future<void> _pickPdf(
    BuildContext context,
    ResearchLifeController controller,
  ) async {
    try {
      final document = await controller.pickPdfDocument(
        category: _selectedCategory,
      );
      if (!context.mounted || document == null) {
        return;
      }
      setState(() => _selectedDocumentId = document.id);
      _showMessage(context, '已加入阅读列表：${document.title}');
    } on StateError catch (error) {
      if (context.mounted) {
        _showMessage(context, error.message);
      }
    }
  }

  Future<void> _addDroppedPdf(
    BuildContext context,
    ResearchLifeController controller,
    String path,
  ) async {
    setState(() => _dragging = false);
    try {
      final document = await controller.addPdfDocumentFromPath(
        path,
        category: _selectedCategory,
      );
      if (!context.mounted) {
        return;
      }
      setState(() => _selectedDocumentId = document.id);
      _showMessage(context, '已加入阅读列表：${document.title}');
    } on StateError catch (error) {
      if (context.mounted) {
        _showMessage(context, error.message);
      }
    }
  }

  Future<void> _confirmDeleteDocument(
    BuildContext context,
    ResearchLifeController controller,
    PdfLibraryDocument document,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除 PDF'),
        content: Text('确定从阅读列表移除《${document.title}》吗？仅移出左侧列表，批注与文件仍保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('移除'),
          ),
        ],
      ),
    );

    if (!context.mounted || confirmed != true) {
      return;
    }

    final message = controller.removeFromReadingList(document.id);
    if (_selectedDocumentId == document.id) {
      setState(() => _selectedDocumentId = null);
    }
    _showMessage(context, message);
  }

  Future<void> _saveCloudEntryAs(
    BuildContext context,
    ResearchLifeController controller,
    CloudFileEntry entry,
  ) async {
    final doc = await controller.prepareCloudFileForReading(entry);
    if (doc == null || !context.mounted) {
      return;
    }
    await _showReadingSaveDialog(context, controller, doc);
  }

  Future<void> _openCloudEntry(CloudFileEntry entry) async {
    final controller = ResearchLifeScope.of(context);
    try {
      final document = await controller.prepareCloudFileForReading(entry);
      if (!mounted || document == null) {
        return;
      }
      setState(() => _selectedDocumentId = document.id);
      _showMessage(context, '已从云端打开《${document.title}》');
    } catch (error) {
      if (mounted) {
        _showMessage(context, '打开失败：$error');
      }
    }
  }

  Future<void> _saveReadingSession(
    BuildContext context,
    ResearchLifeController controller,
    PdfLibraryDocument document,
  ) async {
    final auth = AuthScope.of(context);
    if (!auth.cloudSyncEnabled) {
      await _showReadingSaveDialog(context, controller, document);
      return;
    }

    final documentId = document.id;
    final message = await controller.saveDocumentToCloud(documentId);
    if (!context.mounted) {
      return;
    }

    if (message != null) {
      _showMessage(context, message);
      return;
    }

    setState(() => _readerRefreshTick++);
    _showMessage(context, '已保存到云端');
  }

  Future<void> _showReadingSaveDialog(
    BuildContext context,
    ResearchLifeController controller,
    PdfLibraryDocument document,
  ) async {
    final auth = AuthScope.of(context);
    final result = await showReadingSaveDialog(
      context,
      currentTitle: document.title,
      cloudSyncEnabled: auth.cloudSyncEnabled,
    );
    if (!context.mounted || result == null) {
      return;
    }
    switch (result) {
      case ReadingCloseResult():
        setState(() => _selectedDocumentId = null);
      case ReadingSaveLocalResult():
        await controller.waitForPendingPdfPersistence();
        if (document.cloudOnly && document.serverId != null) {
          final entry = controller.cloudFileEntryByServerId(document.serverId!);
          if (entry != null) {
            await controller.moveCloudEntryToLocal(entry);
          }
        }
        if (context.mounted) {
          setState(() => _readerRefreshTick++);
          _showMessage(context, '已保存到本机');
        }
      case ReadingSaveCloudResult(
        overwrite: final overwrite,
        newTitle: final newTitle,
      ):
        final docId = document.id;
        final message = await controller.saveDocumentToCloud(
          docId,
          newTitle: overwrite ? null : newTitle,
        );
        if (!context.mounted) {
          return;
        }
        if (message != null) {
          _showMessage(context, message);
          return;
        }
        setState(() => _readerRefreshTick++);
        _showMessage(context, '已保存到云端');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FullscreenReadingRoute extends StatelessWidget {
  const _FullscreenReadingRoute({
    required this.document,
    required this.controller,
    this.initialPageNumber,
    this.focusAnnotationId,
  });

  final PdfLibraryDocument document;
  final ResearchLifeController controller;
  final int? initialPageNumber;
  final String? focusAnnotationId;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: _PdfReader(
            document: document,
            controller: controller,
            fullscreen: true,
            trackReadingTime: false,
            initialPageNumber: initialPageNumber,
            focusAnnotationId: focusAnnotationId,
            onExitFullscreen: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

class _ReadingHeader extends StatelessWidget {
  const _ReadingHeader({
    required this.busy,
    required this.category,
    required this.categories,
    required this.onCategoryChanged,
    required this.onImport,
  });

  final bool busy;
  final String category;
  final List<String> categories;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('科研文献', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                '阅读 PDF、高亮批注；点工具栏「保存」将批注同步到云端',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 132,
          child: DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '分类',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final option in categories)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: busy
                ? null
                : (value) {
                    if (value != null) {
                      onCategoryChanged(value);
                    }
                  },
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: busy ? null : onImport,
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('导入 PDF'),
        ),
      ],
    );
  }
}

class _DocumentLibraryPanel extends StatelessWidget {
  const _DocumentLibraryPanel({
    required this.documents,
    required this.selectedDocumentId,
    required this.dragging,
    required this.annotationCountFor,
    required this.onSelect,
    required this.onDelete,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDragDone,
  });

  final List<PdfLibraryDocument> documents;
  final String? selectedDocumentId;
  final bool dragging;
  final int Function(String documentId) annotationCountFor;
  final ValueChanged<PdfLibraryDocument> onSelect;
  final ValueChanged<PdfLibraryDocument> onDelete;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final ValueChanged<String> onDragDone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return DropTarget(
      onDragEntered: (_) => onDragEntered(),
      onDragExited: (_) => onDragExited(),
      onDragDone: (details) {
        if (details.files.isEmpty) {
          onDragExited();
          return;
        }
        onDragDone(details.files.first.path);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.panelSurface,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(
            color: dragging ? tokens.accent : tokens.borderFaint,
            width: dragging ? 1.6 : 1,
          ),
          boxShadow: tokens.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_copy_rounded, color: tokens.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '文库',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _MiniPill(label: '${documents.length} 份'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: documents.isEmpty
                  ? Center(
                      child: Text(
                        dragging ? '松开后导入 PDF' : '还没有 PDF，点击上方导入或拖到这里。',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: documents.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final document = documents[index];
                        return _DocumentChip(
                          document: document,
                          selected: document.id == selectedDocumentId,
                          annotationCount: annotationCountFor(document.id),
                          onTap: () => onSelect(document),
                          onDelete: () => onDelete(document),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentChip extends StatelessWidget {
  const _DocumentChip({
    required this.document,
    required this.selected,
    required this.annotationCount,
    required this.onTap,
    required this.onDelete,
  });

  final PdfLibraryDocument document;
  final bool selected;
  final int annotationCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final pageLabel = document.pageCount == null
        ? '第 ${document.lastPage} 页'
        : '第 ${document.lastPage}/${document.pageCount} 页';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? tokens.accentSoft : tokens.panelSubtle,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(
            color: selected ? tokens.accent : tokens.borderFaint,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected ? tokens.accent : tokens.panelSurface,
                borderRadius: BorderRadius.circular(tokens.radiusSmall),
                border: Border.all(color: tokens.borderFaint),
              ),
              child: Icon(
                Icons.picture_as_pdf_rounded,
                color: selected ? Colors.white : tokens.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _MiniPill(label: document.category),
                      _MiniPill(label: pageLabel),
                      _MiniPill(label: '$annotationCount 条标注'),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '移除',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfReader extends StatefulWidget {
  const _PdfReader({
    required this.document,
    required this.controller,
    this.fullscreen = false,
    this.trackReadingTime = true,
    this.documents,
    this.selectedDocumentId,
    this.dragging = false,
    this.annotationCountFor,
    this.onSelectDocument,
    this.onDeleteDocument,
    this.onDragEntered,
    this.onDragExited,
    this.onDragDone,
    this.onOpenFullscreen,
    this.onExitFullscreen,
    this.onCloseReading,
    this.onSaveReading,
    this.initialPageNumber,
    this.focusAnnotationId,
    this.onNavigationConsumed,
    super.key,
  });

  final PdfLibraryDocument document;
  final ResearchLifeController controller;
  final bool fullscreen;
  final bool trackReadingTime;
  final int? initialPageNumber;
  final String? focusAnnotationId;
  final VoidCallback? onNavigationConsumed;
  final List<PdfLibraryDocument>? documents;
  final String? selectedDocumentId;
  final bool dragging;
  final int Function(String documentId)? annotationCountFor;
  final ValueChanged<PdfLibraryDocument>? onSelectDocument;
  final ValueChanged<PdfLibraryDocument>? onDeleteDocument;
  final VoidCallback? onDragEntered;
  final VoidCallback? onDragExited;
  final ValueChanged<String>? onDragDone;
  final VoidCallback? onOpenFullscreen;
  final VoidCallback? onExitFullscreen;
  final VoidCallback? onCloseReading;
  final VoidCallback? onSaveReading;

  @override
  State<_PdfReader> createState() => _PdfReaderState();
}

class _PdfReaderState extends State<_PdfReader> {
  static const _highlightColorValue = 0xFFFFD54F;
  static const _underlineColorValue = 0xFF2F6B4B;
  static const _strikethroughColorValue = 0xFFB4443F;
  static const _wavyColorValue = 0xFF256AA6;
  static const _noteColorValue = 0xFFFFB74D;
  static const _highlightColorOptions = [
    _AnnotationColorOption('黄', 0xFFFFD54F),
    _AnnotationColorOption('绿', 0xFF9CCC65),
    _AnnotationColorOption('蓝', 0xFF64B5F6),
    _AnnotationColorOption('粉', 0xFFF48FB1),
  ];

  final PdfViewerController _pdfController = PdfViewerController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  PdfTextSearcher? _textSearcher;
  late final DateTime _readingStartedAt;
  late final int _initialPageNumber;
  int? _pageCount;
  int _currentPageNumber = 1;
  int _selectedHighlightColorValue = _highlightColorValue;
  late _ReaderSideTab _sideTab;
  bool _sideRailCollapsed = false;
  bool _hasActiveTextSelection = false;
  bool _searchVisible = false;
  bool _readingSessionRecorded = false;
  PdfTextAnnotation? _hoveredNote;
  Offset? _hoverTooltipPosition;

  bool get _hasLibraryTab => widget.documents != null;

  @override
  void initState() {
    super.initState();
    _sideTab = _hasLibraryTab
        ? _ReaderSideTab.library
        : _ReaderSideTab.thumbnails;
    _readingStartedAt = DateTime.now();
    final requestedPage = widget.initialPageNumber;
    _initialPageNumber = requestedPage != null && requestedPage > 0
        ? requestedPage
        : widget.document.lastPage < 1
        ? 1
        : widget.document.lastPage;
    _currentPageNumber = _initialPageNumber;
    _pageCount = widget.document.pageCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.markPdfDocumentOpened(widget.document.id);
      unawaited(_loadReaderPreferences());
      unawaited(_focusPendingAnnotation());
      widget.onNavigationConsumed?.call();
    });
  }

  @override
  void didUpdateWidget(covariant _PdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasLibraryTab && _sideTab == _ReaderSideTab.library) {
      _sideTab = _ReaderSideTab.thumbnails;
    }
  }

  @override
  void dispose() {
    _recordReadingSession();
    _textSearcher?.removeListener(_onTextSearchChanged);
    _textSearcher?.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (!File(widget.document.path).existsSync()) {
      return EmptyState(
        title: '找不到 PDF 文件',
        description: widget.document.path,
        icon: Icons.file_present_rounded,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(
        widget.fullscreen ? tokens.radiusMedium : tokens.radiusLarge,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.panelSurface,
          border: Border.all(color: tokens.borderFaint),
          boxShadow: widget.fullscreen ? tokens.shadowSm : const [],
        ),
        child: Column(
          children: [
            _ReaderToolbar(
              document: widget.document,
              currentPageNumber: _currentPageNumber,
              pageCount: _pageCount,
              bookmarked: widget.controller.pdfPageBookmarked(
                widget.document.id,
                _currentPageNumber,
              ),
              fullscreen: widget.fullscreen,
              sideRailCollapsed: _sideRailCollapsed,
              onToggleSideRail: _toggleSideRail,
              onOpenFullscreen: widget.onOpenFullscreen,
              onExitFullscreen: widget.onExitFullscreen,
              onCloseReading: widget.onCloseReading,
              onSaveReading: widget.onSaveReading,
              onToggleBookmark: _toggleBookmark,
              onPageSubmitted: _goToPage,
              onPreviousPage: _previousPage,
              onNextPage: _nextPage,
              onZoomOut: _zoomOut,
              onZoomIn: _zoomIn,
              onFitWidth: _fitWidth,
              onFitPage: _fitPage,
              searchVisible: _searchVisible,
              searchController: _searchController,
              searchFocusNode: _searchFocusNode,
              searchMatchCount: _textSearcher?.matches.length ?? 0,
              currentSearchIndex: _textSearcher?.currentIndex,
              searchBusy: _textSearcher?.isSearching ?? false,
              searchProgress: _textSearcher?.searchProgress,
              onOpenSearch: _openSearch,
              onCloseSearch: _closeSearch,
              onSearchChanged: _searchText,
              onSearchSubmitted: _submitSearch,
              onSearchPrevious: _textSearcher?.matches.isNotEmpty == true
                  ? () => unawaited(_goToPreviousSearchMatch())
                  : null,
              onSearchNext: _textSearcher?.matches.isNotEmpty == true
                  ? () => unawaited(_goToNextSearchMatch())
                  : null,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showSideRail =
                      !_sideRailCollapsed &&
                      constraints.maxWidth >= (widget.fullscreen ? 900 : 760);
                  return Row(
                    children: [
                      if (showSideRail)
                        _ReaderSideRail(
                          document: widget.document,
                          controller: widget.controller,
                          documents: widget.documents,
                          selectedDocumentId: widget.selectedDocumentId,
                          dragging: widget.dragging,
                          annotationCountFor: widget.annotationCountFor,
                          pageCount: _pageCount,
                          currentPageNumber: _currentPageNumber,
                          selectedTab: _sideTab,
                          onTabSelected: _setSideTab,
                          onSelectDocument: widget.onSelectDocument,
                          onDeleteDocument: widget.onDeleteDocument,
                          onDragEntered: widget.onDragEntered,
                          onDragExited: widget.onDragExited,
                          onDragDone: widget.onDragDone,
                          onPageSelected: _goToPage,
                          onAnnotationsChanged: _refreshAnnotationPaint,
                          hasActiveTextSelection: _hasActiveTextSelection,
                          selectedHighlightColorValue:
                              _selectedHighlightColorValue,
                          highlightColorOptions: _highlightColorOptions,
                          onHighlightColorChanged: _setHighlightColorValue,
                          onHighlightSelection: () => unawaited(
                            _createAnnotationFromCurrentSelection(
                              PdfAnnotationKind.highlight,
                            ),
                          ),
                          onUnderlineSelection: () => unawaited(
                            _createAnnotationFromCurrentSelection(
                              PdfAnnotationKind.underline,
                            ),
                          ),
                          onStrikethroughSelection: () => unawaited(
                            _createAnnotationFromCurrentSelection(
                              PdfAnnotationKind.strikethrough,
                            ),
                          ),
                          onWavyUnderlineSelection: () => unawaited(
                            _createAnnotationFromCurrentSelection(
                              PdfAnnotationKind.wavyUnderline,
                            ),
                          ),
                          onCopySelection: () =>
                              unawaited(_copyCurrentSelection()),
                          onNoteSelection: () => unawaited(
                            _createAnnotationFromCurrentSelection(
                              PdfAnnotationKind.note,
                            ),
                          ),
                        ),
                      Expanded(child: _buildViewer(context)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer(BuildContext context) {
    final tokens = context.tokens;
    return PdfViewer.file(
      widget.document.path,
      key: ValueKey(widget.document.path),
      controller: _pdfController,
      initialPageNumber: _initialPageNumber,
      params: PdfViewerParams(
        backgroundColor: tokens.panelSubtle,
        margin: widget.fullscreen ? 16 : 12,
        maxScale: 6,
        useAlternativeFitScaleAsMinScale: false,
        pageDropShadow: BoxShadow(
          color: Colors.black.withValues(alpha: 0.16),
          blurRadius: 14,
          offset: const Offset(0, 8),
        ),
        matchTextColor: _searchMatchColor,
        activeMatchTextColor: _searchActiveMatchColor,
        textSelectionParams: PdfTextSelectionParams(
          showContextMenuAutomatically: true,
          onTextSelectionChange: (selection) {
            if (!mounted ||
                _hasActiveTextSelection == selection.hasSelectedText) {
              return;
            }
            setState(() => _hasActiveTextSelection = selection.hasSelectedText);
          },
        ),
        pagePaintCallbacks: [
          if (_textSearcher != null) _textSearcher!.pageTextMatchPaintCallback,
          _paintAnnotations,
        ],
        viewerOverlayBuilder: _buildViewerOverlaysWithNotes,
        onViewerReady: (document, controller) {
          _ensureTextSearcher();
          final pageCount = document.pages.length;
          if (mounted) {
            setState(() => _pageCount = pageCount);
          }
          widget.controller.updatePdfReadingPosition(
            widget.document.id,
            pageCount: pageCount,
          );
        },
        onPageChanged: (pageNumber) {
          if (pageNumber == null) {
            return;
          }
          if (mounted) {
            setState(() => _currentPageNumber = pageNumber);
          }
          widget.controller.updatePdfReadingPosition(
            widget.document.id,
            pageNumber: pageNumber,
          );
        },
        buildContextMenu: _buildSelectionContextMenu,
      ),
    );
  }

  Widget? _buildSelectionContextMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    if (!params.textSelectionDelegate.hasSelectedText) {
      return null;
    }

    // Let pdfrx measure and position this custom toolbar. Wrapping it in
    // AdaptiveTextSelectionToolbar on desktop forces Flutter's narrow native
    // context-menu width, which clips the wider annotation controls.
    return _buildSelectionToolbar(
      onHighlight: () =>
          unawaited(_createAnnotation(params, PdfAnnotationKind.highlight)),
      onUnderline: () =>
          unawaited(_createAnnotation(params, PdfAnnotationKind.underline)),
      onStrikethrough: () =>
          unawaited(_createAnnotation(params, PdfAnnotationKind.strikethrough)),
      onWavyUnderline: () =>
          unawaited(_createAnnotation(params, PdfAnnotationKind.wavyUnderline)),
      onCopy: params.textSelectionDelegate.isCopyAllowed
          ? () => unawaited(_copySelection(params))
          : null,
      onNote: () =>
          unawaited(_createAnnotation(params, PdfAnnotationKind.note)),
    );
  }

  List<Widget> _buildViewerOverlaysWithNotes(
    BuildContext context,
    Size size,
    PdfViewerHandleLinkTap handleLinkTap,
  ) {
    final overlays = <Widget>[
      Positioned.fill(
        child: Listener(
          onPointerHover: _handleViewerHover,
          behavior: HitTestBehavior.translucent,
          child: const SizedBox.expand(),
        ),
      ),
    ];

    if (_hoveredNote != null && _hoverTooltipPosition != null) {
      overlays.add(
        Positioned(
          left: (_hoverTooltipPosition!.dx + 12).clamp(8.0, size.width - 280),
          top: (_hoverTooltipPosition!.dy - 8).clamp(8.0, size.height - 120),
          width: 260,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.inverseSurface,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                _hoveredNote!.note ?? '',
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_hasActiveTextSelection) {
      overlays.add(
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: Center(
              child: _buildSelectionToolbar(
                onHighlight: () => unawaited(
                  _createAnnotationFromCurrentSelection(
                    PdfAnnotationKind.highlight,
                  ),
                ),
                onUnderline: () => unawaited(
                  _createAnnotationFromCurrentSelection(
                    PdfAnnotationKind.underline,
                  ),
                ),
                onStrikethrough: () => unawaited(
                  _createAnnotationFromCurrentSelection(
                    PdfAnnotationKind.strikethrough,
                  ),
                ),
                onWavyUnderline: () => unawaited(
                  _createAnnotationFromCurrentSelection(
                    PdfAnnotationKind.wavyUnderline,
                  ),
                ),
                onCopy: () => unawaited(_copyCurrentSelection()),
                onNote: () => unawaited(
                  _createAnnotationFromCurrentSelection(PdfAnnotationKind.note),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return overlays;
  }

  void _handleViewerHover(PointerHoverEvent event) {
    if (!_pdfController.isReady) {
      return;
    }
    final hit = _pdfController.getPdfPageHitTestResult(
      event.localPosition,
      useDocumentLayoutCoordinates: false,
    );
    if (hit == null) {
      if (_hoveredNote != null && mounted) {
        setState(() {
          _hoveredNote = null;
          _hoverTooltipPosition = null;
        });
      }
      return;
    }

    final pageNumber = hit.page.pageNumber;
    final pagePoint = hit.offset;
    PdfTextAnnotation? matched;
    for (final annotation in widget.controller.pdfAnnotationsFor(
      widget.document.id,
    )) {
      if (annotation.kind != PdfAnnotationKind.note ||
          annotation.pageNumber != pageNumber ||
          annotation.note?.trim().isEmpty != false) {
        continue;
      }
      for (final rect in annotation.rects) {
        if (pagePoint.x >= rect.left &&
            pagePoint.x <= rect.right &&
            pagePoint.y <= rect.top &&
            pagePoint.y >= rect.bottom) {
          matched = annotation;
          break;
        }
      }
      if (matched != null) {
        break;
      }
    }

    if (!mounted) {
      return;
    }
    if (matched?.id == _hoveredNote?.id &&
        _hoverTooltipPosition == event.localPosition) {
      return;
    }
    setState(() {
      _hoveredNote = matched;
      _hoverTooltipPosition = matched == null ? null : event.localPosition;
    });
  }

  Widget _buildSelectionToolbar({
    required VoidCallback onHighlight,
    required VoidCallback onUnderline,
    required VoidCallback onStrikethrough,
    required VoidCallback onWavyUnderline,
    required VoidCallback? onCopy,
    required VoidCallback onNote,
  }) {
    return _SelectionToolbar(
      highlightColorValue: _selectedHighlightColorValue,
      highlightColorOptions: _highlightColorOptions,
      onHighlightColorChanged: _setHighlightColorValue,
      onHighlight: onHighlight,
      onUnderline: onUnderline,
      onStrikethrough: onStrikethrough,
      onWavyUnderline: onWavyUnderline,
      onCopy: onCopy,
      onNote: onNote,
    );
  }

  Future<void> _loadReaderPreferences() async {
    await widget.controller.ensurePdfReaderPreferencesLoaded();
    if (!mounted) {
      return;
    }
    final preferences = widget.controller.pdfReaderPreferences;
    setState(() {
      _sideRailCollapsed = preferences.sideRailCollapsed;
      _sideTab = _sideTabFromPreference(preferences.sideTab);
      _selectedHighlightColorValue = preferences.highlightColorValue;
    });
  }

  void _toggleSideRail() {
    _setSideRailCollapsed(!_sideRailCollapsed);
  }

  void _setSideRailCollapsed(bool value) {
    if (_sideRailCollapsed == value) {
      return;
    }
    setState(() => _sideRailCollapsed = value);
    _persistReaderPreferences(sideRailCollapsed: value);
  }

  void _setSideTab(_ReaderSideTab tab) {
    final resolvedTab = _normalizeSideTab(tab);
    if (_sideTab == resolvedTab) {
      return;
    }
    setState(() => _sideTab = resolvedTab);
    _persistReaderPreferences(sideTab: resolvedTab);
  }

  void _setHighlightColorValue(int colorValue) {
    if (_selectedHighlightColorValue == colorValue) {
      return;
    }
    setState(() => _selectedHighlightColorValue = colorValue);
    _persistReaderPreferences(highlightColorValue: colorValue);
  }

  void _persistReaderPreferences({
    bool? sideRailCollapsed,
    _ReaderSideTab? sideTab,
    int? highlightColorValue,
  }) {
    final current = widget.controller.pdfReaderPreferences;
    final next = current.copyWith(
      sideRailCollapsed: sideRailCollapsed,
      sideTab: sideTab == null ? null : _preferenceValueForSideTab(sideTab),
      highlightColorValue: highlightColorValue,
    );
    unawaited(widget.controller.savePdfReaderPreferences(next));
  }

  _ReaderSideTab _sideTabFromPreference(String value) {
    return _normalizeSideTab(switch (value) {
      'annotations' => _ReaderSideTab.annotations,
      'thumbnails' => _ReaderSideTab.thumbnails,
      _ => _ReaderSideTab.library,
    });
  }

  _ReaderSideTab _normalizeSideTab(_ReaderSideTab tab) {
    if (!_hasLibraryTab && tab == _ReaderSideTab.library) {
      return _ReaderSideTab.thumbnails;
    }
    return tab;
  }

  String _preferenceValueForSideTab(_ReaderSideTab tab) {
    return switch (tab) {
      _ReaderSideTab.library => 'library',
      _ReaderSideTab.thumbnails => 'thumbnails',
      _ReaderSideTab.annotations => 'annotations',
    };
  }

  Future<void> _copySelection(PdfViewerContextMenuBuilderParams params) async {
    params.dismissContextMenu();
    await _copySelectionFromDelegate(params.textSelectionDelegate);
  }

  Future<void> _copyCurrentSelection() async {
    final delegate = _selectionDelegateOrNull();
    if (delegate == null) {
      _showSelectionRequiredMessage();
      return;
    }
    await _copySelectionFromDelegate(delegate);
  }

  Future<void> _copySelectionFromDelegate(
    PdfTextSelectionDelegate delegate,
  ) async {
    if (!delegate.hasSelectedText) {
      _showSelectionRequiredMessage();
      return;
    }
    if (!delegate.isCopyAllowed) {
      _showReaderMessage('当前 PDF 不允许复制选中文本。');
      return;
    }
    await delegate.copyTextSelection();
    await delegate.clearTextSelection();
    _setHasActiveTextSelection(false);
  }

  Future<void> _createAnnotation(
    PdfViewerContextMenuBuilderParams params,
    PdfAnnotationKind kind,
  ) async {
    await _createAnnotationFromDelegate(
      params.textSelectionDelegate,
      kind,
      dismissContextMenu: params.dismissContextMenu,
    );
  }

  Future<void> _createAnnotationFromCurrentSelection(
    PdfAnnotationKind kind,
  ) async {
    final delegate = _selectionDelegateOrNull();
    if (delegate == null) {
      _showSelectionRequiredMessage();
      return;
    }
    await _createAnnotationFromDelegate(delegate, kind);
  }

  Future<void> _createAnnotationFromDelegate(
    PdfTextSelectionDelegate delegate,
    PdfAnnotationKind kind, {
    VoidCallback? dismissContextMenu,
  }) async {
    if (!delegate.hasSelectedText) {
      _showSelectionRequiredMessage();
      return;
    }

    final selection = await _captureSelection(delegate);
    dismissContextMenu?.call();
    if (selection == null) {
      _showReaderMessage('没有识别到可标注的选区。');
      return;
    }

    String? note;
    PdfAnnotationContentType contentType = PdfAnnotationContentType.text;
    String? latexContent;
    if (kind == PdfAnnotationKind.note) {
      if (!mounted) {
        return;
      }
      final draft = await showReadingNoteDialog(
        context: context,
        selectedText: selection.selectedText,
      );
      if (draft == null || draft.reflection.trim().isEmpty) {
        return;
      }
      note = draft.reflection;
      contentType = draft.contentType;
      latexContent = draft.latexContent;
    }

    for (final entry in selection.rectsByPage.entries) {
      final pageText = selection.textByPage[entry.key]?.join(' ').trim();
      final annotationText = pageText != null && pageText.isNotEmpty
          ? pageText
          : selection.selectedText;
      await widget.controller.addPdfAnnotation(
        documentId: widget.document.id,
        pageNumber: entry.key,
        kind: kind,
        selectedText: annotationText,
        rects: entry.value,
        colorValue: _colorValueForKind(kind),
        opacity: _opacityForKind(kind),
        note: note,
        contentType: contentType,
        latexContent: latexContent,
      );
    }

    await delegate.clearTextSelection();
    _setHasActiveTextSelection(false);
    if (_pdfController.isReady) {
      _pdfController.forceRepaintAllPageImages();
    }
  }

  PdfTextSelectionDelegate? _selectionDelegateOrNull() {
    if (!_pdfController.isReady) {
      return null;
    }
    try {
      final delegate = _pdfController.textSelectionDelegate;
      return delegate.hasSelectedText ? delegate : null;
    } on Object {
      return null;
    }
  }

  void _setHasActiveTextSelection(bool hasSelection) {
    if (!mounted || _hasActiveTextSelection == hasSelection) {
      return;
    }
    setState(() => _hasActiveTextSelection = hasSelection);
  }

  void _showSelectionRequiredMessage() {
    _showReaderMessage('请先选中文字，再使用标注工具。');
  }

  void _showReaderMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<_SelectionSnapshot?> _captureSelection(
    PdfTextSelectionDelegate delegate,
  ) async {
    try {
      final selectedText = (await delegate.getSelectedText()).trim();
      final ranges = await delegate.getSelectedTextRanges();
      final rectsByPage = <int, List<PdfAnnotationRect>>{};
      final textByPage = <int, List<String>>{};

      for (final range in ranges) {
        final pageRects = rectsByPage.putIfAbsent(range.pageNumber, () => []);
        for (final fragmentRect in range.enumerateFragmentBoundingRects()) {
          final bounds = fragmentRect.bounds;
          pageRects.add(
            PdfAnnotationRect(
              left: bounds.left,
              top: bounds.top,
              right: bounds.right,
              bottom: bounds.bottom,
            ),
          );
        }

        final text = range.text.trim();
        if (text.isNotEmpty) {
          textByPage.putIfAbsent(range.pageNumber, () => []).add(text);
        }
      }

      if (rectsByPage.isEmpty) {
        return null;
      }
      return _SelectionSnapshot(
        selectedText: selectedText,
        rectsByPage: rectsByPage,
        textByPage: textByPage,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _focusPendingAnnotation() async {
    final annotationId = widget.focusAnnotationId;
    if (annotationId == null) {
      return;
    }
    final annotation = widget.controller.pdfAnnotationById(
      widget.document.id,
      annotationId,
    );
    if (annotation == null || !_pdfController.isReady) {
      return;
    }
    await _pdfController.goToPage(pageNumber: annotation.pageNumber);
    if (annotation.rects.isNotEmpty) {
      final rect = annotation.rects.first;
      final pdfRect = PdfRect(rect.left, rect.top, rect.right, rect.bottom);
      await _pdfController.goToRectInsidePage(
        pageNumber: annotation.pageNumber,
        rect: pdfRect,
      );
    }
    if (mounted) {
      setState(() => _currentPageNumber = annotation.pageNumber);
    }
  }

  void _paintAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    final pageAnnotations = widget.controller
        .pdfAnnotationsFor(widget.document.id)
        .where((annotation) => annotation.pageNumber == page.pageNumber);

    for (final annotation in pageAnnotations) {
      final color = Color(
        annotation.colorValue,
      ).withValues(alpha: annotation.opacity);
      for (final rect in annotation.rects) {
        final pageBounds = PdfRect(
          rect.left,
          rect.top,
          rect.right,
          rect.bottom,
        ).toRectInDocument(page: page, pageRect: pageRect);

        switch (annotation.kind) {
          case PdfAnnotationKind.highlight:
            _paintHighlight(canvas, pageBounds, color);
          case PdfAnnotationKind.underline:
            _paintLine(canvas, pageBounds, color, _LinePlacement.underline);
          case PdfAnnotationKind.strikethrough:
            _paintLine(canvas, pageBounds, color, _LinePlacement.strikethrough);
          case PdfAnnotationKind.wavyUnderline:
            _paintWavyUnderline(canvas, pageBounds, color);
          case PdfAnnotationKind.note:
            _paintNoteMarker(canvas, pageBounds, color);
          case PdfAnnotationKind.bookmark:
            _paintBookmark(canvas, pageBounds, color);
        }
      }
    }
  }

  void _paintHighlight(Canvas canvas, Rect bounds, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.multiply;
    canvas.drawRect(bounds.inflate(1), paint);
  }

  void _paintNoteMarker(Canvas canvas, Rect bounds, Color color) {
    final underlinePaint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.multiply;
    canvas.drawRect(bounds.inflate(1), underlinePaint);

    final radius = math.min(7.0, bounds.height * 0.35).clamp(4.0, 8.0);
    final center = Offset(
      bounds.right - radius * 0.4,
      bounds.top + radius * 0.6,
    );
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, radius, fillPaint);
    canvas.drawCircle(center, radius, ringPaint);
  }

  void _paintBookmark(Canvas canvas, Rect bounds, Color color) {
    final width = math.max(bounds.width, 16.0);
    final height = math.max(bounds.height, 28.0);
    final left = bounds.left + 4;
    final top = bounds.top + 4;
    final path = Path()
      ..moveTo(left, top)
      ..lineTo(left + width, top)
      ..lineTo(left + width, top + height)
      ..lineTo(left + width / 2, top + height - 7)
      ..lineTo(left, top + height)
      ..close();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  void _paintLine(
    Canvas canvas,
    Rect bounds,
    Color color,
    _LinePlacement placement,
  ) {
    final strokeWidth = (bounds.height * 0.08).clamp(1.2, 3.0).toDouble();
    final dy = switch (placement) {
      _LinePlacement.underline => bounds.bottom - bounds.height * 0.12,
      _LinePlacement.strikethrough => bounds.top + bounds.height * 0.52,
    };
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    canvas.drawLine(Offset(bounds.left, dy), Offset(bounds.right, dy), paint);
  }

  void _paintWavyUnderline(Canvas canvas, Rect bounds, Color color) {
    final strokeWidth = (bounds.height * 0.07).clamp(1.1, 2.6).toDouble();
    final amplitude = (bounds.height * 0.08).clamp(1.2, 3.0).toDouble();
    final waveLength = (bounds.height * 0.45).clamp(6.0, 12.0).toDouble();
    final baseline = bounds.bottom - bounds.height * 0.12;
    final path = Path()..moveTo(bounds.left, baseline);
    var x = bounds.left;
    while (x < bounds.right) {
      path.relativeQuadraticBezierTo(
        waveLength / 4,
        -amplitude,
        waveLength / 2,
        0,
      );
      path.relativeQuadraticBezierTo(
        waveLength / 4,
        amplitude,
        waveLength / 2,
        0,
      );
      x += waveLength;
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    canvas.drawPath(path, paint);
  }

  int _colorValueForKind(PdfAnnotationKind kind) {
    return switch (kind) {
      PdfAnnotationKind.bookmark => _noteColorValue,
      PdfAnnotationKind.highlight => _selectedHighlightColorValue,
      PdfAnnotationKind.underline => _underlineColorValue,
      PdfAnnotationKind.strikethrough => _strikethroughColorValue,
      PdfAnnotationKind.wavyUnderline => _wavyColorValue,
      PdfAnnotationKind.note => _noteColorValue,
    };
  }

  double _opacityForKind(PdfAnnotationKind kind) {
    return switch (kind) {
      PdfAnnotationKind.bookmark => 0.92,
      PdfAnnotationKind.highlight => 0.42,
      PdfAnnotationKind.underline => 0.96,
      PdfAnnotationKind.strikethrough => 0.92,
      PdfAnnotationKind.wavyUnderline => 0.94,
      PdfAnnotationKind.note => 0.72,
    };
  }

  void _previousPage() {
    _goToPage(_currentPageNumber - 1);
  }

  void _nextPage() {
    _goToPage(_currentPageNumber + 1);
  }

  void _goToPage(int pageNumber) {
    if (!_pdfController.isReady) {
      return;
    }
    final count = _pageCount ?? _pdfController.pageCount;
    final clampedPageNumber = pageNumber.clamp(1, count).toInt();
    unawaited(
      _pdfController.goToPage(
        pageNumber: clampedPageNumber,
        anchor: PdfPageAnchor.top,
      ),
    );
  }

  void _zoomIn() {
    if (_pdfController.isReady) {
      unawaited(_pdfController.zoomUp());
    }
  }

  void _zoomOut() {
    if (_pdfController.isReady) {
      unawaited(_pdfController.zoomDown());
    }
  }

  void _fitWidth() {
    if (!_pdfController.isReady) {
      return;
    }
    final matrix = _pdfController.calcMatrixFitWidthForPage(
      pageNumber: _currentPageNumber,
    );
    unawaited(_pdfController.goTo(matrix));
  }

  void _fitPage() {
    if (!_pdfController.isReady) {
      return;
    }
    final matrix = _pdfController.calcMatrixForFit(
      pageNumber: _currentPageNumber,
    );
    unawaited(_pdfController.goTo(matrix));
  }

  void _refreshAnnotationPaint() {
    if (_pdfController.isReady) {
      _pdfController.forceRepaintAllPageImages();
    }
  }

  void _ensureTextSearcher() {
    if (_textSearcher != null || !_pdfController.isReady) {
      return;
    }
    _textSearcher = PdfTextSearcher(_pdfController)
      ..addListener(_onTextSearchChanged);
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _textSearcher!.startTextSearch(query, searchImmediately: true);
    }
  }

  void _onTextSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _openSearch() {
    setState(() => _searchVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _textSearcher?.resetTextSearch();
    _searchFocusNode.unfocus();
    setState(() => _searchVisible = false);
  }

  void _searchText(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      _textSearcher?.resetTextSearch();
      return;
    }
    _ensureTextSearcher();
    _textSearcher?.startTextSearch(query);
  }

  void _submitSearch(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      _textSearcher?.resetTextSearch();
      return;
    }
    _ensureTextSearcher();
    final textSearcher = _textSearcher;
    if (textSearcher == null) {
      return;
    }
    if (textSearcher.pattern == query && textSearcher.matches.isNotEmpty) {
      unawaited(_goToNextSearchMatch());
      return;
    }
    textSearcher.startTextSearch(query, searchImmediately: true);
  }

  Future<void> _goToNextSearchMatch() async {
    final textSearcher = _textSearcher;
    if (textSearcher == null) {
      return;
    }
    if (textSearcher.matches.isEmpty) {
      _submitSearch(_searchController.text);
      return;
    }
    final index = await textSearcher.goToNextMatch();
    if (index < 0 && textSearcher.matches.isNotEmpty) {
      await textSearcher.goToMatchOfIndex(0);
    }
  }

  Future<void> _goToPreviousSearchMatch() async {
    final textSearcher = _textSearcher;
    if (textSearcher == null) {
      return;
    }
    if (textSearcher.matches.isEmpty) {
      _submitSearch(_searchController.text);
      return;
    }
    final index = await textSearcher.goToPrevMatch();
    if (index < 0 && textSearcher.matches.isNotEmpty) {
      await textSearcher.goToMatchOfIndex(textSearcher.matches.length - 1);
    }
  }

  void _toggleBookmark() {
    unawaited(_toggleBookmarkAndRefresh());
  }

  Future<void> _toggleBookmarkAndRefresh() async {
    await widget.controller.togglePdfPageBookmark(
      documentId: widget.document.id,
      pageNumber: _currentPageNumber,
    );
    if (mounted) {
      setState(() {});
    }
    if (_pdfController.isReady) {
      _pdfController.forceRepaintAllPageImages();
    }
  }

  void _recordReadingSession() {
    if (!widget.trackReadingTime || _readingSessionRecorded) {
      return;
    }
    _readingSessionRecorded = true;
    unawaited(
      widget.controller.recordPdfReadingSession(
        documentId: widget.document.id,
        startedAt: _readingStartedAt,
        endedAt: DateTime.now(),
      ),
    );
  }
}

class _ReaderToolbar extends StatelessWidget {
  const _ReaderToolbar({
    required this.document,
    required this.currentPageNumber,
    required this.pageCount,
    required this.bookmarked,
    required this.fullscreen,
    required this.sideRailCollapsed,
    required this.onToggleSideRail,
    required this.onToggleBookmark,
    required this.onPageSubmitted,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFitWidth,
    required this.onFitPage,
    required this.searchVisible,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchMatchCount,
    required this.currentSearchIndex,
    required this.searchBusy,
    required this.searchProgress,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onSearchPrevious,
    required this.onSearchNext,
    this.onOpenFullscreen,
    this.onExitFullscreen,
    this.onCloseReading,
    this.onSaveReading,
  });

  final PdfLibraryDocument document;
  final int currentPageNumber;
  final int? pageCount;
  final bool bookmarked;
  final bool fullscreen;
  final bool sideRailCollapsed;
  final VoidCallback onToggleSideRail;
  final VoidCallback onToggleBookmark;
  final ValueChanged<int> onPageSubmitted;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFitWidth;
  final VoidCallback onFitPage;
  final bool searchVisible;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final int searchMatchCount;
  final int? currentSearchIndex;
  final bool searchBusy;
  final double? searchProgress;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback? onSearchPrevious;
  final VoidCallback? onSearchNext;
  final VoidCallback? onOpenFullscreen;
  final VoidCallback? onExitFullscreen;
  final VoidCallback? onCloseReading;
  final VoidCallback? onSaveReading;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final totalPageLabel = pageCount == null ? '-' : '$pageCount';

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        border: Border(bottom: BorderSide(color: tokens.borderFaint)),
      ),
      child: Row(
        children: [
          _ToolbarIconButton(
            tooltip: sideRailCollapsed ? '展开侧栏' : '收起侧栏',
            icon: Icons.view_sidebar_rounded,
            onPressed: onToggleSideRail,
          ),
          const SizedBox(width: 8),
          Icon(Icons.menu_book_rounded, color: tokens.accent),
          const SizedBox(width: 12),
          Expanded(
            child: searchVisible
                ? _PdfSearchField(
                    controller: searchController,
                    focusNode: searchFocusNode,
                    matchCount: searchMatchCount,
                    currentIndex: currentSearchIndex,
                    busy: searchBusy,
                    progress: searchProgress,
                    onChanged: onSearchChanged,
                    onSubmitted: onSearchSubmitted,
                    onPrevious: onSearchPrevious,
                    onNext: onSearchNext,
                    onClose: onCloseSearch,
                  )
                : Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          if (!searchVisible) ...[
            const SizedBox(width: 8),
            _ToolbarIconButton(
              tooltip: '搜索',
              icon: Icons.search_rounded,
              onPressed: onOpenSearch,
            ),
          ],
          _PageJumpField(
            pageNumber: currentPageNumber,
            pageCount: pageCount,
            onSubmitted: onPageSubmitted,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '/ $totalPageLabel',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: tokens.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          _ToolbarIconButton(
            tooltip: bookmarked ? '取消书签' : '添加书签',
            icon: bookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            onPressed: onToggleBookmark,
          ),
          _ToolbarIconButton(
            tooltip: '上一页',
            icon: Icons.keyboard_arrow_up_rounded,
            onPressed: onPreviousPage,
          ),
          _ToolbarIconButton(
            tooltip: '下一页',
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: onNextPage,
          ),
          _ToolbarIconButton(
            tooltip: '缩小',
            icon: Icons.zoom_out_rounded,
            onPressed: onZoomOut,
          ),
          _ToolbarIconButton(
            tooltip: '放大',
            icon: Icons.zoom_in_rounded,
            onPressed: onZoomIn,
          ),
          _ToolbarIconButton(
            tooltip: '适应宽度',
            icon: Icons.swap_horiz_rounded,
            onPressed: onFitWidth,
          ),
          _ToolbarIconButton(
            tooltip: '适应整页',
            icon: Icons.fit_screen_rounded,
            onPressed: onFitPage,
          ),
          _ToolbarIconButton(
            tooltip: fullscreen ? '退出全屏' : '全屏阅读',
            icon: fullscreen
                ? Icons.close_fullscreen_rounded
                : Icons.open_in_full_rounded,
            onPressed: fullscreen ? onExitFullscreen : onOpenFullscreen,
          ),
          if (onSaveReading != null)
            _ToolbarIconButton(
              tooltip: '保存到云端',
              icon: Icons.cloud_upload_outlined,
              onPressed: onSaveReading,
            ),
          if (onCloseReading != null)
            _ToolbarIconButton(
              tooltip: '关闭阅读',
              icon: Icons.close_rounded,
              onPressed: onCloseReading,
            ),
        ],
      ),
    );
  }
}

class _PdfSearchField extends StatelessWidget {
  const _PdfSearchField({
    required this.controller,
    required this.focusNode,
    required this.matchCount,
    required this.currentIndex,
    required this.busy,
    required this.progress,
    required this.onChanged,
    required this.onSubmitted,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int matchCount;
  final int? currentIndex;
  final bool busy;
  final double? progress;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.insetSurface,
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
          border: Border.all(color: tokens.borderFaint),
        ),
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 8),
              Icon(Icons.search_rounded, color: tokens.textSecondary, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    hintText: '搜索 PDF',
                  ),
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => _SearchStatusBadge(
                  query: value.text,
                  matchCount: matchCount,
                  currentIndex: currentIndex,
                  busy: busy,
                  progress: progress,
                ),
              ),
              _ToolbarIconButton(
                tooltip: '上一个结果',
                icon: Icons.keyboard_arrow_up_rounded,
                onPressed: onPrevious,
              ),
              _ToolbarIconButton(
                tooltip: '下一个结果',
                icon: Icons.keyboard_arrow_down_rounded,
                onPressed: onNext,
              ),
              _ToolbarIconButton(
                tooltip: '关闭搜索',
                icon: Icons.close_rounded,
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchStatusBadge extends StatelessWidget {
  const _SearchStatusBadge({
    required this.query,
    required this.matchCount,
    required this.currentIndex,
    required this.busy,
    required this.progress,
  });

  final String query;
  final int matchCount;
  final int? currentIndex;
  final bool busy;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final trimmedQuery = query.trim();
    final label = _labelFor(trimmedQuery);

    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                value: progress?.clamp(0.0, 1.0).toDouble(),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }

  String _labelFor(String query) {
    if (query.isEmpty) {
      return '输入';
    }
    if (matchCount == 0) {
      return busy ? '搜索中' : '0/0';
    }
    final visibleIndex = ((currentIndex ?? 0) + 1).clamp(1, matchCount);
    return '$visibleIndex/$matchCount';
  }
}

class _PageJumpField extends StatefulWidget {
  const _PageJumpField({
    required this.pageNumber,
    required this.pageCount,
    required this.onSubmitted,
  });

  final int pageNumber;
  final int? pageCount;
  final ValueChanged<int> onSubmitted;

  @override
  State<_PageJumpField> createState() => _PageJumpFieldState();
}

class _PageJumpFieldState extends State<_PageJumpField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.pageNumber}');
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _PageJumpField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.pageNumber != widget.pageNumber) {
      _controller.text = '${widget.pageNumber}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: 64,
      height: 38,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.pageCount != null,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: Theme.of(context).textTheme.labelLarge,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          filled: true,
          fillColor: tokens.insetSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSmall),
          ),
        ),
        onSubmitted: _submit,
      ),
    );
  }

  void _submit(String value) {
    final pageNumber = int.tryParse(value.trim());
    if (pageNumber == null) {
      _controller.text = '${widget.pageNumber}';
      return;
    }
    widget.onSubmitted(pageNumber);
    _focusNode.unfocus();
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon));
  }
}

enum _ReaderSideTab { library, thumbnails, annotations }

class _ReaderSideRail extends StatelessWidget {
  const _ReaderSideRail({
    required this.document,
    required this.controller,
    required this.documents,
    required this.selectedDocumentId,
    required this.dragging,
    required this.annotationCountFor,
    required this.pageCount,
    required this.currentPageNumber,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onSelectDocument,
    required this.onDeleteDocument,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDragDone,
    required this.onPageSelected,
    required this.onAnnotationsChanged,
    required this.hasActiveTextSelection,
    required this.selectedHighlightColorValue,
    required this.highlightColorOptions,
    required this.onHighlightColorChanged,
    required this.onHighlightSelection,
    required this.onUnderlineSelection,
    required this.onStrikethroughSelection,
    required this.onWavyUnderlineSelection,
    required this.onCopySelection,
    required this.onNoteSelection,
  });

  final PdfLibraryDocument document;
  final ResearchLifeController controller;
  final List<PdfLibraryDocument>? documents;
  final String? selectedDocumentId;
  final bool dragging;
  final int Function(String documentId)? annotationCountFor;
  final int? pageCount;
  final int currentPageNumber;
  final _ReaderSideTab selectedTab;
  final ValueChanged<_ReaderSideTab> onTabSelected;
  final ValueChanged<PdfLibraryDocument>? onSelectDocument;
  final ValueChanged<PdfLibraryDocument>? onDeleteDocument;
  final VoidCallback? onDragEntered;
  final VoidCallback? onDragExited;
  final ValueChanged<String>? onDragDone;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onAnnotationsChanged;
  final bool hasActiveTextSelection;
  final int selectedHighlightColorValue;
  final List<_AnnotationColorOption> highlightColorOptions;
  final ValueChanged<int> onHighlightColorChanged;
  final VoidCallback onHighlightSelection;
  final VoidCallback onUnderlineSelection;
  final VoidCallback onStrikethroughSelection;
  final VoidCallback onWavyUnderlineSelection;
  final VoidCallback onCopySelection;
  final VoidCallback onNoteSelection;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final showLibraryTab = documents != null;
    final selected = showLibraryTab || selectedTab != _ReaderSideTab.library
        ? selectedTab
        : _ReaderSideTab.thumbnails;
    final segments = <ButtonSegment<_ReaderSideTab>>[
      if (showLibraryTab)
        const ButtonSegment(
          value: _ReaderSideTab.library,
          icon: Icon(Icons.folder_copy_rounded),
          label: Text('文库'),
        ),
      const ButtonSegment(
        value: _ReaderSideTab.thumbnails,
        icon: Icon(Icons.view_sidebar_rounded),
        label: Text('缩略图'),
      ),
      const ButtonSegment(
        value: _ReaderSideTab.annotations,
        icon: Icon(Icons.bookmark_border_rounded),
        label: Text('标注'),
      ),
    ];

    return Container(
      width: showLibraryTab ? 280 : 240,
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        border: Border(right: BorderSide(color: tokens.borderFaint)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<_ReaderSideTab>(
              showSelectedIcon: false,
              segments: segments,
              selected: {selected},
              onSelectionChanged: (selection) => onTabSelected(selection.first),
            ),
          ),
          Expanded(child: _buildSelectedTab(selected)),
        ],
      ),
    );
  }

  Widget _buildSelectedTab(_ReaderSideTab selected) {
    return switch (selected) {
      _ReaderSideTab.library => _DocumentLibraryPanel(
        documents: documents ?? const [],
        selectedDocumentId: selectedDocumentId,
        dragging: dragging,
        annotationCountFor: annotationCountFor ?? ((_) => 0),
        onSelect: onSelectDocument ?? (_) {},
        onDelete: onDeleteDocument ?? (_) {},
        onDragEntered: onDragEntered ?? () {},
        onDragExited: onDragExited ?? () {},
        onDragDone: onDragDone ?? (_) {},
      ),
      _ReaderSideTab.thumbnails => _ThumbnailList(
        document: document,
        currentPageNumber: currentPageNumber,
        fallbackPageCount: pageCount,
        onPageSelected: onPageSelected,
      ),
      _ReaderSideTab.annotations => _AnnotationList(
        document: document,
        controller: controller,
        currentPageNumber: currentPageNumber,
        onPageSelected: onPageSelected,
        onAnnotationsChanged: onAnnotationsChanged,
        hasActiveTextSelection: hasActiveTextSelection,
        selectedHighlightColorValue: selectedHighlightColorValue,
        highlightColorOptions: highlightColorOptions,
        onHighlightColorChanged: onHighlightColorChanged,
        onHighlightSelection: onHighlightSelection,
        onUnderlineSelection: onUnderlineSelection,
        onStrikethroughSelection: onStrikethroughSelection,
        onWavyUnderlineSelection: onWavyUnderlineSelection,
        onCopySelection: onCopySelection,
        onNoteSelection: onNoteSelection,
      ),
    };
  }
}

class _ThumbnailList extends StatelessWidget {
  const _ThumbnailList({
    required this.document,
    required this.currentPageNumber,
    required this.fallbackPageCount,
    required this.onPageSelected,
  });

  final PdfLibraryDocument document;
  final int currentPageNumber;
  final int? fallbackPageCount;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return PdfDocumentViewBuilder.file(
      document.path,
      builder: (context, pdfDocument) {
        final count = pdfDocument?.pages.length ?? fallbackPageCount ?? 0;
        if (count == 0) {
          return Center(
            child: Text(
              '正在生成缩略图',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          itemCount: count,
          itemBuilder: (context, index) {
            final pageNumber = index + 1;
            final selected = pageNumber == currentPageNumber;
            return _ThumbnailTile(
              pageNumber: pageNumber,
              selected: selected,
              onTap: () => onPageSelected(pageNumber),
              child: pdfDocument == null
                  ? const SizedBox.expand()
                  : PdfPageView(
                      document: pdfDocument,
                      pageNumber: pageNumber,
                      maximumDpi: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
            );
          },
        );
      },
    );
  }
}

class _ThumbnailTile extends StatelessWidget {
  const _ThumbnailTile({
    required this.pageNumber,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final int pageNumber;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? tokens.accentSoft : tokens.panelSurface,
            borderRadius: BorderRadius.circular(tokens.radiusSmall),
            border: Border.all(
              color: selected ? tokens.accent : tokens.borderFaint,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: 150, width: double.infinity, child: child),
              const SizedBox(height: 8),
              Text('第 $pageNumber 页'),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnotationList extends StatefulWidget {
  const _AnnotationList({
    required this.document,
    required this.controller,
    required this.currentPageNumber,
    required this.onPageSelected,
    required this.onAnnotationsChanged,
    required this.hasActiveTextSelection,
    required this.selectedHighlightColorValue,
    required this.highlightColorOptions,
    required this.onHighlightColorChanged,
    required this.onHighlightSelection,
    required this.onUnderlineSelection,
    required this.onStrikethroughSelection,
    required this.onWavyUnderlineSelection,
    required this.onCopySelection,
    required this.onNoteSelection,
  });

  final PdfLibraryDocument document;
  final ResearchLifeController controller;
  final int currentPageNumber;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onAnnotationsChanged;
  final bool hasActiveTextSelection;
  final int selectedHighlightColorValue;
  final List<_AnnotationColorOption> highlightColorOptions;
  final ValueChanged<int> onHighlightColorChanged;
  final VoidCallback onHighlightSelection;
  final VoidCallback onUnderlineSelection;
  final VoidCallback onStrikethroughSelection;
  final VoidCallback onWavyUnderlineSelection;
  final VoidCallback onCopySelection;
  final VoidCallback onNoteSelection;

  @override
  State<_AnnotationList> createState() => _AnnotationListState();
}

class _AnnotationListState extends State<_AnnotationList> {
  _AnnotationFilter _filter = _AnnotationFilter.all;

  @override
  Widget build(BuildContext context) {
    final annotations = widget.controller.pdfAnnotationsFor(widget.document.id);
    final filteredAnnotations = annotations
        .where((annotation) => _filter.matches(annotation))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: _AnnotationToolsPanel(
            hasActiveTextSelection: widget.hasActiveTextSelection,
            selectedHighlightColorValue: widget.selectedHighlightColorValue,
            highlightColorOptions: widget.highlightColorOptions,
            onHighlightColorChanged: widget.onHighlightColorChanged,
            onHighlight: widget.onHighlightSelection,
            onUnderline: widget.onUnderlineSelection,
            onStrikethrough: widget.onStrikethroughSelection,
            onWavyUnderline: widget.onWavyUnderlineSelection,
            onCopy: widget.onCopySelection,
            onNote: widget.onNoteSelection,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: _AnnotationTile(
            title: '当前页',
            subtitle: '第 ${widget.currentPageNumber} 页',
            icon: Icons.my_location_rounded,
            onTap: () => widget.onPageSelected(widget.currentPageNumber),
          ),
        ),
        if (annotations.isEmpty)
          const Expanded(
            child: EmptyState(
              title: '还没有标注',
              description: '当前页和标注会显示在这里。',
              icon: Icons.bookmark_border_rounded,
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_AnnotationFilter>(
                showSelectedIcon: false,
                segments: [
                  for (final filter in _AnnotationFilter.values)
                    ButtonSegment(
                      value: filter,
                      icon: Icon(filter.icon),
                      label: Text(filter.label),
                    ),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) =>
                    setState(() => _filter = selection.first),
              ),
            ),
          ),
          Expanded(
            child: filteredAnnotations.isEmpty
                ? EmptyState(
                    title: '没有${_filter.label}标注',
                    description: '切换筛选条件查看其他标注。',
                    icon: _filter.icon,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    itemCount: filteredAnnotations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final annotation = filteredAnnotations[index];
                      return _AnnotationTile(
                        title:
                            '${annotation.kind.label} · 第 ${annotation.pageNumber} 页',
                        subtitle: annotation.note?.isNotEmpty == true
                            ? annotation.note!
                            : annotation.selectedText,
                        icon: _iconForAnnotation(annotation.kind),
                        markerColor: Color(annotation.colorValue),
                        onTap: () =>
                            widget.onPageSelected(annotation.pageNumber),
                        onEdit: annotation.kind == PdfAnnotationKind.note
                            ? () => _editNote(annotation)
                            : null,
                        onDelete: () => _deleteAnnotation(annotation),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  IconData _iconForAnnotation(PdfAnnotationKind kind) {
    return switch (kind) {
      PdfAnnotationKind.bookmark => Icons.bookmark_rounded,
      PdfAnnotationKind.highlight => Icons.border_color_rounded,
      PdfAnnotationKind.underline => Icons.format_underlined_rounded,
      PdfAnnotationKind.strikethrough => Icons.strikethrough_s_rounded,
      PdfAnnotationKind.wavyUnderline => Icons.show_chart_rounded,
      PdfAnnotationKind.note => Icons.sticky_note_2_outlined,
    };
  }

  void _deleteAnnotation(PdfTextAnnotation annotation) {
    final message = widget.controller.deletePdfAnnotation(
      widget.document.id,
      annotation.id,
    );
    widget.onAnnotationsChanged();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _editNote(PdfTextAnnotation annotation) async {
    final draft = await showReadingNoteDialog(
      context: context,
      selectedText: annotation.selectedText,
      initialReflection: annotation.note,
      initialContentType: annotation.contentType,
      initialLatex: annotation.latexContent,
    );
    if (!mounted || draft == null) {
      return;
    }

    final message = widget.controller.updatePdfAnnotation(
      widget.document.id,
      annotation.id,
      note: draft.reflection,
      clearNote: draft.reflection.trim().isEmpty,
      contentType: draft.contentType,
      latexContent: draft.latexContent,
      clearLatex: draft.latexContent == null,
    );
    widget.onAnnotationsChanged();

    final auth = AuthScope.of(context);
    if (auth.cloudSyncEnabled) {
      final cloudMessage = await widget.controller.saveDocumentToCloud(
        widget.document.id,
      );
      widget.onAnnotationsChanged();
      if (mounted && cloudMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(cloudMessage)));
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _AnnotationToolsPanel extends StatelessWidget {
  const _AnnotationToolsPanel({
    required this.hasActiveTextSelection,
    required this.selectedHighlightColorValue,
    required this.highlightColorOptions,
    required this.onHighlightColorChanged,
    required this.onHighlight,
    required this.onUnderline,
    required this.onStrikethrough,
    required this.onWavyUnderline,
    required this.onCopy,
    required this.onNote,
  });

  final bool hasActiveTextSelection;
  final int selectedHighlightColorValue;
  final List<_AnnotationColorOption> highlightColorOptions;
  final ValueChanged<int> onHighlightColorChanged;
  final VoidCallback onHighlight;
  final VoidCallback onUnderline;
  final VoidCallback onStrikethrough;
  final VoidCallback onWavyUnderline;
  final VoidCallback onCopy;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_rounded, color: tokens.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '选区工具',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _MiniPill(label: hasActiveTextSelection ? '已选中' : '未选中'),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _PanelHighlightTool(
                  colorValue: selectedHighlightColorValue,
                  options: highlightColorOptions,
                  onPressed: onHighlight,
                  onColorChanged: onHighlightColorChanged,
                ),
                _PanelToolButton(
                  tooltip: '下划线',
                  icon: Icons.format_underlined_rounded,
                  onPressed: onUnderline,
                ),
                _PanelToolButton(
                  tooltip: '删除线',
                  icon: Icons.strikethrough_s_rounded,
                  onPressed: onStrikethrough,
                ),
                _PanelToolButton(
                  tooltip: '波浪线',
                  icon: Icons.show_chart_rounded,
                  onPressed: onWavyUnderline,
                ),
                _PanelToolButton(
                  tooltip: '复制',
                  icon: Icons.content_copy_rounded,
                  onPressed: onCopy,
                ),
                _PanelToolButton(
                  tooltip: '做笔记',
                  icon: Icons.note_add_outlined,
                  onPressed: onNote,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelHighlightTool extends StatelessWidget {
  const _PanelHighlightTool({
    required this.colorValue,
    required this.options,
    required this.onPressed,
    required this.onColorChanged,
  });

  final int colorValue;
  final List<_AnnotationColorOption> options;
  final VoidCallback onPressed;
  final ValueChanged<int> onColorChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.panelSubtle,
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: '高亮',
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: 38,
                height: 36,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Center(
                      child: Icon(
                        Icons.border_color_rounded,
                        color: tokens.textPrimary,
                        size: 20,
                      ),
                    ),
                    Positioned(
                      right: 7,
                      bottom: 7,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: Color(colorValue),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<int>(
            tooltip: '高亮颜色',
            padding: EdgeInsets.zero,
            onSelected: onColorChanged,
            itemBuilder: (context) => [
              for (final option in options)
                PopupMenuItem<int>(
                  value: option.colorValue,
                  child: Row(
                    children: [
                      _ColorSwatch(
                        color: Color(option.colorValue),
                        selected: option.colorValue == colorValue,
                      ),
                      const SizedBox(width: 10),
                      Text(option.label),
                    ],
                  ),
                ),
            ],
            child: SizedBox(
              width: 28,
              height: 36,
              child: Icon(
                Icons.arrow_drop_down_rounded,
                color: tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelToolButton extends StatelessWidget {
  const _PanelToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(icon, color: tokens.textPrimary, size: 20),
          ),
        ),
      ),
    );
  }
}

class _AnnotationTile extends StatelessWidget {
  const _AnnotationTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.markerColor,
    this.onEdit,
    this.onDelete,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? markerColor;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.panelSurface,
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: markerColor ?? tokens.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: '编辑笔记',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_note_rounded),
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: '删除标注',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AnnotationFilter { all, highlight, note, bookmark }

extension _AnnotationFilterDetails on _AnnotationFilter {
  String get label {
    return switch (this) {
      _AnnotationFilter.all => '全部',
      _AnnotationFilter.highlight => '高亮',
      _AnnotationFilter.note => '笔记',
      _AnnotationFilter.bookmark => '书签',
    };
  }

  IconData get icon {
    return switch (this) {
      _AnnotationFilter.all => Icons.list_alt_rounded,
      _AnnotationFilter.highlight => Icons.border_color_rounded,
      _AnnotationFilter.note => Icons.sticky_note_2_outlined,
      _AnnotationFilter.bookmark => Icons.bookmark_border_rounded,
    };
  }

  bool matches(PdfTextAnnotation annotation) {
    return switch (this) {
      _AnnotationFilter.all => true,
      _AnnotationFilter.highlight =>
        annotation.kind == PdfAnnotationKind.highlight,
      _AnnotationFilter.note => annotation.kind == PdfAnnotationKind.note,
      _AnnotationFilter.bookmark =>
        annotation.kind == PdfAnnotationKind.bookmark,
    };
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.highlightColorValue,
    required this.highlightColorOptions,
    required this.onHighlightColorChanged,
    required this.onHighlight,
    required this.onUnderline,
    required this.onStrikethrough,
    required this.onWavyUnderline,
    required this.onCopy,
    required this.onNote,
  });

  final int highlightColorValue;
  final List<_AnnotationColorOption> highlightColorOptions;
  final ValueChanged<int> onHighlightColorChanged;
  final VoidCallback onHighlight;
  final VoidCallback onUnderline;
  final VoidCallback onStrikethrough;
  final VoidCallback onWavyUnderline;
  final VoidCallback? onCopy;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.panelSurface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: tokens.borderFaint),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HighlightToolButton(
                colorValue: highlightColorValue,
                options: highlightColorOptions,
                onPressed: onHighlight,
                onColorChanged: onHighlightColorChanged,
              ),
              _SelectionToolButton(
                tooltip: '下划线',
                icon: Icons.format_underlined_rounded,
                onPressed: onUnderline,
              ),
              _SelectionToolButton(
                tooltip: '删除线',
                icon: Icons.strikethrough_s_rounded,
                onPressed: onStrikethrough,
              ),
              _SelectionToolButton(
                tooltip: '波浪线',
                icon: Icons.show_chart_rounded,
                onPressed: onWavyUnderline,
              ),
              Container(width: 1, height: 24, color: tokens.borderFaint),
              _SelectionToolButton(
                tooltip: '复制',
                icon: Icons.content_copy_rounded,
                onPressed: onCopy,
              ),
              _SelectionToolButton(
                tooltip: '做笔记',
                icon: Icons.note_add_outlined,
                onPressed: onNote,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightToolButton extends StatelessWidget {
  const _HighlightToolButton({
    required this.colorValue,
    required this.options,
    required this.onPressed,
    required this.onColorChanged,
  });

  final int colorValue;
  final List<_AnnotationColorOption> options;
  final VoidCallback onPressed;
  final ValueChanged<int> onColorChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: '高亮',
          child: IconButton(
            onPressed: onPressed,
            style: _SelectionToolButton.styleFor(context),
            icon: Stack(
              alignment: Alignment.bottomRight,
              children: [
                const Icon(Icons.border_color_rounded, size: 22),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(colorValue),
                    shape: BoxShape.circle,
                    border: Border.all(color: tokens.panelSurface, width: 1.2),
                  ),
                ),
              ],
            ),
          ),
        ),
        PopupMenuButton<int>(
          tooltip: '高亮颜色',
          padding: EdgeInsets.zero,
          iconColor: tokens.textSecondary,
          onSelected: onColorChanged,
          itemBuilder: (context) => [
            for (final option in options)
              PopupMenuItem<int>(
                value: option.colorValue,
                child: Row(
                  children: [
                    _ColorSwatch(
                      color: Color(option.colorValue),
                      selected: option.colorValue == colorValue,
                    ),
                    const SizedBox(width: 10),
                    Text(option.label),
                  ],
                ),
              ),
          ],
          child: const SizedBox(
            width: 28,
            height: 48,
            child: Icon(Icons.arrow_drop_down_rounded),
          ),
        ),
      ],
    );
  }
}

class _SelectionToolButton extends StatelessWidget {
  const _SelectionToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: styleFor(context),
        icon: Icon(icon, size: 22),
      ),
    );
  }

  static ButtonStyle styleFor(BuildContext context) {
    final tokens = context.tokens;
    return ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      fixedSize: const WidgetStatePropertyAll(Size(44, 48)),
      minimumSize: const WidgetStatePropertyAll(Size(44, 48)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return tokens.accentSoft;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return tokens.panelSubtle;
        }
        return Colors.transparent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return tokens.textSecondary.withValues(alpha: 0.46);
        }
        return tokens.textPrimary;
      }),
      overlayColor: WidgetStatePropertyAll(
        tokens.accentSoft.withValues(alpha: 0.34),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, this.selected = false});

  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.white,
          width: selected ? 2 : 1,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }
}

class _EmptyReader extends StatelessWidget {
  const _EmptyReader({
    required this.dragging,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDragDone,
  });

  final bool dragging;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final ValueChanged<String> onDragDone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DropTarget(
      onDragEntered: (_) => onDragEntered(),
      onDragExited: (_) => onDragExited(),
      onDragDone: (details) {
        if (details.files.isEmpty) {
          onDragExited();
          return;
        }
        onDragDone(details.files.first.path);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(
            color: dragging ? tokens.accent : tokens.borderFaint,
            width: dragging ? 1.6 : 1,
          ),
        ),
        child: const EmptyState(
          title: '选择一份 PDF 开始阅读',
          description: '导入后的文献会显示在左侧文库。',
          icon: Icons.picture_as_pdf_rounded,
        ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.panelSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

class _SelectionSnapshot {
  const _SelectionSnapshot({
    required this.selectedText,
    required this.rectsByPage,
    required this.textByPage,
  });

  final String selectedText;
  final Map<int, List<PdfAnnotationRect>> rectsByPage;
  final Map<int, List<String>> textByPage;
}

enum _LinePlacement { underline, strikethrough }

class _AnnotationColorOption {
  const _AnnotationColorOption(this.label, this.colorValue);

  final String label;
  final int colorValue;
}
