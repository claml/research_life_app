# Task 4 Independent Code Review

Date: 2026-08-09

## Scope and evidence

Reviewed the local-workbench design, Task 4 implementation plan, `task-4-report.md`, the complete current working diff, all Task 4 production files, the controller/repository/storage paths they call, and both new test files.

I did not repeat the supplied fresh verification: full suite 228/228, `dart analyze` with only the six baseline findings, and `git diff --check` exit 0.

## Strengths

- The four active pages no longer import `AuthScope`, `AuthController`, cloud pickers, or sync UI. Settings removed the account/login/logout/migration/sync sections and replaces them with `LocalBackupPanel` (`settings_page.dart:141-161`).
- My Files routes local PDFs to Reading, supported documents to Document View, and PDFs to PDF Tools through controller-owned navigation requests (`my_files_page.dart:101-122`). AppShell consumes the new PDF-tools and AI-settings requests without introducing auth/cloud dependencies (`app_shell.dart:123-145`).
- PDF Tools selects local paths, checks selected PDF existence for ordinary operations, supports multiple input files for merge, and asks for a local output directory (`pdf_tools_page.dart:141-165,186-197,296-345`). `pdfOperationApi` is constructed with `ApiClient()` and therefore sends no hidden `AuthController` access token (`research_life_controller.dart:1287`; `api_client.dart:31-43`).
- Agent does not construct its conversation controller until the settings load and `localAiConfigured` is true; the unconfigured state exposes the requested Settings action (`agent_page.dart:32-81,84-125`). Message sends pass the current provider/base URL/model/key explicitly (`agent_page.dart:210-216`; `agent_controller.dart:111-152`).
- The backup panel displays latest validated time, backup directory, controller message/error state, busy progress, and exactly the three planned actions (`local_backup_panel.dart:15-93`). Restore validates before confirmation, names the selected backup timestamp, and validates again inside the serialized controller restore before the terminal runtime handoff (`local_backup_panel.dart:102-143`; `local_backup_controller.dart:117-123`). The disposed-controller guard from Task 2 makes the successful replacement safe.

## Critical

### 1. Backups validate successfully while omitting every materialized My Files payload

Files: `lib/state/research_life_controller.dart:2053-2111`; `lib/services/storage/local_workspace_service.dart:44-52,156-200`; `lib/services/storage/local_file_library_store.dart:217-239`; `lib/services/storage/backup_service.dart:163-190,277-339`.

`addWorkspaceFileFromPath()` copies an imported file through `copyFileIntoMaterials()`. That method stores the payload under `<storage base>/资料/<category>`, outside the `.research_life` storage directory. The local library JSON stores the resulting absolute path.

Backup creation copies the database, preferences, workspace manifest, and `.research_life/local_files`; the latter contains `library_manifest.json` and `annotations.json`, not the material payloads. No code adds the sibling `资料` tree to the manifest, validation, restore plan, or rollback. A backup therefore passes hashes and is presented as valid while containing only pointers to the live files. After file loss or restoring on another path/device, documents are missing; after editing a file, restore does not return its content to the backup-time version. This violates the design's workspace-file backup requirement and makes the Task 5 file-hash restore drill impossible.

Concrete fix: establish one owned payload root and include it in backup/restore. Either import managed files into `.research_life/local_files/payloads`, or extend the manifest with a separately rooted materials payload list and implement validated, traversal-safe, atomic copy/rollback/restore for it. Add a real temporary-workspace test that imports a file, backs up, mutates/deletes it, restores into a fresh runtime, and verifies both bytes and the restored document path.

## Important

### 1. My Files rename/delete/open are not complete local-file operations

Files: `lib/features/files/my_files_page.dart:124-203,233-267`; `lib/state/research_life_controller.dart:1976-1989,2163-2173,5046-5073`.

- Rename changes only `PdfLibraryDocument.title`; it does not rename the managed file or update its path.
- Delete removes the in-memory item and queues a soft-deleted manifest record, but never deletes the copied payload. It immediately reports “deleted” even though the persistence queue deliberately absorbs errors for later flush, so a failed write reappears after restart without any action-level error.
- The picker accepts PNG/JPEG, but `canOpen` disables Open for image kinds. The fallback message in `_openLocalFile` is unreachable because the button cannot invoke it. Thus an accepted/imported local type has no open route.

