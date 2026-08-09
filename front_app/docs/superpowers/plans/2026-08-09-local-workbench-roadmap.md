# 研LIFE Local Workbench Implementation Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safely convert the Flutter Windows app into a local-only personal workbench, land the approved workbench UI, and finish the Weather standby experience without losing local data.

**Architecture:** Execute three bounded plans in order. Plan 1 establishes backup protection and a local-only runtime; Plan 2 closes remaining local business flows and replaces the navigation shell; Plan 3 adds the accepted Weather experience, optional local credentials, removes dead cloud code, and performs final Windows validation.

**Tech Stack:** Flutter 3 / Dart 3.11, Material 3, Drift/SQLite, local JSON manifests, `win32`, Flutter widget tests, Windows desktop visual QA.

## Global Constraints

- The app starts without login and remains usable with no network.
- Drift, the local workspace, and local manifests are the only sources of truth.
- Weather and AI may use the network independently; neither may block startup.
- No cloud-only data migration is required.
- Keep old sync schema during the first local-runtime phase; remove it only in the final cleanup migration.
- Weather is manually opened; static visual quality is mandatory and motion is optional enhancement.
- AI exists only inside Research.
- Glass is limited to Weather information, search/brand chrome, floating tools, dialogs, and status feedback.
- Scrolling lists, file tables, reading surfaces, and PDF content must remain opaque.
- Copy remains concise: at most one short explanatory line per page or empty state.
- Desktop targets are 1280×800 and approximately 980px wide.
- The workspace is not a Git repository. Do not initialize Git. Replace commit steps with SDD checkpoints containing changed-file inventory, test output, and review verdict.

---

## Execution Order

1. [Local Data Protection and Runtime Plan](2026-08-09-local-runtime-implementation.md)
2. [Business Flows and Workbench UI Plan](2026-08-09-workbench-ui-implementation.md)
3. [Weather, Optional Network, and Cloud Cleanup Plan](2026-08-09-weather-cleanup-implementation.md)

Each plan must finish with all scoped tests green and an independent code review before the next plan starts. Critical and Important findings block progression. Minor findings must be recorded and either fixed in the same plan or assigned to an exact later task.

## Final Acceptance Command Set

```powershell
flutter analyze
flutter test
```

Then build and launch the Windows app, verify the four acceptance paths at 1280×800 and approximately 980px, inspect screenshots against the accepted Web concepts at original detail, and confirm a backup/restore round trip on a disposable fixture workspace.

