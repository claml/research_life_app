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

