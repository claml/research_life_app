# Business Flows and Workbench UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete local event/folder business flows and replace the legacy flat `AppSection` sidebar with the approved Weather/Today/Research/Materials/Life/Settings workbench shell while preserving existing page state.

**Architecture:** Fix the two remaining local data transactions first. Then introduce a pure navigation model and shared page components before replacing `AppShell`; existing feature pages are adapted into workspace tabs rather than rewritten simultaneously.

**Tech Stack:** Flutter Material 3, Drift transactions, local filesystem/JSON manifests, ChangeNotifier, widget tests, golden-free Browser/Web concept comparison through Windows screenshots.

## Global Constraints

- Plan 1 must be accepted before this plan starts.
- Existing local data remains the only source of truth.
- Weather is a manual global entry, not an idle timer.
- Primary navigation order is Weather, Today, Research, Materials, Life, Settings.
- AI appears only in Research.
- Secondary navigation is a short horizontal tab row, never a second sidebar.
- Switching tabs preserves selection, filters, and scroll position.
- Copy is concise and each page has at most one primary action.
- No Git initialization; use SDD checkpoints and independent review.

---

## File Structure

**Create**

- `lib/services/storage/local_folder_service.dart` — safe directory rename and manifest path rewrite.
- `lib/app/workbench_destination.dart` — primary workspaces, secondary tabs, labels, icons, mapping to existing features.
- `lib/app/workbench_navigation_controller.dart` — pure navigation state, per-workspace tab memory, Weather snapshot.
- `lib/app/workbench_shell.dart` — new shell layout and sidebar.
- `lib/shared/widgets/page_scaffold.dart` — title, concise description, action, tabs, body.
- `lib/shared/widgets/workspace_tabs.dart` — accessible horizontal secondary tabs.
- `lib/features/workbench/today_workspace.dart`
- `lib/features/workbench/research_workspace.dart`
- `lib/features/workbench/materials_workspace.dart`
- `lib/features/workbench/life_workspace.dart`
- Tests matching each unit.

**Modify**

- `lib/services/database/repositories/manual_events_repository.dart`
- `lib/state/research_life_controller.dart`
- `lib/features/calendar/calendar_page.dart`
- `lib/services/storage/local_file_library_store.dart`
- `lib/app/research_life_app.dart`
- `lib/core/theme/app_tokens.dart`, `lib/core/theme/app_theme.dart`
- Existing feature pages only where they need embedded-mode headers/actions.

**Retire after replacement**

- `lib/app/app_shell.dart` and `lib/app/app_section.dart`, only after all cross-section navigation is mapped and tests pass.

---

### Task 1: Manual Event Delete Transaction

**Files:**
- Modify: `lib/services/database/repositories/manual_events_repository.dart`
- Modify: `lib/state/research_life_controller.dart`
- Modify: `lib/features/calendar/calendar_page.dart`
- Test: `test/manual_events_repository_test.dart`
- Test: `test/research_life_controller_test.dart`
- Test: `test/calendar_manual_event_delete_test.dart`

**Interfaces:**
- Produces: `ManualEventsRepository.deleteManualEvent(String id)`; deletes the manual event and its `todoStatus` row in one Drift transaction.
- Produces: `ResearchLifeController.deleteManualEvent(String eventId)` returning `Future<String>`.

- [ ] **Step 1: Write failing repository and controller tests**

```dart
test('deletes a manual event and its todo state atomically', () async {
  await repository.saveManualEvent(manualEvent);
  await todoRepository.upsert(
    EventTodoState(eventId: manualEvent.id, isDone: true),
  );

  await repository.deleteManualEvent(manualEvent.id);

  expect(await repository.loadManualEvents(), isEmpty);
  expect(await todoRepository.loadAll(), isNot(contains(manualEvent.id)));
});

test('controller refuses to delete imported calendar events', () async {
  final message = await controller.deleteManualEvent('institution_1');
  expect(message, '该记录不允许删除。');
});
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\manual_events_repository_test.dart test\research_life_controller_test.dart
```

- [ ] **Step 3: Implement the Drift transaction**

```dart
Future<void> deleteManualEvent(String id) {
  return _database.transaction(() async {
    await (_database.delete(_database.todoStatus)
          ..where((row) => row.eventId.equals(id)))
        .go();
    await (_database.delete(_database.events)
          ..where((row) =>
              row.id.equals(id) &
              row.origin.equals(EventOrigin.manual.name)))
        .go();
  });
}
```

- [ ] **Step 4: Implement controller state update after persistence succeeds**

