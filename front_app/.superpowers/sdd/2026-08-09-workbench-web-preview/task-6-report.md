# Task 6 Report: Responsive, Accessibility, and Fidelity QA

## Changes

- Weather `<time datetime>` now comes from the same demo time rendered to users.
- The inert Search form prevents submission, so Enter cannot reload the preview.
- Materials retains its ARIA table/row/cell model while each row exposes a labelled native selection button; full-row pointer and keyboard focus styling are preserved.
- Added focused reducer coverage for sidebar toggling, Weather fallback/chrome validation, and reduced-transparency validation.
- Added the required local launch and acceptance README.
- Added `fidelity-ledger.md` with six checks for each accepted screen and documented intended deviations.

## TDD evidence

RED command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs docs\workbench_preview\tests\shell.test.mjs
```

RED result: exit 1, 24 tests, 21 passed, 3 expected failures: dynamic Weather datetime, inert Search submission, and accessible material-row button semantics.

GREEN result for the same command: exit 0, 24 tests passed, 0 failed.

The added reducer cases were expected to pass immediately because Task 2 already implemented all action contracts; they close the deferred focused-coverage gap rather than justify a production reducer change.

## QA notes

- Re-inspected the four accepted 1440×900 concepts at high detail.
- Existing reviewed Browser evidence covers 1280×800 and approximately 980×800 shell/view fidelity; the controller owns the four specified live interaction paths for this final pass.
- Task 6 semantic/controller changes do not alter the accepted shell geometry, Weather reveal/action wording, or responsive composition.
- No Flutter source, Flutter initialization, dependencies, or product business logic were changed.

## Verification

Fresh full preview suite:

```powershell
node --test docs\workbench_preview\tests\shell.test.mjs docs\workbench_preview\tests\state.test.mjs
```

Result: exit 0, 24 passed, 0 failed.

The brief's exact state-suite command also passed independently: exit 0, 17 passed, 0 failed.

Final recursive inventory: 19 files, all non-empty. File-map/policy scan: 17 required files present, 0 missing, 0 empty, 0 temporary/debug/screenshot/build/font artifacts. The two intentional additions beyond the original map are `assets/weather-cloudscape.png` (the reviewed Weather background asset) and `tests/shell.test.mjs` (the shell/accessibility regression suite).

The controller owns the final live Browser interaction/viewport pass; no screenshots or Browser artifacts were written into the product preview.

## Fix round 1/5: keyboard focus

### Changed files

- `docs/workbench_preview/scripts/render.js`
- `docs/workbench_preview/scripts/app.js`
- `docs/workbench_preview/tests/shell.test.mjs`
- `.superpowers/sdd/2026-08-09-workbench-web-preview/task-6-report.md`
- `.superpowers/sdd/2026-08-09-workbench-web-preview/progress.md`

### Fixes

- Hidden Weather return/transparency controls now render with `tabindex="-1"`; the reveal control remains tabbable and focusing it reveals the chrome.
- State-changing navigation, tabs, sidebar, disclosures, material selectors, and Weather controls expose stable `data-focus-key` values.
- The controller captures the active focus key before an `innerHTML` rerender and restores the matching eligible control afterward.
- Entering Weather remembers the Weather navigation origin and focuses Return; Return or `Escape` restores focus to the Weather navigation entry. Sidebar and other same-view controls retain focus across rerenders.

### RED → GREEN evidence

RED:

```powershell
node --test docs\workbench_preview\tests\shell.test.mjs
```

Exit 1: the focused suite could not import the not-yet-implemented `focusKeyFromRoot` helper. This failed at the new focus-restoration boundary before production changes.

After implementation, the first targeted run was 10/11: the remaining stable material-key assertion exposed an incomplete minimal test fixture, not a product failure. The test was corrected to use the complete frozen demo-data structure.

GREEN targeted result: 11/11 passed. Fresh full preview result:

```powershell
node --test docs\workbench_preview\tests\shell.test.mjs docs\workbench_preview\tests\state.test.mjs
```

Exit 0: 28 passed, 0 failed.

No visual CSS, Flutter code, dependencies, or preview artifacts changed in this fix round. The controller's live Browser keyboard regression passed: rerendered Research/sidebar controls retained focus, Weather entry focused Return, Escape restored the prior workspace and `nav-weather`, hidden Weather controls left the Tab order, and keyboard focus on reveal restored the chrome.
