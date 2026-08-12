# Task 3 Fix Round 3 Independent Review

Date: 2026-08-09

## Scope and evidence

Reviewed the Task 3 plan and report, the complete current Task 3 source/test set and working diff, the Windows runner/base-window dispatch path, and the Flutter Windows programmatic-exit behavior relevant to explicit tray quit.

I did not repeat the supplied fresh verification: Task 3 plus auth 18/18, full suite 224/224, successful Windows debug build, and `dart analyze` with only the six baseline findings.

## Strengths

- The runner now owns the first native `WM_CLOSE` before calling `HandleTopLevelWindowProc` (`windows/runner/flutter_window.cpp:60-82`). It coalesces repeated close messages while the Dart request is pending and treats a Boolean `false` response as cancellation (`flutter_window.cpp:95-126`).
- The confirmed-close path is genuinely isolated from Flutter and plugins. When `close_confirmed_` is set, the second `WM_CLOSE` goes directly to `Win32Window::MessageHandler` (`flutter_window.cpp:64-67`); the base falls through to `DefWindowProc`, which destroys the HWND, and its `WM_DESTROY` handling posts the process quit message (`windows/runner/win32_window.cpp:179-189,221-223`). The engine lifecycle delegate and `window_manager` cannot re-enter this confirmed close.
- Dart implements the hide-or-exit contract correctly. `research_life_app.dart:178-201` asks the active runtime for close policy; handled/hide returns `false` without setting `_exitRequested` or disposing anything. A false policy result, absent runtime, or policy exception reaches and awaits `_shutdownForExit()` before returning `true`. The terminal cleanup boundary still absorbs close errors only after best-effort disposal (`research_life_app.dart:203-229`).
- The production policy reaches the tray service through the runtime API (`local_app_runtime.dart:25-37,229-232`). With close-to-tray enabled, `TrayService.handleWindowCloseRequest()` awaits `windowManager.hide()` before reporting handled; with it disabled, it returns false (`tray_service.dart:86-95`).
- The conflicting `window_manager` ownership is removed. There is no `setPreventClose`, window-close listener, `onWindowClose`, or `windowManager.destroy()` in the active source. `TrayService` retains only its tray listener and explicitly removes it during disposal (`tray_service.dart:24-66`).
- Explicit tray quit remains framework-coordinated. `TrayService.quit()` shares the injected exit future (`tray_service.dart:75-77`), and the production injection calls `ServicesBinding.exitApplication(AppExitType.cancelable)` (`research_life_app.dart:50-55,169-175`). On Windows this programmatic request has no originating HWND, so after Dart returns `exit` the engine posts the quit message directly rather than sending another `WM_CLOSE`; the new native bridge does not interfere.
- The requested restore-close regression is behaviorally meaningful (`test/local_app_runtime_test.dart:123-164`): the old fake throws from `close`, recovery is opened and installed, `restoreBackup` is absent from the event list, and the original `StateError` message is preserved.

## Critical

None.

## Important

None.

## Minor

### 1. The Dart close-policy exception branch is correct but not directly regression-tested

File: `test/local_app_runtime_test.dart:300-359,457-505`.

The two native-channel widget tests cover handled/hide and ordinary false/exit, while the fake cannot throw from `handleWindowCloseRequest()`. The production catch at `research_life_app.dart:183-200` does await terminal cleanup and returns `true`, so this is a coverage gap rather than a discovered behavior defect. Add a fake policy-error flag and assert that a native request still returns true, closes the runtime exactly once, and emits no uncaught widget-test exception.

The C++ source-boundary test also cannot execute an actual HWND message loop, but the successful Windows build plus the direct, early `WM_CLOSE` branch and base-call trace are sufficient for this review.

## Assessment

**PASS**

Fix Round 3 resolves the previous Important finding. Native X-button close now has one owner, hide leaves runtime ownership intact, terminal close waits for cleanup, and confirmed close bypasses both Flutter lifecycle interception and `window_manager`. No Critical or Important issues remain.
