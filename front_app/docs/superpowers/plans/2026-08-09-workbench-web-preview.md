# 研LIFE Workbench Web Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local, interactive Web preview that lets the user approve the redesigned navigation, weather standby surface, glass treatment, density, and four representative workbench views before any Flutter UI code changes.

**Architecture:** Create a dependency-free static ES-module prototype under `docs/workbench_preview/`. Keep navigation/state transitions in pure JavaScript modules with Node built-in tests; render semantic HTML from fixed demo data; keep design tokens, shell styling, and view styling in separate CSS files. Generate and approve complete visual concepts before writing the prototype, then verify the implementation in the in-app Browser at desktop and compact widths.

**Tech Stack:** HTML5, CSS custom properties, vanilla ES modules, Node.js built-in `node:test`, local Python static server, in-app Browser, ImageGen concept images.

## Global Constraints

- The real product remains Flutter Windows; the Web deliverable is design-only and must not connect to the backend, filesystem, authentication, sync, AI, PDF processing, or personal data.
- Preserve the approved information architecture: weather, today, research, materials, life, and bottom settings; AI belongs inside research.
- The weather page is entered manually only; no idle timer or automatic navigation.
- Page descriptions are optional, one line maximum, and must remain visually secondary.
- Use glass only for weather information surfaces, brand/search areas, floating controls, dialogs, quick actions, and status surfaces.
- Do not use glass as the base for scrolling lists, file tables, reading content, or every summary panel.
- Desktop acceptance viewport is 1280×800; compact acceptance width is approximately 980px with no horizontal overflow.
- Respect `prefers-reduced-motion`; provide a preview toggle that replaces blur with an opaque fallback for reduced-transparency inspection.
- The workspace has no `.git` repository. Do not run `git init`; task checkpoints use tests and file inventories instead of commits.
- Source specification: `docs/superpowers/specs/2026-08-09-workbench-redesign-design.md`.

---

## File Map

Create the following focused files:

- `docs/workbench_preview/index.html` — semantic shell, app mount point, SVG sprite link, and no business data.
- `docs/workbench_preview/assets/icons.svg` — consistent 24×24 rounded-line icon symbols.
- `docs/workbench_preview/assets/concepts/weather.png` — approved weather concept reference.
- `docs/workbench_preview/assets/concepts/today.png` — approved today concept reference.
- `docs/workbench_preview/assets/concepts/research.png` — approved research concept reference.
- `docs/workbench_preview/assets/concepts/materials.png` — approved materials concept reference.
- `docs/workbench_preview/styles/tokens.css` — palette, typography, spacing, radii, elevation, blur, motion, and fallback tokens.
- `docs/workbench_preview/styles/shell.css` — viewport, sidebar, header, workspace tabs, responsive rules, and weather shell behavior.
- `docs/workbench_preview/styles/components.css` — buttons, glass surfaces, search, badges, rows, feedback, and tooltip styling.
- `docs/workbench_preview/styles/views.css` — weather, today, research, materials, life, and settings compositions.
- `docs/workbench_preview/scripts/nav-config.js` — immutable navigation and secondary-tab definitions.
- `docs/workbench_preview/scripts/demo-data.js` — fixed Chinese demonstration content only.
- `docs/workbench_preview/scripts/state.js` — pure preview state and reducer.
- `docs/workbench_preview/scripts/render.js` — render functions that consume state and demo data.
- `docs/workbench_preview/scripts/app.js` — DOM event binding, keyboard behavior, and startup.
- `docs/workbench_preview/tests/state.test.mjs` — reducer and navigation contract tests.
- `docs/workbench_preview/README.md` — local launch, interaction checklist, and explicit prototype limitations.

## Interfaces

