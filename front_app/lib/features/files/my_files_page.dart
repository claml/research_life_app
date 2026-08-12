import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../state/research_life_controller.dart';
import 'cloud_file_dialogs.dart';

class MyFilesPage extends StatefulWidget {
  const MyFilesPage({super.key});

  @override
  State<MyFilesPage> createState() => _MyFilesPageState();
}

class _MyFilesPageState extends State<MyFilesPage> {
  PdfLibraryDocument? _selectedLocal;

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    final tokens = context.tokens;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final localDocs = controller.localMaterializedDocuments;
        final selectedId = _selectedLocal?.id;
        final selected = selectedId == null
            ? null
            : controller.pdfDocumentById(selectedId);
        if (selectedId != null && selected == null) {
          _selectedLocal = null;
        }

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
                '文件仅保存在本机；PDF 可进入文献阅读，文本与办公文档可直接查阅。',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _FilePanel(
                  title: '本机文件',
                  subtitle: '${localDocs.length} 项',
                  toolbar: _LocalToolbar(
                    selected: selected,
                    onImport: () => _importLocalFile(context, controller),
                    onRename: selected == null
                        ? null
                        : () => _renameLocal(context, controller, selected),
                    onRenameFolder: selected == null
                        ? null
                        : () =>
                              _renameLocalFolder(context, controller, selected),
                    onDelete: selected == null
                        ? null
                        : () => _deleteLocal(context, controller, selected),
                    onOpen: selected == null
                        ? null
                        : () => _openLocalFile(controller, selected),
                    onPdfTools: selected?.fileKind.isPdf == true
                        ? () => _goPdfTools(context, selected!)
                        : null,
                  ),
                  child: localDocs.isEmpty
                      ? const _EmptyHint(message: '尚无本机文件，点“导入”添加。')
                      : ListView.separated(
                          itemCount: localDocs.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final doc = localDocs[index];
                            return Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                selected: selected?.id == doc.id,
                                leading: Icon(doc.fileKind.icon),
                                title: Text(doc.title),
                                subtitle: Text(doc.fileKind.label),
                                onTap: () =>
                                    setState(() => _selectedLocal = doc),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openLocalFile(
    ResearchLifeController controller,
    PdfLibraryDocument document,
  ) {
    try {
      if (document.fileKind.isPdf) {
        controller.requestOpenReading(documentId: document.id);
      } else if (document.fileKind.isViewable) {
        controller.requestOpenDocumentView(documentId: document.id);
      } else {
        _snack('该类型请在系统默认应用中打开。');
      }
    } catch (error) {
      _snack('$error');
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
      ],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !context.mounted) {
      return;
    }
    try {
      await controller.ensurePdfLibraryLoaded();
      await controller.addWorkspaceFileFromPath(file.path);
      await controller.waitForPendingPdfPersistence();
      if (context.mounted) {
        _snack('已导入到本机文件库');
      }
    } catch (error) {
      if (context.mounted) {
        _snack('$error');
      }
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
    try {
      final message = await controller.renameLocalPdfDocument(
        document.id,
        title,
      );
      if (message != null) {
        _snack(message);
      } else {
        setState(
          () => _selectedLocal = controller.pdfDocumentById(document.id),
        );
      }
    } catch (error) {
      _snack('$error');
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
    try {
      final message = await controller.deletePdfDocument(document.id);
      setState(() => _selectedLocal = null);
      _snack(message);
    } catch (error) {
      _snack('$error');
    }
  }

  Future<void> _renameLocalFolder(
    BuildContext context,
    ResearchLifeController controller,
    PdfLibraryDocument document,
  ) async {
    final folder = Directory(document.path).parent;
    final name = await showCloudNameDialog(
      context,
      title: '重命名文件夹',
      initialValue: p.basename(folder.path),
      hint: '文件夹名称',
    );
    if (name == null || name.isEmpty || !context.mounted) {
      return;
    }
    try {
      final message = await controller.renameLocalFolder(folder.path, name);
      if (!context.mounted) {
        return;
      }
      setState(() => _selectedLocal = controller.pdfDocumentById(document.id));
      _snack(message);
    } catch (error) {
      _snack('$error');
    }
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _LocalToolbar extends StatelessWidget {
  const _LocalToolbar({
    required this.selected,
    required this.onImport,
    this.onRename,
    this.onRenameFolder,
    this.onDelete,
    this.onOpen,
    this.onPdfTools,
  });

  final PdfLibraryDocument? selected;
  final VoidCallback onImport;
  final VoidCallback? onRename;
  final VoidCallback? onRenameFolder;
  final VoidCallback? onDelete;
  final VoidCallback? onOpen;
  final VoidCallback? onPdfTools;

  @override
  Widget build(BuildContext context) {
    final canOpen =
        selected != null &&
        (selected!.fileKind.isPdf || selected!.fileKind.isViewable);
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
            onPressed: onRename,
            icon: const Icon(Icons.drive_file_rename_outline, size: 18),
            label: const Text('重命名'),
          ),
          TextButton.icon(
            onPressed: onRenameFolder,
            icon: const Icon(Icons.folder_copy_outlined, size: 18),
            label: const Text('重命名文件夹'),
          ),
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除'),
          ),
          TextButton.icon(
            onPressed: canOpen ? onOpen : null,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('打开'),
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
    required this.toolbar,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget toolbar;

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
          toolbar,
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
    return Center(child: Text(message, textAlign: TextAlign.center));
  }
}