```dart
Future<String> deleteManualEvent(String eventId) async {
  await ensureManualEventsLoaded();
  final eventIndex = _manualEvents.indexWhere((item) => item.id == eventId);
  if (eventIndex == -1 || !_manualEvents[eventIndex].isEditable) {
    return '该记录不允许删除。';
  }
  await _manualEventsRepository!.deleteManualEvent(eventId);
  _manualEvents = _manualEvents.where((item) => item.id != eventId).toList();
  _todoStatus = {..._todoStatus}..remove(eventId);
  notifyListeners();
  return '已删除记录。';
}
```

- [ ] **Step 5: Add the destructive UI action**

The editor dialog returns a sealed result distinguishing save, cancel, and delete. Show Delete only for editable manual events. Confirm with `确定删除“<title>”吗？` before calling the controller.

- [ ] **Step 6: Run GREEN**

```powershell
flutter test test\manual_events_repository_test.dart test\research_life_controller_test.dart test\calendar_manual_event_delete_test.dart
```

- [ ] **Step 7: Record Task 1 checkpoint and review**

---

### Task 2: Local Folder Rename with Descendant Path Rewrite

**Files:**
- Create: `lib/services/storage/local_folder_service.dart`
- Modify: `lib/services/storage/local_file_library_store.dart`
- Modify: `lib/state/research_life_controller.dart`
- Modify: `lib/features/files/my_files_page.dart`
- Test: `test/local_folder_service_test.dart`

**Interfaces:**
- Produces: `LocalFileLibraryStore.replaceDocumentPaths(Map<String, String> paths)`.
- Produces: `LocalFolderService.renameFolder({required Directory folder, required String newName})` returning `Future<Directory>`.

- [ ] **Step 1: Write failing path and rollback tests**

```dart
test('renames a folder and rewrites every descendant document path', () async {
  final oldFolder = await fixture.createFolder('资料/旧名称');
  final first = await fixture.addDocument('资料/旧名称/a.pdf');
  final second = await fixture.addDocument('资料/旧名称/子目录/b.pdf');

  final renamed = await service.renameFolder(
    folder: oldFolder,
    newName: '新名称',
  );

  expect(renamed.path, endsWith('资料${Platform.pathSeparator}新名称'));
  expect((await store.findById(first.id))!.path, endsWith('新名称/a.pdf'));
  expect((await store.findById(second.id))!.path, endsWith('新名称/子目录/b.pdf'));
});

test('manifest failure rolls the directory name back', () async {
  fixture.store.failNextWrite = true;
  await expectLater(
    service.renameFolder(folder: fixture.folder, newName: '新名称'),
    throwsA(isA<LocalFolderException>()),
  );
  expect(await fixture.folder.exists(), isTrue);
});
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\local_folder_service_test.dart
```

- [ ] **Step 3: Make manifest writes atomic**

```dart
Future<void> _writeManifest(_LibraryManifest manifest) async {
  final target = await _manifestFile();
  final pending = File('${target.path}.pending');
  await pending.writeAsString(jsonEncode(manifest.toJson()), flush: true);
  if (await target.exists()) await target.delete();
  await pending.rename(target.path);
}
```

Keep the previous manifest bytes in memory during rename so a failed path rewrite can restore them.

- [ ] **Step 4: Implement validated same-parent rename and rollback**

Reject empty names, path separators, `.`/`..`, workspace root, and an existing destination. Rename the directory first, rewrite every document path whose normalized path equals the old path or starts with `oldPath + separator`, and rename the directory back if the manifest update fails.

- [ ] **Step 5: Wire the Files UI and controller**

The dialog displays only the current folder name and one field. On success, reload the local manifest and preserve the selected document by ID.

- [ ] **Step 6: Run GREEN**

```powershell
flutter test test\local_folder_service_test.dart test\local_workspace_service_test.dart
```

- [ ] **Step 7: Record Task 2 checkpoint and review**

---

### Task 3: Pure Workbench Navigation Model

**Files:**
- Create: `lib/app/workbench_destination.dart`
- Create: `lib/app/workbench_navigation_controller.dart`
- Test: `test/workbench_navigation_controller_test.dart`

**Interfaces:**
- Produces: `enum WorkbenchWorkspace { today, research, materials, life, settings }`.
- Produces: `enum WorkbenchTab` with exact tab IDs from the spec.
- Produces: `WorkbenchNavigationController.openWeather()`, `exitWeather()`, `selectWorkspace()`, and `selectTab()`.
- Produces: `WeatherReturnSnapshot` storing workspace and per-workspace active tab.

- [ ] **Step 1: Write failing state tests**

