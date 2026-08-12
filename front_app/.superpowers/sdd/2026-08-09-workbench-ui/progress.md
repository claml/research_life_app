# Workbench UI implementation progress

## Task 1 — Manual event deletion

- Status: completed
- RED: repository and controller tests failed because `deleteManualEvent` did not exist; widget test then failed because the editor had no Delete action.
- GREEN: `flutter test --no-pub test\calendar_manual_event_delete_test.dart test\manual_events_repository_test.dart test\research_life_controller_test.dart` — 51/51 passed.
- Behavior: manual event and todo state are deleted in one Drift transaction; imported events are refused; the calendar editor exposes Delete only for manual events and requires explicit confirmation.
- Files: `manual_events_repository.dart`, `research_life_controller.dart`, `calendar_page.dart`, and three focused test files.

## Task 2 — Local folder rename

- Status: completed
- RED: service/store interfaces and controller injection were absent; the file-page widget then lacked a folder rename entry.
- GREEN: `flutter test --no-pub test\my_files_folder_rename_test.dart test\local_folder_service_test.dart test\local_workspace_service_test.dart test\local_app_runtime_test.dart` — 27/27 passed.
- Behavior: same-parent managed folder rename runs under the shared write coordinator, rewrites all descendant manifest paths once, and restores the original directory on manifest failure. The Files page opens a folder-name-only dialog from the selected document and keeps selection keyed by document ID.
- Incidental UI correction: local `ListTile` rows now have a transparent `Material` ancestor so selection and ink feedback remain visible.

## Task 3 — Workbench navigation state

- Status: completed
- GREEN: `flutter test --no-pub test/workbench_navigation_controller_test.dart` — 5/5 passed.
- Behavior: five primary workspaces remember their own tab, Weather is manual and restores the exact prior state, and controller-driven navigation can atomically close Weather and open a requested tab.

## Task 4 — Shared page scaffold and tabs

- Status: completed
- GREEN: `flutter test --no-pub test/page_scaffold_test.dart` — 2/2 passed.
- Behavior: concise page header, single primary action, horizontally scrolling tabs, selected semantics, visible focus, and Left/Right keyboard movement.

## Task 5 — Workbench shell and sidebar

- Status: completed
- GREEN: `flutter test --no-pub test/workbench_shell_test.dart` — 3/3 passed.
- Behavior: approved primary order, 224/80 responsive sidebar, 980px forced compact mode, manual Weather entry, Escape return, stable focus, and retained workspace state.

## Task 6 — Workspace adapters and production migration

- Status: completed
- GREEN: focused navigation/scaffold/shell/workspace suite — 13/13 passed; production-shell suite — 2/2 passed.
- Production entry now uses `PinLockGate(child: WorkbenchShell())`; legacy `AppShell`, `AppSection`, and `AuthGate` files were removed.
- Added Today, Research, Materials, Life, and Settings workspace adapters with state-preserving `IndexedStack` pages. Controller requests route Reading, Document View, and PDF Tools into their new tabs.
- Global search now emits `WorkbenchTab` destinations instead of the removed legacy section enum.
- Native QA found and fixed an unbounded-height `Spacer` in the Research overview; the regression is covered by a real production-shell widget test.

## Task 7 — Visual and Weather gate

- Status: in progress
- Added `assets/weather/cloudscape.png`, generated with built-in ImageGen from the accepted Weather concept as a clean UI-free cloudscape.
- Weather standby now keeps the static cloudscape when motion is disabled and layers only a restrained atmospheric animation when enabled. The glass panel follows the accepted left-card composition.
- GREEN: `weather_standby_test.dart`, `workbench_production_shell_test.dart`, and `workbench_shell_test.dart` — 6/6 passed.
- Native Windows debug build launches without logged Flutter exceptions. Direct visual review is currently gated by the user's PIN lock screen; no attempt was made to read or bypass the PIN.
- `dart analyze` completed with the existing one test warning plus seven style/deprecation infos and no new compile errors.
