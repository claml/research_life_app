# Task 4 Report — Local Files, PDF, AI State, and Settings

Date: 2026-08-09

## Completed behavior

- `MyFilesPage` now renders one local library only. Import, selection, rename,
  delete, document/PDF open routing, and PDF-tools routing remain available.
  Account, guest, upload, download, cloud tree, sync state, and cloud-message
  branches were removed from the active page.
- `PdfToolsPage` now accepts local PDF paths only, including multiple files for
  merge. Every generated binary prompts for a local output directory and is
  written directly to that directory. Cloud selection, cloud placeholders,
  upload choices, and authentication gates were removed.
- The PDF operation client is constructed without an application account token.
  The existing processing service remains optional; a failure is localized to
  the PDF page and does not affect startup or local library access.
- `AgentPage` no longer reads `AuthScope` or `AuthController`. Before creating
  the conversation controller it waits for local AI settings and shows a short
  `AI 服务尚未配置` state when URL, model, or key is absent.
- The AI empty-state action requests cross-section navigation to Settings.
- Settings no longer imports or renders account, login, logout, migration,
  SyncStatusPanel, or immediate-sync controls. They are replaced by a local
  backup-and-restore section.
- `LocalBackupPanel` shows the newest validated backup time, backup root,
  controller message/busy state, and exactly three actions: immediate backup,
  open backup directory, restore backup. Restore validates the selected folder
  before presenting a confirmation that names its timestamp.

## Changed files

- `lib/features/files/my_files_page.dart`
- `lib/features/pdf_tools/pdf_tools_page.dart`
- `lib/features/agent/agent_page.dart`
- `lib/features/settings/settings_page.dart`
- `lib/features/settings/widgets/local_backup_panel.dart`
- `lib/state/local_backup_controller.dart`
- `lib/state/research_life_controller.dart`
- `lib/app/app_shell.dart`
- `test/local_only_pages_test.dart`
- `test/settings_local_backup_panel_test.dart`

## TDD evidence

Initial RED:

```text
Error when reading local_backup_panel.dart: system cannot find the file.
Method not found: LocalBackupPanel.
active local pages do not import auth or cloud UI: AuthScope still present.
AI and Settings expose local configuration and backup only:
AI 服务尚未配置 was absent.
```

Focused GREEN:

```text
flutter test test/local_only_pages_test.dart test/settings_local_backup_panel_test.dart
00:01 +4: All tests passed!
```

Plan 1 local-safety suite:

```text
flutter test test/local_only_pages_test.dart test/settings_local_backup_panel_test.dart test/backup_service_test.dart test/local_backup_controller_test.dart test/local_app_runtime_test.dart
00:07 +52: All tests passed!
```

Fresh full verification:

```text
flutter test
00:12 +228: All tests passed!

dart analyze
1 warning + 5 info (all pre-existing baseline findings)

git diff --check
exit 0
```

## Scope notes

- This task did not add or redesign AI credential persistence. That remains a
  separate security-focused task as required by the plan.
- Legacy auth/sync/cloud source remains outside the active local page/runtime
  graph for phased deletion later; this task removes only active UI/runtime
  dependencies.
- No production workspace or user file was opened, changed, or deleted during
  tests. Backup-panel tests use fakes and all runtime/backup integration tests
  use isolated temporary data.

## Review fix round 1

The independent review found that imported file payloads lived outside the
backup boundary, while their manifest entries used absolute paths. It also
found optimistic rename/delete behavior, an overwrite-prone PDF output path,
scan error-handling gaps, and visible PDF AI actions wired to a fixed backend.

Fixes:

- Imported payloads now live below
  `.research_life/local_files/payloads/<category>` and are therefore included
  recursively in every validated backup.
- The local library manifest stores managed paths relative to `local_files`.
  Loading resolves them against the current workspace, so restoring into a
  different root remains usable. Existing absolute local paths are migrated
  into managed storage when they are first loaded.
