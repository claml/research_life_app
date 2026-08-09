# Task 5 Fix Round 1 Review

## Scope

Read-only re-review of the original Important finding only: a non-PDF selection must not expose the PDF-only `合并页面` / `提取页面` / `另存为` operations in `PDF 工具`. The deferred `button role="row"` Minor is out of scope.

## Finding Verdict

**ADDRESSED.** `renderMaterialsTool` now derives `isPdf` from the persisted selected material (`material?.type === 'PDF'`) and renders the three PDF page operations only in that branch (`scripts/render.js:332-359`). For DOCX, XLSX, MD, and PNG selections, the shared non-PDF branch instead emits an explicit `data-state="requires-pdf"` rail with the current file type. This is type-based rather than dependent on a single DOCX title, so it covers every non-PDF material in the supplied dataset.

## New Breakage

None found in the changed render, CSS, and test code. The PDF branch retains the prior operations; the non-PDF branch is escaped, concise, and styled as an opaque, hairline-separated rail without altering the Materials layout.

## Evidence

- Render: `scripts/render.js:335` gates the operations; `scripts/render.js:352-359` has mutually exclusive PDF and `requires-pdf` output.
- CSS: `styles/views.css:783-802` adds only restrained unsupported-rail presentation.
- Regression: `tests/state.test.mjs:212-229` selects `protocol-route` (DOCX), persists it into `pdf-tools`, asserts all three PDF operations absent, and asserts the requested fallback state.
- Accepted supplied evidence: fresh Node preview suite **19/19 passing**; Browser DOCX-to-PDF-tools evidence shows zero `合并页面` and `提取页面` controls, the fallback copy, and no console errors/warnings. The full suite was not rerun for this re-review, per scope.

## Final Verdict

**ACCEPTED — original Important finding addressed; no new Critical or Important breakage found.**
