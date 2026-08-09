# Local Data Protection and Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Protect existing local data, boot directly into a local-only runtime, remove authentication and sync from the active dependency graph, and expose reliable backup/restore controls.

**Architecture:** Harden the existing `BackupService`, introduce a restartable `LocalAppRuntime`, and replace `AuthScope`/`AppServicesScope` with a small local-services boundary. Existing auth/sync source files remain temporarily but are unreachable at runtime.

**Tech Stack:** Flutter, Dart async/IO, Drift/SQLite WAL, JSON manifests, SHA-256, Material 3, Flutter tests.

## Global Constraints

- Never overwrite user data before a validated safety backup exists.
- Startup must not create `AuthController`, `SyncOutboxRepository`, `CloudFileService`, `DeviceIdService`, or `FileSyncEngine`.
- Phase 1 does not drop sync tables or columns.
- AI credentials are not implemented in this plan; AI displays a local “not configured” state until Plan 3.
- Weather remains functional and independent of workbench authentication.
- Do not initialize Git; create one SDD checkpoint and independent review per task.

---

## File Structure

**Create**

- `lib/app/local_app_runtime.dart` — constructs and owns the restartable local database, repositories, controller, backup service, and tray service.
- `lib/app/local_services_scope.dart` — exposes only local backup/runtime actions needed by Settings.
- `lib/state/local_backup_controller.dart` — backup list, busy state, messages, create/validate/restore orchestration.
- `test/local_app_runtime_test.dart` — verifies the production runtime has no auth/sync dependencies.
- `test/local_backup_controller_test.dart` — tests migration backup, retention, validation, and restore state.
- `test/local_only_pages_test.dart` — verifies active pages do not request auth/cloud services.

**Modify**

- `lib/services/storage/backup_service.dart` — pending-directory finalization, list/prune APIs, explicit purpose.
- `lib/services/storage/backup_manifest.dart` — manifest purpose and format compatibility.
- `lib/app/research_life_app.dart` — async local runtime and direct `PinLockGate → AppShell` startup.
- `lib/state/research_life_controller.dart` — expose a single `flushLocalPersistence()` method; stop active sync enqueue paths.
- `lib/features/files/my_files_page.dart` — local library only.
- `lib/features/pdf_tools/pdf_tools_page.dart` — local inputs and local save targets only.
- `lib/features/agent/agent_page.dart` — no `AuthScope`; show local provider configuration state.
- `lib/features/settings/settings_page.dart` — replace account/sync sections with backup/restore.
- `test/backup_service_test.dart`, `test/research_life_controller_test.dart`.

**Retain but make unreachable**

- `lib/app/auth_gate.dart`, `lib/app/auth_scope.dart`, `lib/state/auth_controller.dart`.
- `lib/services/sync/**`, `lib/features/sync/**`, cloud-only file widgets.

---

### Task 1: Atomic Backup Finalization and Retention

**Files:**
- Modify: `lib/services/storage/backup_manifest.dart`
- Modify: `lib/services/storage/backup_service.dart`
- Test: `test/backup_service_test.dart`

**Interfaces:**
- Produces: `BackupService.createBackup({BackupPurpose purpose = BackupPurpose.manual})`
- Produces: `BackupService.listBackups()` returning `Future<List<BackupCreateResult>>`, newest first.
- Produces: `BackupService.pruneBackups({int keep = 10})` returning `Future<int>`.
- Preserves: `validateBackup(Directory)` and `restoreBackup(Directory)`.
- Moves/defines `BackupPurpose` in `backup_manifest.dart` with `manual`, `safety`, and `migration`; persists the purpose in `BackupManifest` so listing does not infer it from directory names.

- [ ] **Step 1: Write failing tests for pending-directory finalization and retention**

```dart
test('publishes a backup only after its manifest validates', () async {
  final fixture = await _BackupFixture.create(
    timestamp: DateTime(2026, 8, 9, 10),
  );
  addTearDown(fixture.dispose);
  await fixture.writeDatabaseValue('safe');

  final result = await fixture.service.createBackup();

  expect(result.directory.path, isNot(contains('.pending-')));
  expect(await fixture.service.validateBackup(result.directory), isNotNull);
  expect(
    await result.directory.parent
        .list()
        .where((entry) => entry.path.contains('.pending-'))
        .isEmpty,
    isTrue,
  );
});

test('retention keeps the newest ten validated backups', () async {
  final fixture = await _BackupFixture.create(
    timestamp: DateTime(2026, 8, 9, 10),
  );
  addTearDown(fixture.dispose);
  await fixture.writeDatabaseValue('safe');
  for (var i = 0; i < 12; i += 1) {
    await fixture.service.createBackup();
    fixture.advance(const Duration(seconds: 1));
  }

  expect(await fixture.service.pruneBackups(keep: 10), 2);
  expect(await fixture.service.listBackups(), hasLength(10));
});
```

