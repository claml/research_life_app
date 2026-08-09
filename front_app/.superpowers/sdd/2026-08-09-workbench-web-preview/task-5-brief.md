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

