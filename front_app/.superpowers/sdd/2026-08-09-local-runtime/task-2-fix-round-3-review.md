# Task 2 Fix Round 3 Final Independent Review

Date: 2026-08-09

Reviewed scope:

- `lib/services/storage/backup_service.dart`
- `lib/state/local_backup_controller.dart`
- `lib/services/database/repositories/preferences_repository.dart`
- `test/backup_service_test.dart`
- `test/local_backup_controller_test.dart`
- the complete current Task 2 change set and all prior Task 2 review findings

Supplied verification: the related preferences, controller, and backup suites pass 38/38. The review did not rerun commands that generate build artifacts.

## Strengths

- `pruneBackups()` computes protected matches only from validated, purpose-filtered candidates. Non-candidate paths cannot incorrectly consume the retention allowance.
- Protected and listed directory paths are normalized to absolute paths, with Windows case folding. The clock-rollback real-file regression now supplies the protected backup through a relative path and still retains the correct absolute directory.
- When matched protected candidates exceed `keep`, the service throws `ArgumentError` before it constructs or executes the deletion loop. The real-file `keep: 1` regression protects two validated directories and proves both still exist after rejection.
- With an allowed protected count, protected entries consume retention slots first and the remaining slots retain the newest unprotected candidates, so the validated candidate total respects `keep`.
- Purpose filtering remains intact; migration pruning cannot delete `manual` or `safety` backups.
- `LocalBackupController` passes the newly created backup's absolute path as protected, refreshes the visible list, then revalidates both existence/integrity and `BackupPurpose.migration` before committing the record.
- The fake backup service now counts validation calls and can fail a selected call. The post-retention regression fails exactly the second validation and proves neither path nor completion marker is written.
- Migration record persistence remains transactional and ordered path-before-marker. Stale records remain invalidated marker-first.
- Restore remains a terminal runtime handoff with no old-service access after replacement, and disposed controllers suppress final listener notification.
- Migration checks, manual backups, restores, and explicit refreshes remain serialized through the same busy boundary.

## Critical

None.

## Important

None.

## Minor

None.

## Assessment

**PASS**

Fix Round 3 resolves the final protected-retention boundary and closes the two targeted coverage gaps. The implementation now preserves the newly created migration backup under clock rollback, enforces the retention limit without destructive side effects for impossible protection requests, revalidates immediately before the atomic marker commit, and maintains the restore and controller lifecycle guarantees from earlier rounds.
