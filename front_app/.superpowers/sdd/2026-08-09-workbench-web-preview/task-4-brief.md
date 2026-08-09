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

