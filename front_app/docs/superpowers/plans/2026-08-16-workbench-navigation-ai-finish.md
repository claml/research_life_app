# Workbench Navigation and AI Finish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish, verify, document, and commit the existing `feature/local-runtime` changes that promote AI and Calendar to global destinations, consolidate Today, move Analysis and Persons to Life, and persist user-visible AI thinking progress.

**Architecture:** Keep `WorkbenchNavigationController` as the single owner of mutually exclusive global-destination state and per-workspace tab memory. Keep AI progress as versioned JSON in the existing `reasoningContent` column, coordinated by `AgentController` and rendered by `AgentPage`, without exposing provider reasoning. Preserve existing repositories and controllers; do not introduce dependencies or schema migrations.

**Tech Stack:** Flutter 3.44.x, Dart, Drift/SQLite, `flutter_test`, Windows desktop build.

## Global Constraints

- Work only in `D:/Vibe Coding/研究生活/research-life-app/.worktrees/local-runtime` on `feature/local-runtime`.
- Preserve unrelated user changes and stage only the files named by each task.
- Do not commit `.qa/`, `front_app/.run_logs/`, build outputs, screenshots, credentials, API keys, Authorization headers, or user conversation text.
- Do not add dependencies or database migrations.
- Weather, AI, and Calendar are mutually exclusive global destinations.
- Today has one integrated page; Research owns Overview/Reading/Notes/Stats; Life owns Campus/Analysis/Persons.
- Provider-internal reasoning is never rendered or persisted as the application thinking trace.
- Because implementation and tests already exist in the dirty worktree, use the existing changed tests as the recovered RED/GREEN history. Add characterization coverage before changing any behavior that is not already asserted.
- Every commit must pass its targeted test command before the next task begins.

---

## File Map

- `front_app/lib/services/agent/agent_models.dart`: typed encoding and tolerant decoding of local thinking traces.
- `front_app/lib/services/database/repositories/agent_chat_repository.dart`: atomic update of a message's `reasoningContent`.
- `front_app/lib/features/agent/state/agent_controller.dart`: transition thinking traces through active, completed, failed, and stopped states.
- `front_app/lib/features/agent/agent_page.dart`: embedded AI layout and expandable thinking-trace presentation.
- `front_app/lib/app/workbench_destination.dart`: authoritative workspace/tab ownership.
- `front_app/lib/app/workbench_navigation_controller.dart`: global destination exclusivity and per-workspace tab memory.
- `front_app/lib/app/workbench_shell.dart`: sidebar entries and retained content hosts for Weather, AI, Calendar, and workspaces.
- `front_app/lib/features/workbench/today_workspace.dart`: integrated schedule and todo view.
- `front_app/lib/features/workbench/research_workspace.dart`: Research tabs and cross-workspace Analysis navigation.
- `front_app/lib/features/workbench/life_workspace.dart`: Campus, Analysis, and Persons tabs.
- `front_app/lib/features/search/search_page.dart`: Calendar result routing to the global destination.
- `front_app/test/agent_controller_test.dart`, `front_app/test/agent_page_test.dart`, `front_app/test/agent_models_test.dart`: AI state, persistence, decoding, and UI coverage.
- `front_app/test/workbench_navigation_controller_test.dart`, `front_app/test/workbench_shell_test.dart`, `front_app/test/workbench_workspaces_test.dart`, `front_app/test/workbench_production_shell_test.dart`, `front_app/test/local_only_pages_test.dart`, `front_app/test/page_scaffold_test.dart`: information architecture and layout coverage.
- `front_app/docs/user_guide.md`, `front_app/docs/project_context_for_consulting.md`, `front_app/docs/visual-qa-2026-08-12.md`: user-facing navigation and final verification record.
- `.gitignore`: local QA and run-log exclusions.

---

### Task 1: Complete AI Thinking Trace Persistence and Embedded Presentation

**Files:**
- Create: `front_app/test/agent_models_test.dart`
- Modify: `front_app/lib/services/agent/agent_models.dart`
- Modify: `front_app/lib/services/database/repositories/agent_chat_repository.dart`
- Modify: `front_app/lib/features/agent/state/agent_controller.dart`
- Modify: `front_app/lib/features/agent/agent_page.dart`
- Test: `front_app/test/agent_models_test.dart`
- Test: `front_app/test/agent_controller_test.dart`
- Test: `front_app/test/agent_page_test.dart`

