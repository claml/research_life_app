# Task 2 Fix Round 1 Independent Review

Date: 2026-08-09

Reviewed scope:

- `lib/state/local_backup_controller.dart`
- `lib/services/database/repositories/preferences_repository.dart`
- the purpose-filtered retention extension in `lib/services/storage/backup_service.dart`
- `test/local_backup_controller_test.dart`
- `test/database_preferences_repository_test.dart`
- relevant backup-service tests and the current working diff

Supplied verification: the preferences, controller, and backup suites pass 35/35. The review did not rerun commands that generate build artifacts.

## Strengths

- `restore()` now treats runtime replacement as a terminal handoff. It validates before delegation and performs no backup-service access after the callback returns.
- `_disposed` plus `_notifyListenersIfActive()` prevents the `_run()` finalizer from notifying an already-disposed `ChangeNotifier`. The new test disposes the controller and closes the fake service from inside the restore callback.
- `ensureMigrationBackup()` now acquires `_run()` before loading preferences or validating the recorded backup, so the completed-record path cannot bypass busy serialization. Public refresh uses the same lock.
- Stale or partial migration records are invalidated marker-first before replacement creation. A failed replacement therefore leaves durable state incomplete.
- Creation, explicit validation, migration-only pruning, and list refresh occur before the migration record is committed.
- `saveLocalMigrationBackupRecord()` writes path then marker inside a Drift transaction, preventing a second-write failure from leaving a partially committed new record.
- The persisted path is now `created.directory.absolute.path`, and a relative-directory regression test verifies the contract.
- Purpose filtering still selects only validated `migration` backups; the real backup-service regression confirms `manual` and `safety` backups are not deleted.
- The doubles are type-valid, and the new lifecycle, stale-record, prune-failure, list-failure, absolute-path, and serialization cases materially improve coverage.

## Critical

None.

## Important

### 1. Retention can delete the newly validated migration backup before its path is marked complete

`lib/state/local_backup_controller.dart:70-81`

`lib/services/storage/backup_service.dart:58-85`

The controller validates `created.directory`, then calls generic purpose-filtered pruning. `pruneBackups()` sorts by manifest `createdAt` and keeps the newest ten candidates; it does not protect the directory just created. If the system clock has moved backwards, or ten existing migration manifests have future timestamps, the new backup is the oldest candidate and is deleted. `_refreshBackups()` can still succeed, after which the controller transaction stores the deleted directory and sets the completion marker true. Startup can then continue without the newly created, validated migration safety backup promised by this operation.

Concrete fix: make retention accept a protected backup/path and exclude `created.directory` from deletion while still enforcing the cap, or implement migration retention that always retains the just-created backup and removes the oldest unprotected migration backups. Revalidate the protected directory immediately before committing the record as a final defense. Add a real `BackupService`/controller integration test with ten future-dated migration backups and a clock-regressed newly created backup; assert the new directory exists, validates, and is the recorded absolute path after pruning.

The current controller fake at `test/local_backup_controller_test.dart:419-428` only records the filter and returns zero, so it cannot expose deletion of the newly created entry.

## Minor

- `test/database_preferences_repository_test.dart:90-108` verifies transactional record success and invalidation but does not force the second insert to fail and prove rollback. The production transaction is correct by inspection, but a database trigger or injectable write failure would make the partial-write guarantee executable.
- `lib/state/local_backup_controller.dart:97-103` intentionally does not publish a restore-success message when the callback leaves the controller alive. This is reasonable for the production terminal-replacement contract, but the behavior should remain documented so a future non-replacing callback does not expect success state on the old controller.

## Assessment

**CHANGES**

Fix Round 1 resolves the previously reported restore lifecycle, disposal, full-operation serialization, stale marker, partial-write, refresh-state, and absolute-path findings. The remaining retention ordering issue is Important because it can mark a path complete after pruning has deleted that exact newly validated backup.
