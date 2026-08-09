import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../state/research_life_controller.dart';

/// 快速捕获目标：存为记录 / 计划 / 独立笔记。
enum QuickCaptureTarget { record, plan, note }

/// 全局快捷键（Ctrl+Shift+C）触发的快速捕获对话框：随手记一句话。
class QuickCaptureDialog extends StatefulWidget {
  const QuickCaptureDialog({required this.controller, super.key});

  final ResearchLifeController controller;

  @override
  State<QuickCaptureDialog> createState() => _QuickCaptureDialogState();
}

class _QuickCaptureDialogState extends State<QuickCaptureDialog> {
  final TextEditingController _textController = TextEditingController();
  QuickCaptureTarget _target = QuickCaptureTarget.record;
  bool _saving = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _saving) {
      return;
    }
    setState(() => _saving = true);

    String message;
    switch (_target) {
      case QuickCaptureTarget.record:
      case QuickCaptureTarget.plan:
        message = widget.controller.addManualEvent(
          date: DateTime.now(),
          title: text,
          category: ItemCategory.other,
          type: _target == QuickCaptureTarget.plan
              ? EventType.plan
              : EventType.record,
        );
      case QuickCaptureTarget.note:
        message = await widget.controller.createNote(title: text);
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.bolt_rounded, size: 22),
          SizedBox(width: 8),
          Text('快速捕获'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _textController,
              autofocus: true,
              maxLines: 2,
              minLines: 1,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                hintText: '随手记下一句话，比如「下午三点和导师讨论方案」…',
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<QuickCaptureTarget>(
              segments: const [
                ButtonSegment(
                  value: QuickCaptureTarget.record,
                  label: Text('记录'),
                  icon: Icon(Icons.notes_rounded, size: 16),
                ),
                ButtonSegment(
                  value: QuickCaptureTarget.plan,
                  label: Text('计划'),
                  icon: Icon(Icons.event_available_rounded, size: 16),
                ),
                ButtonSegment(
                  value: QuickCaptureTarget.note,
                  label: Text('笔记'),
                  icon: Icon(Icons.sticky_note_2_rounded, size: 16),
                ),
              ],
              selected: {_target},
              onSelectionChanged: (selection) {
                setState(() => _target = selection.first);
              },
            ),
            const SizedBox(height: 6),
            Text(
              '记录/计划会写入今天的日历，笔记会存入「我的笔记」。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text('保存'),
        ),
      ],
    );
  }
}
