# Plan 1 final review package

## Scope and fixed product decisions

Plan 1 converts the Flutter Windows workbench to a single-device local runtime.
The production startup path must not require login, tokens, cloud files, device
identity, an outbox, or sync. Weather and AI may use optional network services,
but their unavailable states must remain page-local. Weather is opened manually.
Visual redesign is explicitly deferred to Plan 2.

Baseline commit: `6d817bb11f000fe05ea5337a90b933f8cdd945c0`.
Current work is intentionally uncommitted and unpushed. The pre-change backup is
already on `origin/backup/local-20260809` at `f3057ed`.

## Delivered boundaries

- Atomic, versioned, hashed backup/restore for the database, preferences,
  workspace manifest, local-file manifest/annotations, and managed payload bytes.
- Backup copies physically remove dormant AI/weather secrets, reject future or
  mismatched database schemas, retain the newest ten safety snapshots, and use
  failure-tolerant rollback that continues restoring every data class.
- One-time migration safety backup with a durable completion marker.
- Direct `LocalAppRuntime` startup through the local scopes and `AppShell`, with
  no active authentication or sync constructors.
- Restartable restore handoff, ordered flush/close, recoverable failure paths,
  tray-aware Windows shutdown, and a shared local-data coordinator/OS lock.
- Local-only My Files, PDF inputs/outputs, AI configuration fallback, Settings,
  and backup controls.
- Managed-file atomic manifest updates, operation journal/recovery, collision-safe
  output names, portable paths, semantic backup validation, and cross-root restore.
- Local-only Research Reading: importing, reading, annotations, notes, and save
  actions no longer depend on `AuthScope` or expose cloud UI.
- Local-only Document Viewer: direct selection and opening are backed only by
  `localViewableDocuments`; the page no longer imports `AuthScope` or the cloud
  picker.
- Local-only Notes refresh and runtime startup perform no cloud refresh or
  awaited weather request. AI remains explicitly unconfigured until a future
  Windows Credential Manager phase.
- All production structured repositories join the shared backup/OS-lock write
  barrier, including multi-key migration-marker transactions.

## Independent task reviews

- Task 1: implementation/report completed; later integration reviews exercised
  its backup contract.
- Task 2: fix round 3 accepted.
- Task 3: fix round 3 accepted (one minor missing policy-exception test only).
- Task 4: fix round 4 PASS, 0 Critical / 0 Important / 3 Minor.
- Task 5 must receive a separate whole-plan verdict with no Critical or Important
  before Plan 2 begins.

## Automated evidence

Fresh full suite on 2026-08-11:

```text
flutter test --no-pub -r failures-only
267 tests passed, 0 failed, exit 0
```

Focused local-only regressions after the real Windows red-screen reproduction
and the subsequent active-page dependency audit:

```text
flutter test --no-pub -r expanded test/local_only_pages_test.dart
7 tests passed, 0 failed, exit 0
```

Restore drill (real temporary runtime/workspace):

```text
flutter test --no-pub -r expanded --timeout 60s \
  .superpowers/sdd/2026-08-09-local-runtime/plan1_restore_drill_test.dart
1 test passed, 0 failed
```

The drill creates an event, note, PDF record, annotation, and payload hash;
creates a migration backup; mutates every class; restores; replaces/reopens the
runtime; and verifies every original value and SHA-256.

Fresh analyzer result after removing the final introduced warning:

```text
dart analyze
0 errors, 1 warning, 5 info
```

All six diagnostics are the unchanged baseline:

- `test/research_life_controller_test.dart:1129` unnecessary `!` warning.
- `lib/services/agent/agent_api.dart:36-38` three null-aware style infos.
- `test/file_sync_engine_session_test.dart:187` local-name style info.
- `test/stats_calculator_test.dart:228` local-name style info.

`git diff --check` exits 0; output contains only the repository's LF/CRLF notices.

## Windows offline evidence

Debug build:

```text
flutter build windows --debug --no-pub
Built build/windows/x64/runner/Debug/research_life.exe
```

The app was launched with an isolated workspace and restricted network state.
Observed in the real Windows UI:

- Direct workbench startup; no login page or startup network blocker.
- Weather remained closed until manually requested; Home showed a restrained
  missing-API fallback instead of failing startup.
- Todo, Calendar, local AI-unconfigured state, My Files, PDF Tools, Research
  Notes, Settings, and backup controls all rendered and remained navigable.
- Settings showed only local backup/restore and local configuration; no account
  or sync controls.
- A first Research Reading check exposed an `AuthScope is missing` red screen.
  A RED source-boundary regression was added, the page was localized, the Windows
  app was rebuilt, and the same navigation now renders the local PDF library with
  “内容自动保存在本机” and no cloud/login controls.
- The same active-page scan found Document Viewer still importing `AuthScope` and
  `WorkspaceCloudPicker`. A second RED regression captured it; the page now lists
  only imported local documents and reads them through `DocumentTextLoader`.
- The final Windows build opened directly to the workbench and displayed the
  restrained local AI-unconfigured state without login, sync, or startup error.

## Known deferred/minor items

- Legacy auth/sync/cloud source and tests remain for the separately planned phase
  that deletes unreachable code and database structures; they are outside the
  active runtime/UI dependency graph.
- Ordinary PDF transformations still use the optional configured processing
  service; its failure is localized to PDF Tools. Destination disclosure and
  junction-aware containment hardening remain minor follow-ups from Task 4.
- The three Task 4 round-4 minor test/hardening notes remain documented in
  `task-4-fix-round-4-review.md`.
- Plan 2 owns the approved Flutter navigation and visual redesign.

## Review request

Review the design, implementation plan, all Task 1-4 reports/reviews, the entire
working diff including untracked production/tests, this evidence package, and the
restore drill. Report Critical/Important/Minor findings and write
`plan-final-review.md`. Plan 1 passes only with zero Critical and Important.
