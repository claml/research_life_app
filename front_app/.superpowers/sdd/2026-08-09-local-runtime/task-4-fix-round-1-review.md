# Task 4 Fix Round 1 Independent Code Review

Date: 2026-08-09

## Scope and evidence

Reviewed the current uncommitted working tree against Task 4 of the implementation plan, the local-workbench design, the original `task-4-review.md`, and the updated `task-4-report.md`. The review followed the managed-file bytes and manifest through import, legacy migration, rename, delete, backup, restore into another workspace root, and PDF output creation. I also inspected the new and changed tests, including the subsequently added real legacy-absolute-path migration test.

I did not repeat the full suite or analyzer. The supplied evidence is 234/234 for the then-current full suite, the unchanged analyzer baseline of one warning and five infos, and `git diff --check` exit 0. I freshly ran:

```text
flutter test test\managed_local_files_test.dart test\local_pdf_output_test.dart test\local_backup_controller_test.dart
00:00 +17: All tests passed!
```

This fresh run includes both managed-file integration tests, including the newly added legacy migration case.

## Strengths

- The previous Critical defect is materially fixed for the normal path. `copyFileIntoMaterials()` now writes below `.research_life/local_files/payloads`, `LocalFileLibraryStore` stores those paths relative to `local_files`, and `BackupService` recursively hashes, copies, restores, and rolls back the whole `local_files` tree. The real integration test restores into a different root and verifies the original payload bytes (`local_workspace_service.dart:89-110,196-225`; `local_file_library_store.dart:287-317`; `managed_local_files_test.dart:13-96`).
- The added legacy test is behavioral rather than a source scan: it starts with an absolute `资料/...` manifest entry, loads it, checks the copied bytes, and verifies the manifest was rewritten to `payloads/...` (`managed_local_files_test.dart:98-153`).
- Rename and delete now operate on managed bytes and attempt rollback around repository failure. The happy-path and pre-write-failure tests use real temporary files and a real `LocalFileLibraryStore`, so they establish more than in-memory behavior (`research_life_controller.dart:1976-2013,2187-2229`; `research_life_controller_test.dart:1331-1431`).
- My Files no longer offers image types that it cannot open, and import waits for the queued manifest write before displaying success (`my_files_page.dart:124-161`). The visible PDF AI actions have been removed; the Agent remains the sole configured AI surface.
- Scan-to-PDF now uses the common busy/error/finally path and checks `mounted` after the picker (`pdf_tools_page.dart:168-207,289-303`). Sequential filename collisions preserve the prior file, as the real output test demonstrates (`local_pdf_output_test.dart:8-27`).
- `inspectBackup()` now enters the same controller serialization and busy notification path as the other backup operations (`local_backup_controller.dart:42-47,140-163`).

## Critical

None.

## Important

### 1. Managed-file mutations still are not serialized with pending persistence or backup creation

Files: `lib/state/research_life_controller.dart:1161-1172,1976-2013,2187-2229,5102-5114`; `lib/state/local_backup_controller.dart:110-126,140-163`; `lib/services/storage/backup_service.dart:323-346`.

Queued document updates use `_pendingPdfPersistence`, and backup preflight waits for that future. Rename and delete bypass the queue and call the repository directly after moving/staging the payload. There is also no shared write mutex between `ResearchLifeController` and `LocalBackupController`. Therefore `flushLocalPersistence()` does not mean that a rename/delete already in flight has completed, and it does not prevent a new mutation from starting after the flush.

A reproducible ordering is:

1. Rename moves `old.pdf` to `new.pdf`, then pauses before its manifest save.
2. A manual backup starts. Its flush sees no queued PDF work and returns.
3. The backup copies the old manifest and the payload tree containing only `new.pdf`.
4. Hash validation succeeds because it validates copied files, not that every live manifest path exists.

Delete has an equivalent window with the `.deleting-*` staged name. The published backup can therefore be cryptographically valid yet restore a live document whose referenced payload is absent. Concurrent direct repository writes can also race the store's read-modify-write cycle, and repeated UI actions are not disabled while rename/delete are awaiting.

Concrete fix: put import, rename, delete, legacy migration, and all manifest updates behind one managed-library operation coordinator. Backup must acquire the same write exclusion after draining prior work and hold it through the snapshot. Alternatively, make every mutation part of one controller future chain and have backup atomically close that chain to new entrants. Add semantic backup validation that parses `library_manifest.json` and requires every non-deleted managed relative path to be present in the hashed file list. Test the ordering above with gates, plus two simultaneous delete/rename calls.

### 2. The manifest write and action rollback are not crash-safe transactions

Files: `lib/services/storage/local_file_library_store.dart:99-105,150-180`; `lib/state/research_life_controller.dart:1976-2013,2077-2135,2187-2229`; `test/research_life_controller_test.dart:1382-1431`.

