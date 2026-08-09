import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../../state/research_life_controller.dart';
import 'cloud_file_dialogs.dart';

enum CloudFileExplorerMode { manage, readingPicker }

class CloudFileExplorer extends StatefulWidget {
  const CloudFileExplorer({
    super.key,
    required this.entries,
    required this.busy,
    required this.controller,
    required this.mode,
    this.onOpenFile,
    this.onMoveToLocal,
    this.onSaveAs,
    this.fileFilter,
    this.compact = false,
  });

  final List<CloudFileEntry> entries;
  final bool busy;
  final ResearchLifeController controller;
  final CloudFileExplorerMode mode;
  final ValueChanged<CloudFileEntry>? onOpenFile;
  final ValueChanged<CloudFileEntry>? onMoveToLocal;
  final Future<void> Function(CloudFileEntry entry)? onSaveAs;
  final bool Function(CloudFileEntry entry)? fileFilter;
  final bool compact;

  @override
  State<CloudFileExplorer> createState() => _CloudFileExplorerState();
}

class _CloudFileExplorerState extends State<CloudFileExplorer> {
  int? _selectedFolderId;
  CloudFileEntry? _selectedEntry;

  CloudFileEntry? get _root {
    for (final entry in widget.entries) {
      if (entry.systemRoot) {
        return entry;
      }
    }
    return null;
  }

  int? get _currentFolderId => _selectedFolderId ?? _root?.serverId;

  List<CloudFileEntry> _childrenOf(int? parentId) {
    final root = _root;
    if (parentId == null) {
      return const [];
    }
    return widget.entries
        .where(
          (entry) =>
              !entry.systemRoot &&
              (entry.parentId == parentId ||
                  (entry.parentId == null && parentId == root?.serverId)) &&
              (entry.isFolder || (widget.fileFilter?.call(entry) ?? true)),
        )
        .toList()
      ..sort((a, b) {
        if (a.isFolder != b.isFolder) {
          return a.isFolder ? -1 : 1;
        }
        return a.title.compareTo(b.title);
      });
  }

