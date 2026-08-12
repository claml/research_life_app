import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../state/research_life_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../../services/document/document_text_loader.dart';

/// 文档查阅：读取已导入本机文件库的文本 / PPT / docx 等文档。
class DocumentViewerPage extends StatefulWidget {
  const DocumentViewerPage({super.key});

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  PdfLibraryDocument? _activeLocal;
  String? _content;
  bool _loading = false;
  String? _error;
  ResearchLifeController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeOpenRequest());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ResearchLifeScope.of(context);
    if (!identical(_controller, controller)) {
      _controller?.removeListener(_handleDocumentViewNavigation);
      _controller = controller;
      controller.addListener(_handleDocumentViewNavigation);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleDocumentViewNavigation);
    super.dispose();
  }

  void _handleDocumentViewNavigation() {
    if (_controller?.hasPendingDocumentViewOpen == true) {
      unawaited(_consumeOpenRequest());
    }
  }

  Future<void> _consumeOpenRequest() async {
    final controller = ResearchLifeScope.read(context);
    final request = controller.consumeDocumentViewOpenRequest();
    if (request == null) {
      return;
    }
    if (request.documentId != null) {
      final doc = controller.pdfDocumentById(request.documentId!);
      if (doc != null && doc.fileKind.isViewable) {
        await _openLocal(doc);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    final tokens = context.tokens;
    final localDocs = controller.localViewableDocuments;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '文档查阅',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '查阅已导入本机的文本、Markdown、CSV、docx、PPT 等文档。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: 12),
          _LocalDocumentPicker(
            documents: localDocs,
            selectedDocumentId: _activeLocal?.id,
            onSelected: _openLocal,
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildPreview(context, tokens)),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context, AppTokens tokens) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final title = _activeLocal?.title;
    if (title == null) {
      return Center(
        child: Text(
          '从上方选择本机文档，或先到「我的文件」导入。',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: tokens.textMuted),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.shellBorder),
        color: tokens.shellSurface.withValues(alpha: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(WorkspaceFileKind.fromPath(title).icon, size: 20),
                const SizedBox(width: 8),
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
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                _content ?? '',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  fontFamily: 'Consolas',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLocal(PdfLibraryDocument doc) async {
    setState(() {
      _activeLocal = doc;
      _loading = true;
      _error = null;
      _content = null;
    });
    try {
      final text = await DocumentTextLoader.loadFromPath(doc.path);
      if (!mounted) {
        return;
      }
      setState(() {
        _content = text;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }
}

class _LocalDocumentPicker extends StatelessWidget {
  const _LocalDocumentPicker({
    required this.documents,
    required this.selectedDocumentId,
    required this.onSelected,
  });

  final List<PdfLibraryDocument> documents;
  final String? selectedDocumentId;
  final ValueChanged<PdfLibraryDocument> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (documents.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.panelSurface,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.borderFaint),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '还没有可查阅文档，请先在「我的文件」导入。',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      key: ValueKey(selectedDocumentId),
      initialValue: documents.any((item) => item.id == selectedDocumentId)
          ? selectedDocumentId
          : null,
      decoration: InputDecoration(
        labelText: '本机文档（${documents.length}）',
        prefixIcon: const Icon(Icons.description_outlined),
        border: const OutlineInputBorder(),
      ),
      hint: const Text('选择一份文档'),
      items: [
        for (final document in documents)
          DropdownMenuItem(value: document.id, child: Text(document.title)),
      ],
      onChanged: (id) {
        if (id == null) {
          return;
        }
        for (final document in documents) {
          if (document.id == id) {
            onSelected(document);
            return;
          }
        }
      },
    );
  }
}