**Interfaces:**
- Consumes: `AgentChatMessage.reasoningContent`, `AgentChatStore`, `AgentController.messages`, and the existing Drift `agent_chat_messages.reasoning_content` column.
- Produces: `AgentThinkingStatus`, `AgentThinkingTrace.encode()`, `AgentThinkingTrace.tryDecode(String?)`, `AgentChatStore.updateMessageReasoningContent(...)`, and `AgentPage({bool embedded = false})`.

- [ ] **Step 1: Record the current targeted baseline**

Run:

```powershell
cd 'D:\Vibe Coding\研究生活\research-life-app\.worktrees\local-runtime\front_app'
flutter test test/agent_controller_test.dart test/agent_page_test.dart
```

Expected: the command either reports the remaining failures in the recovered dirty worktree or completes successfully. Save the exact failing test names; do not change production code before reading the complete failure output.

- [ ] **Step 2: Add codec characterization tests**

Create `test/agent_models_test.dart` with these cases:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/agent/agent_models.dart';

void main() {
  test('thinking trace round-trips status and ordered steps', () {
    const trace = AgentThinkingTrace(
      status: AgentThinkingStatus.completed,
      steps: ['已保存用户消息', '已整理对话上下文', '已生成回复'],
    );

    final decoded = AgentThinkingTrace.tryDecode(trace.encode());

    expect(decoded?.status, AgentThinkingStatus.completed);
    expect(decoded?.steps, trace.steps);
  });

  test('thinking trace ignores foreign and malformed reasoning content', () {
    expect(AgentThinkingTrace.tryDecode(null), isNull);
    expect(AgentThinkingTrace.tryDecode('provider reasoning'), isNull);
    expect(AgentThinkingTrace.tryDecode('{"kind":"other"}'), isNull);
    expect(
      AgentThinkingTrace.tryDecode(
        '{"kind":"research_life_thinking_trace","version":1,'
        '"status":"unknown","steps":["step"]}',
      ),
      isNull,
    );
  });
}
```

- [ ] **Step 3: Run the codec test before editing the codec**

Run:

```powershell
flutter test test/agent_models_test.dart
```

Expected: PASS if the recovered codec is already correct. If it fails, the failure must identify round-trip loss or acceptance of foreign/malformed content.

- [ ] **Step 4: Make the codec and repository contract exact**

Keep the trace envelope versioned and reject foreign content:

```dart
enum AgentThinkingStatus { active, completed, failed, stopped }

final class AgentThinkingTrace {
  const AgentThinkingTrace({required this.status, required this.steps});

  static const _kind = 'research_life_thinking_trace';

  final AgentThinkingStatus status;
  final List<String> steps;

  String encode() => jsonEncode({
    'kind': _kind,
    'version': 1,
    'status': status.name,
    'steps': steps,
  });
}
```

The store update must remain a coordinated database write and return the refreshed domain message:

```dart
Future<domain.AgentChatMessage> updateMessageReasoningContent({
  required int messageId,
  required String? reasoningContent,
});
```

```dart
return _operationCoordinator.runExclusive(() async {
  await (_database.update(
    _database.agentChatMessages,
  )..where((message) => message.id.equals(messageId))).write(
    db.AgentChatMessagesCompanion(
      reasoningContent: Value(reasoningContent),
    ),
  );
  return _messageById(messageId);
});
```

- [ ] **Step 5: Make controller transitions deterministic**

Ensure the user message receives these terminal mappings:

```dart
AgentThinkingStatus.completed // assistant response persisted
AgentThinkingStatus.failed    // request or local-context read failed
AgentThinkingStatus.stopped   // cancellation became sticky
```

Use `_setThinkingTrace` to attempt durable storage, then replace the in-memory message with an equivalent message containing `trace.encode()` if the trace-only update fails. Do not replace or discard the user's message content.

- [ ] **Step 6: Keep provider reasoning private and render only local traces**

In `agent_page.dart`, decode only user-message traces:

```dart
final trace = message.isUser
    ? AgentThinkingTrace.tryDecode(message.reasoningContent)
    : null;
