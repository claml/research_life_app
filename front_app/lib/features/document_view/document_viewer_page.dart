import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/auth_scope.dart';
import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../state/research_life_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../../features/files/workspace_cloud_picker.dart';
import '../../services/document/document_text_loader.dart';

/// 文档查阅：直连云端或本机缓存，文本 / PPT / docx。
class DocumentViewerPage extends StatefulWidget {
  const DocumentViewerPage({super.key});

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  final Set<int> _selectedCloudIds = {};
  CloudFileEntry? _activeCloud;
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
    if (request.cloudServerId != null) {
      final entry = controller.cloudFileEntryByServerId(request.cloudServerId!);
      if (entry != null) {
        setState(() => _selectedCloudIds.add(entry.serverId));
        await _openCloud(entry);
      }
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
    final auth = AuthScope.read(context);
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
            '可直接从云端选择文本、Markdown、CSV、docx、PPT 等查阅，无需先导入本地。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: 12),
          WorkspaceCloudPicker(
            filter: WorkspaceCloudFilter.viewableOnly,
            selectedServerIds: _selectedCloudIds,
            onSelectionChanged: (ids) {
              setState(
                () => _selectedCloudIds
                  ..clear()
                  ..addAll(ids),
              );
              if (ids.length == 1) {
                final entry = controller.cloudFileEntryByServerId(ids.first);
                if (entry != null) {
                  unawaited(_openCloud(entry));
                }
              }
            },
          ),
          if (!auth.isGuest) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '本机已缓存 ${_localCount(localDocs)} 个可查阅文件',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(child: _buildPreview(context, tokens)),
        ],
      ),
    );
  }

  int _localCount(List<PdfLibraryDocument> docs) => docs.length;

  Widget _buildPreview(BuildContext context, AppTokens tokens) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final title = _activeCloud?.title ?? _activeLocal?.title;
    if (title == null) {
      return Center(
        child: Text(
          '从上方云端列表选择文件，或从「我的文件」打开',
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

  Future<void> _openCloud(CloudFileEntry entry) async {
    setState(() {
      _activeCloud = entry;
      _activeLocal = null;
      _loading = true;
      _error = null;
      _content = null;
    });
    try {
      final controller = ResearchLifeScope.read(context);
      final file = await controller.ensureCloudEntryFile(entry);
      final text = await DocumentTextLoader.loadFromPath(file.path);
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

  Future<void> _openLocal(PdfLibraryDocument doc) async {
    setState(() {
      _activeLocal = doc;
      _activeCloud = null;
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
