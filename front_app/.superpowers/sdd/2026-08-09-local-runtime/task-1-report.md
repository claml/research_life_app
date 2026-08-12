# Task 1 Report — Atomic Backup Finalization and Retention

日期：2026-08-09

## 完成内容

- 备份先写入同级 `.pending-<timestamp>` 目录，完整校验 manifest、文件大小和 SHA-256 后再通过目录重命名发布。
- 创建或校验失败时只删除当前 pending 目录，不触碰已有正式、损坏或人工恢复目录。
- `BackupPurpose` 移入 manifest 层，支持 `manual`、`safety`、`migration`，并持久化为 JSON 字段。
- 兼容旧版 manifest：缺少 `purpose` 时按 `manual` 读取。
- 新增有效备份列表，按 `createdAt` 从新到旧排序；pending、损坏和不可读目录不进入列表，也不会被自动删除。
- 新增保留策略，默认保留最新 10 份有效备份；`keep < 1` 明确拒绝。

## 变更文件

- `lib/services/storage/backup_manifest.dart`
- `lib/services/storage/backup_service.dart`
- `test/backup_service_test.dart`

## TDD 证据

### RED

1. 原子发布测试：期望首次目录事件以 `.pending-` 开头，旧实现实际首先暴露 `2026-08-09_100000`。
2. 用途元数据测试：编译失败，旧实现缺少 `BackupPurpose.migration`、`createBackup(purpose:)` 和 `BackupManifest.purpose`。
3. 有效列表测试：编译失败，旧实现缺少 `listBackups()`。
4. 保留策略测试：编译失败，旧实现缺少 `pruneBackups()`。
5. 旧 manifest 兼容测试：移除 `purpose` 后校验失败，错误为 `Unsupported backup purpose: null`。

### GREEN

命令：

```powershell
flutter test test\backup_service_test.dart
```

初轮结果：`00:01 +11: All tests passed!`

## 独立审查与修复轮 1

独立审查发现 0 Critical、2 Important：

1. 相同时钟的并发备份可能共享 pending 目录并互相覆盖或清理。
2. `createdAt` 与 `localFileLibraryFiles` 等结构错误可能被宽松解析，使损坏目录进入保留删除集合。

### 修复轮 RED 原始关键输出

并发测试：

```text
PathExistsException: Cannot copy file to '...\.pending-2026-08-09_100000\research_life.sqlite'
BackupService publishes concurrent same-clock backups without sharing pending data [E]
```

结构校验测试：

```text
Expected: throws <Instance of 'BackupValidationException'>
Actual: emitted <Instance of 'BackupManifest'>
createdAt
```

保留安全测试：

```text
Expected: <1>
Actual: <2>
BackupService retention preserves a structurally invalid backup directory [E]
```

### 修复内容

- pending 目录改用 `Directory.createTemp()` 在备份目录内获得独占名称。
- 发布时使用同级 `Directory.rename()` 原子抢占正式时间戳；若并发冲突则顺延一秒重试。
- pending 清理失败不再掩盖原始备份异常；残留 pending 不进入列表或保留删除集合。
- manifest 严格验证必填版本、应用版本、时间、数据库 schema、工作区路径，以及可选对象/列表的实际类型和所有列表元素。

### 修复轮 GREEN 原始输出

```text
00:00 +0: BackupService creates backup successfully
00:00 +1: BackupService keeps a backup pending until validation succeeds
00:00 +2: BackupService publishes concurrent same-clock backups without sharing pending data
00:00 +6: BackupService rejects structurally malformed manifest metadata
00:00 +10: BackupService retention preserves a structurally invalid backup directory
00:01 +14: All tests passed!
```

最终覆盖原子发布、同秒并发、用途持久化、旧格式兼容、严格结构校验、列表排序、损坏目录保留、保留策略、SHA-256 校验、安全备份和本地资料恢复。

## 独立复核与修复轮 2

复核确认并发修复有效，但发现数值/字符串仍会被隐式转换：例如 `1.9` 被截断为 `1`、`42` 被转为字符串。这类 manifest 仍可能进入自动删除集合。

### RED 原始关键输出

```text
Expected: throws <Instance of 'BackupValidationException'>
Actual: emitted <Instance of 'BackupManifest'>
appVersion

BackupService rejects fractional backup file sizes without truncation [E]
Expected: throws <Instance of 'BackupValidationException'>
Actual: emitted <Instance of 'BackupManifest'>
```

### 修复

- 文本字段只接受 JSON string，不再调用字符串插值进行转换。
- 版本号和文件大小只接受 JSON int，不再接受浮点截断或数字字符串。
- 只有 `purpose` 字段完全缺失时才兼容为 `manual`；显式 `null` 或错误类型均拒绝。
- 自动删除回归改用错误类型 `appVersion: 42`，证明这类目录不会被保留策略删除。

### 最终 GREEN

```text
00:00 +6: BackupService rejects structurally malformed manifest metadata
00:00 +7: BackupService rejects fractional backup file sizes without truncation
00:01 +11: BackupService retention preserves a structurally invalid backup directory
00:01 +15: All tests passed!
TEST_EXIT=0 ANALYZE_EXIT=2
```

`ANALYZE_EXIT=2` 对应改造前已存在的 1 warning + 5 info；没有 error，也没有本任务新增提示。

## 最终独立复核

结论：**PASS**。0 Critical，0 Important。复核确认精确类型校验、旧 purpose 兼容边界、独占 pending、原子发布冲突重试和损坏目录保留均符合数据安全要求。

## 静态分析

`flutter analyze` 在 Flutter 3.44.8、当前中文工作区路径下稳定触发 analysis server LSP 初始化 JSON 截断；这是改造前即可复现的环境问题。`dart analyze` 正常完成，结果仍为改造前已有的 1 条 warning 和 5 条 info，本任务未新增静态问题。

## 数据隔离声明

所有备份测试均通过 `Directory.systemTemp.createTemp()` 创建一次性工作区，并在测试结束后递归清理。测试没有读取、写入或恢复用户的生产 `.research_life` 工作区。
