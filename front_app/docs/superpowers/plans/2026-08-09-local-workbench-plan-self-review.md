# Local Workbench Plan Self-Review

Date: 2026-08-09

## Spec coverage

| Confirmed requirement | Implementing plan/task |
| --- | --- |
| No login or cloud runtime dependencies | Local Runtime Tasks 3–5 |
| Local database/workspace as only source of truth | Local Runtime Tasks 3–4 |
| Migration safety backup, hashes, atomic publish, retention | Local Runtime Tasks 1–2 |
| Restore closes/reopens the runtime and preserves rollback | Local Runtime Tasks 2–5 |
| Manual event delete and todo-state cleanup | Workbench UI Task 1 |
| Folder rename and descendant path rewrite | Workbench UI Task 2 |
| Primary and secondary navigation with state memory | Workbench UI Tasks 3, 5, 6 |
| AI only in Research | Workbench UI Task 6; Weather/Cleanup Task 4 |
| Static-first Weather, optional light motion | Weather/Cleanup Tasks 1–2 |
| Reduced motion and reduced transparency | Weather/Cleanup Tasks 2–3 |
| Windows credential storage for AI | Weather/Cleanup Task 4 |
| Delete auth/sync/cloud code only after local acceptance | Weather/Cleanup Task 5 |
| Protected Drift v9 cleanup migration | Weather/Cleanup Task 6 |
| 1280×800 and ~980px Windows verification | Workbench UI Task 7; Weather/Cleanup Task 7 |
| Selective glass and concise copy | Workbench UI Tasks 4–7; Weather/Cleanup Task 3 |
| Full automated and visual acceptance | All three integration gates and final Task 7 |

No confirmed requirement lacks an implementing task.

## Placeholder scan

Scanned the roadmap and all three plans for `TBD`, `TODO`, “implement later”, generic error-handling/test placeholders, and cross-task “similar to” instructions. No matches remain.

## Interface consistency

- `BackupPurpose.migration` is introduced in Local Runtime Task 1 and consumed from Task 2 onward.
- Migration backup completion and absolute path keys are written in Local Runtime Task 2 and read by `LocalSchemaMigrationGuard` in Weather/Cleanup Task 6.
- `RuntimeRestore` is defined before `LocalAppRuntimeFactory`; runtime construction, backup controller, scope, and root restart use the same callback type.
- `WorkbenchWorkspace`, `WorkbenchTab`, and `WeatherReturnSnapshot` are defined in Workbench UI Task 3 and consumed by Tasks 5–7.
- `LocalCredentialStore` and `LocalAiClientFactory.createDio(LocalAiConfiguration, String)` are defined and consumed within Weather/Cleanup Task 4.
- Drift schema version moves from 8 to 9 only in Weather/Cleanup Task 6, after the safety guard and cloud-code review.

## Scope check

The confirmed design spans three independently reviewable subsystems, so it is intentionally split into three sequential plans. The roadmap prevents UI work from starting before local data safety, and prevents schema cleanup before both runtime and UI acceptance.

