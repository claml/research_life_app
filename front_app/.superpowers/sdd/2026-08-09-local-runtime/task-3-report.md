# Task 3 Report — Restartable Local Runtime and Direct Startup

日期：2026-08-09

## 完成内容

- 新增 `LocalAppRuntime`，统一拥有本地数据库、repositories、`ResearchLifeController`、`LocalBackupController`、`BackupService` 与托盘服务。
- 生产运行时不构造 `AuthController`、`SyncOutboxRepository`、`CloudFileService` 或 `FileSyncEngine`；PDF repository 仅使用本地文件库。
- 根组件改为异步打开本地运行时，默认路径为 `LocalServicesScope → ResearchLifeScope → MaterialApp → PinLockGate → AppShell`，不再经过登录门。
- 新增启动失败重试面；文案仅描述本地工作台，不提登录或网络。
- 恢复流程按 flush → close old runtime → restore files → open fresh runtime 执行；失败时重新打开当前回滚后的本地工作区。
- `ResearchLifeController.flushLocalPersistence()` 成为唯一写队列收口点。
- `TrayService` 保存并移除自身监听器；本地运行时关闭时等待托盘初始化后再释放监听器、控制器和数据库。
- 首次打开在临时/生产工作区创建并验证 migration 安全备份后，才完成本地状态初始化。

## 变更文件

- `lib/app/local_app_runtime.dart`
- `lib/app/local_services_scope.dart`
- `lib/app/research_life_app.dart`
- `lib/services/tray/tray_service.dart`
- `lib/state/research_life_controller.dart`
- `test/local_app_runtime_test.dart`

## TDD 证据

### RED

```text
Error when reading 'lib/app/local_app_runtime.dart': 系统找不到指定的文件。
Type 'AppRuntime' not found.
No named parameter with the name 'runtimeFactory'.
```

真实运行时测试的第二轮 RED：

```text
Error: No named parameter with the name 'initializeTray'.
```

### GREEN

```text
00:01 +6: All tests passed!
```

覆盖：启动面、直接本地内容、成功恢复重启、失败恢复重开、生产源码依赖扫描、临时工作区真实 runtime open/close。

计划指定回归：

```text
flutter test test\local_app_runtime_test.dart test\auth_controller_test.dart
00:01 +8: All tests passed!
```

完整回归：

```text
00:19 +214: All tests passed!
```

## 静态分析与依赖扫描

`dart analyze` 仍为改造前已有的 1 warning + 5 info，没有 error 或本任务新增提示。对 `local_app_runtime.dart` 与 `research_life_app.dart` 的构造器/Scope 扫描对以下模式均为零命中：

```text
AuthController(
SyncOutboxRepository(
CloudFileService(
FileSyncEngine(
AuthScope(
AuthGate(
```

## 数据隔离

生产 runtime open/close 测试使用 `Directory.systemTemp` 注入的 `LocalWorkspaceService`，并禁用托盘插件；真实 migration 备份、Drift 数据库和关闭顺序均在临时目录完成，未访问生产工作区。

## Fix Round 1

独立审查报告 `task-3-review.md` 提出 3 个 Important 生命周期缺陷。新增用例首先因缺少 `requestExit` 与 `RuntimeDisposalCoordinator` 得到编译 RED，并在行为层覆盖以下边界：

- pre-close flush 失败时旧 runtime 保持安装，不调用 recovery factory；
- 启动中收到退出请求，迟到 runtime 只关闭一次且不安装；
- 恢复中收到退出请求，等待 transition 并关闭 replacement；
- 托盘菜单与 close-to-tray=false 均委托根优雅退出协调器；
- 任一 disposal 步骤失败后仍执行全部后续清理，并对重复 close 只执行一次。

实现修复：

- 根组件显式串行化 open/restore/shutdown transition，并设置不可逆 `exitRequested` 状态。
- restore preflight flush 在移除旧 runtime 前执行；只有终止式 close 已尝试后才允许 recovery。
- `RuntimeDisposalCoordinator` 共享 close future，保留首个错误但完成托盘、controller 与 database 的 best-effort 清理。
- `TrayService` 通过注入的 `requestExit` 回调退出，不再直接 `windowManager.destroy()`；重复退出请求合并。

