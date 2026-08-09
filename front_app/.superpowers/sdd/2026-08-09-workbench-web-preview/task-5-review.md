# Task 5 Review — Materials, Life, and Settings

## Review basis

- Reviewed only the five files listed in `task-5-review-package.md`; their byte counts, line counts, and SHA-256 hashes match the package exactly.
- Inspected `materials.png` and `today.png` at original detail and compared the implementation with `design-inventory.md`.
- Accepted the controller's fresh evidence: Node preview suite 18/18, Browser checks at 1280×800 and 980×800, selection persistence, empty console, and reduced-transparency/settings coverage. Per instruction, the full suite was not rerun.
- The reducer selection regression being green immediately is consistent with Task 2's all-actions contract. The reported 9-pass/4-fail RED and 13/13 GREEN cover genuinely new action/render behavior and are valid Task 5 TDD evidence.

## Spec Compliance

**Mostly compliant; one important contextual-action defect remains.**

The implementation delivers the shared shell and an opaque three-pane Materials workbench with a folder tree, six fictional table rows, selected-row contrast, persistent selection, and a concise inspector. It does not convert rows to cards, does not put glass behind the scrolling table, contains no personal/local/cloud claims, and uses `导出` / `另存为` rather than `下载`. Life provides distinct, concise Campus, Companion, and Personalization views. Settings is limited to appearance/accessibility and connects reduced transparency to the existing state action. Controller Browser evidence confirms the intended 1280×800 composition and usable ~980px continuation without visible page-level horizontal overflow.

The remaining mismatch is that PDF-only operations are rendered for every selected material type, rather than being contextual to PDF content.

## Task Quality

**Good, with one targeted correction required.**

### Strengths

- The data is compact, fully fictional, consistently frozen, and contains the requested six rows and metadata without local paths, usernames, IDs, or real titles (`scripts/demo-data.js:73`).
- Selection is connected through the real delegated action path and existing reducer contract, not a render-only imitation (`scripts/app.js:14`).
- Materials preserves the accepted concept's rail/table/inspector proportions, opaque surfaces, hairline separation, sticky table header, and restrained full-row selection (`styles/views.css:405`, `styles/views.css:512`, `styles/views.css:565`).
- Life and Settings stay concise and recognizable rather than falling back to generic placeholders or long explanatory blocks (`scripts/render.js:367`, `scripts/render.js:407`).
- Responsive rules preserve the folder/file workflow, hide the inspector only at narrower widths, and compress table columns instead of cardifying rows (`styles/views.css:1466`, `styles/views.css:1515`, `styles/views.css:1573`).
- Tests exercise the new action mapping, three-pane output, six-row contract, selection persistence across tabs, prohibited copy, three Life states, and transparency state (`tests/state.test.mjs:165`).

## Findings

### Critical

None.

### Important

1. **PDF-only actions are offered for non-PDF selections.** `renderMaterialsTool` derives `isViewer` only from the active tab and unconditionally renders `合并页面`, `提取页面`, and `另存为` whenever the tab is `pdf-tools`; it never checks `material.type` (`scripts/render.js:332`, `scripts/render.js:351`). A user can select the DOCX, XLSX, MD, or PNG row in Files and then switch to PDF Tools, while selection correctly persists, producing a visibly invalid tool context. This conflicts with the task's requirement that PDF/document actions remain contextual. Gate the PDF operations on a PDF selection and show a concise unsupported/selection state otherwise, then add a regression that selects a non-PDF row and asserts PDF page actions are absent. The current secondary-tab test only exercises `paper-hci`, which is a PDF (`tests/state.test.mjs:191`).

### Minor

1. **Clickable file rows lose their control semantics.** Each native `<button>` is assigned `role="row"` (`scripts/render.js:314`), overriding the button role exposed to assistive technology. Keyboard activation may still work in browsers, but the row is no longer announced as an actionable control. Keep the table row semantics on a non-button row container and place a real labelled button in it, or preserve button semantics with a list/table pattern that does not override the native role.

## Assessment

**CHANGES REQUESTED** — Task 5 is visually and structurally strong, and the supplied test/Browser evidence supports the main acceptance criteria. Resolve the non-PDF/PDF-tools context defect before accepting the task. The ARIA row/control issue is a worthwhile minor follow-up and does not independently block the visual demo.
