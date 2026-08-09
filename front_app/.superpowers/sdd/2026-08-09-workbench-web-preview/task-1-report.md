# Task 1 Implementation / Self-Review Report

- Date: 2026-08-09
- Status: **DONE**
- Scope: visual concepts only; no Web or Flutter code was written.
- Generation mode: **default built-in ImageGen mode** (`image_gen.imagegen`). No CLI/API-key fallback was used.

## Final generated paths

1. `D:\Vibe Coding\研究生活\research-life-app\front_app\docs\workbench_preview\assets\concepts\weather.png`
2. `D:\Vibe Coding\研究生活\research-life-app\front_app\docs\workbench_preview\assets\concepts\today.png`
3. `D:\Vibe Coding\研究生活\research-life-app\front_app\docs\workbench_preview\assets\concepts\research.png`
4. `D:\Vibe Coding\研究生活\research-life-app\front_app\docs\workbench_preview\assets\concepts\materials.png`

All four built-in outputs were generated at 1586×992, then resampled with ImageMagick/Lanczos to the required exact 1440×900 PNG dimensions. The native and requested aspect ratios differ by less than 0.1%, so this introduced no visible crop or layout loss.

## Prompt record

### Weather

Final generation prompt (verbatim approved brief):

```text
Create a complete 1440×900 desktop product UI concept for 研LIFE, a personal Flutter workbench balancing research and daily life equally. This screen is a manually opened weather standby page. Use a restrained academic-green brand, true cool pearl-white text, a calm atmospheric sky background, and selective iOS-like frosted glass only for the clock/weather information surface and small floating controls. Show large time, Chinese date, concise weather, and no more than three short today items. The navigation chrome fades away in standby mode; include a subtle left-edge reveal affordance and an unobtrusive return control. No marketing hero, no badges, no filler metrics, no card grid, no auto-idle language. Text must be Chinese and concise. Controls and text are intended to be code-native. Professional Windows desktop app, 7/10 creativity, readable and implementable.
```

Built-in intent: generate, no input image.

### Today

Base generation prompt (verbatim approved brief):

```text
Create a complete 1440×900 desktop product UI concept for 研LIFE using the same visual system as the approved weather concept. Show the expanded 216px sidebar with brand/search, fixed weather entry, Today selected, Research, Materials, Life, and bottom Settings. Use a lighter selected row with a slim left accent, not a large white pill. Main content: concise page title, tabs Today / Calendar / Todos, one primary quick-capture action, left chronological timeline, right actionable todo list. Research and life should feel equally important across the product. Use selective frosted glass only in brand/search or a floating quick action; lists remain opaque and crisp. Avoid excessive cards, explanatory copy, badges, and decorative dashboard metrics.
```

Final refinement prompt:

```text
Edit the displayed Today-workspace UI concept. Change only the sidebar material: make the full sidebar base an opaque cool desaturated academic-green surface with no sky or cloud visibility through it, no background blur, no translucency, no reflection, and no glass effect. The search control itself may retain its subtle frosted-glass treatment. Preserve the 216px expanded sidebar geometry, 研LIFE brand, weather entry, Today selected row with its lighter opaque background and slim left accent, Research / Materials / Life / Settings navigation, all icons and text, the cool pearl-white main content, tabs, quick-capture action, timeline, todo list, spacing, typography, and every other visible element exactly unchanged.
```

Built-in intent: generate with the Weather concept as the single style reference, then edit the displayed result.

### Research

Base generation prompt (verbatim approved brief):

```text
Create a complete 1440×900 research-workspace UI concept for 研LIFE in the exact same shell, palette, typography, icon style, density, and glass system as the approved today concept. Research is selected. Secondary tabs: Overview, Literature, Notes, Weekly Analysis, People, Statistics. The Overview shows recent reading, notes needing organization, this-week plans, and one restrained AI assistant action. Use open sections and rows rather than a repetitive card grid. Keep descriptions to one short line maximum. No fake business metrics, no marketing copy, no hero eyebrow, no excessive glass.
```

Final refinement prompts, in order:

