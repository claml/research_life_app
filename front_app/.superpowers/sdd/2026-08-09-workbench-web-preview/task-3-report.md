# Task 3 Report — App Shell, Navigation, and Weather Standby

## Status

`DONE_WITH_CONCERNS`

The Task 3 implementation slice and its Node test contracts are present. Browser verification did not complete, so this report does not claim visual or interactive Browser acceptance.

## Files created

| File | Bytes | Purpose |
|---|---:|---|
| `docs/workbench_preview/index.html` | 671 | Chinese semantic entry document, ordered stylesheet entry points, app mount, noscript fallback |
| `docs/workbench_preview/assets/icons.svg` | 6,927 | Shared rounded-line SVG symbol sprite |
| `docs/workbench_preview/styles/tokens.css` | 1,150 | Approved cool palette, spacing, radii, elevation, blur, motion, and opaque fallback tokens |
| `docs/workbench_preview/styles/shell.css` | 4,258 | Viewport, shared shell, sidebar, header/tabs, compact continuation, reduced-motion rules |
| `docs/workbench_preview/styles/components.css` | 6,159 | Brand/search/nav controls, tabs, quick action, glass/fallback, visible focus and toggle states |
| `docs/workbench_preview/styles/views.css` | 11,055 | First-slice Today shell content and full-bleed CSS weather standby composition |
| `docs/workbench_preview/scripts/demo-data.js` | 1,392 | Frozen fictional Chinese preview data only |
| `docs/workbench_preview/scripts/render.js` | 8,936 | Semantic shared-shell/weather renderer consuming Task 2 navigation configuration |
| `docs/workbench_preview/scripts/app.js` | 2,528 | `startPreview(root)`, single delegated root click contract, weather presentation events, Escape handling |
| `docs/workbench_preview/tests/shell.test.mjs` | 2,888 | Focused renderer and event-contract tests added test-first |

Task 2 files `scripts/nav-config.js`, `scripts/state.js`, and `tests/state.test.mjs` were consumed without modification. No Flutter files were changed. No Git repository was initialized.

## TDD evidence

### RED

Command:

```powershell
node --test docs\workbench_preview\tests\shell.test.mjs
```

Observed before production modules were created:

```text
Error [ERR_MODULE_NOT_FOUND]: Cannot find module
...\docs\workbench_preview\scripts\render.js
tests 1
pass 0
fail 1
exit code 1
```

This was the expected missing-feature failure for the new rendering entry point.

### GREEN — new shell/event contracts

Command:

```powershell
node --test docs\workbench_preview\tests\shell.test.mjs
```

Observed after implementation:

```text
✔ workspace render exposes semantic navigation and configured labels
✔ weather render keeps a return control and no more than three today items
✔ delegated controls map to reducer action contracts
tests 3
pass 3
fail 0
exit code 0
```

The tests protect the following consumer-visible breaks:

- loss of the semantic navigation/header landmarks or configured primary/secondary labels;
- loss of the weather return action, clock/temperature identity, or the three-item cap;
- incorrect mapping of delegated workspace/tab/weather/transparency controls to the reducer actions.

### GREEN — prescribed Task 2 state suite

Command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Observed:

```text
✔ weather is manual and restores the previous workspace
✔ secondary tabs are remembered independently
✔ unknown workspaces and tabs leave state unchanged
tests 3
pass 3
fail 0
exit code 0
```

## SVG inventory

The sprite contains exactly 25 requested symbols, each with `viewBox="0 0 24 24"`, `currentColor`, rounded caps/joins, and a 1.8px base stroke:

`brand`, `weather`, `today`, `calendar`, `todo`, `research`, `literature`, `notes`, `analysis`, `people`, `statistics`, `materials`, `document`, `pdf`, `life`, `campus`, `companion`, `personalization`, `settings`, `search`, `sidebar-toggle`, `back`, `chevron`, `quick-capture`, `ai`.

## Implementation inventory and self-review