```js
// scripts/nav-config.js
export const PRIMARY_NAV;
export const WORKSPACE_TABS;
export function isWorkspaceId(value);
export function defaultTabFor(workspaceId);

// scripts/state.js
export function createInitialState();
export function reducePreviewState(state, action);

// scripts/render.js
export function renderPreview(root, state, data);

// scripts/app.js
export function startPreview(root);
```

State shape:

```js
{
  workspace: 'today',
  workspaceTabs: {
    today: 'today-overview',
    research: 'research-overview',
    materials: 'files',
    life: 'campus'
  },
  sidebarCollapsed: false,
  weatherChromeVisible: true,
  previousWorkspace: null,
  selectedMaterialId: 'paper-gnss',
  expandedResearchPanel: null,
  reducedTransparency: false
}
```

Supported action types:

```js
{ type: 'SELECT_WORKSPACE', workspace }
{ type: 'SELECT_TAB', workspace, tab }
{ type: 'TOGGLE_SIDEBAR' }
{ type: 'ENTER_WEATHER' }
{ type: 'SET_WEATHER_CHROME', visible }
{ type: 'EXIT_WEATHER' }
{ type: 'SELECT_MATERIAL', id }
{ type: 'TOGGLE_RESEARCH_PANEL', id }
{ type: 'SET_REDUCED_TRANSPARENCY', enabled }
```

---

### Task 1: Generate and Approve Complete Visual Concepts

**Files:**
- Create: `docs/workbench_preview/assets/concepts/weather.png`
- Create: `docs/workbench_preview/assets/concepts/today.png`
- Create: `docs/workbench_preview/assets/concepts/research.png`
- Create: `docs/workbench_preview/assets/concepts/materials.png`

**Interfaces:**
- Consumes: approved design specification and existing academic-green brand direction.
- Produces: four 1440×900 concept screenshots that become the visual source of truth for later tasks.

- [ ] **Step 1: Read the ImageGen skill and approved specification**

Read the complete `imagegen/SKILL.md` and `docs/superpowers/specs/2026-08-09-workbench-redesign-design.md`. Do not write prototype code before the concepts are approved.

- [ ] **Step 2: Generate the weather concept**

Use this exact design brief:

```text
Create a complete 1440×900 desktop product UI concept for 研LIFE, a personal Flutter workbench balancing research and daily life equally. This screen is a manually opened weather standby page. Use a restrained academic-green brand, true cool pearl-white text, a calm atmospheric sky background, and selective iOS-like frosted glass only for the clock/weather information surface and small floating controls. Show large time, Chinese date, concise weather, and no more than three short today items. The navigation chrome fades away in standby mode; include a subtle left-edge reveal affordance and an unobtrusive return control. No marketing hero, no badges, no filler metrics, no card grid, no auto-idle language. Text must be Chinese and concise. Controls and text are intended to be code-native. Professional Windows desktop app, 7/10 creativity, readable and implementable.
```

- [ ] **Step 3: Generate the today concept**

Use this exact design brief:

```text
Create a complete 1440×900 desktop product UI concept for 研LIFE using the same visual system as the approved weather concept. Show the expanded 216px sidebar with brand/search, fixed weather entry, Today selected, Research, Materials, Life, and bottom Settings. Use a lighter selected row with a slim left accent, not a large white pill. Main content: concise page title, tabs Today / Calendar / Todos, one primary quick-capture action, left chronological timeline, right actionable todo list. Research and life should feel equally important across the product. Use selective frosted glass only in brand/search or a floating quick action; lists remain opaque and crisp. Avoid excessive cards, explanatory copy, badges, and decorative dashboard metrics.
```

- [ ] **Step 4: Generate the research concept**

Use this exact design brief:

```text
Create a complete 1440×900 research-workspace UI concept for 研LIFE in the exact same shell, palette, typography, icon style, density, and glass system as the approved today concept. Research is selected. Secondary tabs: Overview, Literature, Notes, Weekly Analysis, People, Statistics. The Overview shows recent reading, notes needing organization, this-week plans, and one restrained AI assistant action. Use open sections and rows rather than a repetitive card grid. Keep descriptions to one short line maximum. No fake business metrics, no marketing copy, no hero eyebrow, no excessive glass.
```

