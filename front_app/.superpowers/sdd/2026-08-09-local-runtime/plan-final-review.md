# Plan 1 Final Review

Date: 2026-08-11  
Reviewer: independent Codex review  
Baseline: `6d817bb11f000fe05ea5337a90b933f8cdd945c0`  
Final verdict: **PASS**

## Review scope

I read the approved design, the complete Plan 1 implementation plan, every Task 1-4 report and review/fix-round review, `plan-review-package.md`, the restore drill, the complete tracked diff, and all untracked production and test files. I also traced the final active widget/runtime graph rather than treating the reports or source-string tests as proof.

The final state includes the whole-plan audit fixes for Research Reading, Document Viewer, AI credentials, structured-write backup serialization, restore rollback, safety retention, and startup weather isolation.

## Spec Compliance

| Requirement | Result | Evidence |
| --- | --- | --- |
| Direct local startup, no active auth/sync/cloud constructors | PASS | `ResearchLifeApp` installs `PinLockGate(child: AppShell())` at `lib/app/research_life_app.dart:261-278`; `LocalAppRuntime.open` constructs only local repositories/services at `lib/app/local_app_runtime.dart:121-205`. A final constructor scan found no `AuthController`, `SyncOutboxRepository`, `CloudFileService`, `DeviceIdService`, or `FileSyncEngine` construction in either file. |
| Active pages do not require `AuthScope` or cloud UI | PASS | Reading and Document Viewer now consume only `ResearchLifeScope` and managed local documents (`lib/features/reading/reading_page.dart:49-118`; `lib/features/document_view/document_viewer_page.dart:35-76`). The final active-page scan also found no forbidden auth/cloud/sync references in My Files, PDF Tools, Agent, Settings, or My Notes. |
| AI remains unconfigured without ordinary credential persistence | PASS | `localAiConfigured` is hard-false and active loaders/savers retain empty settings (`lib/state/research_life_controller.dart:392`, `3233-3291`); active Settings panels are informational only (`lib/features/settings/settings_page.dart:145-182`, `1465-1474`, `1646-1655`). Portable backups remove legacy AI/weather credential rows and compact the copied SQLite file (`lib/services/storage/backup_service.dart:641-681`). |
| Snapshot consistency and migration backup semantics | PASS | The production runtime injects one zone-reentrant/OS-lock coordinator into every structured repository, the local manifest store, controller, and `BackupService` (`lib/app/local_app_runtime.dart:127-188`). Migration path/marker writes are one coordinator-protected Drift transaction (`lib/services/database/repositories/preferences_repository.dart:213-230`), and marking follows create, validation, protected retention, refresh, and post-retention validation (`lib/state/local_backup_controller.dart:57-107`). |
| Restore validates first, creates a safety backup, retains ten, and replaces runtime ownership | PASS | Schema/checksum/managed-payload validation precedes overwrite; restore protects the selected source and new safety backup during retention (`lib/services/storage/backup_service.dart:229-251`). Partial move-aside, copy, cleanup, and rollback failures preserve or continue recovering all pre-restore artifacts (`lib/services/storage/backup_service.dart:282-401`). Root restore preflush/close/reopen and exit races are serialized at `lib/app/research_life_app.dart:88-167`, `203-229`. |
| Managed files are portable and crash-recoverable | PASS | Payload paths are stored relative to `.research_life/local_files`, legacy absolute records are copied before backup, manifest/payload mutations share the coordinator, and rename/delete use a durable operation journal (`lib/services/storage/local_file_library_store.dart:35-99`, `269-340`; `lib/state/research_life_controller.dart:1974-2050`, `2252-2333`). Backup validation proves every live manifest record has a copied payload (`lib/services/storage/backup_service.dart:180-221`). |
| Windows close/tray lifecycle is unified | PASS | Native `WM_CLOSE` asks Dart for policy and confirmed close bypasses the engine/plugin dispatch; Dart either hides for close-to-tray or awaits terminal shutdown. Final Windows debug compilation succeeded. |
| Local UI operations remain complete | PASS | My Files retains import/open/rename/delete/PDF routing; Reading saves notes/annotations locally; PDF Tools accepts local inputs and collision-safe local output directories; Settings exposes one backup panel with validated selection and explicit timestamp confirmation. |

## Task Quality