- `render.js` imports `PRIMARY_NAV` and `WORKSPACE_TABS`; it does not define another navigation array. Primary labels, workspace title, and tab labels are rendered from the Task 2 configuration.
- The document keeps business/demo content out of `index.html`; code-native labels and fictional demo data live in modules.
- The workspace shell contains an `aside` navigation landmark, semantic search form, primary navigation buttons with `aria-current`, bottom Settings, manual sidebar collapse, header, tabs, and content region.
- Settings remains the bottom navigation item. Reduced transparency is a separate visible preview control rather than another primary destination.
- Weather can only be entered by an explicit weather control. There are no idle listeners, intervals, timer-driven navigation, or automatic weather entry.
- The only automatic presentation response is inside an already open weather page: pointer leave hides weather chrome; hovering the short left-edge affordance shows it. This dispatches only `SET_WEATHER_CHROME`.
- The return button and Escape dispatch `EXIT_WEATHER`; Escape has no effect outside weather. The Task 2 reducer preserves and restores the prior workspace and its remembered tab.
- Reduced transparency sets a root data state and removes `backdrop-filter` from glass/search/quick/floating surfaces, replacing them with tokenized opaque surfaces.
- `prefers-reduced-motion: reduce` removes transform/opacity transition behavior.
- The desktop shell uses the approved cool cloudy blue surround, academic-green sidebar, pearl-white main surface, open content structure, slim selected-row accent, and no cream/beige substitution.
- The weather reference is not embedded in the implementation. Sky and cloud atmosphere are CSS-native; all interface text remains DOM text.
- The left-edge reveal control is 28×112px in its resting state, shorter and quieter than the accepted concept draft.
- No action uses `下载`; Task 3 does not expose a file export action.
- Compact CSS at 1,040px forces an icon-width sidebar and keeps the content grid min-width-safe; the 980px result still needs Browser confirmation.
- Quick capture and search are present for shell identity but intentionally have no feature behavior in this Task 3 slice. Research, Materials, Life, and Settings content remains a restrained structural placeholder for later tasks, without visible “coming soon” filler.

## Accepted-concept inspection

Before editing, the following approved references were opened with `view_image` at original detail:

- `docs/workbench_preview/assets/concepts/weather.png` (1440×900)
- `docs/workbench_preview/assets/concepts/today.png` (1440×900)

Implementation choices compared against those references included the shared 224px-class green sidebar, cool pearl workspace panel, open Today split, restrained tab rule, tall left weather glass surface, right return control, bottom utility control, and short left-edge reveal affordance.

## Browser status and blocker

Browser runtime selection, in-app Browser binding, complete Browser documentation, local-development guidance, and viewport capability setup all succeeded. A Python server process was started on port 8765 and the 1280×800 viewport override was requested.

The subsequent Browser call that created/navigated the tab and waited for `networkidle` was interrupted after approximately 277 seconds. It returned no completed DOM snapshot, console log result, screenshot, page-identity evidence, or interaction evidence. The main controller subsequently observed no listener on port 8765.

Therefore the following required items are **not verified in this report**:

- Browser page identity and visible-label smoke check;
- console-error inspection;
- sidebar collapse/expand interaction;
- manual weather entry, Return, and Escape restoration;
- weather pointer-leave/left-edge chrome behavior;
- reduced-transparency visual state;
- 1280×800 and approximately 980px overflow behavior;
- Browser screenshot capture and `view_image` comparison against the accepted concepts.

No latest implementation screenshot exists to inspect, so the frontend fidelity/agency-signoff gate is intentionally left open for the main controller's Browser QA.

## Concerns for central QA

1. Confirm the local server is listening before opening the URL; the earlier process was no longer observable after the interrupted Browser call.
2. Inspect external SVG symbol loading in the actual Browser. The markup uses `assets/icons.svg#icon-*`, which requires serving over HTTP as prescribed.
3. Compare the CSS-generated weather atmosphere to the accepted photographic reference; this is the highest visual-judgment risk.
4. Verify the tall weather panel remains unclipped at 1280×800 and the icon-only sidebar/content remain usable at approximately 980px.
5. Inspect console logs and exercise the exact state path `Today → Research → Notes → Weather → Esc`, plus sidebar and reduced-transparency toggles.

---

## Fix Round 1 — Three Important Review Findings

### Status

Implementation fixes are complete and the focused Node contracts are GREEN. Browser re-verification is intentionally delegated to the main controller per the round brief.

### Exact files added or modified