- [ ] **Step 5: Generate the materials concept**

Use this exact design brief:

```text
Create a complete 1440×900 materials-workbench UI concept for 研LIFE in the exact same approved design system. Materials is selected. Secondary tabs: Files, Document View, PDF Tools. Use a desktop three-pane structure: narrow folder tree, central file table/list, right detail inspector with concise metadata and contextual actions. Keep scrolling content opaque and highly readable. Glass is allowed only for shell search and a small floating status/control surface. Do not convert the file table into cards. No fake cloud claims or personal data.
```

- [ ] **Step 6: Inspect all four concepts visually**

Use `view_image` on every concept. Reject and regenerate any concept with unreadable text, mismatched navigation, warm cream substituted for the approved cool light surfaces, excessive glass, a card-grid layout, missing secondary tabs, or invented features.

- [ ] **Step 7: Present the concept set to the user and stop for approval**

Show all four images with brief labels. Do not continue to Task 2 until the user explicitly approves the concepts or approves a revised set.

- [ ] **Step 8: Record the checkpoint**

Run:

```powershell
Get-ChildItem docs\workbench_preview\assets\concepts -Filter *.png | Select-Object Name,Length
```

Expected: exactly `weather.png`, `today.png`, `research.png`, and `materials.png`, each non-empty.

---

### Task 2: Implement Navigation Configuration and Pure State

**Files:**
- Create: `docs/workbench_preview/scripts/nav-config.js`
- Create: `docs/workbench_preview/scripts/state.js`
- Create: `docs/workbench_preview/tests/state.test.mjs`

**Interfaces:**
- Consumes: state/action contracts defined in this plan.
- Produces: `PRIMARY_NAV`, `WORKSPACE_TABS`, `createInitialState()`, and `reducePreviewState()` for all later rendering and interaction tasks.

- [ ] **Step 1: Write the failing state tests**

Create `tests/state.test.mjs` with Node built-in tests covering:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createInitialState, reducePreviewState } from '../scripts/state.js';

test('weather is manual and restores the previous workspace', () => {
  const initial = createInitialState();
  const inResearch = reducePreviewState(initial, {
    type: 'SELECT_WORKSPACE',
    workspace: 'research'
  });
  const inWeather = reducePreviewState(inResearch, { type: 'ENTER_WEATHER' });
  assert.equal(inWeather.workspace, 'weather');
  assert.equal(inWeather.previousWorkspace, 'research');
  const restored = reducePreviewState(inWeather, { type: 'EXIT_WEATHER' });
  assert.equal(restored.workspace, 'research');
  assert.equal(restored.previousWorkspace, null);
});

test('secondary tabs are remembered independently', () => {
  let state = createInitialState();
  state = reducePreviewState(state, {
    type: 'SELECT_TAB',
    workspace: 'research',
    tab: 'notes'
  });
  state = reducePreviewState(state, {
    type: 'SELECT_TAB',
    workspace: 'today',
    tab: 'calendar'
  });
  assert.equal(state.workspaceTabs.research, 'notes');
  assert.equal(state.workspaceTabs.today, 'calendar');
});

