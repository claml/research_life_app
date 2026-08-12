import 'package:flutter/material.dart';

import '../../app/workbench_destination.dart';
import '../../app/workbench_navigation_controller.dart';
import '../document_view/document_viewer_page.dart';
import '../files/my_files_page.dart';
import '../pdf_tools/pdf_tools_page.dart';
import 'workbench_workspace_frame.dart';

class MaterialsWorkspace extends StatelessWidget {
  const MaterialsWorkspace({required this.navigation, this.pages, super.key});

  final WorkbenchNavigationController navigation;
  final Map<WorkbenchTab, Widget>? pages;

  @override
  Widget build(BuildContext context) {
    return WorkbenchWorkspaceFrame(
      key: const Key('materials-workspace'),
      workspace: WorkbenchWorkspace.materials,
      navigation: navigation,
      pages:
          pages ??
          const {
            WorkbenchTab.materialsFiles: MyFilesPage(),
            WorkbenchTab.materialsDocumentView: DocumentViewerPage(),
            WorkbenchTab.materialsPdfTools: PdfToolsPage(),
          },
    );
  }
}
