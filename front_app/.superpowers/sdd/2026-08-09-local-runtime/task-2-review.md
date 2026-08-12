# Task 2 Independent Review

Date: 2026-08-09

## Strengths

- Existing migration records are revalidated and must have `BackupPurpose.migration`; missing, corrupt, or wrong-purpose records trigger replacement.
- New backups are explicitly revalidated before persistence. `PreferencesRepository` writes the path before the completion marker.
- Purpose-filtered pruning operates on validated, newest-first backups and correctly leaves `manual` and `safety` backups untouched.
- Manual backup and restore remain separated correctly: the controller validates and delegates runtime replacement instead of directly replacing an open database.
- Test doubles are type-valid and override all currently invoked `BackupService` methods.

## Critical

None.

## Important

### 1. Restore continues using a controller/runtime that the callback may already have disposed

`lib/state/local_backup_controller.dart:94-98,126-128`

Task 3 defines `restoreRuntime` as closing and replacing the current runtime. After it returns, the old controller calls `_refreshBackups()` through the old service, mutates messages, and finally calls `notifyListeners()`. Flutter's `ChangeNotifier.notifyListeners()` asserts when called after disposal, while the old service/database may also be closed.

Concrete fix: treat successful `restoreRuntime` as a terminal handoff, perform no old-service refresh afterward, and guard final notification with explicit disposal state, or defer disposal until the controller future has unwound. Add a test whose restore callback disposes the controller and makes the old backup service unusable.

### 2. The completion marker remains true on multiple failed replacement branches

`lib/state/local_backup_controller.dart:43-78`

`lib/services/database/repositories/preferences_repository.dart:196-198`

If a previously completed backup is missing, corrupt, or wrong-purpose, the controller falls through without invalidating the stale marker. A subsequent create or validation failure therefore leaves `complete == true`. For a new backup, the record is saved before pruning and refresh, so either later failure is reported while the marker is already true. This contradicts the Task 2 requirement that every failed migration branch leave completion false.

Concrete fix: invalidate a stale record before replacement, perform create, validation, pruning, and refresh first, and make the durable path-plus-marker commit the final fallible step. Prefer an atomic repository transaction or explicit invalidation API. Test stale-record plus create failure, prune failure, refresh failure, and second-write failure.

### 3. `ensureMigrationBackup()` does not acquire serialization before accessing preferences and backup files

`lib/state/local_backup_controller.dart:38-60`

Preference loading, recorded-backup validation, and the completed-path refresh occur outside `_run`. Thus an already-completed migration check can overlap an active restore and touch preferences while the runtime/database is closing. It also bypasses `busy` and error-message handling.

Concrete fix: acquire the controller operation lock at method entry and keep the whole method inside it; parameterize flushing if the no-op validation path should not flush. Add a concurrency test using an already-completed valid record during a gated restore or manual backup.

### 4. The persisted path is not guaranteed to be absolute

`lib/state/local_backup_controller.dart:68-70`

The contract explicitly requires an absolute path, but the controller stores `created.directory.path`. `LocalWorkspaceService` permits injected or environment-configured relative roots.

Concrete fix: persist `created.directory.absolute.path` and test using a relative fake directory.

## Minor

- `lib/state/local_backup_controller.dart:43-50,102-109`: successful early return and public refresh do not normalize `message` and `messageIsError`. A failed post-marker prune followed by a successful retry can leave `messageIsError == true`. Clear success state on every successful exit and surface refresh failures consistently.
- `test/local_backup_controller_test.dart:137-140,192-198`: the restore double never models runtime disposal, and the preference failure double fails before either field changes. They therefore miss the two principal lifecycle and ordering defects. The doubles are syntactically valid but behaviorally incomplete.

## Assessment

**CHANGES**

The supplied 29/29 result confirms covered paths, but the uncovered lifecycle, serialization, and marker-failure branches are material Task 2 contract violations.
