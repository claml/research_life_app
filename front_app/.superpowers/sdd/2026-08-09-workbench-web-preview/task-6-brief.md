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
