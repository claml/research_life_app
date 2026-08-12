import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../../services/pdf/pdf_operation_api.dart';
import '../../state/research_life_controller.dart';
import 'local_pdf_output.dart';
import 'pdf_operation_dialogs.dart';

class PdfToolsPage extends StatefulWidget {
  const PdfToolsPage({super.key});

  @override
  State<PdfToolsPage> createState() => _PdfToolsPageState();
}

class _PdfToolsPageState extends State<PdfToolsPage> {
  final List<PdfLibraryDocument> _selected = [];
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

  void _handlePdfToolsNavigation() {
    if (_controller?.hasPendingPdfToolsSelection == true) {
      unawaited(_consumeOpenRequest());
    }
  }

  Future<void> _consumeOpenRequest() async {
    final controller = ResearchLifeScope.read(context);
    final request = controller.consumePdfToolsOpenRequest();
    final id = request?.documentId;
    if (id == null) {
      return;
    }
    final document = controller.pdfDocumentById(id);
    if (document == null || !document.fileKind.isPdf || document.path.isEmpty) {
      return;
    }
    setState(() {
      _selected
        ..clear()
        ..add(document);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
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
            '只使用本地 PDF；处理完成后选择保存文件夹。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _pickLocalPdfs,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('选择本地 PDF'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SelectedPdfSourceBar(
                  documents: _selected,
                  onClear: _selected.isEmpty
                      ? null
                      : () => setState(_selected.clear),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '输出时会请你“选择保存文件夹”。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: 12),
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

  Future<void> _pickLocalPdfs() async {
    const group = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final files = await openFiles(acceptedTypeGroups: [group]);
    if (files.isEmpty || !mounted) {
      return;
    }
    final now = DateTime.now();
    setState(() {
      _selected
        ..clear()
        ..addAll(
          files.map(
            (file) => PdfLibraryDocument(
              id: 'picked-${file.path.hashCode}',
              title: _fileStem(file.path),
              path: file.path,
              fileKind: WorkspaceFileKind.pdf,
              createdAt: now,
              updatedAt: now,
              inReadingList: false,
            ),
          ),
        );
    });
  }

  Future<void> _runOperation(_PdfOp operation) async {
    final controller = ResearchLifeScope.read(context);
    if (operation == _PdfOp.openReader) {
      if (_selected.length != 1) {
        _snack('请选择一个 PDF');
        return;
      }
      final selected = _selected.single;
      if (controller.pdfDocumentById(selected.id) == null) {
        _snack('请先在“我的文件”中导入后阅读');
        return;
      }
      controller.requestOpenReading(documentId: selected.id);
      return;
    }
    if (operation != _PdfOp.scanToPdf && _selected.isEmpty) {
      _snack('请先选择 PDF');
      return;
    }
    if (operation == _PdfOp.merge && _selected.length < 2) {
      _snack('合并至少选择 2 个 PDF');
      return;
    }

    setState(() => _busy = true);
    try {
      if (operation == _PdfOp.scanToPdf) {
        await _scanImagesToPdf(controller);
      } else {
        await _executeOperation(controller, operation);
      }
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

  Future<void> _executeOperation(
    ResearchLifeController controller,
    _PdfOp operation,
  ) async {
    final api = controller.pdfOperationApi;
    Map<String, dynamic>? params;
    File? signature;

    switch (operation) {
      case _PdfOp.split:
      case _PdfOp.deletePages:
      case _PdfOp.extractPages:
        final pages = await promptPages(context);
        if (pages == null || pages.isEmpty) return;
        params = {'pages': pages};
      case _PdfOp.rotate:
        final degrees = await promptText(
          context,
          title: '旋转',
          label: '角度 90/180/270',
          initial: '90',
        );
        if (degrees == null) return;
        params = {'degrees': int.tryParse(degrees) ?? 90};
      case _PdfOp.reorder:
        final order = await promptPages(context, hint: '新顺序，如 3,1,2');
        if (order == null) return;
        params = {'order': order};
      case _PdfOp.watermark:
        final text = await promptText(context, title: '水印', label: '水印文字');
        if (text == null) return;
        params = {'text': text};
      case _PdfOp.encrypt:
        final password = await promptText(
          context,
          title: '加密',
          label: '密码',
          obscure: true,
        );
        if (password == null || password.isEmpty) return;
        params = {'password': password};
      case _PdfOp.decrypt:
        final password = await promptText(
          context,
          title: '解密',
          label: '密码（无密码可留空）',
        );
        params = {'password': password ?? ''};
      case _PdfOp.redact:
        final keyword = await promptText(context, title: '遮盖', label: '关键词');
        if (keyword == null) return;
        params = {'keyword': keyword};
      case _PdfOp.sign:
        const group = XTypeGroup(
          label: '图片',
          extensions: ['png', 'jpg', 'jpeg'],
        );
        final picked = await openFile(acceptedTypeGroups: [group]);
        if (picked == null) return;
        signature = File(picked.path);
      default:
        break;
    }

    final localFiles = _selected.map((item) => File(item.path)).toList();
    for (final file in localFiles) {
      if (!file.existsSync()) {
        throw StateError('本地 PDF 文件不存在：${file.path}');
      }
    }
    final output = await api.process(
      operation: operation.apiName,
      localFiles: localFiles,
      params: params,
      signatureImage: signature,
    );
    await _saveOutput(output);
  }

  Future<void> _scanImagesToPdf(ResearchLifeController controller) async {
    const group = XTypeGroup(
      label: '图片',
      extensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp'],
    );
    final files = await openFiles(acceptedTypeGroups: [group]);
    if (files.isEmpty || !mounted) {
      return;
    }
    final output = await controller.pdfOperationApi.process(
      operation: 'IMAGES_TO_PDF',
      localFiles: files.map((file) => File(file.path)).toList(),
    );
    await _saveOutput(output);
  }

  Future<void> _saveOutput(PdfProcessOutput output) async {
    final directoryPath = await getDirectoryPath(confirmButtonText: '选择保存文件夹');
    if (directoryPath == null) {
      _snack('已取消保存');
      return;
    }
    final target = await writePdfOutputCollisionSafe(
      directory: Directory(directoryPath),
      preferredFileName: output.fileName,
      bytes: output.bytes,
    );
    _snack('已保存到 ${target.path}');
  }

  String _fileStem(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _SelectedPdfSourceBar extends StatelessWidget {
  const _SelectedPdfSourceBar({required this.documents, required this.onClear});

  final List<PdfLibraryDocument> documents;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = switch (documents.length) {
      0 => '尚未选择 PDF',
      1 => '已选：${documents.single.title}',
      final count => '已选 $count 个本地 PDF',
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
              Icons.picture_as_pdf_rounded,
              size: 18,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
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
  const _Tile(this.label, this.icon, this.operation);
  final String label;
  final IconData icon;
  final _PdfOp operation;
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
                    onPressed: enabled ? () => onTap(tile.operation) : null,
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
