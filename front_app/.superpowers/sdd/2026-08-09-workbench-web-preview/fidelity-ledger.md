# Workbench Preview Fidelity Ledger

Basis: all four accepted 1440×900 concept images were re-inspected at high detail; prior task review evidence covered the implementation at 1280×800 and approximately 980×800. Task 6 changes are limited to semantics, inert-form handling, demo-time metadata, and focus-safe material-row markup.

## Weather

- Navigation/copy: manual entry, visible `返回`, concise date/weather, and no more than three today items are preserved.
- Layout: full-bleed cloudscape and one tall left information surface match the accepted composition.
- Typography: the large low-weight clock remains the dominant element; supporting labels remain compact.
- Palette/glass: cool teal sky, pearl-white type, selective frosted card/controls, and opaque reduced-transparency tokens remain intact.
- Spacing/container: the information card keeps generous inset spacing and the reveal control stays short and quiet.
- Responsive: the card narrows with bounded side offsets at compact widths; primary content remains contained.

## Today

- Navigation/copy: Today is selected, Today/Calendar/Todos remain present, and Quick Capture is the sole contextual primary action.
- Layout: the approved open timeline/action-list split is retained rather than a dashboard card grid.
- Typography: one clear page title, compact section headings, and restrained row metadata preserve hierarchy.
- Palette/glass: deep academic-green sidebar and opaque pearl workspace remain distinct from the cloudy surround; glass stays limited to permitted chrome.
- Spacing/container: the shared shell offsets, sidebar track, main panel radius, and two-column whitespace are normalized with the other workspaces.
- Responsive: columns compact and then stack without page-level horizontal overflow.

## Research

- Navigation/copy: the six accepted tabs remain available and only the overview exposes one restrained AI Assistant action.
- Layout: readings, notes, plans, and weekly analysis remain open hairline-separated sections, not cards.
- Typography: section titles and row metadata remain compact with one-line supporting copy.
- Palette/glass: the opaque research reading surface and academic-green navigation match the shared system.
- Spacing/container: normalized shell geometry and repeated open-row rhythm align with Today.
- Responsive: metadata columns collapse before core row labels, keeping disclosures keyboard operable and legible.

## Materials

- Navigation/copy: Files/Document View/PDF Tools remain present; ambiguous Download wording is intentionally replaced by Export/Save As.
- Layout: folder rail, central table, and opaque inspector preserve the accepted three-pane workbench.
- Typography: dense file metadata remains subordinate to filenames and pane headings.
- Palette/glass: scrolling content stays opaque; selected rows use restrained green contrast rather than detached cards.
- Spacing/container: pane dividers, sticky header, aligned table columns, and inspector density remain consistent.
- Responsive: the inspector narrows and then hides while folder/file selection remains available; row selection is now exposed by a labelled native button inside an ARIA row/cell structure.

## Intended deviations

- Concept-image dates, filenames, and counts are reference-only; the implementation uses a smaller fixed fictional demo dataset.
- The Weather concept tagline is omitted to honor the accepted concise-copy inventory.
- The concept's taller left-edge Weather reveal is implemented as the approved shorter, quieter affordance.
- Materials uses `导出` / `另存为` instead of the concept's ambiguous `下载` wording.
- At compact width the Materials inspector may hide, as explicitly allowed, while the folder/file workflow remains usable.

No unintended visual deviation was introduced by the Task 6 hardening changes. A controller can perform the final live Browser approval pass without storing screenshots inside `docs/workbench_preview`.
