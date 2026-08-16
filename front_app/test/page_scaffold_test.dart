import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/workbench_destination.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/shared/widgets/page_scaffold.dart';
import 'package:research_life/shared/widgets/workspace_tabs.dart';

void main() {
  testWidgets('renders one concise description and one primary action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        PageScaffold(
          title: '科研',
          description: '整理阅读、笔记与每周分析。',
          tabs: WorkspaceTabs<WorkbenchTab>(
            items: const [
              WorkspaceTabItem(
                value: WorkbenchTab.researchOverview,
                label: '概览',
              ),
              WorkspaceTabItem(value: WorkbenchTab.researchNotes, label: '笔记'),
            ],
            selected: WorkbenchTab.researchOverview,
            onSelected: (_) {},
          ),
          primaryAction: FilledButton(
            onPressed: () {},
            child: const Text('AI 助手'),
          ),
          body: const SizedBox(key: Key('page-body')),
        ),
      ),
    );

    expect(find.text('科研'), findsOneWidget);
    expect(find.text('整理阅读、笔记与每周分析。'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byKey(const Key('page-body')), findsOneWidget);
  });

  testWidgets('arrow keys move focus and selection across workspace tabs', (
    tester,
  ) async {
    var selected = WorkbenchTab.todayOverview;
    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder: (context, setState) => WorkspaceTabs<WorkbenchTab>(
            items: const [
              WorkspaceTabItem(value: WorkbenchTab.todayOverview, label: '今天'),
              WorkspaceTabItem(value: WorkbenchTab.materialsFiles, label: '文件'),
              WorkspaceTabItem(
                value: WorkbenchTab.materialsPdfTools,
                label: 'PDF 工具',
              ),
            ],
            selected: selected,
            onSelected: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );
    final firstFocus = tester.widget<Focus>(
      find.byKey(const ValueKey(WorkbenchTab.todayOverview)),
    );
    firstFocus.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(selected, WorkbenchTab.materialsFiles);
    final fileSemantics = tester.getSemantics(find.bySemanticsLabel('文件'));
    expect(fileSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(
      tester
          .widget<Focus>(
            find.byKey(const ValueKey(WorkbenchTab.materialsFiles)),
          )
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );
}
