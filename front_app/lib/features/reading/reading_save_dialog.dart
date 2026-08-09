import 'package:flutter/material.dart';

sealed class ReadingSaveDialogResult {
  const ReadingSaveDialogResult();
}

class ReadingCloseResult extends ReadingSaveDialogResult {
  const ReadingCloseResult();
}

class ReadingSaveLocalResult extends ReadingSaveDialogResult {
  const ReadingSaveLocalResult();
}

class ReadingSaveCloudResult extends ReadingSaveDialogResult {
  const ReadingSaveCloudResult({required this.overwrite, this.newTitle});

  final bool overwrite;
  final String? newTitle;
}

Future<ReadingSaveDialogResult?> showReadingSaveDialog(
  BuildContext context, {
  required String currentTitle,
  bool cloudSyncEnabled = true,
}) {
  return showDialog<ReadingSaveDialogResult>(
    context: context,
    builder: (dialogContext) => _ReadingSaveDialog(
      currentTitle: currentTitle,
      cloudSyncEnabled: cloudSyncEnabled,
    ),
  );
}

class _ReadingSaveDialog extends StatefulWidget {
  const _ReadingSaveDialog({
    required this.currentTitle,
    required this.cloudSyncEnabled,
  });

  final String currentTitle;
  final bool cloudSyncEnabled;

  @override
  State<_ReadingSaveDialog> createState() => _ReadingSaveDialogState();
}

class _ReadingSaveDialogState extends State<_ReadingSaveDialog> {
  bool _rename = false;
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.currentTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('保存修改'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('保存将把当前 PDF 与高亮批注同步到云端；关闭则不同步。'),
            if (widget.cloudSyncEnabled) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('另存为新文件（重命名）'),
                subtitle: const Text('关闭则覆盖云端原文件'),
                value: _rename,
                onChanged: (value) => setState(() => _rename = value),
              ),
              if (_rename) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '新文件名',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('当前为本地模式，仅可保存到本机。'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const ReadingCloseResult()),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const ReadingSaveLocalResult()),
          child: const Text('仅本地'),
        ),
        if (widget.cloudSyncEnabled)
          FilledButton(
            onPressed: () {
              final title = _titleController.text.trim();
              if (_rename && title.isEmpty) {
                return;
              }
              Navigator.of(context).pop(
                ReadingSaveCloudResult(
                  overwrite: !_rename,
                  newTitle: _rename ? title : null,
                ),
              );
            },
            child: Text(_rename ? '另存到云端' : '保存到云端'),
          ),
      ],
    );
  }
}
