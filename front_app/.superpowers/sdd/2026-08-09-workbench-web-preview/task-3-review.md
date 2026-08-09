# Task 3 Review — App Shell, Navigation, and Weather Standby

## Verdicts

- **Spec Compliance: NEEDS CHANGES.** The semantic shell, manual weather flow, accepted primary IA, limited weather agenda, selective glass usage, responsive structure, and motion preference are implemented. However, the reduced-transparency contract is incomplete, and the weather scene does not preserve the accepted concept's defining cloudscape. The latter is a fidelity-blocking mismatch for this task-scoped acceptance gate.
- **Task Quality: NEEDS CHANGES.** The module boundaries and event model are clean, and the supplied fresh evidence is credible, but the wide-screen collapsed-sidebar layout is internally inconsistent and two small semantic/interaction details remain rough.

No Critical issues were found. The task should not be accepted until the Important issues below are resolved.

## Evidence Reviewed

- Task brief, implementer report, and manual non-Git review package.
- Every added file enumerated in the review package, and no unrelated implementation files.
- Accepted `assets/concepts/weather.png` and `assets/concepts/today.png` at original detail.
- Fresh controller evidence in the review package: 6/6 Node tests, empty browser error/warn log, manual weather/return/Escape/transparency/sidebar paths, and 980×800 no-overflow result. The full suite was not rerun.
- One focused local visual attempt was started, but the browser wait primitive rejected `networkidle` before the Weather screenshot was captured; no conclusion below relies on that incomplete attempt.

## Strengths

- The document entry is minimal and correctly ordered: Chinese locale and title, token/shell/component/view styles in sequence, a semantic app mount, noscript fallback, and module entry point (`index.html:2-16`). Demo/business content is not inlined into HTML.
- The SVG sprite contains the complete requested 25-symbol inventory and consistently applies `viewBox="0 0 24 24"`, `currentColor`, rounded joins/caps, and 1.8px stroke treatment (`assets/icons.svg:2-76`).
- The renderer consumes `PRIMARY_NAV` and `WORKSPACE_TABS` rather than creating a second navigation model (`scripts/render.js:1,15-17,31-80`). The shell exposes an `aside`, search landmark, workspace `nav`, selected-page semantics, bottom controls, header, and tabs (`scripts/render.js:31-80,127-145`).
- Weather is entered explicitly and preserves a visible return path. The weather view caps agenda output to three items (`scripts/render.js:148-202`), while delegated actions and Escape handling do not create idle or automatic navigation (`scripts/app.js:5-25,41-65`). This aligns with the privacy/scope constraint that weather is manual and returns to the prior workspace.
- The Today composition is recognizably faithful to the accepted concept: green academic sidebar, pearl-white main surface, restrained tab rule, open two-column timeline/todo structure, and no glass base under list content (`styles/shell.css:63-70,72-83,113-129`; `styles/views.css:1-15,24-142`).
- The implementation keeps glass selective: search, quick action, Weather card, and floating controls use it, while workspace/list/content surfaces remain opaque (`styles/components.css:70-82,247-282`; `styles/shell.css:113-129`; `styles/views.css:1-178`).
- Motion tokens and reduced-motion behavior are present (`styles/tokens.css:42-44`; `styles/shell.css:228-237`; `styles/views.css:573-583`). The controller's 980×800 evidence closes the requested compact-overflow check.
- No Flutter, backend, filesystem, auth, sync, AI, PDF, or personal-data connection is introduced in the reviewed files. The AI symbol exists only as unused sprite vocabulary (`assets/icons.svg:74-76`), so no AI surface leaks outside Research.

## Issues

### Critical

None.

### Important

1. **The Weather background is materially less atmospheric/cloud-like than the accepted concept and is fidelity-blocking.** The accepted `weather.png` is dominated by a photographic-looking cloudscape: distinct illuminated cloud edges, deep layered cloud masses, visible sky depth, and rays/light falloff. The implementation constructs the entire scene from a teal linear gradient plus a handful of broad, blurred radial ellipses (`styles/views.css:180-224`). Those primitives can produce soft pale blobs, but not the accepted concept's recognizable cloud forms, depth, or luminous focal structure. Because the atmosphere occupies nearly the whole viewport and is the defining Weather surface—not a peripheral decoration—this is a material concept change even though hue temperature and card placement are broadly aligned. Replace or substantially enrich this layer so a 1280×800 capture reads immediately as a cloudy sky at normal viewing size while keeping all UI text in the DOM.

2. **The reduced-transparency control does not remove transparency/blur from every glass surface.** The fallback selector disables backdrop filtering for `.glass-surface`, `.floating-control`, `.search-control`, and `.quick-action` (`styles/components.css:299-305`), but the left-edge Weather reveal remains translucent and retains `backdrop-filter: blur(...)` (`styles/views.css:444-465`). In addition, the reduced-transparency search fallback is still an alpha color rather than an opaque tokenized surface (`styles/components.css:312-314`). This conflicts with the brief's explicit requirement that enabled fallbacks use opaque tokenized backgrounds and no backdrop filter. Include the reveal control in the state selector, remove its blur, and give both reveal/search opaque fallback tokens.

3. **Wide-screen sidebar collapse changes only the sidebar element, not its grid track.** Above 1040px, `.app-shell` always allocates a 224px first column (`styles/shell.css:63-70`), while the collapsed sidebar is assigned only `width: 80px` (`styles/shell.css:86-88`). `renderPreview` adds no shell/root collapsed-state class that could change the track (`scripts/render.js:205-214`). The result is an 80px rail sitting in a 224px column with roughly 144px of dead space; the workspace does not expand. This makes the visible collapse affordance functionally incomplete on the principal desktop viewport. Drive the grid column from collapsed state (or use a layout rule that lets the track follow the sidebar width).

### Minor

1. **The clock's machine-readable value is hard-coded.** Visible time comes from demo data, but `datetime="16:38"` is fixed (`scripts/render.js:168`). If the demo time changes, visual and semantic time diverge. Derive and escape the attribute from the same data source.

2. **The inert search form can still submit and reload/reset the preview.** The shell renders a real `<form>` without a submit action override (`scripts/render.js:47-51`), while the root delegation handles only clicks (`scripts/app.js:41-43`). Pressing Enter in the advertised-but-intentionally-inert search control can therefore perform the browser's default GET/navigation and reset state. Either prevent submit for this preview slice or render a non-submitting search control until search behavior exists.

3. **Focused tests do not protect the two CSS-state regressions above.** The renderer tests cover landmarks, labels, the three-item cap, and action mapping (`tests/shell.test.mjs:35-85`), but nothing asserts collapsed track reclamation or complete reduced-transparency fallbacks. The fresh manual run confirms the buttons operate, not that all affected surfaces honor their layout/accessibility contract. Add focused static or browser assertions when fixing the Important issues.

## Assessment

Task 3 establishes a sound structural foundation: it is scoped to the Web preview, uses clean code-native rendering, respects the accepted IA, keeps weather manual, and carries the Today concept convincingly into a responsive shell. The implementation is close, and the supplied 6/6 plus interaction/overflow evidence removes concern about basic state wiring.

Acceptance should nevertheless remain open. The Weather background is the dominant visual identity of the accepted concept, and the current CSS construction reduces it to an abstract teal field; that is the explicitly identified risk, and it is material. The reduced-transparency gap is also a direct accessibility/spec miss, while the desktop collapse defect is a visible quality issue. Address those three Important items, then repeat only focused visual checks at 1280×800 and ~980×800 plus the existing small test suite.
