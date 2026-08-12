# Task 4 Fix Round 4 Review

Date: 2026-08-09  
Reviewer: independent Codex review  
Assessment: **PASS**

## Scope and verification

This was a deliberately narrow review of the two Important findings in `task-4-fix-round-3-review.md`, plus the active-empty-path and unknown-journal-type hardening added in the same fix round. I traced the production controller/repository/store call chain, coordinator re-entry, manifest merge fields, delete recovery states, and the new behavioral doubles/tests.

Fresh focused verification:

```text
flutter test test/managed_local_files_test.dart test/research_life_controller_test.dart test/backup_service_test.dart
00:02 +72: All tests passed!
```

## Strengths

- Direct rename and delete still enter through `_runTrackedPdfOperation`, which acquires the shared coordinator before invoking the operation (`lib/state/research_life_controller.dart:1979-1983`, `2252-2256`, `5216-5224`). Their `findById` calls therefore execute as re-entrant repository/store calls under that same lease and read the latest persisted record before choosing a physical path (`research_life_controller.dart:1988-2001`, `2257-2275`; `lib/services/database/repositories/pdf_documents_repository.dart:61-64`). The stale-delete regression uses a peer-renamed payload and proves the fresh path is staged and removed (`test/research_life_controller_test.dart:1509-1531`).
- Queued open/reading metadata writes are explicitly tagged `metadata` (`research_life_controller.dart:5201-5213`). The repository routes only that operation to `mergeMetadata`, and the store reads the current manifest while holding its coordinator before merging (`lib/services/database/repositories/pdf_documents_repository.dart:71-87`; `lib/services/storage/local_file_library_store.dart:125-172`). The merge starts from the current persisted document and does not replace `id`, `title`, `path`, `fileKind`, `category`, `createdAt`, or `isDeleted`; it applies only mutable metadata fields (`local_file_library_store.dart:140-165`). Thus a stale writer no longer reverts a peer rename or resurrects a tombstone. The regression verifies peer title/path and the requested metadata all survive (`test/managed_local_files_test.dart:457-497`).
- In the staged-delete cleanup plus compensating-save double failure, the initial delete has already committed a tombstone. If payload cleanup fails and the compensating save also fails, the inner catch removes the cached controller record and annotations, notifies listeners, and rethrows without restoring the staged payload or clearing the journal (`research_life_controller.dart:2288-2323`). Durable manifest state and controller state therefore both represent deletion. A fresh store sees the committed-delete journal, removes the staging file, and only then clears the journal (`lib/services/storage/local_file_library_store.dart:318-330`). The injected test checks the thrown result, retained journal, removed controller entry, and successful reopen cleanup (`test/research_life_controller_test.dart:1533-1563`, `1617-1664`).
- Active non-cloud records with an empty path now fail semantic backup validation instead of bypassing payload checks (`lib/services/storage/backup_service.dart:181-201`; `test/managed_local_files_test.dart:499-523`).
- Journal `type` and non-empty `documentId` are validated before either portable path is resolved or any filesystem mutation occurs, so malformed operation metadata fails closed (`lib/services/storage/local_file_library_store.dart:282-303`).

## Critical

None.

## Important

None.

## Minor

### 1. A successful manifest rollback followed by payload-restore failure removes the controller entry temporarily

`lib/state/research_life_controller.dart:2307-2323`

The inner catch handles failures from three different steps: compensating manifest save, staged-file restore, and journal clear. Removing the controller entry is correct when the compensating save itself failed because the tombstone remains committed. If that save succeeded but `restoreStagedManagedFile` or journal cleanup then fails, the durable manifest is active while the controller entry is removed until reload. The journal is retained and startup recovery remains safe, so this is not a data-loss or acceptance blocker.

Concrete fix: track whether the compensating manifest save committed. On a later restore/clear failure, reconcile the controller from the persisted record (or retain the original entry and expose a recovery-required error); remove it only when the tombstone is still the committed state. Add an injected restore failure test.

### 2. The stale-metadata regression does not assert tombstone preservation

`test/managed_local_files_test.dart:457-497`

The implementation preserves `isDeleted` because the merge starts from `current` and never supplies `isDeleted`, but the regression only asserts peer `title`/`path` and `lastPage`. A future widening of the merge could accidentally resurrect a peer-deleted record without this test detecting it.

Concrete fix: add a second stale metadata case where the current persisted record is tombstoned and assert `isDeleted` remains true (also retaining current path/title).

### 3. Unknown journal type rejection has no behavioral regression

`lib/services/storage/local_file_library_store.dart:282-303`

The validation is correctly ordered before path resolution and mutation, but no focused test constructs an unknown-type journal and verifies that both payload paths and the journal remain untouched.

Concrete fix: add a malformed-journal test asserting `loadDocuments` throws `FormatException` and neither source nor target is moved or deleted.

## Assessment

**PASS.** Both Round 3 Important findings are closed in the reviewed production paths. Fresh persisted identity is used under the same coordinator lease for rename/delete, metadata merge preserves structural identity and deletion state, and the delete double-failure branch retains the recovery journal while aligning controller state with the committed tombstone. The remaining findings are bounded recovery-state or regression-coverage improvements; none introduces a Critical or Important data-safety defect.