```text
Edit the displayed research-workspace UI concept. Change only the research action treatment: replace the top-right “+ 快速记录” control with one restrained secondary button labeled “AI 助手”, and remove the separate bottom “AI 助手” row together with its “开始生成” button so the open-list content ends cleanly after “本周计划”. Preserve the entire shell, selected Research navigation, all six secondary tabs, recent reading rows, notes-needing-organization rows, this-week plan rows, cool pearl-white surfaces, academic-green palette, typography, spacing, density, and every other visible element exactly unchanged. Do not add any new feature, metric, card, explanatory copy, or glass surface.
```

```text
Edit the displayed Research-workspace UI concept. Change only the sidebar material: make the full sidebar base an opaque cool desaturated academic-green surface with no sky or cloud visibility through it, no background blur, no translucency, no reflection, and no glass effect. The search control itself may retain its subtle frosted-glass treatment. Preserve the 216px expanded sidebar geometry, 研LIFE brand, weather entry, Research selected row with its lighter opaque background and slim left accent, Today / Materials / Life / Settings navigation, all icons and text, the cool pearl-white main content, all six secondary tabs, the single top-right AI assistant action, all open list rows, spacing, typography, and every other visible element exactly unchanged.
```

The preceding sidebar edit altered the outer shell and was rejected. The final corrective prompt was:

```text
Image 1 is the Research-workspace edit target. Image 2 is the approved Today-workspace style reference. Edit Image 1 only. Match the Research sidebar shell to Image 2 exactly: the same opaque cool academic-green base, same rounded sidebar card shape, same inset outer margins, same subtle shadow, same sky visible only outside the opaque sidebar, same search-field glass treatment, and the same lighter selected-row treatment with slim left accent. Keep Research selected. Preserve every Research-specific element exactly: title, all six secondary tabs, the single AI assistant button, recent reading, notes needing organization, this-week plans, all rows, timestamps, icons, typography, main-panel shape, cool pearl-white content surface, and outer sky. Do not import Today content and do not change the main layout.
```

Built-in intent: generate with Today as the single style reference, followed by displayed-image edits; the rejected intermediate was not saved as a final asset.

### Materials

Base generation prompt (verbatim approved brief):

```text
Create a complete 1440×900 materials-workbench UI concept for 研LIFE in the exact same approved design system. Materials is selected. Secondary tabs: Files, Document View, PDF Tools. Use a desktop three-pane structure: narrow folder tree, central file table/list, right detail inspector with concise metadata and contextual actions. Keep scrolling content opaque and highly readable. Glass is allowed only for shell search and a small floating status/control surface. Do not convert the file table into cards. No fake cloud claims or personal data.
```

Final refinement prompts, in order:

```text
Edit the most recent materials-workbench UI concept. Change only the small floating status surface at the bottom right: replace the cloud icon and the text “同步已完成 / 今天 09:31” with a neutral local folder icon and the concise Chinese text “已选择 1 项 / 本地文件”. Preserve the entire three-pane layout, shell, selected Materials navigation, Files / Document View / PDF Tools tabs, file table, detail inspector, palette, typography, spacing, density, and every other visible element exactly unchanged. Do not add any cloud, sync, upload, account, or personal-data language.
```

```text
Edit the displayed materials-workbench UI concept. Remove only the top-right “+ 快速记录” button and leave that header area clean and empty. Preserve the entire shell, selected Materials navigation, Files / Document View / PDF Tools tabs, three-pane folder-tree / file-table / detail-inspector structure, local selection status surface, all file rows, metadata, contextual actions, cool pearl-white surfaces, academic-green palette, typography, spacing, density, and every other visible element exactly unchanged. Do not add any replacement control, new feature, cloud, sync, upload, account, or personal-data language.
```

```text
Image 1 is the approved opaque-sidebar shell style reference. Image 2 is the Materials-workbench edit target. Edit Image 2 only. Match the Materials sidebar shell to Image 1 exactly: the same opaque cool academic-green base, same rounded sidebar card shape, same inset outer margins, same subtle shadow, same sky visible only outside the opaque sidebar, same search-field glass treatment, and the same lighter selected-row treatment with slim left accent. Keep Materials selected. Preserve every Materials-specific element exactly: title, Files / Document View / PDF Tools tabs, three-pane folder tree / file table / detail inspector, all rows and metadata, contextual actions, the local “已选择 1 项 / 本地文件” status surface, typography, main-panel shape, cool pearl-white content surface, and outer sky. Do not import Research content, do not add a top-right action, and do not add cloud, sync, upload, account, or personal-data language.
```

