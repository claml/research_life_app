# Task 5 Fix Round 1 Manual Review Package

## Scope

Verify only the Important finding that non-PDF selections exposed PDF-only page operations.

## Diff summary

- `scripts/render.js`: PDF-tools rendering now gates operations on `material.type === 'PDF'`; non-PDF files render a concise `请选择 PDF 资料` state.
- `styles/views.css`: restrained unsupported-state rail styling.
- `tests/state.test.mjs`: focused DOCX selection regression.

## Evidence

- RED: focused suite 13 passed / 1 failed; DOCX incorrectly contained PDF actions.
- GREEN: fresh controller full preview suite 19 passed / 0 failed, exit 0.
- Browser: selected `路径选择实验方案.docx` → `PDF 工具`; `合并页面` count 0, `提取页面` count 0, concise `请选择 PDF 资料 / 当前资料为 DOCX` visible, console error/warn list empty.

The deferred Minor `button role="row"` semantic issue is out of scope.