| File | Action | Final bytes | Change |
|---|---|---:|---|
| `docs/workbench_preview/assets/weather-cloudscape.png` | Added | 1,646,563 | Interface-free ImageGen cloudscape used by Weather |
| `docs/workbench_preview/scripts/render.js` | Modified | 8,992 | Adds `is-sidebar-collapsed` to the rendered shell when state is collapsed |
| `docs/workbench_preview/styles/tokens.css` | Modified | 1,222 | Adds fully opaque `--surface-opaque-search` and `--surface-opaque-reveal` tokens |
| `docs/workbench_preview/styles/shell.css` | Modified | 4,473 | Collapsed desktop shell changes its first grid track from 224px to 80px; compact rules retain their breakpoint widths |
| `docs/workbench_preview/styles/components.css` | Modified | 6,401 | Reduced-transparency state removes reveal blur and applies opaque search/reveal token backgrounds |
| `docs/workbench_preview/styles/views.css` | Modified | 9,880 | Replaces abstract radial cloud construction with the new full-bleed cloudscape asset and removes the synthetic overlay layers |
| `docs/workbench_preview/tests/shell.test.mjs` | Modified | 4,234 | Adds two focused regression contracts before implementation |

No Minor findings were included. No Flutter files were touched, and no Git repository was initialized.

### ImageGen workflow and prompt

Tool: built-in `image_gen` edit workflow (`image_gen.imagegen`), using `docs/workbench_preview/assets/concepts/weather.png` as the local reference/edit target after inspecting it with `view_image` at original detail.

Final project asset: `docs/workbench_preview/assets/weather-cloudscape.png`, 1586×992 PNG.

Exact structured prompt:

```text
Use case: precise-object-edit
Asset type: full-bleed desktop application weather background, 16:10 landscape
Input image: Image 1 is the accepted composition, cloud atmosphere, cool teal-blue palette, and lighting reference, and is also the edit target.
Primary request: remove every interface element from the reference and reconstruct the obscured sky so the final result is a seamless interface-free cloudy-sky background.
Scene/backdrop: a calm, photorealistic expansive sky with deep teal-blue distance, layered cumulus cloud masses across the lower and right regions, smaller wisps in the upper-right, distinct softly illuminated silver-white cloud edges, atmospheric depth, subtle sun rays and natural light falloff emerging from the lower-left/center.
Composition/framing: 1440×900-style wide desktop background. Preserve the accepted visual balance: quieter, softer open sky on the upper-left so code-native UI can sit there; the most dimensional cloud mass and luminous focal structure extend across the center-right and lower half; continuous edge-to-edge sky with no frame.
Lighting/mood: serene late-afternoon diffuse light, cinematic but restrained, softly glowing cloud rims, dimensional shadows, gentle haze.
Color palette: cool desaturated blue-green and teal, pearl-white cloud highlights, muted blue-gray shadows. No warm beige or orange cast.
Constraints: output must be a standalone background image only. Remove and forbid every glass panel, card, sidebar, button, return control, reveal tab, settings control, logo, brand, text, number, date, weather icon, agenda item, divider, border, glyph, or other UI surface. Reconstruct natural clouds behind all removed regions. No overlaid tint or vignette that flattens cloud detail. No people, buildings, ground, watermark, or typography.
Avoid: abstract gradient-only fields, soft featureless blobs, repeated radial shapes, UI remnants, readable or pseudo text, icons, rectangles, rounded panels, controls, logos.
```

The generated image was copied from the built-in output location to the project asset path without overwriting the accepted concept.

### Output inspection

`weather-cloudscape.png` was opened with `view_image` at original detail after copying into the project. Inspection confirmed:

- no UI surface, logo, text, number, icon, control, rounded panel, or watermark remains;
- distinct bright cloud rims appear around the lower-left illuminated mass;
- layered foreground and distance cloud masses provide readable depth across the lower and right regions;
- natural light rays and falloff emerge from the lower-left/center;
- the upper-left remains comparatively quiet for the code-native weather panel;
- the palette remains cool teal-blue with pearl-white highlights and blue-gray shadows;
- the asset reads as a cloudy sky rather than broad radial blobs.

`styles/views.css` consumes the asset directly as a full-bleed `background` with `center / cover no-repeat`. The prior radial-gradient cloud construction and pseudo-element overlay layers were removed, so the image is not flattened by an additional UI tint. All Weather interface text, glass, buttons, icons, and agenda content remain code-native DOM/CSS.

### TDD evidence

#### RED

The two regression tests were added before production changes.

Command:

```powershell
node --test docs\workbench_preview\tests\shell.test.mjs
```

Observed:

```text
✔ workspace render exposes semantic navigation and configured labels
✔ weather render keeps a return control and no more than three today items
✔ delegated controls map to reducer action contracts
✖ reduced-transparency fallbacks make search and weather reveal opaque
✖ collapsed desktop shell reclaims the sidebar grid track
tests 5
pass 3
fail 2
exit code 1
```