  List<CloudFileEntry> get _folderNodes {
    final root = _root;
    if (root == null) {
      return const [];
    }
    final folders =
        widget.entries
            .where((entry) => entry.isFolder && !entry.systemRoot)
            .toList()
          ..sort(
            (a, b) => (a.relativePath ?? a.title).compareTo(
              b.relativePath ?? b.title,
            ),
          );
    return [root, ...folders];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (widget.busy) {
      return const Center(child: CircularProgressIndicator());
    }
    final root = _root;
    if (root == null) {
      return const Center(child: Text('云端目录尚未加载'));
    }

    final listEntries = _childrenOf(_currentFolderId);
    final treeWidth = widget.compact ? 200.0 : 240.0;
    final listHeight = widget.compact ? 200.0 : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.mode == CloudFileExplorerMode.manage) _buildToolbar(root),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: treeWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: tokens.borderFaint),
                    borderRadius: BorderRadius.circular(tokens.radiusSmall),
                  ),
                  child: ListView(
                    children: [
                      for (final folder in _folderNodes)
                        _FolderTreeRow(
                          entry: folder,
                          depth: folder.systemRoot ? 0 : _depthOf(folder, root),
                          selected: _currentFolderId == folder.serverId,
                          onTap: () => setState(() {
                            _selectedFolderId = folder.systemRoot
                                ? null
                                : folder.serverId;
                            _selectedEntry = null;
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPathBar(root),
                    Expanded(
                      child: listHeight != null
                          ? SizedBox(
                              height: listHeight,
                              child: _buildFileList(listEntries),
                            )
                          : _buildFileList(listEntries),
                    ),
                    if (_selectedEntry != null) _buildSelectionBar(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _depthOf(CloudFileEntry entry, CloudFileEntry root) {
    var depth = 0;
    var parentId = entry.parentId;
    while (parentId != null && parentId != root.serverId) {
      depth++;
      CloudFileEntry? parent;
      for (final item in widget.entries) {
        if (item.serverId == parentId) {
          parent = item;
          break;
        }
      }
      if (parent == null) {
        break;
      }
      parentId = parent.parentId;
    }
    return depth + 1;
  }

  Widget _buildToolbar(CloudFileEntry root) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => _createFolder(root),
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('新建文件夹'),
          ),
          FilledButton.tonalIcon(
            onPressed: _currentFolderId == null ? null : _uploadFile,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('上传文件'),
          ),
          OutlinedButton.icon(
            onPressed: _selectedEntry == null ? null : _renameSelected,
            icon: const Icon(Icons.drive_file_rename_outline, size: 18),
            label: const Text('重命名'),
          ),
          OutlinedButton.icon(
            onPressed: _selectedEntry == null ? null : _moveSelected,
            icon: const Icon(Icons.drive_file_move_outline, size: 18),
            label: const Text('移动'),
          ),
          OutlinedButton.icon(
            onPressed: _selectedEntry == null ? null : _deleteSelected,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除'),
          ),
          IconButton(
            tooltip: '刷新并同步 MinIO',
            onPressed: () =>
                widget.controller.refreshCloudFiles(reconcile: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildPathBar(CloudFileEntry root) {
    final path = _pathLabels(root);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: path,
      ),
    );
  }

  List<Widget> _pathLabels(CloudFileEntry root) {
    final widgets = <Widget>[
      ActionChip(
        label: Text(root.title),
        onPressed: () => setState(() {
          _selectedFolderId = null;
          _selectedEntry = null;
        }),
      ),
    ];
    if (_currentFolderId == null || _currentFolderId == root.serverId) {
      return widgets;
    }
    final chain = <CloudFileEntry>[];
    var cursor = _currentFolderId;
    while (cursor != null && cursor != root.serverId) {
      CloudFileEntry? folder;
      for (final entry in widget.entries) {
        if (entry.serverId == cursor) {
          folder = entry;
          break;
        }
      }
      if (folder == null) {
        break;
      }
      chain.insert(0, folder);
      cursor = folder.parentId;
    }
    for (final folder in chain) {
      widgets.add(const Icon(Icons.chevron_right_rounded, size: 16));
      final id = folder.serverId;
      widgets.add(
        ActionChip(
          label: Text(folder.title),
          onPressed: () => setState(() {
            _selectedFolderId = id;
            _selectedEntry = null;
          }),
        ),
      );
    }
    return widgets;
  }

  Widget _buildFileList(List<CloudFileEntry> listEntries) {
    if (listEntries.isEmpty) {
      return const Center(child: Text('此文件夹为空'));
    }
    return ListView.separated(
      itemCount: listEntries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = listEntries[index];
        final selected = _selectedEntry?.serverId == entry.serverId;
        return ListTile(
          dense: widget.compact,
          selected: selected,
          leading: Icon(
            entry.isFolder
                ? Icons.folder_rounded
                : WorkspaceFileKind.fromPath(entry.title).icon,
          ),
          title: Text(entry.title),
          subtitle: entry.isFolder
              ? null
              : Text(entry.relativePath ?? entry.category, maxLines: 1),
          trailing: entry.isFolder
              ? const Icon(Icons.chevron_right_rounded)
              : null,
          onTap: () {
            if (entry.isFolder) {
              setState(() {
                _selectedFolderId = entry.serverId;
                _selectedEntry = null;
              });
            } else {
              setState(() => _selectedEntry = entry);
              if (widget.mode == CloudFileExplorerMode.readingPicker) {
                widget.onOpenFile?.call(entry);
              }
            }
          },
          onLongPress: () => setState(() => _selectedEntry = entry),
        );
      },
    );
  }

  Widget _buildSelectionBar() {
    final entry = _selectedEntry!;
    if (entry.isFolder) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        children: [
          if (widget.mode == CloudFileExplorerMode.manage) ...[
            FilledButton.icon(
              onPressed: () => widget.onOpenFile?.call(entry),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('阅读'),
            ),
            if (widget.onMoveToLocal != null)
              OutlinedButton.icon(
                onPressed: () => widget.onMoveToLocal!(entry),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('移到本地'),
              ),
          ],
          if (widget.mode == CloudFileExplorerMode.readingPicker) ...[
            FilledButton.icon(
              onPressed: () => widget.onOpenFile?.call(entry),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('打开'),
            ),
            if (widget.onSaveAs != null)
              OutlinedButton.icon(
                onPressed: () => unawaited(widget.onSaveAs!(entry)),
                icon: const Icon(Icons.save_as_outlined, size: 18),
                label: const Text('另存'),
              ),
          ],
          OutlinedButton.icon(
            onPressed: _deleteSelected,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _createFolder(CloudFileEntry root) async {
    final title = await showCloudNameDialog(
      context,
      title: '新建文件夹',
      hint: '文件夹名称',
    );
    if (title == null || title.isEmpty || !mounted) {
      return;
    }
    await widget.controller.createCloudFolder(
      title: title,
      parentId: _currentFolderId ?? root.serverId,
    );
  }

  Future<void> _uploadFile() async {
    final parentId = _currentFolderId;
    if (parentId == null) {
      return;
    }
    const group = XTypeGroup(
      label: '所有文件',
      extensions: [
        'pdf',
        'txt',
        'md',
        'markdown',
        'csv',
        'json',
        'xml',
        'log',
        'ppt',
        'pptx',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'png',
        'jpg',
        'jpeg',
      ],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !mounted) {
      return;
    }
    final message = await widget.controller.uploadFileToCloudFolder(
      parentId: parentId,
      filePath: file.path,
    );
    if (mounted && message != null) {
      _showSnack(message);
    } else if (mounted) {
      _showSnack('已上传到当前文件夹');
    }
  }

  Future<void> _renameSelected() async {
    final entry = _selectedEntry;
    if (entry == null) {
      return;
    }
    final title = await showCloudNameDialog(
      context,
      title: entry.isFolder ? '重命名文件夹' : '重命名文件',
      initialValue: entry.title,
    );
    if (title == null || title.isEmpty || title == entry.title || !mounted) {
      return;
    }
    final message = await widget.controller.renameCloudEntry(
      entry: entry,
      title: title,
    );
    if (mounted) {
      if (message != null) {
        _showSnack(message);
      } else {
        setState(() {
          _selectedEntry = entry.copyWith(title: title);
        });
      }
    }
  }

  Future<void> _deleteSelected() async {
    final entry = _selectedEntry;
    if (entry == null) {
      return;
    }
    final confirmed = await showCloudDeleteConfirm(
      context,
      name: entry.title,
      isFolder: entry.isFolder,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final message = await widget.controller.deleteCloudEntry(entry);
    if (mounted) {
      if (message != null) {
        _showSnack(message);
      } else {
        setState(() => _selectedEntry = null);
        _showSnack('已删除「${entry.title}」');
      }
    }
  }

  Future<void> _moveSelected() async {
    final entry = _selectedEntry;
    if (entry == null) {
      return;
    }
    final target = await showMoveTargetFolderDialog(
      context,
      entries: widget.entries,
      movingEntry: entry,
    );
    if (target == null || !mounted) {
      return;
    }
    final message = await widget.controller.moveCloudEntry(
      entry: entry,
      parentId: target.serverId,
    );
    if (mounted && message != null) {
      _showSnack(message);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FolderTreeRow extends StatelessWidget {
  const _FolderTreeRow({
    required this.entry,
    required this.depth,
    required this.selected,
    required this.onTap,
  });

  final CloudFileEntry entry;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8.0 + depth * 14.0, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                entry.systemRoot ? Icons.cloud_rounded : Icons.folder_rounded,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on CloudFileEntry {
  CloudFileEntry copyWith({String? title}) {
    return CloudFileEntry(
      serverId: serverId,
      clientId: clientId,
      title: title ?? this.title,
      entryType: entryType,
      parentId: parentId,
      relativePath: relativePath,
      systemRoot: systemRoot,
      category: category,
      lastPage: lastPage,
      pageCount: pageCount,
      storageKey: storageKey,
      contentHash: contentHash,
      version: version,
      updatedAt: updatedAt,
    );
  }
}