Extend `_BackupFixture` with a mutable timestamp captured by the injected `clock` and this helper:

```dart
void advance(Duration duration) => timestamp = timestamp.add(duration);
```

- [ ] **Step 2: Run the focused test and record RED**

Run:

```powershell
flutter test test\backup_service_test.dart
```

Expected: FAIL because `createBackup` has no named purpose, pending directories are not used, and list/prune APIs do not exist.

- [ ] **Step 3: Add purpose metadata and create the backup in a pending directory**

```dart
Future<BackupCreateResult> createBackup({
  BackupPurpose purpose = BackupPurpose.manual,
}) async {
  final result = await _createBackup(
    createdAt: _now(),
    requireDatabase: true,
    purpose: purpose,
    pending: true,
  );
  await validateBackup(result.directory);
  final published = await _publishPendingDirectory(result.directory);
  return BackupCreateResult(
    directory: published,
    manifest: result.manifest,
    purpose: result.purpose,
  );
}
```

Use a sibling `.pending-<timestamp>` directory and `Directory.rename()` only after every file and `backup_manifest.json` validates. On failure, delete only that pending directory.

- [ ] **Step 4: Implement validated listing and retention**

```dart
Future<int> pruneBackups({int keep = 10}) async {
  if (keep < 1) throw ArgumentError.value(keep, 'keep');
  final backups = await listBackups();
  var removed = 0;
  for (final backup in backups.skip(keep)) {
    await backup.directory.delete(recursive: true);
    removed += 1;
  }
  return removed;
}
```

Ignore pending and invalid directories during retention; never delete an invalid directory automatically because it may be manually recoverable.

- [ ] **Step 5: Run GREEN and a corruption regression**

```powershell
flutter test test\backup_service_test.dart
```

Expected: all backup tests pass, including existing checksum/path-traversal/rollback tests.

- [ ] **Step 6: Record Task 1 checkpoint**

Write `.superpowers/sdd/2026-08-09-local-runtime/task-1-report.md` with changed files, exact RED/GREEN output, and a statement that no production workspace was used by tests. Request independent review.

---

### Task 2: Local Backup Controller and Migration Safety Backup

**Files:**
- Create: `lib/state/local_backup_controller.dart`
- Modify: `lib/services/database/repositories/preferences_repository.dart`
- Test: `test/local_backup_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 `BackupService` APIs.
- Produces: `LocalBackupController.ensureMigrationBackup()`; persists both validation state and backup directory.
- Produces: `LocalBackupController.createManualBackup()`.
- Produces: `LocalBackupController.restore(Directory)` through an injected `RuntimeRestore` callback; the controller never replaces an open database itself.
- Produces listenable state: `busy`, `message`, `messageIsError`, `backups`.

- [ ] **Step 1: Write failing controller tests**

```dart
test('migration backup runs once and is marked only after validation', () async {
  final preferences = _FakeLocalMigrationPreferences();
  final backup = _FakeBackupService();
  final controller = LocalBackupController(
    backupService: backup,
    migrationPreferences: preferences,
    flushLocalWrites: () async {},
    restoreRuntime: (_) async => fakeRestoreResult,
  );

  await controller.ensureMigrationBackup();
  await controller.ensureMigrationBackup();

  expect(backup.createdPurposes, [BackupPurpose.migration]);
  expect(preferences.completed, isTrue);
  expect(preferences.backupPath, backup.lastCreatedDirectory.path);
});

test('failed migration backup never marks migration complete', () async {
  final preferences = _FakeLocalMigrationPreferences();
  final backup = _FakeBackupService()..failCreate = true;
  final controller = LocalBackupController(
    backupService: backup,
    migrationPreferences: preferences,
    flushLocalWrites: () async {},
    restoreRuntime: (_) async => fakeRestoreResult,
  );

  await expectLater(controller.ensureMigrationBackup(), throwsA(isA<BackupException>()));
  expect(preferences.completed, isFalse);
});
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\local_backup_controller_test.dart
```

Expected: FAIL because the controller and migration preference methods do not exist.

- [ ] **Step 3: Add the exact migration preference API**

```dart
static const localMigrationBackupCompleteKey =
    'local_mode.migration_backup_v1.complete';
static const localMigrationBackupPathKey =
    'local_mode.migration_backup_v1.path';

Future<bool> loadLocalMigrationBackupComplete() async =>
    await loadString(localMigrationBackupCompleteKey) == 'true';

Future<String?> loadLocalMigrationBackupPath() =>
    loadString(localMigrationBackupPathKey);