- **Task 1:** Backup publication is pending-directory based, manifests are typed/versioned and hashed, validation rejects future or mismatched DB schema, credential bytes are absent even from SQLite free pages, retention protects in-flight sources, and restore rollback is now exhaustive rather than fail-fast.
- **Task 2:** The controller has a narrow backup API, serialized busy state, correct marker ordering, absolute persisted paths, migration-only pruning, post-retention validation, and safe `ChangeNotifier` behavior when restore disposes the old controller.
- **Task 3:** Runtime ownership and exactly-once disposal are explicit. Startup, restore, exit, tray menu, native close, late-runtime, and cleanup-failure branches have behavioral tests; production startup has no auth/sync constructors.
- **Task 4:** Managed-file implementation uses portable payloads, atomic manifest replacement, crash journaling, shared in-process and OS locks, stale-peer identity reconciliation, and collision-safe PDF output. Reading and Document Viewer were correctly added to the final active-page audit after real Windows testing exposed their former `AuthScope` dependencies.
- **Integration evidence:** The restore drill creates and mutates an event, note, document, annotation, and real payload, then restores/reopens and verifies values plus SHA-256. The suite contains meaningful filesystem, SQLite, concurrency, lifecycle, and injected-failure tests in addition to source-boundary checks.

## Critical

None.

## Important

None.

## Minor

### 1. Document Viewer can apply a stale asynchronous load result

`lib/features/document_view/document_viewer_page.dart:171-195`

If document A is slow and the user selects B before A finishes, A can complete last and replace B's content/error while the title still identifies B. This is display-only and does not mutate user data.

Concrete fix: increment a request generation (or capture the document id) for each `_openLocal` call and apply success/error only if it still matches `_activeLocal?.id`.

### 2. One delete-compensation sub-branch can temporarily disagree with durable state

`lib/state/research_life_controller.dart:2300-2321`

If compensating manifest save succeeds but restoring the staged payload or clearing its journal then fails, the catch removes the controller entry even though the durable manifest is live. Startup journal recovery remains safe, so this is a temporary UI/reload issue rather than data loss.

Concrete fix: track whether the compensating save committed; retain/reload the original controller record in later-step failures, and remove it only when the tombstone is still committed.

### 3. Managed-path containment remains lexical rather than reparse-point aware

`lib/services/storage/local_workspace_service.dart:243-282`

The Windows path checks normalize strings but do not resolve junctions/reparse points. A user-created junction below `payloads` can therefore refer outside the workspace while passing the lexical test.

Concrete fix: resolve/finalize each existing path component and reject reparse-point escapes before rename, delete, journal, and backup traversal.

### 4. PDF Tools does not disclose that ordinary transformations use a network processor

`lib/features/pdf_tools/pdf_tools_page.dart:274-302`; `lib/services/pdf/pdf_operation_api.dart:49-70`

Inputs and outputs are local as required, authentication is not used, and network failure is page-local. However, selected document bytes are uploaded to the configured PDF endpoint without an adjacent disclosure, which can surprise users interpreting “local PDF” as local-only processing.

Concrete fix: label the processing destination before execution (or provide a genuinely local implementation in a later plan).

### 5. Local-only page regressions are primarily source-string assertions

`test/local_only_pages_test.dart:6-111`

These checks are useful guardrails but do not prove that each active page can actually build and complete its first-frame work without `AuthScope`; the prior Reading red screen illustrates the limitation.

Concrete fix: add widget tests that pump Reading, Document Viewer, Agent, My Files, PDF Tools, My Notes, and Settings under only the production local scopes, exercise their first local action, and fail on framework exceptions.

### 6. Two managed-file recovery contracts lack direct regressions

`test/managed_local_files_test.dart:457-497`; `lib/services/storage/local_file_library_store.dart:282-340`

The implementation preserves a peer tombstone during metadata merge and rejects unknown journal types before mutation, but tests do not directly assert those two contracts.

Concrete fix: add a stale metadata/tombstone test and an unknown-journal test that verifies both paths and the journal remain untouched.

## Verification Evidence

Fresh commands run against the final filesystem state:

```text
flutter test --no-pub -r compact
267 tests passed, 0 failed, exit 0

flutter test --no-pub -r expanded test/backup_service_test.dart
24 tests passed, 0 failed, exit 0

flutter test --no-pub -r expanded --timeout 60s \
  .superpowers/sdd/2026-08-09-local-runtime/plan1_restore_drill_test.dart
1 test passed, 0 failed, exit 0

flutter build windows --debug --no-pub
Built build/windows/x64/runner/Debug/research_life.exe, exit 0

dart analyze
0 errors; 1 warning and 5 infos, all matching the documented baseline

git -c safe.directory='*' diff --check
exit 0 (line-ending notices only)
```

Final active-page and runtime-constructor `rg` scans returned no matches for the prohibited auth/cloud/sync dependencies.

## Final Verdict

**PASS.** Plan 1 has zero Critical, zero Important, and six Minor findings. The delivered runtime meets the approved local-only boundary and its data-protection/lifecycle gates. The remaining Minor items are bounded display, disclosure, hardening, or test-depth improvements and do not block Plan 2.