The preceding shell transfer omitted the fixed weather entry. The final corrective prompt was:

```text
Image 1 is the Materials-workbench edit target. Image 2 is the approved shell reference. Edit Image 1 only. Add the same fixed weather entry shown in Image 2 between the search control and the primary navigation: identical small partly-cloudy icon, “24°C 多云”, and the concise secondary line “体感 24°C   北风 2 级”. Shift the Materials navigation rows downward as needed while keeping Settings fixed at the bottom. Preserve the opaque rounded academic-green sidebar, Materials selected row and slim left accent, title, Files / Document View / PDF Tools tabs, complete three-pane folder-tree / file-table / detail-inspector content, local selection status, outer sky, main-panel geometry, typography, spacing, and every other visible element. Do not add cloud-service, sync, upload, account, or personal-data language.
```

Built-in intent: generate with Today and Research as style references, followed by displayed-image edits. Rejected intermediates were not saved as final assets.

## Visual inspection findings

Every final workspace PNG was opened with `view_image` at original detail after its last edit.

- **Weather — PASS:** cool atmospheric sky; true pearl-white text; large time, Chinese date, concise weather; exactly three short today items; navigation chrome absent; left-edge reveal affordance and return control present; glass restricted to the clock/weather surface and small controls; no cards, badges, marketing hero, or idle/automatic language.
- **Today — PASS:** expanded academic-green sidebar is opaque; search alone retains light glass; fixed weather entry and all required primary navigation items are present; Today selection uses a lighter row and slim left accent; tabs, one quick-capture action, chronological timeline, and actionable todo list are present; lists are crisp, open, and non-glass.
- **Research — PASS:** exact same final shell/material system as Today; Research selected; all six secondary tabs are readable and present; recent reading, notes needing organization, and this-week plans use open rows; exactly one restrained AI assistant action remains at top right; no card grid, metrics, marketing copy, or excessive glass.
- **Materials — PASS:** same opaque sidebar shell with fixed weather entry; Materials selected; all three secondary tabs are present; folder tree, file table, and detail inspector form a clear desktop three-pane structure; table remains rows rather than cards; scrolling content is opaque; local floating status reads “已选择 1 项 / 本地文件”; no cloud/sync/account claim or personal data; inherited quick-capture control was removed.
- **Cross-screen consistency — PASS:** cool light content surfaces, academic-green brand, typography, icon weight, panel radii, selected-row treatment, spacing, and outer sky are coherent across the three workspaces; glass is limited to allowed surfaces.

## File-size checkpoint

Command run from `D:\Vibe Coding\研究生活\research-life-app\front_app`:

```powershell
Get-ChildItem docs\workbench_preview\assets\concepts -Filter *.png | Select-Object Name,Length
```

Output:

```text
Name           Length
----           ------
materials.png 1186074
research.png  1037997
today.png      973274
weather.png   1258913
```

Independent ImageMagick identity assertions also passed for the exact filename set:

```text
Name          Format Dimensions  Length Status
----          ------ ----------  ------ ------
materials.png PNG    1440x900   1186074 PASS
research.png  PNG    1440x900   1037997 PASS
today.png     PNG    1440x900    973274 PASS
weather.png   PNG    1440x900   1258913 PASS
```

## Concerns

- No blocking concerns.
- These are design-source screenshots; as requested, all controls, icons, and text should be recreated code-native in the later Web preview rather than rasterized from the screenshots.
- Research and Materials retain the English secondary-tab labels explicitly named in their approved prompts, while Today uses concise Chinese labels. User approval can lock the final localization choice before Task 2 without changing this Task 1 artifact contract.

## Fix Round 1 — Normalize Workspace Shell Geometry

