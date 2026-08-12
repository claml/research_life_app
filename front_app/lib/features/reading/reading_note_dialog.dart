import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import 'reading_latex_utils.dart';

class ReadingNoteDraft {
  const ReadingNoteDraft({
    required this.reflection,
    required this.contentType,
    this.latexContent,
  });

  final String reflection;
  final PdfAnnotationContentType contentType;
  final String? latexContent;
}

Future<ReadingNoteDraft?> showReadingNoteDialog({
  required BuildContext context,
  required String selectedText,
  String? initialReflection,
  PdfAnnotationContentType initialContentType = PdfAnnotationContentType.text,
  String? initialLatex,
}) {
  return showDialog<ReadingNoteDraft>(
    context: context,
    builder: (dialogContext) => _ReadingNoteDialog(
      selectedText: selectedText,
      initialReflection: initialReflection,
      initialContentType: initialContentType,
      initialLatex: initialLatex,
    ),
  );
}

class _ReadingNoteDialog extends StatefulWidget {
  const _ReadingNoteDialog({
    required this.selectedText,
    this.initialReflection,
    this.initialContentType = PdfAnnotationContentType.text,
    this.initialLatex,
  });

  final String selectedText;
  final String? initialReflection;
  final PdfAnnotationContentType initialContentType;
  final String? initialLatex;

  @override
  State<_ReadingNoteDialog> createState() => _ReadingNoteDialogState();
}

class _ReadingNoteDialogState extends State<_ReadingNoteDialog> {
  late final TextEditingController _reflectionController;
  late PdfAnnotationContentType _contentType;
  late String? _latexContent;
  bool _detectedLatex = false;

  @override
  void initState() {
    super.initState();
    _reflectionController = TextEditingController(
      text: widget.initialReflection ?? '',
    );
    _contentType = widget.initialContentType;
    _latexContent =
        widget.initialLatex ??
        (ReadingLatexUtils.looksLikeLatex(widget.selectedText)
            ? ReadingLatexUtils.normalizeLatex(widget.selectedText)
            : null);
    _detectedLatex = _latexContent != null;
  }

  @override
  void dispose() {
    _reflectionController.dispose();
    super.dispose();
  }

  void _recomputeLatex() {
    final reflection = _reflectionController.text;
    final contentType = ReadingLatexUtils.resolveContentType(
      selectedText: widget.selectedText,
      reflection: reflection,
    );
    final latex = ReadingLatexUtils.latexToStore(
      selectedText: widget.selectedText,
      reflection: reflection,
      contentType: contentType,
    );
    setState(() {
      _contentType = contentType;
      _latexContent = latex;
      _detectedLatex = latex != null;
    });
  }

  Future<void> _copyLatex() async {
    final latex = _latexContent;
    if (latex == null || latex.isEmpty) {
      return;
    }
    await ReadingLatexUtils.copyForWord(latex);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制 LaTeX（可在 Word 中粘贴为公式）')));
  }

  void _submit() {
    final reflection = _reflectionController.text.trim();
    if (reflection.isEmpty) {
      return;
    }
    _recomputeLatex();
    Navigator.of(context).pop(
      ReadingNoteDraft(
        reflection: reflection,
        contentType: _contentType,
        latexContent: _latexContent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('添加笔记'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('原文摘录', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.selectedText,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (_detectedLatex) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.functions_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '检测到公式，保存后可复制到 Word',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _copyLatex,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('复制公式'),
                  ),
                ],
              ),
              if (_latexContent != null)
                SelectableText(
                  _latexContent!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'Consolas',
                  ),
                ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _reflectionController,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              onChanged: (_) => _recomputeLatex(),
              decoration: const InputDecoration(
                labelText: '感悟 / 批注',
                hintText: '记录你的想法、推导或疑问…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存到本机')),
      ],
    );
  }
}