```dart
test('Weather is manual and restores the exact previous workspace tab', () {
  final nav = WorkbenchNavigationController();
  nav.selectWorkspace(WorkbenchWorkspace.research);
  nav.selectTab(WorkbenchTab.researchNotes);

  nav.openWeather();
  expect(nav.weatherOpen, isTrue);
  nav.exitWeather();

  expect(nav.workspace, WorkbenchWorkspace.research);
  expect(nav.activeTab, WorkbenchTab.researchNotes);
});

test('tabs are remembered independently', () {
  final nav = WorkbenchNavigationController();
  nav.selectTab(WorkbenchTab.todayTodos);
  nav.selectWorkspace(WorkbenchWorkspace.materials);
  nav.selectTab(WorkbenchTab.materialsPdfTools);
  nav.selectWorkspace(WorkbenchWorkspace.today);
  expect(nav.activeTab, WorkbenchTab.todayTodos);
});
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\workbench_navigation_controller_test.dart
```

- [ ] **Step 3: Implement immutable tab configuration and controller validation**

```dart
class WeatherReturnSnapshot {
  const WeatherReturnSnapshot({
    required this.workspace,
    required this.tabs,
  });

  final WorkbenchWorkspace workspace;
  final Map<WorkbenchWorkspace, WorkbenchTab> tabs;
}

static const tabsByWorkspace = <WorkbenchWorkspace, List<WorkbenchTab>>{
  WorkbenchWorkspace.today: [
    WorkbenchTab.todayOverview,
    WorkbenchTab.todayCalendar,
    WorkbenchTab.todayTodos,
  ],
  WorkbenchWorkspace.research: [
    WorkbenchTab.researchOverview,
    WorkbenchTab.researchReading,
    WorkbenchTab.researchNotes,
    WorkbenchTab.researchAnalysis,
    WorkbenchTab.researchPersons,
    WorkbenchTab.researchStats,
  ],
  WorkbenchWorkspace.materials: [
    WorkbenchTab.materialsFiles,
    WorkbenchTab.materialsDocumentView,
    WorkbenchTab.materialsPdfTools,
  ],
  WorkbenchWorkspace.life: [
    WorkbenchTab.lifeCampus,
    WorkbenchTab.lifePet,
    WorkbenchTab.lifePersonalization,
  ],
  WorkbenchWorkspace.settings: [WorkbenchTab.settingsOverview],
};
```

Reject tabs that do not belong to the current workspace without notifying listeners.

- [ ] **Step 4: Run GREEN and record checkpoint**

```powershell
flutter test test\workbench_navigation_controller_test.dart
```

---

### Task 4: Shared Page Scaffold and Tabs

**Files:**
- Create: `lib/shared/widgets/page_scaffold.dart`
- Create: `lib/shared/widgets/workspace_tabs.dart`
- Modify: `lib/core/theme/app_tokens.dart`
- Modify: `lib/core/theme/app_theme.dart`
- Test: `test/page_scaffold_test.dart`

**Interfaces:**
- Produces: `PageScaffold(title, description, tabs, primaryAction, body)`.
- Produces: `WorkspaceTabs(items, selected, onSelected)`.

- [ ] **Step 1: Write failing widget tests**

```dart
testWidgets('renders one concise description and one primary action', (tester) async {
  await tester.pumpWidget(testApp(
    PageScaffold(
      title: '科研',
      description: '阅读、整理与复盘。',
      tabs: tabs,
      primaryAction: FilledButton(onPressed: () {}, child: const Text('AI 助手')),
      body: const SizedBox(),
    ),
  ));
  expect(find.text('科研'), findsOneWidget);
  expect(find.text('阅读、整理与复盘。'), findsOneWidget);
  expect(find.byType(FilledButton), findsOneWidget);
});
```

Add keyboard tests for Left/Right tab movement and visible focus.

- [ ] **Step 2: Run RED**

```powershell
flutter test test\page_scaffold_test.dart
```

- [ ] **Step 3: Implement the shared widgets**

Use a 138px desktop header target, 24–32px outer content padding, 8px spacing grid, horizontal scroll for tabs, and `Semantics(selected: true, button: true)`. Do not insert explanatory copy inside every card.

- [ ] **Step 4: Run GREEN and record checkpoint**

---

### Task 5: Workbench Shell and Sidebar

**Files:**
- Create: `lib/app/workbench_shell.dart`
- Modify: `lib/app/research_life_app.dart`
- Test: `test/workbench_shell_test.dart`

**Interfaces:**
- Consumes: `WorkbenchNavigationController` and workspace widgets from Task 6.
- Produces: primary navigation, collapse state, search action, Settings footer, manual Weather entry, Escape return.

- [ ] **Step 1: Write failing shell tests**

