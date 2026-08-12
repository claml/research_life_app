# Task 2 Fix Round 2 Independent Review

Date: 2026-08-09

Reviewed scope:

- `lib/services/storage/backup_service.dart`
- `lib/state/local_backup_controller.dart`
- `test/backup_service_test.dart`
- `test/local_backup_controller_test.dart`
- the current Task 2 working diff and prior review findings

Supplied verification: the related preferences, controller, and backup suites pass 36/36. The review did not rerun commands that generate build artifacts.

## Strengths

- `BackupService.pruneBackups()` normalizes both supplied protected paths and listed backup directories to absolute paths, with case-insensitive comparison on Windows.
- Purpose filtering still occurs before protection and deletion decisions, so migration retention cannot delete `manual` or `safety` backups.
- For the production controller case of one protected path and `keep: 10`, the algorithm reserves one retained slot for the newly created migration backup and keeps the nine newest unprotected migrations. The total remains ten even when the protected backup is chronologically oldest.
- `LocalBackupController.ensureMigrationBackup()` passes `created.directory.absolute.path` through `protectedPaths`; the controller test explicitly checks the exact protected path supplied.
- After pruning and list refresh, the controller calls `validateBackup(created.directory)` again and checks `BackupPurpose.migration` before the transactional path-plus-marker commit.
- The real-file clock-regression test creates ten future-dated migration backups, moves the injected clock backward, creates an older eleventh backup, invokes protected pruning, and verifies that the protected directory still exists, validates, and that the validated backup count is ten. This exercises actual deletion rather than only a fake call record.
- The prior restore lifecycle, dispose guard, serialization, stale-marker invalidation, transaction, and absolute-path fixes remain intact.

## Critical

None.

## Important

### 1. More protected candidates than `keep` silently violates the retention upper bound

`lib/services/storage/backup_service.dart:87-109`

The implementation retains every matched protected candidate. When `protected.length >= keep`, `unprotectedToKeep` becomes zero and only unprotected candidates are deleted. If, for example, eleven validated paths are protected with `keep: 10`, all eleven protected backups remain and the method succeeds, so `pruneBackups(keep: 10)` no longer maintains its advertised upper bound.

This is impossible in the current controller call, which protects exactly one path, but it is exposed by the new public `Set<String> protectedPaths` API and contradicts the stated protection algorithm requirement to preserve protected priority while maintaining the `keep` limit.

Concrete fix: make the invalid combination explicit. Prefer rejecting the operation with `ArgumentError` when the number of matched protected candidates exceeds `keep`, so no caller is told pruning succeeded while either the cap or protection promise was broken. Alternatively narrow the API to a single optional protected path if only the controller use case is supported. Add a real-file regression with `keep: 1` and two protected validated backups, asserting the chosen contract: rejection without deletion, or a documented deterministic single protected winner.

## Minor

- `test/local_backup_controller_test.dart:398-408` uses one `failValidation` flag for both the initial and post-prune validation. It verifies the second validation exists by source inspection but cannot specifically fail only the post-prune validation and prove the marker remains false. Add a validation-call counter or `failValidationOnCall` for direct coverage.
- `test/backup_service_test.dart:442-473` fully covers the one-protected clock-rollback scenario but not path-equivalent spellings such as relative versus absolute protected inputs. The implementation normalizes them correctly by inspection; a small regression would protect that API detail.

## Assessment

**CHANGES**

Fix Round 2 closes the production controller's clock-rollback deletion bug: the controller truly protects the newly created path, revalidates it after retention, and commits the marker only afterward. The remaining Important finding is the unhandled public-API boundary where matched protected paths outnumber `keep`, causing retention to exceed its declared limit.