```

Keep active traces expanded initially, make terminal traces expandable, and map terminal labels to `思考完成`, `生成失败`, and `已停止`. `AgentPage(embedded: true)` must suppress only the full-screen close/back control; settings, history, composer, send, cancel, and retry remain reachable.

- [ ] **Step 7: Run the AI target suite**

Run:

```powershell
dart format lib/services/agent/agent_models.dart lib/services/database/repositories/agent_chat_repository.dart lib/features/agent/state/agent_controller.dart lib/features/agent/agent_page.dart test/agent_models_test.dart test/agent_controller_test.dart test/agent_page_test.dart
flutter test test/agent_models_test.dart test/agent_controller_test.dart test/agent_page_test.dart
```

Expected: all selected tests pass with exit code 0.

- [ ] **Step 8: Commit the AI unit**

```powershell
git add front_app/lib/services/agent/agent_models.dart front_app/lib/services/database/repositories/agent_chat_repository.dart front_app/lib/features/agent/state/agent_controller.dart front_app/lib/features/agent/agent_page.dart front_app/test/agent_models_test.dart front_app/test/agent_controller_test.dart front_app/test/agent_page_test.dart
git diff --cached --check
git commit -m "feat: persist visible AI thinking progress"
```

---

### Task 2: Complete the Global Navigation and Workspace Ownership Change

**Files:**
- Modify: `front_app/lib/app/workbench_destination.dart`
- Modify: `front_app/lib/app/workbench_navigation_controller.dart`
- Modify: `front_app/lib/app/workbench_shell.dart`
- Modify: `front_app/lib/features/search/search_page.dart`
- Modify: `front_app/lib/features/workbench/today_workspace.dart`
- Modify: `front_app/lib/features/workbench/research_workspace.dart`
- Modify: `front_app/lib/features/workbench/life_workspace.dart`
- Test: `front_app/test/workbench_navigation_controller_test.dart`
- Test: `front_app/test/workbench_shell_test.dart`
- Test: `front_app/test/workbench_workspaces_test.dart`
- Test: `front_app/test/workbench_production_shell_test.dart`
- Test: `front_app/test/local_only_pages_test.dart`
- Test: `front_app/test/page_scaffold_test.dart`

**Interfaces:**
- Consumes: `AgentPage({embedded: true})`, `CalendarPage`, `ResearchLifeController.todayTodoEvents`, `pendingTodoEvents`, `completedTodoEvents`, `toggleTodoDone`, and `setTodoPriority`.
- Produces: `WorkbenchNavigationController.openAi()`, `openCalendar()`, `aiOpen`, `calendarOpen`, the revised `WorkbenchTab` ownership map, and optional `SearchPage.onOpenCalendar`.

- [ ] **Step 1: Add one controller test for complete mutual exclusion**

Append this test to `test/workbench_navigation_controller_test.dart`:

```dart
test('standalone destinations are mutually exclusive and tabs close them', () {
  final navigation = WorkbenchNavigationController();
  addTearDown(navigation.dispose);

  navigation.openWeather();
  expect(navigation.weatherOpen, isTrue);

  navigation.openCalendar();
  expect(navigation.weatherOpen, isFalse);
  expect(navigation.calendarOpen, isTrue);

  navigation.openAi();
  expect(navigation.calendarOpen, isFalse);
  expect(navigation.aiOpen, isTrue);

  navigation.navigateToTab(WorkbenchTab.lifeAnalysis);
  expect(navigation.aiOpen, isFalse);
  expect(navigation.workspace, WorkbenchWorkspace.life);
  expect(navigation.activeTab, WorkbenchTab.lifeAnalysis);
});
```

- [ ] **Step 2: Run the navigation test**

Run:

```powershell
flutter test test/workbench_navigation_controller_test.dart
```

Expected: PASS if the recovered controller already implements all transitions; otherwise FAIL on the first stale global-destination flag.

- [ ] **Step 3: Lock the authoritative tab map**

`WorkbenchWorkspace.tabs` must resolve exactly to:

```dart
WorkbenchWorkspace.today => const [WorkbenchTab.todayOverview],
WorkbenchWorkspace.research => const [
  WorkbenchTab.researchOverview,
  WorkbenchTab.researchReading,
  WorkbenchTab.researchNotes,
  WorkbenchTab.researchStats,
],
WorkbenchWorkspace.materials => const [
  WorkbenchTab.materialsFiles,
  WorkbenchTab.materialsPdfTools,
],
WorkbenchWorkspace.life => const [
  WorkbenchTab.lifeCampus,
  WorkbenchTab.lifeAnalysis,
  WorkbenchTab.lifePersons,
],
WorkbenchWorkspace.settings => const [WorkbenchTab.settingsOverview],
```

Remove the obsolete `todayCalendar`, `todayTodos`, `researchAnalysis`, and `researchPersons` enum cases and update every switch exhaustively.

- [ ] **Step 4: Keep global destinations mutually exclusive in the controller**

Every `selectWorkspace`, `selectTab`, and `navigateToTab` path must set all three global flags to false. Each global opener must set exactly one true:

```dart
void openAi() {
  if (aiOpen && !weatherOpen && !calendarOpen) return;
  _weatherOpen = false;
  _calendarOpen = false;
  _aiOpen = true;
  notifyListeners();
}
```

Use the same shape for Weather and Calendar with their own flag as the single true value.

- [ ] **Step 5: Finish retained content hosting and sidebar routing**

In `WorkbenchShell`, keep optional builders for isolated widget tests and production builders for real pages:

```dart
typedef WorkbenchCalendarBuilder = Widget Function(BuildContext context);
typedef WorkbenchAgentBuilder = Widget Function(BuildContext context);