```dart
testWidgets('shows the approved primary navigation order', (tester) async {
  await tester.pumpWidget(testWorkbenchShell());
  final labels = tester
      .widgetList<Semantics>(find.byType(Semantics))
      .map((widget) => widget.properties.label)
      .whereType<String>()
      .toList();
  expect(labels, containsAllInOrder(['天气', '今天', '科研', '资料', '生活', '设置']));
});

testWidgets('Escape exits only Weather and restores focus to Weather entry', (tester) async {
  await tester.pumpWidget(testWorkbenchShell());
  await tester.tap(find.bySemanticsLabel('天气'));
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.bySemanticsLabel('今天'), findsOneWidget);
  expect(FocusManager.instance.primaryFocus?.debugLabel, contains('weather-entry'));
});
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\workbench_shell_test.dart
```

- [ ] **Step 3: Implement responsive shell geometry**

Expanded sidebar target 224px; collapsed 80px; at `maxWidth <= 1040`, force compact 80px. Every compact icon uses `Tooltip`, `Semantics`, and a stable `FocusNode`. The sidebar state persists while switching workspaces.

- [ ] **Step 4: Implement manual Weather and focus restoration**

Store the Weather entry focus node. Before opening Weather, record the navigation snapshot; on Escape or Return, restore state and request focus after the frame.

- [ ] **Step 5: Run GREEN at desktop and compact constraints**

```powershell
flutter test test\workbench_shell_test.dart
```

Add tests with `tester.view.physicalSize` representing 1280×800 and 980×800 and assert no overflow exceptions.

- [ ] **Step 6: Record checkpoint and independent review**

---

### Task 6: Workspace Adapters and Existing Page Migration

**Files:**
- Create: `lib/features/workbench/today_workspace.dart`
- Create: `lib/features/workbench/research_workspace.dart`
- Create: `lib/features/workbench/materials_workspace.dart`
- Create: `lib/features/workbench/life_workspace.dart`
- Modify existing pages to accept `embedded: true` where they currently render their own top-level header.
- Test: `test/workbench_workspaces_test.dart`

**Interfaces:**
- Produces each workspace as a state-preserving `IndexedStack` keyed by `WorkbenchTab`.
- Maps cross-page requests from Reading/Document/PDF directly to the matching workspace tab.

- [ ] **Step 1: Write failing tab/content mapping tests**

```dart
testWidgets('AI action exists only in Research', (tester) async {
  await tester.pumpWidget(testAllWorkspaces());
  expect(find.text('AI 助手'), findsOneWidget);
  expect(find.descendant(of: find.byKey(const Key('materials-workspace')), matching: find.text('AI 助手')), findsNothing);
});

testWidgets('Materials selection survives Document View and Files tabs', (tester) async {
  final nav = WorkbenchNavigationController();
  await tester.pumpWidget(testMaterialsWorkspace(nav));
  await tester.tap(find.text('交互线索观察稿.pdf'));
  await tester.tap(find.text('文档查看'));
  await tester.tap(find.text('文件'));
  expect(find.byKey(const Key('selected-material-row')), findsOneWidget);
});
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\workbench_workspaces_test.dart
```

- [ ] **Step 3: Implement Today and Research adapters**

Today Overview composes the existing calendar/timeline source and todo source without duplicating repositories. Research Overview shows recent reading, notes to organize, weekly plan, and analysis entry; the single AI action opens the Research AI view/dialog.

- [ ] **Step 4: Implement Materials and Life adapters**

Materials keeps one selected document ID above tab content. Life maps Campus, pet controls, and personalization. Global Settings remains a primary workspace and is not duplicated inside Life.

- [ ] **Step 5: Replace old cross-section navigation**

Map `ReadingOpenRequest`, `DocumentViewOpenRequest`, and `PdfToolsOpenRequest` to `WorkbenchWorkspace.materials` plus the matching tab, preserving the requested local document ID.

- [ ] **Step 6: Run GREEN and retire legacy shell**

```powershell
flutter test test\workbench_workspaces_test.dart test\workbench_shell_test.dart test\workbench_navigation_controller_test.dart
```

Only after zero imports remain, delete `app_shell.dart` and `app_section.dart`, then rerun `rg -n "AppSection|AppShell" lib test` and expect no production references.

- [ ] **Step 7: Record checkpoint and review**

---

### Task 7: Plan 2 Integration and Visual Gate

- [ ] **Step 1: Run complete automated verification**

```powershell
flutter analyze
flutter test
```

- [ ] **Step 2: Run Windows interaction paths**

Verify Today → Research → Notes → Weather → Escape; Materials selection → Document View → Files; collapse → Life → Settings → expand; reduce transparency → Weather.

- [ ] **Step 3: Capture native 1280×800 and 980×800 screenshots**

Capture Weather only as a temporary placeholder at this stage; compare Today, Research, and Materials against accepted Web concepts at original detail. Check shared shell geometry, color, hierarchy, spacing, typography, action placement, and copy differences.

- [ ] **Step 4: Request whole-plan review**

Do not begin Plan 3 until there are no Critical or Important findings.