- Date: 2026-08-09
- Status: **DONE**
- Review finding addressed: the Important finding that `today.png`, `research.png`, and `materials.png` used different sidebar widths, panel gaps, main-panel start positions, top/bottom offsets, and outer proportions.
- Scope control: this round changed only shared workspace shell geometry. The two Minor findings about the weather reveal affordance and the Materials `下载` label were intentionally left unchanged.
- Geometry source of truth: `D:\Vibe Coding\研究生活\research-life-app\front_app\docs\workbench_preview\assets\concepts\today.png`.
- Corrected final files:
  - `D:\Vibe Coding\研究生活\research-life-app\front_app\docs\workbench_preview\assets\concepts\research.png`
  - `D:\Vibe Coding\研究生活\research-life-app\front_app\docs\workbench_preview\assets\concepts\materials.png`

### Fix implementation and ImageGen mode

The correction used the default built-in ImageGen edit mode; no CLI/API-key fallback was used. For each corrected screen, Today was the edit target and exact geometry reference, while the prior Research or Materials screenshot was a content-only reference. The built-in outputs preserved each page's selected workspace, tabs, copy, rows, actions, and glass scope. Because built-in output still introduced a few pixels of geometry drift after the required 1440×900 resampling, the page interiors were calibrated with ImageMagick and composited inside Today's unchanged outer panel boundary pixels. This makes the shared shell anchors exact while retaining the ImageGen-produced page content.

Research edit prompt:

```text
Use case: ui-mockup precise-object edit.
Asset type: 1440×900 desktop product UI concept.
Input images: Image 1 is the exact Today shell geometry edit target and source of truth; Image 2 is the Research content reference.
Primary request: Edit Image 1 only. Keep the entire outer shell geometry pixel-locked to Image 1, then replace only the workspace-specific navigation selection and main-panel contents with the Research content from Image 2.
Exact geometry invariants from Image 1: canvas 1440×900; sidebar outer edges approximately x=21–244 and y=24–875; main panel begins at x=268 and uses the same y=24–875 top/bottom offsets; preserve the exact sidebar width, 24px inter-panel gap, main-panel start, right edge, corner radii, outer margins, panel proportions, sky surround, and shadow footprint of Image 1.
Research content invariants from Image 2: Research selected; Today, Materials, Life, Settings and fixed weather entry unchanged; title “研究”; all tabs “Overview”, “Literature”, “Notes”, “Weekly Analysis”, “People”, “Statistics”; one top-right “AI 助手” action; all recent-reading, notes-needing-organization, and this-week-plan rows, timestamps, icons, and concise copy preserved.
Constraints: change content inside the fixed shell only; preserve the academic-green opaque sidebar, lighter selected row with slim left accent, search-only glass, cool pearl-white main surface, typography, density, and open-row layout.
Avoid: any shell movement or resizing, sidebar-width drift, panel-offset drift, new content, removed rows, altered actions, card grid, extra glass, warm cream, or changes from the two unrelated Minor review findings.
```

Materials edit prompt:

```text
Use case: ui-mockup precise-object edit.
Asset type: 1440×900 desktop product UI concept.
Input images: Image 1 is the exact Today shell geometry edit target and source of truth; Image 2 is the Materials content reference.
Primary request: Edit Image 1 only. Keep the entire outer shell geometry pixel-locked to Image 1, then replace only the workspace-specific navigation selection and main-panel contents with the Materials content from Image 2.
Exact geometry invariants from Image 1: canvas 1440×900; sidebar outer edges approximately x=21–244 and y=24–875; main panel begins at x=268 and uses the same y=24–875 top/bottom offsets; preserve the exact sidebar width, 24px inter-panel gap, main-panel start, right edge, corner radii, outer margins, panel proportions, sky surround, and shadow footprint of Image 1.
Materials content invariants from Image 2: Materials selected; Today, Research, Life, Settings and fixed weather entry unchanged; title “资料”; tabs “Files”, “Document View”, “PDF Tools”; complete three-pane folder tree, central file table, and right detail inspector; all folders, rows, filenames, metadata, contextual actions including “下载”, and the local “已选择 1 项 / 本地文件” floating status preserved.
Constraints: change content inside the fixed shell only; preserve the academic-green opaque sidebar, lighter selected row with slim left accent, search-only glass, cool pearl-white main surface, typography, density, row-based file table, and inspector structure.
Avoid: any shell movement or resizing, sidebar-width drift, panel-offset drift, new content, removed rows, altered labels or actions, card conversion, extra glass, warm cream, cloud/sync claims, or changes from the two unrelated Minor review findings.
```