Future<void> saveLocalMigrationBackupRecord(String path) async {
  await saveString(localMigrationBackupPathKey, path);
  await saveString(localMigrationBackupCompleteKey, 'true');
}
```

- [ ] **Step 4: Implement serialized backup operations**

```dart
Future<T> _run<T>(Future<T> Function() action) async {
  if (_busy) throw const BackupException('已有备份或恢复任务正在进行。');
  _busy = true;
  notifyListeners();
  try {
    await _flushLocalWrites();
    return await action();
  } finally {
    _busy = false;
    notifyListeners();
  }
}
```

`ensureMigrationBackup()` must create `BackupPurpose.migration`, validate it, persist its absolute directory path before the completion marker, and then prune to ten automatic/migration backups without deleting manual safety backups created for restore.

- [ ] **Step 5: Run GREEN**

```powershell
flutter test test\local_backup_controller_test.dart test\backup_service_test.dart
```

- [ ] **Step 6: Record Task 2 checkpoint and review**

Document state transitions and prove the marker remains false on every failure branch.

---

### Task 3: Restartable Local Runtime and Direct Startup

**Files:**
- Create: `lib/app/local_app_runtime.dart`
- Create: `lib/app/local_services_scope.dart`
- Modify: `lib/app/research_life_app.dart`
- Modify: `lib/state/research_life_controller.dart`
- Test: `test/local_app_runtime_test.dart`

**Interfaces:**
- Produces: `LocalAppRuntime.open({LocalWorkspaceService? workspaceService})`.
- Produces: `LocalAppRuntime.close()` and `flushLocalPersistence()`.
- Produces: `LocalServicesScope.backupController`.
- Produces: `ResearchLifeApp({LocalAppRuntimeFactory? runtimeFactory})` for widget-test injection.

- [ ] **Step 1: Write failing source and widget tests**

```dart
testWidgets('starts the local shell without an auth gate', (tester) async {
  final runtime = _FakeLocalAppRuntime();
  await tester.pumpWidget(
    ResearchLifeApp(runtimeFactory: (_) async => runtime),
  );
  await tester.pumpAndSettle();

  expect(find.byType(AppShell), findsOneWidget);
  expect(find.byType(LoginPage), findsNothing);
});

test('production runtime source excludes cloud constructors', () {
  final source = File('lib/app/local_app_runtime.dart').readAsStringSync();
  expect(source, isNot(contains('AuthController(')));
  expect(source, isNot(contains('SyncOutboxRepository(')));
  expect(source, isNot(contains('CloudFileService(')));
  expect(source, isNot(contains('FileSyncEngine(')));
});
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\local_app_runtime_test.dart
```

- [ ] **Step 3: Create the runtime ownership boundary**

```dart
abstract interface class AppRuntime {
  ResearchLifeController get controller;
  LocalBackupController get backupController;
  Future<void> flushLocalPersistence();
  Future<void> close();
}

typedef RuntimeRestore = Future<BackupRestoreResult> Function(
  Directory backupDirectory,
);
typedef LocalAppRuntimeFactory = Future<AppRuntime> Function(
  RuntimeRestore restoreRuntime,
);
```

Change the production factory signature to `LocalAppRuntime.open({LocalWorkspaceService? workspaceService, required RuntimeRestore restoreRuntime})`. It constructs `AppDatabase`, local repositories, `PdfDocumentsRepository` with no outbox repository, `ResearchLifeController` with no sync/cloud arguments, `BackupService`, and `LocalBackupController(restoreRuntime: restoreRuntime)`. It owns disposal order: controller pending writes → tray → database.

- [ ] **Step 4: Add one controller flush boundary**

```dart
Future<void> flushLocalPersistence() async {
  await waitForPendingManualEventPersistence();
  await waitForPendingPersistence();
}
```

Do not let `LocalBackupController` call several private queues directly.

- [ ] **Step 5: Replace the root widget tree**

```dart
return LocalServicesScope(
  backupController: runtime.backupController,
  restoreAndRestart: _restoreAndRestart,
  child: ResearchLifeScope(
    controller: runtime.controller,
    child: MaterialApp(
      title: '研LIFE',
      home: const PinLockGate(child: AppShell()),
    ),
  ),
);
```

`_restoreAndRestart` flushes and closes the current runtime, calls `BackupService.restoreBackup`, creates a fresh runtime through the factory, and replaces the root scope in `setState`. If restore fails, it reopens the pre-restore runtime from the rollback data before reporting the error.

The loading state may use a small branded startup surface. It must not mention login or network.

- [ ] **Step 6: Run focused GREEN and startup regression**

```powershell
flutter test test\local_app_runtime_test.dart test\auth_controller_test.dart
```

The old auth controller test may remain green because its source still exists; it is no longer an active application dependency.

- [ ] **Step 7: Record Task 3 checkpoint and review**

Include a constructor/reference scan proving no auth/sync service is created by `ResearchLifeApp` or `LocalAppRuntime`.

---

### Task 4: Local-Only Files, PDF, AI State, and Settings

**Files:**
- Modify: `lib/features/files/my_files_page.dart`
- Modify: `lib/features/pdf_tools/pdf_tools_page.dart`
- Modify: `lib/features/agent/agent_page.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Create: `lib/features/settings/widgets/local_backup_panel.dart`
- Test: `test/local_only_pages_test.dart`
- Test: `test/settings_local_backup_panel_test.dart`

