# Task 3 Independent Review

Date: 2026-08-09

Reviewed scope:

- Task 3 in `docs/superpowers/plans/2026-08-09-local-runtime-implementation.md`
- `.superpowers/sdd/2026-08-09-local-runtime/task-3-report.md`
- `lib/app/local_app_runtime.dart`
- `lib/app/local_services_scope.dart`
- `lib/app/research_life_app.dart`
- `lib/services/tray/tray_service.dart`
- the persistence boundary in `lib/state/research_life_controller.dart`
- `test/local_app_runtime_test.dart`
- the complete current working diff relevant to Task 3

Supplied verification: Task 3 tests pass 6/6, Task 3 plus auth regression passes 8/8, the full suite passes 214/214, and `dart analyze` reports only the six stated baseline findings. The review did not rerun commands that generate build artifacts.

## Strengths

- `LocalAppRuntime.open()` constructs the database and local repositories without constructing `AuthController`, `SyncOutboxRepository`, `CloudFileService`, `DeviceIdService`, or `FileSyncEngine`. `PdfDocumentsRepository` receives a local store and no outbox/device reader.
- The production startup tree is directly `LocalServicesScope -> ResearchLifeScope -> MaterialApp -> PinLockGate -> AppShell`; neither `AuthGate` nor `AuthScope` is in the root path.
- Startup creates and validates the one-time migration backup before loading mutable local runtime state.
- `ResearchLifeController.flushLocalPersistence()` is the single public persistence boundary and waits for session, manual-event, todo-status, campus-place, and PDF queues.
- The successful restore order is flush current runtime, close it, restore files with the closed runtime's workspace-owned backup service, open a replacement runtime, then install the replacement scope.
- Successful runtime replacement is compatible with Task 2's terminal restore handoff: the old backup controller may be disposed without a later notification or old-service refresh.
- Tray initialization is represented by a future, and normal `LocalAppRuntime.close()` waits for it before removing tray/window listeners, disposing controllers, and closing the database.
- `TrayService` now retains exact listener instances and removes them during normal disposal.
- Initial asynchronous runtime opening handles widget disposal by closing a runtime that completes after the widget has unmounted.
- The isolated production-runtime test uses a temporary workspace and opens a real Drift-backed runtime with a real migration backup.

## Critical

None.

## Important

### 1. A pre-close restore failure can leave the old runtime alive and open a second runtime over the same workspace

`lib/app/research_life_app.dart:84-124`

`lib/app/local_app_runtime.dart:165-176`

`_restoreAndRestart()` handles every failure by opening a recovery runtime. If the explicit `current.flushLocalPersistence()` at line 89 fails, `current.close()` was never called, but the catch still opens another runtime over the same database and workspace. The old controller, timers, tray service, and database remain alive even though `_runtime` has been removed from the widget tree.

The same problem is made harder to recover from by `LocalAppRuntime.close()`: it sets `_closed = true` before `prepareForAppExit()`, flushing, tray disposal, controller disposal, or database close. If any awaited cleanup step throws, every later `close()` returns immediately and the remaining resources can never be released.

Concrete fix: distinguish failures before and after ownership has been closed. If the pre-close flush fails, reinstall the still-live `current` runtime and report the error; do not open a second runtime. Make `close()` a shared close-future/state machine that continues best-effort cleanup after a flush error, closes the database exactly once, and only reaches the terminal closed state after cleanup. Preserve and rethrow the primary failure after cleanup. Add tests for flush failure, close failure at each awaited stage, retry/idempotence, and proof that no recovery factory is called while the old runtime remains open.

### 2. Tray-driven quit paths bypass runtime shutdown and can lose queued local writes

`lib/services/tray/tray_service.dart:82-84`

`lib/services/tray/tray_service.dart:125-138`