`_writeManifest()` writes directly to `library_manifest.json`. `File.writeAsString()` truncates the live file before completing, so an I/O error, disk-full condition, or process termination can leave invalid/truncated JSON. `_readManifest()` then treats malformed JSON as an empty library. Renaming the payload back cannot restore the previous manifest; a later attempted `saveDocument(original)` can rebuild a manifest containing only that one document and discard every other entry.

The rollback doubles throw before calling the real repository, so the tests prove only a pre-write failure. They do not exercise failure after the manifest was replaced/partially written or an outbox-side failure after the local write. Import has a related gap: it copies the payload, inserts the document in memory, and merely queues persistence. The page waits and reports an error, but a failed save leaves the in-memory entry and an orphan payload rather than rolling the import back.

Concrete fix: write a complete manifest to a same-directory temporary file, flush it, and atomically replace the prior manifest while retaining a rollback copy until the whole operation commits. Serialize its read-modify-write cycle. Make import await the transaction internally and remove the new in-memory entry/payload on failure. Inject failures before replacement, after replacement, and after any secondary persistence step in a multi-document test, then verify the old manifest and every payload remain intact.

### 3. Legacy migration can make independent records share one payload and later destroy each other

Files: `lib/services/storage/local_file_library_store.dart:28-76`; `lib/services/storage/local_workspace_service.dart:196-225`; `lib/state/research_life_controller.dart:1976-2013,2187-2229`.

For each absolute legacy entry, migration calls `copyFileIntoMaterials()`. When a target with the same filename and bytes already exists, that helper returns the existing target. Thus two distinct legacy records with the same category, basename, and contents are both rewritten to the same `payloads/<category>/<name>` path. Rename or delete assumes exclusive ownership and moves/deletes that shared file, leaving the other record broken.

The new legacy test covers one well-formed entry and does not expose this aliasing case.

Concrete fix: preserve one owned payload per retained document ID (for example, an ID-scoped directory or filename), or formally model shared payloads with reference counting and copy-on-write before rename/delete. Add a migration test with two absolute source files that have the same basename and bytes, then rename/delete one and verify the other still opens with unchanged bytes.

### 4. PDF output collision handling still has an overwrite race

Files: `lib/features/pdf_tools/local_pdf_output.dart:16-49`; `test/local_pdf_output_test.dart:8-27`.

The helper checks `exists()` and later calls `writeAsBytes()`. Another app instance, another process, or a second helper invocation can create the selected candidate between those operations; `writeAsBytes` then truncates that newly created file. The sequential test passes but does not prove the advertised "never overwrites" guarantee under concurrency.

Concrete fix: claim each candidate with an exclusive-create file mode and write only through that handle; on an already-exists error, advance to the next suffix and retry. Reject empty output before creating the target. Add a gated concurrent-writer test demonstrating that both outputs survive with distinct names.

## Minor

### 1. Managed-path containment is lexical and does not defend against `..` aliases or junctions

File: `lib/services/storage/local_workspace_service.dart:228-235`.

`isManagedFilePath()` lowercases and uses `startsWith(root + '\\')`, but does not canonicalize dot segments or resolve links. A path lexically below `payloads` can traverse out through `..`, and a Windows junction inside the tree can target an external file. Normal application-created paths are sanitized, so this is not an ordinary happy-path failure, but destructive rename/delete should not rely on a lexical check.

Concrete fix: normalize with the platform path library, reject any unresolved traversal, compare canonical parent/root paths, and define a no-follow policy for links/junctions before destructive operations. Add containment tests for a sibling-prefix path, `payloads\category\..\..`, and a supported link/junction case.

### 2. Ordinary PDF operations still have an undisclosed optional backend dependency

Files: `lib/features/pdf_tools/pdf_tools_page.dart:94-123,274-302`; `lib/state/research_life_controller.dart:1287`; `lib/core/config/api_config.dart:5-13`; `lib/services/pdf/pdf_operation_api.dart:30-76`.

The invalid PDF AI surface is gone and no account token is attached, which resolves the prior AI finding. However every remaining transformation, including scan-to-PDF, uploads the selected local files to `/api/v1/pdf/process` at the compile-time `RESEARCH_LIFE_API_BASE_URL` (default loopback). The page describes only local input/output and does not tell the user that processing requires this optional service or that a non-loopback build sends document bytes over the network.

Concrete fix: label the processing dependency and its availability near the operation board, disable actions with a localized setup/offline state when unavailable, and explicitly disclose non-loopback destinations before sending local documents. Keep this separate from Agent configuration as intended by the task scope.

## Assessment

**CHANGES**

The always-missing-payload Critical is fixed, portability works for the tested normal and single-entry legacy paths, and the UI/PDF/backup-controller corrections are real. Task 4 is not yet safe to accept because managed-file writes are not excluded from backup snapshots, the JSON catalog is not atomically committed, duplicate legacy records can alias one destructively managed payload, and the PDF writer's check-then-write sequence does not guarantee non-overwrite under concurrency.
