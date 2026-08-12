# Task 4 Fix Round 3 Review

Date: 2026-08-09  
Reviewer: independent Codex review  
Assessment: **CHANGES**

## Scope and evidence

I reviewed the current uncommitted working tree, the Task 4 plan, `task-4-report.md`, and the previous Fix Round 2 review. I traced the production runtime wiring, the coordinator's in-process queue/re-entry and Windows file-lock lifecycle, managed rename/delete journaling and startup recovery, backup semantic validation, and legacy migration ordering. I also inspected the focused tests rather than relying on the implementation report.

Fresh verification run:

```text
flutter test test/local_data_operation_coordinator_test.dart test/managed_local_files_test.dart test/research_life_controller_test.dart test/local_app_runtime_test.dart
00:04 +69: All tests passed!

git -c safe.directory='*' diff --check
exit 0 (line-ending warnings only)
```

The passing suite covers the ordinary journal recovery states, same-host Windows lock contention, missing-payload rejection, and migration-before-backup ordering. It does not exercise the two failure/concurrency sequences below.

## Strengths

- Production creates one coordinator with the workspace lock file and injects the same instance into the controller, local-file store, and backup service (`lib/app/local_app_runtime.dart:135-170`). On Windows, each coordinator opens a distinct writable handle, retries sharing/lock violations, and releases and closes the handle in `finally`; the in-process tail is released even when the operation or unlock fails (`lib/services/storage/local_data_operation_coordinator.dart:18-75`, `79-95`). The OS mutex itself therefore closes the prior simultaneous pending/previous-file and snapshot-vs-move race for cooperating app processes.
- The zone lease is scoped to the coordinator's private zone key and is invalidated before releasing the outer operation, so nested repository calls re-enter without deadlock while later detached work cannot retain bypass authority (`local_data_operation_coordinator.dart:14-21`, `32-50`).
- Rename/delete publish a flushed journal before moving bytes, and first-load recovery correctly distinguishes the principal pre-manifest and post-manifest states. It rolls an uncommitted move back, completes a committed delete, verifies a committed rename target, and only then clears the journal (`lib/services/storage/local_workspace_service.dart:285-320`; `lib/services/storage/local_file_library_store.dart:232-297`).
- Backup validation now hashes every listed local-library file and checks active portable manifest references against the copied payload set (`lib/services/storage/backup_service.dart:131-162`, `166-207`). The focused missing-payload regression is behavioral and fails through `createBackup`, not through a source-string assertion (`test/managed_local_files_test.dart:423-455`).
- Runtime startup loads the PDF library (including recovery and legacy absolute-path migration) before asking the backup controller to create the one-time migration backup, so the created snapshot contains managed payload bytes (`lib/app/local_app_runtime.dart:189-195`; `test/local_app_runtime_test.dart:408-460`).

## Critical

None.

## Important

### 1. Delete's second failure clears the only recovery record while manifest and payload disagree

`lib/state/research_life_controller.dart:2278-2297`

After the tombstone has been persisted, failure to delete the staged payload enters the cleanup catch. The code then attempts `saveDocument(document)` to roll the manifest back, but that await is inside a `try/finally`; even if the rollback save also fails, the `finally` restores the payload and clears `.managed_file_operation.json`. The resulting durable state is an `isDeleted: true` manifest record plus a live original payload, while the action throws and the controller still exposes the document because `_pdfDocuments.removeAt` was not reached. No journal remains for startup to reconcile that disagreement. The existing test only covers the earlier, single failure where the initial delete persistence fails (`test/research_life_controller_test.dart:1404-1426`).

Concrete fix: choose one committed outcome and retain recoverability until it is durable. If rollback is desired, do not restore the staged file or clear the journal unless `saveDocument(original)` succeeds; after that, restore the staged file and clear only after both manifest and payload agree. If rollback persistence fails, leave the committed tombstone, staged payload, and journal for startup to finalize (and make controller state/reported result match that committed outcome). Add an injected double that fails staged-file deletion and then fails the compensating manifest save; reopen the store and assert a single consistent outcome and journal cleanup.

### 2. The OS lock serializes processes, but stale controller snapshots can still overwrite a peer's committed path

`lib/state/research_life_controller.dart:2305-2327`, `5246-5262`; `lib/services/storage/local_file_library_store.dart:129-135`

Each runtime keeps its own `_pdfDocuments` snapshot. The file lock prevents simultaneous writes, but queued metadata updates persist the entire stale `PdfLibraryDocument`. Reproducible sequence: processes A and B both load `old.pdf`; A renames it to `new.pdf` and commits the new portable path; B then calls `markPdfDocumentOpened` or updates reading position. B acquires the OS lock later, but `_updatePdfDocument` builds from its stale `old.pdf` object and `_saveDocument` replaces the fresh manifest entry by ID with that stale path. The manifest again points to missing `old.pdf`, so a subsequent backup is rejected and the library is broken despite correct mutual exclusion. The analogous stale delete path (`research_life_controller.dart:2247-2267`) can tombstone the fresh record without staging the peer-renamed payload, leaving an orphan.

Concrete fix: inside the same top-level coordinator lease used for a mutation, reload the current persisted record by ID and merge only the intended fields before writing. Rename/delete must derive the physical source from that fresh record, not from the controller cache. Refresh or reconcile the local controller entry after commit. Add a two-runtime/same-lock integration test: A renames, then B updates metadata (and separately deletes); assert the manifest retains the new path and the correct payload is handled.

## Minor

### 1. Semantic validation accepts an active record with no path

`lib/services/storage/backup_service.dart:181-200`

The validator explicitly `continue`s when an active, non-cloud record has an empty path. Such a backup can validate while its active document has no resolvable payload, contrary to the semantic guarantee applied to other active records.

Concrete fix: reject empty paths for active non-cloud documents, then normalize the portable path and require a corresponding hashed `local_files/payloads/...` entry. Add empty/missing-path cases beside the missing-payload regression.

### 2. A store that was already loaded does not recover a journal left by a peer process crash

`lib/services/storage/local_file_library_store.dart:43-50`, `201-229`

Recovery is permanently disabled for a store instance after its first load. This avoids interpreting its own active journal during nested repository calls, but after the new OS lock is introduced it also means an already-running process cannot recover a journal left when another process crashes. Backups can remain rejected and operations can continue against the interrupted layout until some runtime is restarted.

Concrete fix: distinguish an outer lock acquisition from a re-entrant call and perform journal recovery after acquiring an outer lease, or include an operation owner/generation in the journal. That permits recovery after a peer releases the lock by exiting while preventing the active owner from rolling back its own operation. Add a two-coordinator test where B has already loaded, A leaves a pre-commit journal/move and releases its lock as a simulated crash, then B's next operation recovers before reading/writing.

### 3. Journal recovery does not reject unknown operation types

`lib/services/storage/local_file_library_store.dart:245-277`

Version is checked, but `type` is not restricted to `rename` or `delete`; every other value follows rename-style commit/rollback logic. A corrupted restored journal can therefore move a managed payload instead of failing closed.

Concrete fix: validate `type`, non-empty document ID, and distinct contained paths before any filesystem mutation; add malformed-journal tests.

## Assessment

**CHANGES.** The two prior architectural gaps are substantially addressed: the journal/semantic validator protect the normal crash states, the Windows OS lock genuinely serializes cooperating processes, and legacy migration occurs before the migration snapshot. Acceptance is still blocked by the delete double-failure branch and by whole-record writes from stale multi-process controller state. Both can leave the manifest and managed payload layout inconsistent under realistic failure or two-instance sequences.