Concrete fix: replace the synchronous metadata APIs with awaited managed-file operations. Validate that the target is inside the owned payload root, rename/delete the filesystem entity and manifest as one recoverable operation, surface persistence failures before success UI, and either open image/unsupported files through the system handler or stop offering those extensions. Cover imported bytes, restart persistence, rename path, delete behavior, and failure rollback with real temporary files.

### 2. Scan-to-PDF bypasses the page's error boundary, and output silently overwrites existing files

File: `lib/features/pdf_tools/pdf_tools_page.dart:167-207,311-345`.

`scanToPdf` returns before the `_runOperation` busy/try/catch block. `_scanImagesToPdf()` has only `try/finally`: API, file, or save errors escape the button callback as unhandled asynchronous errors. It also calls `setState` after the native picker returns without checking `mounted`, unlike `_pickLocalPdfs()`.

Every generated result is written to `<chosen directory>/<server filename>` with `writeAsBytes`; an existing file is overwritten without a save-file choice, unique-name allocation, or overwrite confirmation. A repeated operation or generic `output.pdf` response can destroy an earlier local result, contrary to the design's destructive-action rule.

Concrete fix: route scan through the same mounted/busy/error wrapper as all other operations. Use a save-file picker or collision-safe filename; if overwrite is allowed, explicitly name and confirm the target. Reject empty output before replacing an existing file and add behavioral tests for scan failure, picker disposal, filename collision, and successful multi-file merge.

### 3. PDF AI ignores the local AI configuration that gates Agent

Files: `lib/features/pdf_tools/pdf_tools_page.dart:269-290,475-480`; `lib/state/research_life_controller.dart:389-394,1287`; `lib/services/pdf/pdf_operation_api.dart:79-117`; `lib/core/config/api_config.dart:5-13`.

The four visible PDF AI actions never check `localAiConfigured` and never pass provider/base URL/model/key. They post the PDF to the legacy `/api/v1/pdf/ai` endpoint on the fixed application backend (default `127.0.0.1:8080`). There is no implicit workbench token, which is good, but configuring Agent does not configure these actions. Depending on the external endpoint's auth/deployment, they either fail or use unrelated server-side settings.

Concrete fix: give PDF AI an explicit provider boundary that consumes the same local AI configuration, or disable it with the same “not configured / go to Settings” state until such an adapter exists. Keep non-AI PDF processing as a separately named optional service if it must remain remote. Test the actual request destination/configuration instead of only scanning page source.

## Minor

### 1. Backup inspection is outside the controller busy/serialization state

Files: `lib/features/settings/widgets/local_backup_panel.dart:102-143`; `lib/state/local_backup_controller.dart:42-44,137-160`.

The potentially long first validation calls `inspectBackup()` directly, so the panel remains enabled and does not show busy progress while it runs. Double clicks can open multiple confirmation flows; another backup action can start concurrently. The final restore is serialized and revalidates, so this is not a restore-corruption defect. Route inspection through a serialized/read-only busy operation or add a panel-local inspection state.

### 2. New tests mostly prove strings, not the claimed behavior

Files: `test/local_only_pages_test.dart:5-52`; `test/settings_local_backup_panel_test.dart:12-44`.

The page tests cannot detect the omitted payloads, metadata-only rename/delete, unhandled scan path, fixed PDF AI backend, or navigation behavior. The backup-panel fake is valid for its display assertion but does not implement/execute inspect, confirmation, restore, or busy transitions. Add controller/widget/integration tests with real temporary files and injectable pickers/API clients; keep source scans only as dependency-boundary checks.

## Assessment

**CHANGES**

The active UI is substantially cleaner and the backup confirmation/runtime-replacement boundary is sound, but Task 4 cannot pass while validated backups omit the actual files shown in My Files. The incomplete filesystem actions and PDF failure/configuration paths also need correction before the local-only workflow is safe and behaviorally complete.