test('unknown workspaces and tabs leave state unchanged', () => {
  const state = createInitialState();
  assert.deepEqual(
    reducePreviewState(state, { type: 'SELECT_WORKSPACE', workspace: 'unknown' }),
    state
  );
  assert.deepEqual(
    reducePreviewState(state, {
      type: 'SELECT_TAB',
      workspace: 'research',
      tab: 'unknown'
    }),
    state
  );
});
```

- [ ] **Step 2: Run the tests and verify failure**

Run:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Expected: FAIL because `scripts/state.js` does not exist.

- [ ] **Step 3: Implement immutable navigation configuration**

Define primary items with IDs `weather`, `today`, `research`, `materials`, `life`, and `settings`. Define the exact secondary tab IDs from the approved specification. Freeze exported arrays/objects so rendering cannot mutate configuration.

- [ ] **Step 4: Implement the pure reducer**

Implement every action contract listed in this plan. `ENTER_WEATHER` must copy the current non-weather workspace into `previousWorkspace`; `EXIT_WEATHER` must restore it or fall back to `today`; no timer action exists.

- [ ] **Step 5: Run state tests**

Run:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Expected: all tests PASS.

- [ ] **Step 6: Record the checkpoint**

Run:

```powershell
Get-ChildItem docs\workbench_preview\scripts\nav-config.js,docs\workbench_preview\scripts\state.js,docs\workbench_preview\tests\state.test.mjs | Select-Object Name,Length
```

Expected: three non-empty files.

---

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

### Task 4: Implement Today and Research Views

**Files:**
- Modify: `docs/workbench_preview/scripts/demo-data.js`
- Modify: `docs/workbench_preview/scripts/render.js`
- Modify: `docs/workbench_preview/styles/views.css`
- Modify: `docs/workbench_preview/styles/components.css`
- Modify: `docs/workbench_preview/tests/state.test.mjs`

**Interfaces:**
- Consumes: shell renderer, workspace tab state, `TOGGLE_RESEARCH_PANEL`.
- Produces: interactive Today/Calendar/Todos tabs and Research overview/detail expansion.

- [ ] **Step 1: Add failing reducer tests for research panel toggling**

Add a test asserting that toggling `recent-reading` sets `expandedResearchPanel` to that ID and toggling it again returns `null`.

- [ ] **Step 2: Run state tests and verify failure**

Run the state test command. Expected: the new panel test FAILS until the reducer handles `TOGGLE_RESEARCH_PANEL`.

- [ ] **Step 3: Implement the reducer action and rerun tests**

Add immutable toggle behavior and rerun tests. Expected: PASS.

- [ ] **Step 4: Add concise demo data**

Use fictional Chinese entries with no personal identifiers: three timeline items, four todos, a compact month strip, three recent readings, three notes, and three weekly plans. Descriptions must be one line or omitted.

- [ ] **Step 5: Render Today tabs**

Today overview uses a timeline/list split; Calendar uses a compact month plus selected-day agenda; Todos uses a task list with priority and completion states. Keep one primary quick-capture button and no dashboard metric row.

- [ ] **Step 6: Render Research tabs**

Research overview uses open sections for recent reading, notes, plans, and weekly analysis. Include one restrained AI action. Other secondary tabs can show structurally accurate compact previews, not generic “coming soon” copy.

- [ ] **Step 7: Match the approved concepts in Browser**

At 1280×800, compare today and research against their approved concept images for navigation anatomy, type scale, open-vs-card layout, palette, glass placement, whitespace, and visible copy. Fix every implementation drift that is not an intentional browser constraint.

- [ ] **Step 8: Re-run tests**

Run state tests. Expected: PASS.

---

### Task 5: Implement Materials, Life, and Settings Views

**Files:**
- Modify: `docs/workbench_preview/scripts/demo-data.js`
- Modify: `docs/workbench_preview/scripts/render.js`
- Modify: `docs/workbench_preview/styles/views.css`
- Modify: `docs/workbench_preview/tests/state.test.mjs`

**Interfaces:**
- Consumes: `SELECT_MATERIAL`, workspace tabs, shell components.
- Produces: three-pane materials workbench, recognizable life/settings states, and selection persistence.

- [ ] **Step 1: Add a failing material-selection reducer test**

Assert that `SELECT_MATERIAL` changes `selectedMaterialId` to `paper-hci` and that an empty ID leaves state unchanged.

- [ ] **Step 2: Run the test and verify failure**

Expected: FAIL until `SELECT_MATERIAL` validation exists.

- [ ] **Step 3: Implement selection state and rerun tests**

Expected: PASS.

- [ ] **Step 4: Add materials demo data**

Create a fictional folder tree, six files with type/modified/size metadata, and detail records. Use no local paths, usernames, cloud IDs, or real document titles.

- [ ] **Step 5: Render the three-pane file workbench**

Use a folder tree, table-like central rows, and an opaque detail inspector. Selected rows update the inspector. Keep PDF/document actions contextual. Do not turn rows into cards or put glass behind the scrolling table.

- [ ] **Step 6: Render life and settings states**

Life shows concise tabs for Campus, Companion, and Personalization with recognizable, polished previews. Settings shows a short appearance/accessibility preview including reduced transparency. Neither page uses a long explanation block.

- [ ] **Step 7: Browser comparison**

Compare materials against its approved concept at 1280×800. Verify row alignment, three-pane proportions, selection contrast, inspector density, and absence of scrolling glass.

- [ ] **Step 8: Re-run tests**

Expected: PASS.

---

### Task 6: Responsive, Accessibility, and Fidelity QA

**Files:**
- Modify: `docs/workbench_preview/styles/shell.css`
- Modify: `docs/workbench_preview/styles/components.css`
- Modify: `docs/workbench_preview/styles/views.css`
- Modify: `docs/workbench_preview/scripts/app.js`
- Create: `docs/workbench_preview/README.md`

**Interfaces:**
- Consumes: complete prototype and all approved concepts.
- Produces: verified local preview and written launch/interaction instructions.

- [ ] **Step 1: Verify semantic navigation and keyboard behavior**

Check all navigation buttons and tabs are keyboard reachable, focus rings are visible, `aria-current` is correct, sidebar controls have labels, and `Escape` exits only the weather view.

- [ ] **Step 2: Verify 1280×800 desktop layout**

Capture weather, today, research, and materials screenshots. Confirm no clipped primary content, accidental wrapping, oversized descriptions, browser-default controls, or card-grid drift.

- [ ] **Step 3: Verify approximately 980px width**

Use the Browser viewport override. Confirm sidebar collapses or uses the compact mode, all views remain usable, and there is no horizontal page overflow. Materials may reduce the detail inspector width but must keep the file list usable.

- [ ] **Step 4: Inspect concepts and implementation screenshots side by side**

Use `view_image` on all four accepted concept images and the latest four Browser screenshots. Record at least five checks per screen: navigation/copy, layout, typography, palette/glass, spacing/container model, and responsive behavior. Fix all non-approved mismatches.

- [ ] **Step 5: Verify interaction paths**

Run these paths in Browser:

```text
Today → Research → Notes tab → Weather → Esc → Research/Notes restored
Materials → select another file → Document View tab → Files tab → selection restored
Collapse sidebar → open Life → open Settings → expand sidebar
Enable reduced transparency → visit Weather → all glass surfaces become opaque
```

- [ ] **Step 6: Run automated tests**

Run:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Expected: all tests PASS.

- [ ] **Step 7: Write the README**

Document the exact local launch command, preview URL, four acceptance paths, keyboard behavior, viewport targets, demo-data-only guarantee, and explicit statement that the preview is not the Flutter application.

- [ ] **Step 8: Final file inventory**

Run:

```powershell
Get-ChildItem docs\workbench_preview -Recurse -File | Select-Object FullName,Length
```

Expected: every file in the File Map exists and is non-empty; no temporary screenshots, debug logs, downloaded fonts, or generated build directories remain inside `docs/workbench_preview`.

---

## Completion Gate

Do not modify Flutter application code as part of this plan. Completion means the user can open the local Web preview, operate the complete navigation, inspect the four representative screens, test weather return and glass fallback behavior, and explicitly approve or request revisions. Flutter and business-logic implementation require a separate plan after that approval.
