# Task 6 Fix Round 1 Review

## Review basis

- Re-read the original `task-6-review.md` and its two Important keyboard-focus findings.
- Inspected only the changed `docs/workbench_preview/scripts/app.js`, `scripts/render.js`, and `tests/shell.test.mjs`, plus the updated `task-6-report.md` and `progress.md`.
- Accepted the controller's fresh 28/28 Node result and live 1280px Browser keyboard/pointer evidence; the full suite was not rerun.
- No production file was modified during this review.

## Spec Compliance

**Verdict: PASS**

Both prior Important findings are resolved. Hidden Weather actions are removed from sequential keyboard navigation, Reveal stays reachable and restores the chrome on focus, state-changing controls expose stable focus identities, rerenders restore eligible controls, Weather entry focuses Return, and Return/Escape restore the Weather navigation origin. The supplied live Browser evidence confirms these behaviors with real focus state.

## Task Quality

**Verdict: PASS WITH MINOR DOCUMENTATION FOLLOW-UP**

The fix is localized, readable, and aligned with the original accessibility defects. It introduces no visual, responsive, integration, demo-data, or Flutter-scope change. Focus helpers have targeted automated coverage, while the controller evidence closes the remaining real-DOM/browser gap.

## Prior Important findings

1. **Hidden Weather controls remained tabbable — RESOLVED.** `scripts/render.js:493-535` derives `tabindex="-1"` for hidden Return and transparency controls while leaving Reveal tabbable. `scripts/app.js:100-105` reveals hidden chrome when Reveal receives focus and restores the same `weather-reveal` focus key through the rerender. `tests/shell.test.mjs:92-103` guards the rendered tab-order contract. The supplied Browser evidence confirms the actual hidden and restored states.

2. **Full rerenders destroyed keyboard focus — RESOLVED.** `scripts/app.js:36-49` captures and restores eligible stable focus keys; `scripts/app.js:54-75` preserves same-control focus and defines explicit Weather entry/exit focus targets. Stable keys are applied to navigation, sidebar controls, tabs, research disclosures, material selectors, and transparency controls in `scripts/render.js:19-78`, `scripts/render.js:196-209`, `scripts/render.js:311-320`, and `scripts/render.js:414-428`. `tests/shell.test.mjs:105-191` covers key presence, helper eligibility, rerender retention, Weather entry/exit, and keyboard Reveal restoration. The supplied Browser evidence confirms Research, sidebar, Weather entry, Escape return, and Reveal paths with real focus.

## Findings

### Critical

None.

### Important

None.

### Minor

1. **The final Browser status is not synchronized across the handoff documents.** `task-6-report.md:86` still says the live Browser keyboard regression remains with the controller, while `progress.md:38` records that it passed. In addition, `progress.md:32-37` duplicates the fix-round-start entry and places the original review finding after the first RED/GREEN entries. Reconcile these lines so the durable audit trail is chronological and unambiguous. This does not affect implementation approval.

## Assessment

Fix round 1 is approved. The two blocking keyboard-focus defects are fixed in code, guarded by focused tests, and verified in the supplied real Browser session. No new Critical or Important issue was introduced. Only the non-blocking report/progress bookkeeping should be tidied before archival.
