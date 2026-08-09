### Task 3: Build the App Shell, Navigation, and Weather Standby View

**Files:**
- Create: `docs/workbench_preview/index.html`
- Create: `docs/workbench_preview/assets/icons.svg`
- Create: `docs/workbench_preview/styles/tokens.css`
- Create: `docs/workbench_preview/styles/shell.css`
- Create: `docs/workbench_preview/styles/components.css`
- Create: `docs/workbench_preview/styles/views.css`
- Create: `docs/workbench_preview/scripts/demo-data.js`
- Create: `docs/workbench_preview/scripts/render.js`
- Create: `docs/workbench_preview/scripts/app.js`

**Interfaces:**
- Consumes: `PRIMARY_NAV`, `WORKSPACE_TABS`, `createInitialState()`, `reducePreviewState()`.
- Produces: a working shell, sidebar, weather screen, semantic DOM, and `startPreview(root)`.

- [ ] **Step 1: Add the semantic document and script/style entry points**

Create a Chinese `index.html` with `<main id="app">`, a `<noscript>` message, the four stylesheet links in token/shell/component/view order, and `<script type="module" src="scripts/app.js"></script>`. Do not inline business/demo content in HTML.

- [ ] **Step 2: Implement exact design tokens extracted from approved concepts**

Define custom properties for canvas, sidebar, text, borders, academic green, semantic colors, 8px spacing scale, 10/14/20px radii, one small shadow, blur strengths, 140/200/220ms motion, and the reduced-transparency opaque surfaces. Lock the background temperature to the approved concept.

- [ ] **Step 3: Create a consistent SVG sprite**

Add symbols for brand, weather, today, calendar, todo, research, literature, notes, analysis, people, statistics, materials, document, PDF, life, campus, companion, personalization, settings, search, sidebar toggle, back, chevron, quick capture, and AI. All symbols use `viewBox="0 0 24 24"`, `currentColor`, rounded caps/joins, and a consistent 1.8px stroke unless the approved concept uses filled shapes.

- [ ] **Step 4: Implement the shell renderer**

`renderPreview(root, state, data)` must output an `<aside>` navigation landmark, search control, primary navigation buttons with `aria-current`, bottom settings, a header/tab region, and a content view. Bind visible labels from `nav-config.js`, not duplicated string arrays.

- [ ] **Step 5: Implement app event delegation**

Use one root click listener reading `data-action`, `data-workspace`, `data-tab`, and item IDs. Re-render after reducer updates. Bind `Escape` only to exit weather. Do not implement idle listeners, intervals, or automatic weather entry.

- [ ] **Step 6: Implement weather chrome behavior**

On weather entry, keep chrome visible long enough to orient the user, then allow pointer leave/left-edge hover to toggle only `weatherChromeVisible`; this is a presentation behavior inside the already manually opened page, not automatic navigation. Provide a visible return button and preserve the prior workspace.

- [ ] **Step 7: Add reduced-motion and reduced-transparency behavior**

In CSS, remove transform/opacity animations under `prefers-reduced-motion: reduce`. Add a visible preview control that dispatches `SET_REDUCED_TRANSPARENCY`; when enabled, glass surfaces use opaque tokenized backgrounds and no `backdrop-filter`.

- [ ] **Step 8: Run pure state tests**

Run:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Expected: PASS.

- [ ] **Step 9: Launch and inspect the shell**

Run from `front_app`:

```powershell
python -m http.server 8765 --bind 127.0.0.1
```

Open `http://127.0.0.1:8765/docs/workbench_preview/` in the in-app Browser. Verify visible brand, search, weather, today, research, materials, life, settings, sidebar toggle, and weather return control. Verify browser console has no errors.

---

