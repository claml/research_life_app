# Task 3 Fix Round 1 Manual Review Package

## Scope

Non-Git workspace. Review only the fix for the three open Important findings from `task-3-review.md` and new breakage introduced by these edits.

## Changed files

- Added `docs/workbench_preview/assets/weather-cloudscape.png` — 1,646,563 bytes, 1586×992 PNG, SHA-256 `6004AF84B149922864B865A7519A6B4E00ABF65221B9785B7711CF957EDAA328`.
- Modified `styles/tokens.css` — opaque search/reveal tokens.
- Modified `styles/shell.css` — collapsed desktop grid track.
- Modified `styles/components.css` — complete reduced-transparency selectors/fallbacks.
- Modified `styles/views.css` — standalone cloudscape background replaces synthetic radial layers.
- Modified `scripts/render.js` — collapsed-state class on shell.
- Modified `tests/shell.test.mjs` — focused regression contracts.

Current full hashes for all except the small token file are recorded in the appended Fix Round 1 report.

## Fresh controller evidence

- `node --test docs\\workbench_preview\\tests\\shell.test.mjs docs\\workbench_preview\\tests\\state.test.mjs`: 8 passed, 0 failed, exit 0.
- `view_image` at original detail on `weather-cloudscape.png`: no UI/text/control remnants; distinct illuminated cloud edges, layered masses, depth, and lower-left rays.
- In-app Browser at 1280×800: updated Weather renders the cloudscape full-bleed, no console errors/warnings, and the composition is materially aligned with accepted `weather.png` while all UI remains code-native.
- Reduced transparency remained pressed on Weather; screenshot showed the weather panel and left reveal as opaque surfaces over the cloud background.
- Return → collapse at 1280×800: screenshot showed the 80px rail with the main panel immediately following the standard gap; the prior 144px dead track was removed.

## Findings under verification

1. Weather background fidelity to the accepted recognizable cloudscape.
2. Fully opaque/no-blur reduced-transparency fallback for every glass surface, specifically search and Weather reveal.
3. Desktop collapsed sidebar grid track reclaims the released width.

The three previously recorded Minor findings are outside this scoped re-review.
