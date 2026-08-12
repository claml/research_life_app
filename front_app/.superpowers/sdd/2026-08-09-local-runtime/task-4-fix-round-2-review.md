# Task 4 Fix Round 2 Independent Code Review

Date: 2026-08-09

## Scope and evidence

Reviewed the current uncommitted working tree against Task 4, `task-4-fix-round-1-review.md`, and the updated `task-4-report.md`. I traced the shared coordinator from production runtime construction through controller/store/backup calls, reviewed re-entry and error release, checked restore and terminal-close ordering, inspected the Windows replacement protocol and recovery states, and reviewed the new behavioral tests. I also re-read the late `_runTrackedPdfOperation` fix and its RED/GREEN regression.

Fresh focused verification after that late fix:

```text
flutter test test\local_data_operation_coordinator_test.dart test\managed_local_files_test.dart test\local_pdf_output_test.dart test\research_life_controller_test.dart test\backup_service_test.dart test\local_backup_controller_test.dart test\local_app_runtime_test.dart
00:09 +97: All tests passed!
```

I did not repeat the full suite or analyzer. The supplied evidence remains `dart analyze` at the one-warning/five-info baseline and `git diff --check` exit 0.

## Round 1 Important closure

| Prior Important | Result | Evidence |
| --- | --- | --- |
| File mutations raced backup/pending persistence | Closed for one running app | `LocalAppRuntime.open()` injects the same coordinator into controller, store, and backup service; add/rename/delete and create/restore enter it. The late tracked-future fix also makes runtime flush wait for a direct managed-file operation (`local_app_runtime.dart:135-165`; `research_life_controller.dart:1979-1981,2084-2090,2216-2218,5150-5158`; `backup_service.dart:30-39,162-165`). |
| Manifest writes were directly truncating and import did not roll back | Closed for ordinary I/O failure | Manifest and annotations use flushed pending files, previous-file rollback, rename replacement, and next-read recovery. Import persists before touching visible state and deletes a newly created payload on save failure (`local_file_library_store.dart:193-309`; `research_life_controller.dart:2103-2164`). |
| Legacy records could alias one payload | Closed | Legacy migration passes `reuseIdenticalFile: false`; the real duplicate-name/bytes test obtains two paths (`local_file_library_store.dart:65-90`; `local_workspace_service.dart:196-240`; `managed_local_files_test.dart:278-320`). |
| PDF collision check had a TOCTOU overwrite | Closed for cooperating writers | Each candidate is reserved with `create(exclusive: true)` before writing; concurrent real writers preserve both outputs (`local_pdf_output.dart:29-57`; `local_pdf_output_test.dart:29-53`). |

## Strengths

- `LocalDataOperationCoordinator` is FIFO for callers outside the owning zone. Operation failure is delivered to that caller while `released` always completes normally, so one failed action does not poison the queue (`local_data_operation_coordinator.dart:11-31`). The nested store/repository calls needed by controller and restore are re-entrant rather than deadlocking.
- Production uses one actual coordinator instance, not merely one type in three independently constructed objects (`local_app_runtime.dart:135-165`). The shared-lock backup test and concurrent manifest-save test are behavioral and use real files (`managed_local_files_test.dart:157-234`).
- `restoreBackup()` holds the coordinator across validation, safety-backup creation, replacement, and rollback; its nested `_createBackup()` re-enters the same zone (`backup_service.dart:162-174`).
- The latest tracking change closes the runtime-close window for direct add/rename/delete. `_runTrackedPdfOperation()` registers the coordinator future in `_pendingPdfPersistence` synchronously, absorbs its error into controller state, and returns the original result to the action caller. The new gated test demonstrates that `flushLocalPersistence()` stays pending until import persistence finishes (`research_life_controller.dart:5150-5158`; `research_life_controller_test.dart:1460-1483`).
- The Windows replacement sequence is conservative for the JSON file itself: it never overwrites the committed target, retains `.previous` across the target-absent gap, restores it if publishing `.pending` fails, and cleans all three recoverable interruption states on the next locked read (`local_file_library_store.dart:262-309`).
- PDF write failure closes and removes its claimed candidate before rethrowing, while successful writers flush before returning (`local_pdf_output.dart:42-57`).

## Critical

None.

## Important

### 1. A crash between the payload move/stage and manifest commit still leaves an unrecovered, backup-valid broken library

Files: `lib/state/research_life_controller.dart:1992-2020,2226-2263`; `lib/services/storage/local_file_library_store.dart:193-224,262-309`; `lib/services/storage/backup_service.dart:145-159,336-359`.

The coordinator prevents concurrent code, and the pending/previous protocol makes one JSON replacement recoverable, but neither makes the payload and its manifest entry one crash transaction.

- Rename moves `old.pdf` to `new.pdf` before saving the new path. If the process terminates in that gap, the committed manifest still points to missing `old.pdf`; startup recovery only repairs `library_manifest.json.pending/previous` and does not discover the renamed payload.
- Delete renames the payload to `.deleting-*` before persisting the tombstone. A crash in that gap leaves a live manifest entry pointing to a missing original and the bytes stranded under the staged name.