**Interfaces:**
- Consumes: `LocalServicesScope.backupController`.
- Produces: local-only file selection/open/delete/rename UI.
- Produces: local-only PDF input/output choices.
- Produces: AI “provider not configured” state without authentication.

- [ ] **Step 1: Write failing page-boundary tests**

```dart
test('active local pages do not import auth or cloud UI', () {
  for (final path in [
    'lib/features/files/my_files_page.dart',
    'lib/features/pdf_tools/pdf_tools_page.dart',
    'lib/features/agent/agent_page.dart',
    'lib/features/settings/settings_page.dart',
  ]) {
    final source = File(path).readAsStringSync();
    expect(source, isNot(contains('AuthScope')));
    expect(source, isNot(contains('CloudFileExplorer')));
    expect(source, isNot(contains('SyncStatusPanel')));
  }
});
```

Add widget tests asserting Settings contains `备份与恢复`, `立即备份`, and `恢复备份`, and contains no `登录`, `退出登录`, or `云同步` controls.

- [ ] **Step 2: Run RED**

```powershell
flutter test test\local_only_pages_test.dart test\settings_local_backup_panel_test.dart
```

- [ ] **Step 3: Simplify Files and PDF tools to local objects**

Remove cloud tree, upload, download, and cloud save-plan branches. Keep `PdfLibraryDocument` selection, local file import, local rename/delete, Document View, Reading, and PDF tools navigation. PDF tools accept only local file paths and save only to a selected local folder.

```dart
final selected = controller.pdfDocumentById(_selectedDocumentId);
final canRunPdfAction = selected != null && selected.fileKind.isPdf;
```

- [ ] **Step 4: Replace AI authentication dependency with a configuration state**

```dart
if (!controller.localAiConfigured) {
  return EmptyState(
    icon: Icons.auto_awesome_rounded,
    title: 'AI 服务尚未配置',
    actionLabel: '前往设置',
    onAction: controller.requestOpenAiSettings,
  );
}
```

Do not add credential persistence in this task.

- [ ] **Step 5: Implement the backup panel**

The panel displays the latest validated backup time, backup directory, busy state, and only three actions: `立即备份`, `打开备份目录`, `恢复备份`. Restore uses a directory picker and an explicit confirmation naming the selected backup timestamp.

- [ ] **Step 6: Run GREEN and full Plan 1 suite**

```powershell
flutter test test\local_only_pages_test.dart test\settings_local_backup_panel_test.dart test\backup_service_test.dart test\local_backup_controller_test.dart test\local_app_runtime_test.dart
flutter analyze
```

- [ ] **Step 7: Record Task 4 checkpoint and independent review**

Reviewer must confirm local file/PDF operations still have complete open, rename, delete, and save paths and that the UI contains no unreachable cloud actions.

---

### Task 5: Plan 1 Integration and Data-Safety Gate

**Files:**
- Modify tests only if a real regression requires a production fix.
- Create: `.superpowers/sdd/2026-08-09-local-runtime/plan-review-package.md`

- [ ] **Step 1: Run all automated checks from a clean process**

```powershell
flutter analyze
flutter test
```

Expected: no errors; existing warnings must be listed with file/line and classified.

- [ ] **Step 2: Perform a disposable migration/restore drill**

Use a temporary workspace fixture containing one event, one note, one PDF manifest record, one annotation, and one local file. Create a migration backup, mutate every item, restore, restart the runtime, and verify the original values and file hashes.

- [ ] **Step 3: Launch Windows offline**

Disconnect or block the configured API endpoint, start the app, and verify: no login page, no startup network blocker, local Today/Research/Materials/Settings usable, Weather shows cache/fallback, AI shows unconfigured state.

- [ ] **Step 4: Request whole-plan review**

The reviewer reads the spec, this plan, all Task 1–4 reports, the complete changed-file set, test output, and the disposable restore evidence. Do not start Plan 2 until the verdict has no Critical or Important findings.