The first failure identified the absent opaque search/reveal tokens. The second showed that collapsed rendering still produced only `class="app-shell"`, so no state was available to reclaim the 224px grid track.

#### GREEN — focused shell suite

Command:

```powershell
node --test docs\workbench_preview\tests\shell.test.mjs
```

Observed after implementation:

```text
✔ workspace render exposes semantic navigation and configured labels
✔ weather render keeps a return control and no more than three today items
✔ delegated controls map to reducer action contracts
✔ reduced-transparency fallbacks make search and weather reveal opaque
✔ collapsed desktop shell reclaims the sidebar grid track
tests 5
pass 5
fail 0
exit code 0
```

#### GREEN — state regression suite

Command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Observed:

```text
✔ weather is manual and restores the previous workspace
✔ secondary tabs are remembered independently
✔ unknown workspaces and tabs leave state unchanged
tests 3
pass 3
fail 0
exit code 0
```

### Finding-by-finding resolution

1. **Weather atmosphere:** resolved with the inspected, interface-free `weather-cloudscape.png`; CSS radial cloud approximations were removed.
2. **Reduced transparency:** both `.search-control` and `.weather-reveal` now use opaque hex-backed tokens. `.weather-reveal` participates in the state selector that sets both standard and prefixed `backdrop-filter` to `none`.
3. **Desktop collapse:** `renderPreview` now adds `is-sidebar-collapsed` to `.app-shell`; desktop CSS changes the first grid track to 80px so the main workspace reclaims the released 144px. Existing compact breakpoints explicitly retain 80px and 64px tracks.

### Remaining concerns / controller QA

- Browser was not attempted in this fix round, as instructed. The controller still needs to capture Weather at 1280×800 and confirm the asset crop, glass legibility, and concept fidelity in the composed interface.
- The controller should toggle reduced transparency on both shared shell and Weather, then inspect computed backgrounds/backdrop filters for search and reveal.
- The controller should collapse the sidebar above 1040px and confirm the main panel visibly expands as the grid track changes from 224px to 80px.
- The generated PNG is approximately 1.65 MB; acceptable for a local preview, but future production integration may choose a quality-checked WebP derivative. No optimization was added in this review-limited round.

---

## Fix Round 2 — Opaque Reduced-Transparency Reveal

### Scope and files

Only the remaining Important finding from `task-3-fix-round-1-review.md` was addressed.

- Modified `docs/workbench_preview/tests/shell.test.mjs`: the existing reduced-transparency regression now extracts the state-specific reveal block carrying `--surface-opaque-reveal` and requires `opacity: 1` there.
- Modified `docs/workbench_preview/styles/components.css`: `.preview-root[data-reduced-transparency="true"] .weather-reveal` now explicitly sets `opacity: 1` in addition to its opaque tokenized background and standard/prefixed `backdrop-filter: none` declarations.

No other finding, Flutter file, asset, or behavior was changed. Browser was not attempted, as instructed.

### RED evidence

The regression assertion was added before the production declaration.

Command:

```powershell
node --test docs\workbench_preview\tests\shell.test.mjs
```

Observed:

```text
✔ workspace render exposes semantic navigation and configured labels
✔ weather render keeps a return control and no more than three today items
✔ delegated controls map to reducer action contracts
✖ reduced-transparency fallbacks make search and weather reveal opaque
✔ collapsed desktop shell reclaims the sidebar grid track
tests 5
pass 4
fail 1
exit code 1
```

The targeted assertion received the correct reduced-transparency rule body—opaque reveal background plus both no-blur declarations—but failed because it did not contain `opacity: 1`.

### GREEN evidence

Focused shell command:

```powershell
node --test docs\workbench_preview\tests\shell.test.mjs
```

Observed after the single CSS declaration was added:

```text
tests 5
pass 5
fail 0
exit code 0
```

State regression command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Observed:

```text
tests 3
pass 3
fail 0
exit code 0
```

### Result and remaining verification

In the normal state, `.weather-reveal` retains the accepted quiet `opacity: 0.52`. When reduced transparency is enabled, the more specific state rule now overrides that value to `1`, so the control's already-opaque token background is composited fully opaquely and no cloudscape shows through it. Controller Browser verification remains the only outstanding confirmation for the composed visual state.
