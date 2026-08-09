import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/auth_scope.dart';
import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../../features/files/post_process_save_dialog.dart';
import '../../features/files/workspace_cloud_picker.dart';
import '../../state/research_life_controller.dart';
import 'pdf_operation_dialogs.dart';

class PdfToolsPage extends StatefulWidget {
  const PdfToolsPage({super.key});

  @override
  State<PdfToolsPage> createState() => _PdfToolsPageState();
}

class _PdfToolsPageState extends State<PdfToolsPage> {
  final Set<int> _selectedCloudIds = {};
  String? _selectedLocalDocumentId;
  bool _busy = false;
  ResearchLifeController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_consumeOpenRequest());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ResearchLifeScope.read(context);
    if (!identical(_controller, controller)) {
      _controller?.removeListener(_handlePdfToolsNavigation);
      _controller = controller;
      controller.addListener(_handlePdfToolsNavigation);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handlePdfToolsNavigation);
    super.dispose();
  }

  List<CloudFileEntry> _selectedCloud(ResearchLifeController controller) {
    return [
      for (final id in _selectedCloudIds)
        if (controller.cloudFileEntryByServerId(id) != null)
          controller.cloudFileEntryByServerId(id)!,
    ];
  }

  PdfLibraryDocument? _selectedLocal(ResearchLifeController controller) {
    final id = _selectedLocalDocumentId;
    if (id == null) {
      return null;
    }
    final doc = controller.pdfDocumentById(id);
    if (doc == null || !doc.fileKind.isPdf || doc.path.isEmpty) {
      return null;
    }
    return doc;
  }

  void _handlePdfToolsNavigation() {
    if (_controller?.hasPendingPdfToolsSelection == true) {
      unawaited(_consumeOpenRequest());
    }
  }

  Future<void> _consumeOpenRequest() async {
    final controller = ResearchLifeScope.read(context);
    final request = controller.consumePdfToolsOpenRequest();
    if (request == null) {
      return;
    }
    if (request.documentId != null) {
      final doc = controller.pdfDocumentById(request.documentId!);
      if (doc != null && doc.fileKind.isPdf) {
        setState(() {
          _selectedLocalDocumentId = doc.id;
          _selectedCloudIds.clear();
        });
      }
      return;
    }
    if (request.cloudServerId != null) {
      final entry = controller.cloudFileEntryByServerId(request.cloudServerId!);
      if (entry != null && WorkspaceFileKind.fromPath(entry.title).isPdf) {
        setState(() {
          _selectedLocalDocumentId = null;
          _selectedCloudIds
            ..clear()
            ..add(entry.serverId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final auth = AuthScope.read(context);
    final controller = ResearchLifeScope.read(context);
    final selectedLocal = _selectedLocal(controller);
    final selectedCloud = _selectedCloud(controller);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PDF 操作',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            auth.isGuest
                ? '本地模式：PDF 结构操作需登录后端。'
                : '直接从云端选择 PDF 处理，完成后可选择下载到本地或上传到云端文件夹。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: 16),
          WorkspaceCloudPicker(
            filter: WorkspaceCloudFilter.pdfOnly,
            multiSelect: true,
            selectedServerIds: _selectedCloudIds,
            onSelectionChanged: (ids) => setState(() {
              _selectedLocalDocumentId = null;
              _selectedCloudIds
                ..clear()
                ..addAll(ids);
            }),
          ),
          const SizedBox(height: 10),
          _SelectedPdfSourceBar(
            localDocument: selectedLocal,
            cloudEntries: selectedCloud,
            onClear: selectedLocal == null && selectedCloud.isEmpty
                ? null
                : () => setState(() {
                    _selectedLocalDocumentId = null;
                    _selectedCloudIds.clear();
                  }),
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: SingleChildScrollView(
              child: _OperationBoard(
                enabled: !_busy,
                onOperation: _runOperation,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runOperation(_PdfOp op) async {
    final auth = AuthScope.read(context);
    final controller = ResearchLifeScope.read(context);

    final selected = _selectedCloud(controller);
    final selectedLocal = _selectedLocal(controller);

    if (op == _PdfOp.openReader) {
      if (selectedLocal == null && selected.isEmpty) {
        _snack('请选择一个 PDF');
        return;
      }
      try {
        if (selectedLocal != null) {
          controller.requestOpenReading(documentId: selectedLocal.id);
        } else {
          await controller.prepareCloudFileForReading(selected.first);
          controller.requestOpenReading(cloudServerId: selected.first.serverId);
        }
        _snack('已在科研文献中打开');
      } catch (error) {
        _snack('$error');
      }
      return;
    }

    if (op == _PdfOp.scanToPdf) {
      await _scanImagesToPdf(controller);
      return;
    }

    if (auth.isGuest) {
      _snack('请登录后使用 PDF 处理功能');
      return;
    }

    if (_needsSelection(op) && selectedLocal == null && selected.isEmpty) {
      _snack('请先选择 PDF');
      return;
    }
    if (op == _PdfOp.merge && selected.length < 2) {
      _snack('合并至少选择 2 个云端 PDF');
      return;
    }

    setState(() => _busy = true);
    try {
      await _executeOp(controller, op, selected);
    } on ApiException catch (error) {
      _snack(error.message);
    } catch (error) {
      _snack('$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  bool _needsSelection(_PdfOp op) => op != _PdfOp.scanToPdf;

  Future<void> _executeOp(
    ResearchLifeController controller,
    _PdfOp op,
    List<CloudFileEntry> selected,
  ) async {
    final api = controller.pdfOperationApi;
    Map<String, dynamic>? params;
    File? signature;
    final selectedLocal = _selectedLocal(controller);
    final sourceEntry = selected.isEmpty ? null : selected.first;
    final sourceDoc = selectedLocal ?? _placeholderDoc(sourceEntry!);

    switch (op) {
      case _PdfOp.split:
      case _PdfOp.deletePages:
      case _PdfOp.extractPages:
        final pages = await promptPages(context);
        if (pages == null || pages.isEmpty) {
          return;
        }
        params = {'pages': pages};
        break;
      case _PdfOp.rotate:
        final deg = await promptText(
          context,
          title: '旋转',
          label: '角度 90/180/270',
          initial: '90',
        );
        if (deg == null) {
          return;
        }
        params = {'degrees': int.tryParse(deg) ?? 90};
        break;
      case _PdfOp.reorder:
        final order = await promptPages(context, hint: '新顺序，如 3,1,2');
        if (order == null) {
          return;
        }
        params = {'order': order};
        break;
      case _PdfOp.watermark:
        final text = await promptText(
          context,
          title: '水印',
          label: '水印文字',
          initial: 'CONFIDENTIAL',
        );
        if (text == null) {
          return;
        }
        params = {'text': text};
        break;
      case _PdfOp.encrypt:
        final pwd = await promptText(
          context,
          title: '加密',
          label: '密码',
          obscure: true,
        );
        if (pwd == null || pwd.isEmpty) {
          return;
        }
        params = {'password': pwd};
        break;
      case _PdfOp.decrypt:
        final pwd = await promptText(context, title: '解密', label: '密码（无密码可留空）');
        params = {'password': pwd ?? ''};
        break;
      case _PdfOp.redact:
        final keyword = await promptText(context, title: '遮盖', label: '关键词');
        if (keyword == null) {
          return;
        }
        params = {'keyword': keyword};
        break;
      case _PdfOp.sign:
        const group = XTypeGroup(
          label: '图片',
          extensions: ['png', 'jpg', 'jpeg'],
        );
        final picked = await openFile(acceptedTypeGroups: [group]);
        if (picked == null) {
          return;
        }
        signature = File(picked.path);
        break;
      case _PdfOp.aiChat:
        final prompt = await promptText(
          context,
          title: '与 PDF 对话',
          label: '你的问题',
        );
        if (prompt == null) {
          return;
        }
        final cacheFile = selectedLocal == null
            ? await controller.ensureCloudEntryFile(sourceEntry!)
            : File(selectedLocal.path);
        final ai = await api.ai(
          operation: 'AI_CHAT',
          localFile: cacheFile,
          fileEntryId: sourceEntry?.serverId,
          prompt: prompt,
        );
        if (!mounted) {
          return;
        }
        await showAiResultDialog(context, ai.resultText);
        return;
      case _PdfOp.aiSummary:
      case _PdfOp.aiTranslate:
      case _PdfOp.aiQuestions:
        final cacheFile = selectedLocal == null
            ? await controller.ensureCloudEntryFile(sourceEntry!)
            : File(selectedLocal.path);
        final ai = await api.ai(
          operation: op.apiName,
          localFile: cacheFile,
          fileEntryId: sourceEntry?.serverId,
        );
        if (!mounted) {
          return;
        }
        await showAiResultDialog(context, ai.resultText);
        return;
      default:
        break;
    }

    final localFiles = <File>[];
    if (selectedLocal != null) {
      final file = File(selectedLocal.path);
      if (!file.existsSync()) {
        throw StateError('本地 PDF 文件不存在');
      }
      localFiles.add(file);
    } else {
      for (final entry in selected) {
        localFiles.add(await controller.ensureCloudEntryFile(entry));
      }
    }

    final output = await api.process(
      operation: op.apiName,
      localFiles: localFiles,
      fileEntryId: selected.length == 1 ? sourceEntry?.serverId : null,
      params: params,
      signatureImage: signature,
    );

    if (!mounted) {
      return;
    }
    final savePlan = await showPostProcessSaveSheet(
      context,
      fileName: output.fileName,
      entries: controller.cloudFileEntries,
    );
    if (savePlan.choice == null) {
      _snack('已处理完成（未保存）');
      return;
    }
    final message = await controller.persistProcessedOutput(
      output: output,
      source: sourceDoc,
      saveLocal:
          savePlan.choice == ProcessSaveChoice.local ||
          savePlan.choice == ProcessSaveChoice.both,
      saveCloud:
          savePlan.choice == ProcessSaveChoice.cloud ||
          savePlan.choice == ProcessSaveChoice.both,
      cloudParentId: savePlan.cloudParentId,
    );
    _snack(message ?? output.message);
  }

  PdfLibraryDocument _placeholderDoc(CloudFileEntry entry) {
    final now = DateTime.now();
    return PdfLibraryDocument(
      id: 'cloud_${entry.serverId}',
      title: entry.title,
      path: '',
      fileKind: WorkspaceFileKind.pdf,
      createdAt: now,
      updatedAt: now,
      serverId: entry.serverId,
      inReadingList: false,
    );
  }

  Future<void> _scanImagesToPdf(ResearchLifeController controller) async {
    if (AuthScope.read(context).isGuest) {
      _snack('请登录后使用扫描转 PDF');
      return;
    }
    const group = XTypeGroup(
      label: '图片',
      extensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp'],
    );
    final files = await openFiles(acceptedTypeGroups: [group]);
    if (files.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      final output = await controller.pdfOperationApi.process(
        operation: 'IMAGES_TO_PDF',
        localFiles: files.map((f) => File(f.path)).toList(),
      );
      final now = DateTime.now();
      final placeholder = PdfLibraryDocument(
        id: 'tmp',
        title: 'scanned',
        path: files.first.path,
        createdAt: now,
        updatedAt: now,
      );
      if (!mounted) {
        return;
      }
      final savePlan = await showPostProcessSaveSheet(
        context,
        fileName: output.fileName,
        entries: controller.cloudFileEntries,
      );
      if (savePlan.choice == null) {
        return;
      }
      await controller.persistProcessedOutput(
        output: output,
        source: placeholder,
        category: '扫描',
        saveLocal:
            savePlan.choice == ProcessSaveChoice.local ||
            savePlan.choice == ProcessSaveChoice.both,
        saveCloud:
            savePlan.choice == ProcessSaveChoice.cloud ||
            savePlan.choice == ProcessSaveChoice.both,
        cloudParentId: savePlan.cloudParentId,
      );
      _snack('扫描 PDF 已保存');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _SelectedPdfSourceBar extends StatelessWidget {
  const _SelectedPdfSourceBar({
    required this.localDocument,
    required this.cloudEntries,
    required this.onClear,
  });

  final PdfLibraryDocument? localDocument;
  final List<CloudFileEntry> cloudEntries;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = switch ((localDocument, cloudEntries.length)) {
      (final doc?, _) => '已选本地 PDF：${doc.title}',
      (_, 0) => '尚未选择 PDF',
      (_, 1) => '已选云端 PDF：${cloudEntries.first.title}',
      (_, final count) => '已选 $count 个云端 PDF',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              localDocument == null
                  ? Icons.cloud_outlined
                  : Icons.picture_as_pdf_rounded,
              size: 18,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
            ),
            IconButton(
              tooltip: '清除选择',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PdfOp {
  compress('COMPRESS'),
  merge('MERGE'),
  split('SPLIT'),
  rotate('ROTATE'),
  deletePages('DELETE_PAGES'),
  extractPages('EXTRACT_PAGES'),
  reorder('REORDER_PAGES'),
  pageNumbers('PAGE_NUMBERS'),
  crop('CROP'),
  watermark('WATERMARK'),
  encrypt('ENCRYPT'),
  decrypt('DECRYPT'),
  flatten('FLATTEN'),
  ocr('OCR_EXTRACT'),
  toWord('TO_WORD'),
  toExcel('TO_EXCEL'),
  toPpt('TO_PPT'),
  toJpg('TO_JPG'),
  sign('SIGN'),
  redact('REDACT'),
  aiChat('AI_CHAT'),
  aiSummary('AI_SUMMARY'),
  aiTranslate('AI_TRANSLATE'),
  aiQuestions('AI_QUESTIONS'),
  scanToPdf('IMAGES_TO_PDF'),
  openReader('OPEN');

  const _PdfOp(this.apiName);
  final String apiName;
}

class _OperationBoard extends StatelessWidget {
  const _OperationBoard({required this.enabled, required this.onOperation});

  final bool enabled;
  final ValueChanged<_PdfOp> onOperation;

  @override
  Widget build(BuildContext context) {
    final sections = [
      _Section('压缩 / 转换', [
        _Tile('压缩 PDF', Icons.compress, _PdfOp.compress),
        _Tile('合并 PDF', Icons.merge_type, _PdfOp.merge),
        _Tile('分割 PDF', Icons.call_split, _PdfOp.split),
        _Tile('PDF OCR', Icons.text_fields, _PdfOp.ocr),
        _Tile('扫描转 PDF', Icons.document_scanner, _PdfOp.scanToPdf),
      ]),
      _Section('整理', [
        _Tile('旋转', Icons.rotate_right, _PdfOp.rotate),
        _Tile('删除页面', Icons.delete_sweep, _PdfOp.deletePages),
        _Tile('提取页面', Icons.content_copy, _PdfOp.extractPages),
        _Tile('整理顺序', Icons.reorder, _PdfOp.reorder),
      ]),
      _Section('检视 & 编辑', [
        _Tile('打开阅读', Icons.menu_book, _PdfOp.openReader),
        _Tile('页码', Icons.format_list_numbered, _PdfOp.pageNumbers),
        _Tile('裁剪', Icons.crop, _PdfOp.crop),
        _Tile('水印', Icons.branding_watermark, _PdfOp.watermark),
        _Tile('遮盖', Icons.visibility_off, _PdfOp.redact),
        _Tile('展平', Icons.layers_clear, _PdfOp.flatten),
      ]),
      _Section('从 PDF 转换', [
        _Tile('转 Word', Icons.description, _PdfOp.toWord),
        _Tile('转 Excel', Icons.table_chart, _PdfOp.toExcel),
        _Tile('转 PPT 大纲', Icons.slideshow, _PdfOp.toPpt),
        _Tile('转 JPG', Icons.image, _PdfOp.toJpg),
      ]),
      _Section('AI PDF', [
        _Tile('AI 对话', Icons.chat, _PdfOp.aiChat),
        _Tile('AI 摘要', Icons.summarize, _PdfOp.aiSummary),
        _Tile('翻译', Icons.translate, _PdfOp.aiTranslate),
        _Tile('AI 出题', Icons.quiz, _PdfOp.aiQuestions),
      ]),
      _Section('签名 / 安全', [
        _Tile('电子签名', Icons.draw, _PdfOp.sign),
        _Tile('加密', Icons.lock, _PdfOp.encrypt),
        _Tile('解密', Icons.lock_open, _PdfOp.decrypt),
      ]),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final section in sections)
          _SectionCard(section: section, enabled: enabled, onTap: onOperation),
      ],
    );
  }
}

class _Section {
  const _Section(this.title, this.tiles);
  final String title;
  final List<_Tile> tiles;
}

class _Tile {
  const _Tile(this.label, this.icon, this.op);
  final String label;
  final IconData icon;
  final _PdfOp op;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.enabled,
    required this.onTap,
  });

  final _Section section;
  final bool enabled;
  final ValueChanged<_PdfOp> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: 200,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.shellBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                section.title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final tile in section.tiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TextButton.icon(
                    onPressed: enabled ? () => onTap(tile.op) : null,
                    icon: Icon(tile.icon, size: 18),
                    label: Text(tile.label),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
