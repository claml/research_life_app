import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/auth_scope.dart';
import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/workspace_file_kind.dart';
import '../../state/research_life_controller.dart';
import 'cloud_file_dialogs.dart';
import 'cloud_file_explorer.dart';

class MyFilesPage extends StatefulWidget {
  const MyFilesPage({super.key});

  @override
  State<MyFilesPage> createState() => _MyFilesPageState();
}

class _MyFilesPageState extends State<MyFilesPage> {
  PdfLibraryDocument? _selectedLocal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = AuthScope.of(context);
      if (auth.cloudSyncEnabled) {
        final controller = ResearchLifeScope.of(context);
        unawaited(controller.refreshCloudFiles(reconcile: true));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    final auth = AuthScope.read(context);
    final tokens = context.tokens;

    return AnimatedBuilder(
      animation: Listenable.merge([controller, auth]),
      builder: (context, _) {
        final localDocs = controller.localMaterializedDocuments;
        final allCloud = controller.cloudFileEntries;

        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '我的文件',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                auth.isGuest
                    ? '本地模式：可导入任意类型文件；PDF 进入科研文献，文本/PPT 进入文档查阅。'
                    : '云端树形管理 + 本机文件库；打开方式按文件类型自动关联各功能模块。',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _FilePanel(
                        title: '云端文件',
                        subtitle: auth.isGuest
                            ? '需登录'
                            : '${allCloud.where((e) => !e.systemRoot && !e.isFolder).length} 个文件',
                        child: auth.isGuest
                            ? const _EmptyHint(message: '登录后可管理云端个人目录')
                            : CloudFileExplorer(
                                entries: allCloud,
                                busy: controller.cloudFilesBusy,
                                controller: controller,
                                mode: CloudFileExplorerMode.manage,
                                onOpenFile: (entry) =>
                                    _openCloudFile(context, controller, entry),
                                onMoveToLocal: (entry) => _moveCloudToLocal(
                                  context,
                                  controller,
                                  entry,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _FilePanel(
                        title: '本机文件',
                        subtitle: '${localDocs.length} 项',
                        toolbar: _LocalToolbar(
                          selected: _selectedLocal,
                          guest: auth.isGuest,
                          cloudSync: auth.cloudSyncEnabled,
                          onImport: () => _importLocalFile(context, controller),
                          onRename: _selectedLocal == null
                              ? null
                              : () => _renameLocal(
                                  context,
                                  controller,
                                  _selectedLocal!,
                                ),
                          onDelete: _selectedLocal == null
                              ? null
                              : () => _deleteLocal(
                                  context,
                                  controller,
                                  _selectedLocal!,
                                ),
                          onSaveCloud:
                              auth.cloudSyncEnabled && _selectedLocal != null
                              ? () => _saveToCloud(
                                  context,
                                  controller,
                                  _selectedLocal!.id,
                                )
                              : null,
                          onOpen: _selectedLocal == null
                              ? null
                              : () =>
                                    _openLocalFile(controller, _selectedLocal!),
                          onPdfTools:
                              _selectedLocal != null &&
                                  _selectedLocal!.fileKind.isPdf
                              ? () => _goPdfTools(context, _selectedLocal!)
                              : null,
                        ),
                        child: localDocs.isEmpty
                            ? const _EmptyHint(
                                message: '尚无本机文件。可从云端下载，或点「导入」添加。',
                              )
                            : ListView.separated(
                                itemCount: localDocs.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final doc = localDocs[index];
                                  final selected = _selectedLocal?.id == doc.id;
                                  return ListTile(
                                    selected: selected,
                                    leading: Icon(doc.fileKind.icon),
                                    title: Text(doc.title),
                                    subtitle: Text(
                                      '${doc.fileKind.label}'
                                      '${auth.isGuest ? '' : ' · ${doc.syncState}'}',
                                    ),
                                    onTap: () =>
                                        setState(() => _selectedLocal = doc),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.cloudFilesMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller.cloudFilesMessage!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _openLocalFile(
    ResearchLifeController controller,
    PdfLibraryDocument doc,
  ) {
    try {
      if (doc.fileKind.isPdf) {
        controller.requestOpenReading(documentId: doc.id);
      } else if (doc.fileKind.isViewable) {
        controller.requestOpenDocumentView(documentId: doc.id);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该类型请使用 PDF 操作或在系统中用默认应用打开')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _goPdfTools(BuildContext context, PdfLibraryDocument document) {
    ResearchLifeScope.read(
      context,
    ).requestOpenPdfTools(documentId: document.id);
  }

  Future<void> _importLocalFile(
    BuildContext context,
    ResearchLifeController controller,
  ) async {
    const group = XTypeGroup(
      label: '文件',
      extensions: [
        'pdf',
        'txt',
        'md',
        'markdown',
        'csv',
        'json',
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
    if (file == null || !context.mounted) {
      return;
    }
    try {
      await controller.ensurePdfLibraryLoaded();
      await controller.addWorkspaceFileFromPath(file.path);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已导入到本机文件库')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _renameLocal(
    BuildContext context,
    ResearchLifeController controller,
    PdfLibraryDocument document,
  ) async {
    final title = await showCloudNameDialog(
      context,
      title: '重命名',
      initialValue: document.title,
    );
    if (title == null || title.isEmpty || !context.mounted) {
      return;
    }
    final message = controller.renameLocalPdfDocument(document.id, title);
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } else {
      setState(() {
        _selectedLocal = document.copyWith(title: title);
      });
    }
  }

  Future<void> _deleteLocal(
    BuildContext context,
    ResearchLifeController controller,
    PdfLibraryDocument document,
  ) async {
    final confirmed = await showCloudDeleteConfirm(
      context,
      name: document.title,
      isFolder: false,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final message = controller.deletePdfDocument(document.id);
    setState(() {
      if (_selectedLocal?.id == document.id) {
        _selectedLocal = null;
      }
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveToCloud(
    BuildContext context,
    ResearchLifeController controller,
    String documentId,
  ) async {
    final doc = controller.pdfDocumentById(documentId);
    if (doc == null) {
      return;
    }
    await controller.refreshCloudFiles(reconcile: false);
    if (!context.mounted) {
      return;
    }
    final folder = await showMoveTargetFolderDialog(
      context,
      entries: controller.cloudFileEntries,
      movingEntry: CloudFileEntry(
        serverId: -1,
        clientId: 'upload',
        title: doc.title,
        entryType: 'file',
      ),
    );
    if (folder == null || !context.mounted) {
      return;
    }
    final message = await controller.uploadLocalDocumentToCloud(
      documentId: documentId,
      parentId: folder.serverId,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message ?? '已上传到「${folder.title}」')));
  }

  Future<void> _openCloudFile(
    BuildContext context,
    ResearchLifeController controller,
    CloudFileEntry entry,
  ) async {
    try {
      final kind = WorkspaceFileKind.fromPath(entry.title);
      if (kind.isPdf) {
        await controller.prepareCloudFileForReading(entry);
        if (!context.mounted) {
          return;
        }
        controller.requestOpenReading(cloudServerId: entry.serverId);
      } else if (kind.isViewable) {
        await controller.prepareCloudFileForView(entry);
        if (!context.mounted) {
          return;
        }
        controller.requestOpenDocumentView(cloudServerId: entry.serverId);
      } else {
        await controller.moveCloudEntryToLocal(entry);
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('《${entry.title}》已下载到本机')));
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开失败：$error')));
    }
  }

  Future<void> _moveCloudToLocal(
    BuildContext context,
    ResearchLifeController controller,
    CloudFileEntry entry,
  ) async {
    try {
      await controller.moveCloudEntryToLocal(entry);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('《${entry.title}》已移到本地')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('移到本地失败：$error')));
    }
  }
}

class _LocalToolbar extends StatelessWidget {
  const _LocalToolbar({
    required this.selected,
    required this.guest,
    required this.cloudSync,
    required this.onImport,
    this.onRename,
    this.onDelete,
    this.onSaveCloud,
    this.onOpen,
    this.onPdfTools,
  });

  final PdfLibraryDocument? selected;
  final bool guest;
  final bool cloudSync;
  final VoidCallback onImport;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onSaveCloud;
  final VoidCallback? onOpen;
  final VoidCallback? onPdfTools;

  @override
  Widget build(BuildContext context) {
    final canOpen =
        selected != null &&
        (selected!.fileKind.isPdf || selected!.fileKind.isViewable);
    final openLabel = selected == null
        ? '打开'
        : selected!.fileKind.isPdf
        ? 'PDF 阅读'
        : '文档查阅';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('导入'),
          ),
          TextButton.icon(
            onPressed: selected != null ? onRename : null,
            icon: const Icon(Icons.drive_file_rename_outline, size: 18),
            label: const Text('重命名'),
          ),
          TextButton.icon(
            onPressed: selected != null ? onDelete : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除'),
          ),
          if (!guest && cloudSync)
            TextButton.icon(
              onPressed: selected != null ? onSaveCloud : null,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('上传云端'),
            ),
          TextButton.icon(
            onPressed: canOpen ? onOpen : null,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(openLabel),
          ),
          if (selected?.fileKind.isPdf == true)
            TextButton.icon(
              onPressed: onPdfTools,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF 操作'),
            ),
        ],
      ),
    );
  }
}

class _FilePanel extends StatelessWidget {
  const _FilePanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.toolbar,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? toolbar;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.shellBorder),
        color: tokens.shellSurface.withValues(alpha: 0.55),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          ?toolbar,
          const Divider(height: 1),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(8), child: child),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}