Both the tray `quit` action and the `closeToTray == false` window-listener branch call `windowManager.destroy()` directly. The Windows runner's graceful path is the intercepted `WM_CLOSE -> requestClose -> ResearchLifeApp._shutdownForExit()` sequence. Direct destruction bypasses that request, so `prepareForAppExit()`, persistence flushing, listener disposal, controller disposal, and database close are not guaranteed to run before the engine/window is destroyed.

Concrete fix: route every user-visible quit path through one injected graceful-exit coordinator owned by `ResearchLifeApp`/the runtime lifecycle. It must await runtime shutdown before final native destruction and avoid re-entering the close-to-tray handler. Add a behavioral test for tray quit and close-to-tray-disabled close that asserts flush and close happen before native destroy.

### 3. Exit requested while startup or restore temporarily has `_runtime == null` can miss the runtime installed afterward

`lib/app/research_life_app.dart:58-74`

`lib/app/research_life_app.dart:84-100`

`lib/app/research_life_app.dart:142-152`

`_shutdownForExit()` memoizes `_runtime?.close() ?? Future.value()` at the instant it is first called. During startup and the whole restore transition, `_runtime` is null. An exit request in that window therefore permanently caches a completed no-op shutdown future. If a replacement/recovery runtime finishes while the widget is still mounted, it can still be installed; `dispose()` then sees `_shutdownFuture != null` and never closes it.

Concrete fix: add an explicit exiting state and serialize open/restore/shutdown transitions. Once exit is requested, factories that complete must close their result instead of installing it. `_shutdownForExit()` should await the in-flight open/restart transition and close the runtime it produces, rather than snapshotting a nullable field. Add gated startup and gated restore tests that request exit while `_runtime` is null and assert every produced runtime is closed exactly once.

## Minor

### 1. The direct-start widget test bypasses the production shell and the dependency scan is primarily textual

`test/local_app_runtime_test.dart:26-47`

`test/local_app_runtime_test.dart:119-132`

The test named `starts the local shell without an auth gate` supplies `runtimeContentBuilder` and renders `_TestLocalShell`; it never builds `LocalServicesScope`, `ResearchLifeScope`, `PinLockGate`, or `AppShell`. Finding no `LoginPage` in that injected widget is tautological. The only assertion on the real root chain is a source substring, which can pass even if unreachable or shadowed.

Concrete fix: supply behaviorally usable controller/backup-controller doubles and build the production content path, asserting `AppShell` and `PinLockGate` are present and `LoginPage`/`AuthGate` are absent. Keep source scanning as a secondary guard, not the behavioral proof.

### 2. Restore and ownership doubles do not exercise the failure branches that define the lifecycle contract

`test/local_app_runtime_test.dart:49-117`

`test/local_app_runtime_test.dart:164-194`

The fake can fail only `restoreBackup()`. It cannot fail or gate flush, close, recovery open, replacement open, or exit, and its `close()` does not model disposal order. Consequently the supplied passing tests do not cover the Important lifecycle defects above.

Concrete fix: give the fake independent gates/failures and exact counters for flush, close, restore, and factory calls. Add a production-runtime ownership test with injectable tray/database/controller collaborators, or expose a narrow lifecycle harness that proves order and exactly-once cleanup without relying on source strings.

### 3. The constructor scan does not prove the transitive active dependency graph

`test/local_app_runtime_test.dart:119-132`

Scanning only `local_app_runtime.dart` and `research_life_app.dart` would miss a cloud/auth constructor moved into a helper or a default constructor invoked transitively by `ResearchLifeController`. The current production path is clean by manual inspection, but the test is weaker than the report claims.

Concrete fix: inject factories/counters for forbidden services or expose runtime dependency metadata and assert no forbidden factory was invoked during a real isolated `LocalAppRuntime.open()`.

## Assessment

**CHANGES**

The normal startup and successful restore path meet Task 3's architectural direction, and the production runtime does not actively construct authentication or synchronization services at startup. However, restore pre-close failures, tray-driven exit, and exit-during-transition can leak or bypass the owned runtime and may skip persistence flushing. These lifecycle issues must be fixed before Task 3 can pass independent review.
