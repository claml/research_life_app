# Task 6 Review: Responsive, Accessibility, and Fidelity QA

## Review basis

- Reviewed `task-6-brief.md`, `task-6-report.md`, `task-6-review-package.md`, `fidelity-ledger.md`, and `design-inventory.md`.
- Inspected only the six files listed in the review package and the preview README.
- Compared all four accepted concept images with the four current `qa-*.png` images at original detail.
- Confirmed the six packaged files still match the reported byte counts, line counts, and SHA-256 hashes.
- Accepted the supplied fresh 24/24 automated result and final Browser-path evidence; the full suite was not rerun.
- Confirmed no screenshot, log, temporary, build, dependency, or cache artifact is present under `docs/workbench_preview`.

## Spec Compliance

**Verdict: CHANGES REQUIRED**

The manual Weather entry/return model, independent tab state, material selection persistence, sidebar persistence, inert Search behavior, reduced-transparency path, responsive evidence, demo-data-only boundary, and exact launch/limits README are all supported by the reviewed implementation and supplied evidence. The four current screenshots remain recognizably faithful to their accepted concepts, with deviations limited to the documented smaller fictional dataset and approved copy/action changes.

However, the keyboard acceptance gate is not fully met: hidden Weather controls remain in the tab sequence, and state-changing keyboard activation replaces the focused DOM node without restoring focus.

## Task Quality

**Verdict: CHANGES REQUIRED**

The hardening is narrowly scoped, readable, evidence-backed, and avoids Flutter or integration work. Semantics improved materially, especially the labelled native material-selection buttons and inert Search handling. The remaining defects are localized but user-visible accessibility regressions, so this task should not receive final sign-off yet.

## Strengths

- `scripts/render.js:19-79` consistently applies labelled native buttons and correct `aria-current="page"` state to primary and secondary navigation.
- `scripts/app.js:53-55` prevents inert Search submission without changing state or reloading the preview.
- `scripts/render.js:305-325` preserves the ARIA table/row/cell structure while exposing each file row through a labelled native button; `styles/views.css:546-580` keeps the full-row pointer target and selected styling.
- `scripts/app.js:72-77` confines `Escape` navigation to Weather, while the supplied Browser evidence confirms the preceding Research/Notes state is restored.
- `styles/views.css:1499-1664` provides compact continuations for the principal views and Materials panes; the supplied 980px evidence reports no page-level horizontal overflow.
- `styles/views.css:1688-1703` removes transitions from every transition-bearing selector in this modified stylesheet under reduced motion.
- `docs/workbench_preview/README.md:3-36` gives the exact launch command and URL, all four acceptance paths, keyboard behavior, viewport targets, fixed-fictional-data guarantee, explicit integration exclusions, and the required statement that this is not the Flutter application.

## Findings

### Critical

None.

### Important

1. **Hidden Weather actions remain keyboard-focusable and can receive invisible focus.** `scripts/app.js:57-69` changes `weatherChromeVisible` only from pointer boundary/reveal events. When hidden, `styles/views.css:1457-1462` applies only `pointer-events: none`, `opacity: 0`, and a transform to the Weather card, Return button, and transparency button rendered at `scripts/render.js:529-535`. Those native buttons remain in sequential keyboard navigation, and focusing them does not reveal the chrome. A user who moves the pointer out and then presses `Tab` can therefore land on an invisible Return or transparency action, violating the visible-focus and keyboard-operability requirement. Make hidden controls inert/untabbable, or reveal the chrome on keyboard focus before focus reaches them, and add a real focus-sequence regression test.

2. **Every state-changing keyboard action destroys focus without restoring it.** `scripts/app.js:40-47` calls a full render after each reducer state change, and `scripts/render.js:545-547` replaces the entire root through `innerHTML`. The activated navigation button, tab, disclosure, material row button, or sidebar control is therefore removed from the DOM; no equivalent control or destination heading receives focus afterward. This makes repeated keyboard operation unnecessarily restart from the document and means `Escape` does not restore focus to the Weather entry point. Preserve/restore a stable focus key around render, or move focus intentionally to the selected control/destination according to the navigation pattern.

### Minor

1. **The automated accessibility coverage cannot detect either runtime focus defect.** `tests/shell.test.mjs:27-34` uses string/fake-target helpers, `tests/shell.test.mjs:80-107` exercises submission without a DOM, and `tests/shell.test.mjs:109-128` validates action mapping only. The regex-oriented rendering assertions are useful structural guards but do not exercise tab order, focus visibility, or post-render focus restoration. Add a small DOM/browser-level keyboard test for Weather chrome hiding/reveal and one representative rerender path.

## Assessment

Task 6 is visually faithful, responsive on the supplied target evidence, correctly limited to a static fictional Web preview, and otherwise ready for approval. Final sign-off is withheld only for the two Important keyboard-focus defects above. Fixing those defects and adding focused DOM/browser regressions should be sufficient; no visual redesign, Flutter work, integration work, or broad refactor is indicated.