- Rename now moves the managed file, persists the new path, and rolls the move
  back if persistence fails. Delete stages the file, persists the deletion,
  then removes the bytes; a persistence failure restores the staged file.
- My Files waits for import persistence before reporting success and no longer
  offers image imports that the page cannot open.
- PDF scan uses the page's common busy/error/mounted flow. PDF output uses a
  collision-safe writer (`result (1).pdf`, etc.) and never overwrites an
  existing file.
- The unconfigured PDF AI section was removed. The separately configured local
  Agent page remains the only visible AI surface.
- Backup inspection now participates in the backup controller's busy-state
  serialization.

Added/updated verification:

```text
flutter test test/managed_local_files_test.dart test/local_pdf_output_test.dart test/research_life_controller_test.dart
00:01 +38: All tests passed!

flutter test test/research_life_controller_test.dart --plain-name "persistence fails"
00:00 +2: All tests passed!

flutter test
00:18 +234: All tests passed!

dart analyze
1 warning + 5 info (unchanged pre-existing baseline)

git diff --check
exit 0
```

Review-fix files:

- `lib/services/storage/local_workspace_service.dart`
- `lib/services/storage/local_file_library_store.dart`
- `lib/state/research_life_controller.dart`
- `lib/features/files/my_files_page.dart`
- `lib/features/pdf_tools/pdf_tools_page.dart`
- `lib/features/pdf_tools/local_pdf_output.dart`
- `lib/state/local_backup_controller.dart`
- `test/managed_local_files_test.dart`
- `test/local_pdf_output_test.dart`
- `test/research_life_controller_test.dart`
- `test/local_workspace_service_test.dart`

## Review fix round 2

The first fix-round review accepted the cross-root payload restore, but found
four remaining race/crash boundaries. They are now addressed as follows:

- `LocalDataOperationCoordinator` provides a FIFO, zone-reentrant exclusive
  section. The production runtime shares one coordinator between
  `ResearchLifeController`, `LocalFileLibraryStore`, and `BackupService`, so
  file copy/move/delete, manifest writes, backup snapshots, and restore cannot
  overlap into a torn but hash-valid backup.
- Direct import/rename/delete futures are also tracked by
  `_pendingPdfPersistence`; runtime shutdown and backup flushing wait for an
  already-running managed-file operation before closing the database.
- Manifest and annotation JSON use flushed `*.pending` writes, preserve the
  prior committed file as `*.previous`, atomically rename the pending file,
  and recover an interrupted replacement on the next read.
- Imports persist before entering visible controller state and remove a newly
  copied payload if persistence fails.
- Legacy absolute-path migration disables identical-file reuse, so two records
  with identical names and bytes receive distinct managed payload paths.
- PDF output reserves its path with exclusive file creation before opening it;
  concurrent writers receive `result.pdf`, `result (1).pdf`, and so on without
  overwriting either writer.

RED evidence included a reproducible one-path result from two simultaneous PDF
writes, a missing coordinator API, and an import that returned success while
its injected repository save failed. GREEN verification:

```text
flutter test test/local_data_operation_coordinator_test.dart test/managed_local_files_test.dart test/local_pdf_output_test.dart test/research_life_controller_test.dart test/backup_service_test.dart test/local_backup_controller_test.dart test/local_app_runtime_test.dart
00:09 +96: All tests passed!

flutter test
00:16 +242: All tests passed!

dart analyze
1 warning + 5 info (unchanged pre-existing baseline)

git diff --check
exit 0
```

Additional round-2 files:

- `lib/services/storage/local_data_operation_coordinator.dart`
- `lib/services/storage/backup_service.dart`
- `lib/app/local_app_runtime.dart`
- `test/local_data_operation_coordinator_test.dart`

## Review fix round 3

The second fix-round review identified two remaining multi-instance and crash
consistency gaps. This round closes both boundaries:

- The shared local-data coordinator now optionally acquires a workspace OS
  file lock. Production runtimes use `.research_life/.local_data.lock`, so
  independent app processes serialize managed-file mutations, backup, and
  restore instead of racing fixed pending/previous files.
- The coordinator's re-entrant zone lease expires when the owning operation
  finishes, so detached asynchronous work cannot retain lock-bypass authority.
- Managed rename/delete operations write a flushed, atomically published
  `.managed_file_operation.json` before moving bytes. On the next library
  startup, an uncommitted move is rolled back; a committed delete is finalized;
  and the journal is removed only after the file and manifest agree.
- Backup validation parses `library_manifest.json` and requires every active
  portable `payloads/...` reference to have a corresponding hashed backup
  entry. A hash-valid archive with a missing payload is now rejected.
- Legacy absolute-path records are migrated into managed storage before the
  one-time migration backup is created, ensuring the safety snapshot includes
  the actual payload bytes.

RED evidence reproduced an unsupported OS lock resolver, a rename left at its
target after an interrupted pre-commit move, and a missing payload backup that
incorrectly validated. An integration regression also caught active journals
being mistaken for stale startup journals; recovery is now limited to the
store's first library load.

```text
flutter test test/local_data_operation_coordinator_test.dart test/managed_local_files_test.dart
00:01 +10: All tests passed!

flutter test test/research_life_controller_test.dart test/local_app_runtime_test.dart
00:03 +58: All tests passed!

flutter test
00:15 +249: All tests passed!

dart analyze
1 pre-existing warning + 5 pre-existing info after removing the new warning

git diff --check
exit 0 (line-ending notices only)
```

Additional round-3 files:

- `lib/services/storage/local_data_operation_coordinator.dart`
- `lib/services/storage/local_workspace_service.dart`
- `lib/services/storage/local_file_library_store.dart`
- `lib/services/storage/backup_service.dart`
- `lib/state/research_life_controller.dart`
- `lib/app/local_app_runtime.dart`
- `test/local_data_operation_coordinator_test.dart`
- `test/managed_local_files_test.dart`
- `test/research_life_controller_test.dart`
- `test/local_app_runtime_test.dart`

## Review fix round 4

The round-3 review found two remaining consistency failures. Both now have
behavioral regressions and durable recovery paths:

- Rename and delete reload the latest persisted document while already inside
  the shared coordinator lease, so their physical source path comes from the
  peer's most recent commit rather than from stale controller memory.
- Queued reading/open-state writes use a metadata-merge mode. The local store
  merges those fields into the fresh manifest record while preserving its
  managed identity, title, path, deletion state, and creation fields.
- Staged payload deletion is now an injectable workspace operation. If payload
  cleanup fails and the compensating manifest save also fails, the controller
  reflects the committed tombstone and leaves the staged payload plus journal
  for startup recovery; it no longer restores bytes and clears the only
  recovery record.
- Backup semantic validation also rejects active non-cloud records with an
  empty path. Legacy structural test fixtures now mark pathless placeholders
  as deleted records rather than weakening production validation.
- Journal recovery rejects unknown operation types and empty document IDs
  before mutating files.

RED evidence reproduced a stale controller deleting the old missing path while
leaving the peer-renamed payload, a metadata save reverting the manifest to
that missing path, and a double-failure delete that incorrectly returned
success. GREEN verification:

```text
flutter test test/managed_local_files_test.dart test/research_life_controller_test.dart
00:01 +54: All tests passed!

flutter test test/backup_service_test.dart test/managed_local_files_test.dart test/research_life_controller_test.dart
passed

flutter test
00:19 +253: All tests passed!
```

Additional round-4 files:

- `lib/services/storage/local_workspace_service.dart`
- `lib/services/storage/local_file_library_store.dart`
- `lib/services/database/repositories/pdf_documents_repository.dart`
- `lib/services/storage/backup_service.dart`
- `lib/state/research_life_controller.dart`
- `test/backup_service_test.dart`
- `test/managed_local_files_test.dart`
- `test/research_life_controller_test.dart`
