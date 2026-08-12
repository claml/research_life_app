# Task 3 Fix Round 2 Independent Review

Date: 2026-08-09

## Scope and evidence

Reviewed the Task 3 plan, `task-3-report.md`, the complete current Task 3 source/test set and working diff, and the Windows close behavior of the resolved `window_manager 0.5.2` package. I also traced the Windows engine implementation used by this checkout (`WindowsLifecycleManager`, `PlatformHandler`, and `WindowProcDelegateManager`).

I did not repeat the full suite. The supplied fresh evidence is 221/221 tests passing, a successful Windows debug build, and `dart analyze` containing only the six baseline findings.

## Strengths

- Terminal Dart cleanup failures are now contained at the correct boundary. `research_life_app.dart:168-197` awaits the shared shutdown, logs `runtime.close()` failures, and still returns `AppExitResponse.exit`; `dispose()` reuses the same future. This fixes the previous unhandled-async failure for a runtime close error.
- Restore behavior remains intentionally different from terminal shutdown. `research_life_app.dart:103-146` performs the preflight flush, detaches the old runtime, and keeps `current.close()` inside the restore `try`; any close/restore/open failure enters the recovery-factory branch and the original error is rethrown after recovery. The terminal-only catch does not swallow restore errors.
- `RuntimeDisposalCoordinator` retains its shared future, runs every ownership cleanup step exactly once, and rethrows the first cleanup error only after later resources have been attempted (`local_app_runtime.dart:42-83`).
- The custom runner bridge and its direct pre-dispatch `WM_CLOSE` branch were removed. The runner now consistently delegates top-level messages to Flutter before falling back to `Win32Window` (`windows/runner/flutter_window.cpp:50-72`).

## Critical

None.

## Important

### 1. Native `WM_CLOSE` still cannot implement either close-to-tray branch correctly

Files: `windows/runner/flutter_window.cpp:21-28,50-60`; `lib/services/tray/tray_service.dart:55-76`; `lib/app/research_life_app.dart:168-199`; `test/local_app_runtime_test.dart:257-263,311-326`.

The report's claim that `window_manager` receives the real close event first is false for the Flutter Windows engine used by this build:

1. The runner constructs the engine/controller and only then registers plugins (`flutter_window.cpp:21-28`). The engine registers its lifecycle top-level-window delegate during construction (`D:/local_environment/Flutter/flutter/engine/src/flutter/shell/platform/windows/flutter_windows_engine.cc:202-233`). Top-level delegates run in registration order and stop at the first handled result (`window_proc_delegate_manager.h:33-40`; `window_proc_delegate_manager.cc:37-51`).
2. On the first native `WM_CLOSE`, the engine lifecycle delegate requests `System.requestAppExit` and returns handled (`windows_lifecycle_manager.cc:41-62,65-76`). Consequently the later `window_manager` plugin delegate does not see that first close at all.
3. `_handleExitRequested()` always performs terminal shutdown (`research_life_app.dart:168-199`) and never checks `closeToTray`. Therefore an X-button close with `closeToTray=true` disposes the runtime instead of hiding the window.
4. After Dart returns `exit`, the engine re-posts the stored native `WM_CLOSE` (`windows_lifecycle_manager.cc:21-31,47-55`). `window_manager 0.5.2` then sees this second close, emits `close`, and returns a handled result when prevent-close is enabled (`C:/Users/24439/AppData/Local/Pub/Cache/hosted/pub.dev/window_manager-0.5.2/windows/window_manager_plugin.cpp:319-323`).
5. This app enables prevent-close at `tray_service.dart:56`, but disposal only removes the Dart listener and never calls `setPreventClose(false)` (`tray_service.dart:64-76`). The re-posted close is therefore consumed after the runtime/listener has already been removed. For `closeToTray=false`, the native X-button shutdown cleans up but the process/window is not allowed to close; for `true`, it both destroys the live runtime and fails to perform the requested hide behavior.

The new source test only proves that the runner no longer contains the old bridge. The framework-channel test injects `System.requestAppExit` directly and the tray test calls `handleWindowClose()` directly, so neither exercises the actual first-close/lifecycle-delegate/re-posted-close/plugin sequence.

Concrete fix: make one layer explicitly own native-close policy instead of relying on plugin registration order. For example, distinguish an explicit tray-menu exit from a native close in the root exit coordinator: on a native request with `closeToTray=true`, hide and return `cancel` without disposing the runtime; on a real exit, disable `window_manager` prevent-close before returning `exit` (or use a native close bridge that owns both hide and confirmed-exit behavior). Add a Windows/native-message integration test or small runner/plugin harness that proves: (a) true hides while leaving the runtime alive, and (b) false cleans up once and lets the re-posted close reach default destruction.

## Minor

### 1. Restore-close recovery has no direct regression test

File: `test/local_app_runtime_test.dart:88-159,361-402`.

The implementation correctly routes an old-runtime `close()` error through recovery, but the existing restore failure test fails in `restoreBackup`, while `failClose` is used only by the terminal-shutdown test. Add a test with `oldRuntime.failClose = true` that verifies the recovery factory is invoked, the recovery runtime is installed, `restoreBackup` is not called, and the original close error is returned to the restore caller. This protects the intentional terminal-vs-restore error-boundary distinction.

## Assessment

**CHANGES**

The Dart cleanup-failure fix and restore error boundary are sound, but the second required fix is not complete. The actual Flutter Windows delegate ordering means the plugin does not receive the initial `WM_CLOSE`, and its still-enabled prevent-close flag consumes the engine's confirmed close after runtime disposal. Task 3 should not pass until native X-button behavior is proven for both close-to-tray settings.