Widget _buildProductionCalendar(BuildContext context) => const CalendarPage();
Widget _buildProductionAgent(BuildContext context) =>
    const AgentPage(embedded: true);
```

Create Calendar and AI content only after first visit, then retain them with `Offstage`, `IgnorePointer`, and `TickerMode`. Sidebar order must remain Weather, AI, Calendar, Today, Research, Materials, Life, with Settings anchored at the bottom.

- [ ] **Step 6: Finish workspace composition**

Use these page maps:

```dart
// Today
WorkbenchTab.todayOverview: _TodayOverview(onQuickCapture: onQuickCapture)

// Life
WorkbenchTab.lifeCampus: CampusMapPage(),
WorkbenchTab.lifeAnalysis: AnalysisPage(),
WorkbenchTab.lifePersons: PersonsPage(),
```

Research must not construct `AgentPage`, `AnalysisPage`, or `PersonsPage`. Its overview action for weekly analysis must call:

```dart
navigation.navigateToTab(WorkbenchTab.lifeAnalysis)
```

The integrated Today todo list must sort pending items by descending `TodoPriority` rank and then ascending `startAt`, expose `toggleTodoDone` and `setTodoPriority`, and keep completed items behind an initially collapsed header.

- [ ] **Step 7: Route Calendar search results through the global destination**

Keep `SearchPage.onOpenCalendar` optional. In the production search dialog, close the dialog before invoking `_openCalendar()`:

```dart
onOpenCalendar: () {
  Navigator.of(dialogContext).pop();
  _openCalendar();
},
```

- [ ] **Step 8: Run the information-architecture target suite**

Run:

```powershell
dart format lib/app/workbench_destination.dart lib/app/workbench_navigation_controller.dart lib/app/workbench_shell.dart lib/features/search/search_page.dart lib/features/workbench/today_workspace.dart lib/features/workbench/research_workspace.dart lib/features/workbench/life_workspace.dart test/workbench_navigation_controller_test.dart test/workbench_shell_test.dart test/workbench_workspaces_test.dart test/workbench_production_shell_test.dart test/local_only_pages_test.dart test/page_scaffold_test.dart
flutter test test/workbench_navigation_controller_test.dart test/workbench_shell_test.dart test/workbench_workspaces_test.dart test/workbench_production_shell_test.dart test/local_only_pages_test.dart test/page_scaffold_test.dart
```

Expected: all selected tests pass with exit code 0 and no layout exception at 1280px, 980px, or the existing narrow-page constraints.

- [ ] **Step 9: Commit the navigation unit**

```powershell
git add front_app/lib/app/workbench_destination.dart front_app/lib/app/workbench_navigation_controller.dart front_app/lib/app/workbench_shell.dart front_app/lib/features/search/search_page.dart front_app/lib/features/workbench/today_workspace.dart front_app/lib/features/workbench/research_workspace.dart front_app/lib/features/workbench/life_workspace.dart front_app/test/workbench_navigation_controller_test.dart front_app/test/workbench_shell_test.dart front_app/test/workbench_workspaces_test.dart front_app/test/workbench_production_shell_test.dart front_app/test/local_only_pages_test.dart front_app/test/page_scaffold_test.dart
git diff --cached --check
git commit -m "feat: promote calendar and AI to global navigation"
```

---

### Task 3: Align Documentation, Ignore Local Artifacts, and Run Final Verification

**Files:**
- Modify: `.gitignore`
- Modify: `front_app/docs/user_guide.md`
- Modify: `front_app/docs/project_context_for_consulting.md`
- Modify: `front_app/docs/visual-qa-2026-08-12.md`
- Verify: all tracked files changed by Tasks 1 and 2

**Interfaces:**
- Consumes: the final navigation labels, ownership map, AI trace behavior, and verification command output.
- Produces: accurate user documentation, ignored local QA artifacts, and a reproducible final verification record.

- [ ] **Step 1: Ignore only the known local artifact directories**

Add these root-relative entries to `.gitignore`:

```gitignore
/.qa/
/front_app/.run_logs/
```

Do not ignore all ZIP, PNG, or log files globally because tracked product assets and documentation images may use those extensions.

- [ ] **Step 2: Update the user-facing navigation description**

In `front_app/docs/user_guide.md`, make the primary navigation list and page table state:

```text
全局入口：天气、AI 助手、日历
今日：今日时间线、未完成待办、优先级和已完成事项
科研：概览、文献、笔记、统计
生活：校园、周分析、人物
```

State that AI history and visible progress are stored locally, while provider-internal reasoning is not displayed.

- [ ] **Step 3: Update technical context without rewriting historical specs**

In `front_app/docs/project_context_for_consulting.md`, replace stale navigation ownership statements with the same authoritative map. Leave the dated 2026-08-09 and 2026-08-11 specs intact; the 2026-08-16 design document records their superseded clauses.

- [ ] **Step 4: Run formatting and verify it creates no unexpected files**

Run:

```powershell
cd 'D:\Vibe Coding\研究生活\research-life-app\.worktrees\local-runtime\front_app'
dart format lib test
git -C .. status --short
```

Expected: formatting succeeds. The status contains only the intended source, test, documentation, and `.gitignore` paths; `.qa/` and `front_app/.run_logs/` no longer appear.

- [ ] **Step 5: Run the complete Flutter test suite**

Run:

```powershell
flutter test
```

Expected: exit code 0 and the final line reports all tests passed.

- [ ] **Step 6: Run static analysis**

Run:

```powershell
dart analyze
```

Expected: exit code 0, no error, and no warning. Record any remaining info diagnostics verbatim in the QA document; do not describe them as new warnings.

- [ ] **Step 7: Build the Windows Debug application**

Run:

```powershell
flutter build windows --debug
```

Expected: exit code 0 and `build\windows\x64\runner\Debug\research_life.exe` exists.

- [ ] **Step 8: Perform the bounded Windows smoke check when desktop control is available**

Launch the Debug executable and check only these behaviors:

1. Weather, AI, and Calendar select independently and leave the main sidebar visible.
2. Returning to a workspace closes the global destination and restores its last tab.
3. Today shows one integrated page with quick capture and todo controls.
4. Life exposes Campus, Analysis, and Persons; Research does not duplicate Analysis, Persons, or AI.
5. AI history collapses to 60px, settings/composer remain reachable, and embedded mode has no full-screen back button.

If desktop control is unavailable, record that limitation without claiming a manual pass.

- [ ] **Step 9: Append fresh verification evidence**

Add a dated `2026-08-16` section to `front_app/docs/visual-qa-2026-08-12.md` containing the exact test count, analyzer error/warning/info counts, Windows build result, and each smoke-check result or limitation.

- [ ] **Step 10: Commit documentation and artifact hygiene**

```powershell
cd 'D:\Vibe Coding\研究生活\research-life-app\.worktrees\local-runtime'
git add .gitignore front_app/docs/user_guide.md front_app/docs/project_context_for_consulting.md front_app/docs/visual-qa-2026-08-12.md
git diff --cached --check
git commit -m "docs: align workbench navigation guidance"
```

- [ ] **Step 11: Verify the final branch state**

Run:

```powershell
git status --short --branch
git log -4 --oneline --decorate
```

Expected: no modified or untracked task files remain, `feature/local-runtime` is ahead of its remote by the new local commits, and the most recent commits separately represent the design, AI unit, navigation unit, and documentation/verification unit.
