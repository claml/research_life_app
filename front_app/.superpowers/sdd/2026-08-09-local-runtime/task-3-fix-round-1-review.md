# Task 3 Fix Round 1 Independent Review

Date: 2026-08-09

Reviewed scope:

- `lib/app/local_app_runtime.dart`
- `lib/app/research_life_app.dart`
- `lib/services/tray/tray_service.dart`
- `test/local_app_runtime_test.dart`
- the Windows close bridge relevant to the tray/exit path
- the complete current Task 3 diff and the original Task 3 review

Supplied verification: Task 3 tests pass 11/11, Task 3 plus auth regression passes 13/13, the full suite passes 219/219, and `dart analyze` reports only the six stated baseline findings. The review did not rerun commands that generate build artifacts.

## Strengths

- Restore preflight flushing now occurs before the old runtime is removed from the widget tree. A preflight failure leaves the old runtime installed and does not invoke the recovery factory.
- After preflight succeeds, the old runtime is removed before terminal close and file restoration, preventing UI interaction with a closing controller/database.
- `RuntimeDisposalCoordinator` memoizes one close future, executes every cleanup step even after failures, preserves the first error and stack, and prevents repeated or concurrent close calls from repeating disposal.
- Startup failure cleanup preserves the original startup error after best-effort ownership cleanup.
- Restore/exit state now has an irreversible `_exitRequested` flag and an explicitly tracked transition. Startup runtimes, restore replacements, and recovery runtimes that complete after exit is requested are closed instead of installed.
- Shutdown waits for the captured transition-completion future, then closes any runtime installed by that transition exactly once.
- Restore detects an exit request after preflight and before removing the current runtime, allowing shutdown to retain and close the correct owner.
- Tray menu quit and the `closeToTray == false` handler no longer call `windowManager.destroy()` directly. They delegate to an injected exit request, and a shared `_exitFuture` merges repeated requests on the same `TrayService`.
- Production wiring requests a cancelable framework exit, allowing `AppLifecycleListener.onExitRequested` to coordinate runtime cleanup before process termination.
- Added tests behaviorally cover preflight failure, gated startup exit, gated restore exit, cleanup-after-failure, exactly-once disposal, and both direct tray delegation methods.
- Direct local startup, migration safety, terminal backup-controller disposal, and absence of startup auth/sync constructors remain intact.

## Critical

None.

## Important

### 1. A cleanup error is propagated through terminal exit after the runtime has already been detached and disposed

`lib/app/local_app_runtime.dart:68-82`

`lib/app/research_life_app.dart:172-201`

`lib/app/research_life_app.dart:204-211`

The coordinator correctly continues cleanup and then rethrows its first failure. That behavior is useful for restore, where close failure should trigger recovery. The terminal shutdown path, however, directly awaits `runtime.close()` and propagates the error from `_handleExitRequested()`. For tray-driven `ServicesBinding.exitApplication(AppExitType.cancelable)`, an errored exit-response future can prevent or error the cancelable exit even though `_runtime` has already been set to null, controllers and database have been disposed, and `_exitRequested` permanently prevents reopening. The application can be left running on the startup surface with no usable runtime. Widget `dispose()` also launches the same potentially failing shutdown future with bare `unawaited`, creating an unhandled asynchronous error.

Concrete fix: keep `AppRuntime.close()` error-reporting for restore callers, but make the terminal exit coordinator consume/report close errors after best-effort cleanup and still return `AppExitResponse.exit`. Attach explicit error handling to disposal-triggered shutdown as well. Add a widget test whose runtime `close()` performs cleanup and then throws; request exit through the framework/native path and assert the request completes, the runtime closes once, and no uncaught async error is emitted.

### 2. The real Windows close button bypasses `TrayService.handleWindowClose()`, so close-to-tray remains ineffective

`windows/runner/flutter_window.cpp:64-76`

`lib/app/research_life_app.dart:177-181`

`lib/services/tray/tray_service.dart:92-98`

The runner intercepts every `WM_CLOSE` and returns before calling `flutter_controller_->HandleTopLevelWindowProc()`, which is the path that delivers top-level window messages to plugins such as `window_manager`. Therefore the `_WindowCloseListener` does not get the real close event: the native channel always calls `_shutdownForExit()` and confirms process exit, regardless of the persisted `closeToTray` setting. The unit test calls `handleWindowClose()` directly and proves only the method's local branch, not that native Windows events can reach it.

Concrete fix: establish one authoritative Windows close path. Either let `window_manager` receive `WM_CLOSE` before the custom runner decides to exit, or make the native close request ask Dart whether to hide or exit and return that decision. Preserve graceful shutdown only for the exit decision. Add a Windows integration/source-boundary test proving `closeToTray == true` hides without shutdown and `false` awaits shutdown before native close confirmation.

## Minor

### 1. The tray test does not prove request coalescing or the production framework-exit bridge

`test/local_app_runtime_test.dart:276-291`

It uses two separate services with counting callbacks and calls each once. It does not call `quit()` and `handleWindowClose()` concurrently on the same instance, nor does it exercise `_requestGracefulExit()` and `AppLifecycleListener` together. Add a gated shared callback and assert both calls return the same one-shot request, then exercise the production cancelable exit channel in a widget test.

### 2. The direct-start test still renders an injected shell instead of the production `PinLockGate -> AppShell` tree

`test/local_app_runtime_test.dart:29-50`

Absence of `LoginPage` in `_TestLocalShell` is tautological; the real chain remains protected only by a source substring. Supply usable controller/backup-controller doubles and build the production content branch, asserting the real widget types.

### 3. The forbidden-constructor check remains textual and non-transitive

`test/local_app_runtime_test.dart:230-243`

Moving a forbidden constructor into a helper/default dependency would evade the scan. The current runtime is clean by inspection and by its explicit constructor arguments, but factory counters or runtime dependency metadata would provide a stronger executable guarantee.

## Assessment

**CHANGES**

Fix Round 1 resolves the original restore preflight, disposal idempotence, direct-destroy, and transition ownership defects. Two exit edges remain: terminal cleanup errors are not converted into a completed best-effort exit, and the Windows runner intercepts the actual close event before the tray listener can honor close-to-tray. Both should be addressed before Task 3 receives a final pass.
