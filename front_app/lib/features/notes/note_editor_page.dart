import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';

/// 独立笔记的全屏编辑器：标题 + Markdown 正文，支持保存/删除。
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    this.note,
    required this.onCreate,
    required this.onUpdate,
    required this.onDelete,
    super.key,
  });

  final UserNote? note;
  final Future<String> Function(String title, String content) onCreate;
  final Future<String> Function(String id, String title, String content)
  onUpdate;
  final Future<void> Function(String id) onDelete;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.note?.title ?? '',
  );
  late final TextEditingController _contentController = TextEditingController(
    text: widget.note?.contentMarkdown ?? '',
  );
  bool _saving = false;
  bool _previewing = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final title = _titleController.text;
    final content = _contentController.text;
    String message = '已保存。';
    if (widget.note == null) {
      message = await widget.onCreate(title, content);
    } else {
      message = await widget.onUpdate(widget.note!.id, title, content);
    }
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final note = widget.note;
    if (note == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记'),
        content: Text('确定删除「${note.title}」吗？删除后云端也会同步移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE5484D),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await widget.onDelete(note.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildPreview(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final content = _contentController.text;

    if (content.trim().isEmpty) {
      return Center(
        child: Text(
          '还没有内容可预览',
          style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: MarkdownBody(
        data: content,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          code: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: theme.colorScheme.onSurface,
            backgroundColor: tokens.panelSubtle,
          ),
          codeblockDecoration: BoxDecoration(
            color: tokens.panelSubtle,
            borderRadius: BorderRadius.circular(8),
          ),
          blockquoteDecoration: BoxDecoration(
            color: tokens.accentSoft.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? '新建笔记' : '编辑笔记'),
        actions: [
          IconButton(
            tooltip: _previewing ? '返回编辑' : '纯文本预览',
            onPressed: _saving
                ? null
                : () => setState(() => _previewing = !_previewing),
            icon: Icon(
              _previewing ? Icons.edit_rounded : Icons.visibility_rounded,
            ),
          ),
          if (widget.note != null)
            IconButton(
              tooltip: '删除',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_rounded, size: 16),
              label: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                hintText: '笔记标题',
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: _previewing
                  ? _buildPreview(context)
                  : TextField(
                      controller: _contentController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText: '用 Markdown 书写你的想法…\n\n# 标题\n- 列表\n**加粗** 等',
                        border: InputBorder.none,
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              '支持 Markdown 语法；登录后内容会自动同步到云端。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