修复后：

```text
00:01 +11: All tests passed!
flutter test test\local_app_runtime_test.dart test\auth_controller_test.dart
00:01 +13: All tests passed!
```

完整回归与静态分析：

```text
00:20 +219: All tests passed!
dart analyze: 1 warning + 5 info（均为改造前基线）
```

## Fix Round 2

The independent Fix Round 1 review found two remaining terminal-exit edges.

RED evidence:

```text
terminal cleanup failure still completes a framework exit exactly once
Expected: null
Actual: StateError: close failed after cleanup

Windows close messages are not intercepted before plugin dispatch
Expected: not contains 'RequestDartClose'
Actual: runner intercepted WM_CLOSE before HandleTopLevelWindowProc
```

Implementation:

- Terminal shutdown now catches and records a runtime close failure after the
  best-effort ownership cleanup, so `AppLifecycleListener` still returns
  `AppExitResponse.exit`. Restore continues to receive close failures because
  only the terminal exit coordinator consumes them.
- The duplicate native `research_life/window_lifecycle` bridge and its
  pre-plugin `WM_CLOSE` interception were removed from the Windows runner.
  `window_manager` now receives the real close event first; its listener can
  hide the window for close-to-tray or request the same framework-coordinated
  graceful exit when close-to-tray is disabled.
- Startup/restore exit tests now exercise the production
  `System.requestAppExit` framework channel instead of a test-only native
  lifecycle bridge.

Changed in this fix round:

- `lib/app/research_life_app.dart`
- `windows/runner/flutter_window.cpp`
- `windows/runner/flutter_window.h`
- `test/local_app_runtime_test.dart`

Fresh verification:

```text
flutter test test/local_app_runtime_test.dart
00:01 +13: All tests passed!

flutter test test/local_app_runtime_test.dart test/auth_controller_test.dart
00:01 +15: All tests passed!

flutter build windows --debug
Built build/windows/x64/runner/Debug/research_life.exe

flutter test
00:20 +221: All tests passed!

dart analyze
1 warning + 5 info (all pre-existing baseline findings)

git diff --check
exit 0
```

## Fix Round 3

Fix Round 2 review traced the actual Flutter Windows delegate order and showed
that relying on `window_manager` to receive the first `WM_CLOSE` was invalid.
The engine lifecycle delegate is registered first, while the plugin's retained
prevent-close state could consume the engine's confirmed second close.

RED evidence:

```text
native close can hide without disposing the local runtime
Null check operator used on a null value (native bridge absent)

native close awaits cleanup before confirming window close
Null check operator used on a null value (native bridge absent)

Windows runner owns hide-or-confirm close without plugin re-entry
Expected source to contain RequestDartClose; it did not.
```

Implementation:

- Restored one native lifecycle bridge, but changed its contract from
  unconditional exit to a Dart hide-or-confirm decision.
- `AppRuntime.handleWindowCloseRequest()` delegates to `TrayService`. With
  close-to-tray enabled it hides and returns handled without touching runtime
  ownership; otherwise the root awaits terminal cleanup and confirms exit.
- Removed `window_manager.setPreventClose(true)` and the duplicate window-close
  listener. The runner now owns native X-button policy exclusively.
- A confirmed second `WM_CLOSE` bypasses Flutter/plugin delegates and calls the
  base Win32 handler directly, so it cannot be swallowed by lifecycle or plugin
  registration order.
- Added the requested direct restore-close failure regression: recovery opens,
  restore is not attempted, and the original close error is preserved.

Fresh verification:

```text
flutter test test/local_app_runtime_test.dart test/auth_controller_test.dart
00:01 +18: All tests passed!

flutter build windows --debug
Built build/windows/x64/runner/Debug/research_life.exe

flutter test
00:14 +224: All tests passed!

dart analyze
1 warning + 5 info (all pre-existing baseline findings)

git diff --check
exit 0
```