### Final visual inspection

The following final workspace concepts were reopened with `view_image` at original detail after the corrected files were saved:

- `today.png` — inspected as the unchanged geometry source; sidebar, gap, main panel, top/bottom offsets, and panel proportions remain the approved reference.
- `research.png` — inspected after correction; exact Today shell is retained; Research remains selected; all six tabs, one AI action, and all three open-row sections remain present and readable.
- `materials.png` — inspected after correction; exact Today shell is retained; Materials remains selected; all three tabs, complete folder tree/file table/detail inspector, `下载`, and local selection status remain present and readable.

No visual changes from either Minor review finding were introduced.

### Exact shell-anchor assertion

Exact command run from `D:\Vibe Coding\研究生活\research-life-app\front_app`:

```powershell
Add-Type -AssemblyName System.Drawing; $dir='D:\Vibe Coding\研究生活\research-life-app\front_app\docs\workbench_preview\assets\concepts'; $source=[System.Drawing.Bitmap]::FromFile((Join-Path $dir 'today.png')); $anchors=@(@('column',21),@('column',244),@('column',245),@('column',267),@('column',268),@('column',1415),@('row',24),@('row',875)); $rows=foreach($name in @('research.png','materials.png')){$target=[System.Drawing.Bitmap]::FromFile((Join-Path $dir $name));$mismatches=0;foreach($anchor in $anchors){$kind=$anchor[0];$coord=[int]$anchor[1];if($kind-eq'column'){for($y=0;$y-lt 900;$y++){if($source.GetPixel($coord,$y).ToArgb()-ne$target.GetPixel($coord,$y).ToArgb()){$mismatches++}}}else{for($x=0;$x-lt 1440;$x++){if($source.GetPixel($x,$coord).ToArgb()-ne$target.GetPixel($x,$coord).ToArgb()){$mismatches++}}}};$target.Dispose();if($mismatches-ne0){throw "$name shell-anchor mismatch count: $mismatches"};[pscustomobject]@{Name=$name;SidebarLeftX=21;SidebarRightX=244;Gap='245-267';MainStartX=268;MainRightX=1415;TopY=24;BottomY=875;AnchorMismatches=$mismatches;Status='PASS'}};$source.Dispose();$rows|Format-Table -AutoSize
```

Output:

```text
Name          SidebarLeftX SidebarRightX Gap     MainStartX MainRightX TopY BottomY AnchorMismatches Status
----          ------------ ------------- ---     ---------- ---------- ---- ------- ---------------- ------
research.png            21           244 245-267        268       1415   24     875                0 PASS
materials.png           21           244 245-267        268       1415   24     875                0 PASS
```

### Exact file inventory and dimensions

Inventory command run:

```powershell
Get-ChildItem docs\workbench_preview\assets\concepts -Filter *.png | Select-Object Name,Length
```

Output:

```text
Name           Length
----           ------
materials.png 1239911
research.png  1076949
today.png      973274
weather.png   1258913
```

Dimensions command run:

```powershell
& 'D:\software\ImageMagick-7.1.2-Q16\magick.exe' identify -format "%f|%m|%wx%h|%b`n" docs\workbench_preview\assets\concepts\weather.png docs\workbench_preview\assets\concepts\today.png docs\workbench_preview\assets\concepts\research.png docs\workbench_preview\assets\concepts\materials.png
```

Output:

```text
weather.png|PNG|1440x900|1.25891MB
today.png|PNG|1440x900|973274B
research.png|PNG|1440x900|1.07695MB
materials.png|PNG|1440x900|1.23991MB
```

### Fix Round 1 concerns

- No blocking concerns for the Important geometry finding.
- The two Minor findings remain intentionally unchanged, per round scope.