On restart, `_resolvePortablePath()` accepts the old relative path without checking that its payload exists. Backup creation copies the broken manifest and whatever payload files remain; validation hashes listed files but does not require every non-deleted manifest path to exist. It can therefore publish and display a valid backup that restores the broken reference. The new exception-path rollback tests cannot simulate process termination between awaits.

Concrete fix: add a small flushed operation journal inside `local_files` before each managed rename/delete, containing document ID, original path, staged/new path, and intended state. Under the shared coordinator, recover it before loading or backing up: restore the old name when the old manifest is still committed, or finish cleanup when the new manifest/tombstone is committed. Remove the journal only after both sides commit. In addition, semantically validate `library_manifest.json` during backup creation/validation and reject any non-deleted managed record whose normalized relative payload is absent from the hashed `local_files` set. Add tests that construct both crash states, reopen the runtime, then create/restore a backup and verify bytes and resolved paths.

### 2. The coordinator and replacement filenames are process-local, but the Windows app is not single-instance

Files: `lib/services/storage/local_data_operation_coordinator.dart:7-31`; `lib/services/storage/local_file_library_store.dart:262-309`; `lib/app/local_app_runtime.dart:135-165`; `windows/runner/main.cpp`; `windows/runner/flutter_window.cpp`.

Each runtime owns an in-memory coordinator. The Windows runner contains no named mutex/single-instance handoff, so two launched app processes can open the same workspace with different coordinators. Their store writes use the same fixed `library_manifest.json.pending` and `.previous` names: one process can delete or rename the other process's pending/previous file, both can read the same old manifest and publish last-writer-wins state, and one process can snapshot while the other moves payloads. This bypasses every new in-process guarantee and can again produce a hash-valid but semantically torn backup.

Concrete fix: simplest for this personal desktop app is to enforce one process per workspace with a named Windows mutex (workspace-derived identity) and bring the existing window forward on a second launch. If multiple processes are intentional, replace the in-memory coordinator with an inter-process lock and use unique transaction filenames plus conflict-aware manifest commit. Add a runner/integration test or a two-process filesystem test proving the second writer cannot enter while the first owns the workspace.

## Minor

### 1. Zone re-entry authority can escape with detached asynchronous work

File: `lib/services/storage/local_data_operation_coordinator.dart:11-30`.

Any future or timer created in the owning zone inherits `_zoneKey`. If an operation launches detached work and then returns, that later callback still sees itself as re-entrant and can bypass a lock now owned by an unrelated queued operation. Current managed-file operations await their repository work, so this is a robustness boundary rather than a demonstrated production race.

Concrete fix: store an owner token with an `active` flag in the zone and allow re-entry only while that specific token remains active; deactivate it before releasing the queue. Test a delayed child that calls `runExclusive` only after its parent returned and verify it queues behind the next owner.

### 2. Terminal close does not wait for a manual backup already holding the coordinator

Files: `lib/app/local_app_runtime.dart:99-107,243-245`; `lib/state/local_backup_controller.dart:110-117`; `lib/services/storage/backup_service.dart:30-39`.

The tracked fix makes close wait for controller-managed file operations, and restore itself is a root transition. A manual backup, however, is owned by `LocalBackupController` and is not part of `controller.flushLocalPersistence()` or the runtime disposal steps. Quitting while it is busy can dispose the controller/database and complete framework exit while backup copying is still running. The current data remains safe and an unpublished `.pending-*` backup is ignored, so this is not an Important data-loss defect.

Concrete fix: expose a backup-controller idle future and await it (or explicitly cancel and await cleanup) before owned services/database are disposed. Add a gated manual-backup-plus-exit test.

### 3. Empty PDF responses are still reported as successfully saved files

File: `lib/features/pdf_tools/local_pdf_output.dart:16-57`.

Exclusive reservation fixes overwrite, but zero-length `bytes` still creates and returns an empty output. A 200 response with an empty body therefore produces a corrupt file and success snackbar.

Concrete fix: reject empty bytes before claiming a path, and test that no file is created. Also preserve the original write error if closing/deleting a partially written candidate fails.

### 4. The two previous defensive/product-boundary Minors remain

Files: `lib/services/storage/local_workspace_service.dart:242-249`; `lib/features/pdf_tools/pdf_tools_page.dart:94-123,274-302`; `lib/services/pdf/pdf_operation_api.dart:30-76`.

Managed-path containment is still lexical and does not resolve `..` aliases or Windows junctions before destructive operations. Ordinary PDF transformations also still upload local documents to the optional compile-time backend without disclosing that dependency/destination in the local-input/output UI. These were not among the four round-2 Important fixes, but remain worth correcting as described in the prior report.

## Assessment

**CHANGES**

All four prior Important findings are closed for the tested single-process, non-crashing execution path, and the late direct-operation tracking fix correctly protects restore/close from disposing too early. Acceptance is still blocked by two uncovered boundaries: payload-plus-manifest operations have no crash journal/recovery or semantic backup validation, and the in-memory lock is ineffective across multiple Windows app instances sharing the workspace.
