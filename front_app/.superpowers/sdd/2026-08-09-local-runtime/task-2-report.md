# Task 2 Report — Local Backup Controller and Migration Safety

日期：2026-08-09

## 完成内容

- 新增 `LocalBackupController`，统一串行执行迁移备份、手动备份和恢复。
- 任何写操作前调用 `flushLocalWrites`；忙碌时拒绝第二个操作。
- 迁移备份必须创建为 `migration`、再次校验用途，并完成保留清理与列表刷新后，才以事务保存绝对目录记录与完成标记。
- 已记录且仍可校验的迁移备份不会重复创建；损坏或缺失记录会重新生成。
- `PreferencesRepository` 新增迁移路径、完成标记及失效 API；保存记录使用 Drift 事务，失效时先删除完成标记。
- 迁移保留策略只清理 `migration`，不删除 `manual` 或 `safety`。
- 控制器公开 `busy`、`message`、`messageIsError` 和最新有效备份列表。
- 恢复回调被视为旧运行时的终止交接：回调后不再访问旧备份服务，且控制器释放后不会再次通知监听者。

## 变更文件

- `lib/state/local_backup_controller.dart`
- `lib/services/database/repositories/preferences_repository.dart`
- `lib/services/storage/backup_service.dart`
- `test/local_backup_controller_test.dart`
- `test/database_preferences_repository_test.dart`
- `test/backup_service_test.dart`

## TDD 证据

### RED

控制器初始测试：

```text
Error when reading 'lib/state/local_backup_controller.dart': 系统找不到指定的文件。
Type 'LocalMigrationPreferences' not found.
Method not found: 'LocalBackupController'.
```

用途过滤保留测试：

```text
Error: No named parameter with the name 'purposes'.
purposes: {BackupPurpose.migration},
```

### GREEN

```text
00:00 +0: saves and loads weekly prompt template
00:00 +5: saves and loads the local migration backup record
00:00 +6: LocalBackupController migration backup runs once and is marked only after validation
00:00 +9: LocalBackupController failed preference write never marks migration complete
00:00 +10: LocalBackupController manual backup flushes writes and refreshes the visible list
00:00 +11: LocalBackupController restore validates, flushes, and delegates runtime replacement
00:00 +12: LocalBackupController rejects a second backup operation while one is active
00:02 +29: All tests passed!
```

命令：

```powershell
flutter test test\database_preferences_repository_test.dart test\local_backup_controller_test.dart test\backup_service_test.dart
```

## 静态分析

`dart analyze` 仍为改造前已有的 1 warning + 5 info，没有 error 或本任务新增提示。`flutter analyze` 的已知 LSP 截断问题不变。

## Fix Round 1

独立审查发现 4 个 Important：恢复回调后的旧运行时访问、失败后完成标记残留、迁移检查绕过操作锁、相对路径可能被持久化。修复前新增回归用例得到预期 RED：

```text
00:00 +7 -6: Some tests failed.
```

修复内容：

- `ensureMigrationBackup` 从入口开始持有操作锁；有效记录检查不重复 flush，替换路径在创建前先失效旧标记。
- 新迁移记录改为 create → validate → prune → refresh → transaction commit，任何前置失败都不会写完成标记。
- 持久化 `created.directory.absolute.path`。
- `restoreRuntime` 返回后不再刷新旧服务；控制器增加释放状态通知保护。
- 公共备份列表刷新也进入相同串行操作通道。

修复后：

```text
00:02 +35: All tests passed!
```

命令：

```powershell
flutter test test\local_backup_controller_test.dart test\database_preferences_repository_test.dart test\backup_service_test.dart
```

## 数据隔离

控制器测试使用行为受限的备份假实现；真实文件复制、哈希、并发 pending 与恢复回滚继续由 `backup_service_test.dart` 的系统临时目录覆盖。偏好记录使用 Drift 内存数据库，不访问生产工作区。

## Fix Round 2

复审发现系统时间回拨时，新建迁移备份可能被按 manifest 时间排序的保留清理误删。新增用例先得到预期编译 RED：

```text
Error: No named parameter with the name 'protectedPaths'.
```

`pruneBackups` 现支持显式保护路径，并在总保留数内优先保留这些目录；控制器保护本次新建目录，刷新后再次完成哈希与用途校验，最后才提交完成标记。

```text
00:02 +36: All tests passed!
```

## Fix Round 3

复审指出公共 `protectedPaths` API 在命中保护项多于 `keep` 时会静默突破上限。真实文件回归先得到预期 RED（返回 `0`，未抛出 `ArgumentError`）；现改为在任何删除前拒绝无解参数组合。同步补充了相对保护路径归一化和 post-retention 二次校验失败不写 marker 的直接覆盖。

```text
00:02 +38: All tests passed!
```

完整回归：

```text
00:13 +206: All tests passed!
```
