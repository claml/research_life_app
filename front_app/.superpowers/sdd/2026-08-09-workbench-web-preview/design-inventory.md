# Workbench Preview Design Inventory

## Accepted references

- `docs/workbench_preview/assets/concepts/weather.png` — 1440×900, full-screen standby state.
- `docs/workbench_preview/assets/concepts/today.png` — 1440×900, shared workspace shell source.
- `docs/workbench_preview/assets/concepts/research.png` — 1440×900, same shell and open-row research layout.
- `docs/workbench_preview/assets/concepts/materials.png` — 1440×900, same shell and three-pane file layout.

## Visible copy and navigation

- Brand: `研LIFE`; search: `搜索`.
- Primary navigation: `天气`, `今天`, `科研`, `资料`, `生活`; bottom item: `设置`.
- Today tabs: `今天`, `日历`, `待办`; primary action: `快速记录`.
- Research tabs: `概览`, `文献`, `笔记`, `周分析`, `人员`, `统计`; sole AI action: `AI 助手`.
- Materials tabs: `文件`, `文档查看`, `PDF 工具`; ambiguous concept action `下载` becomes `导出` or `另存为` in code.
- Weather: `返回`, large time/date/weather, and at most three today items. No idle or automatic-entry copy.
- Life and Settings may use only the concise tab/action labels required by the approved specification; no long explanatory blocks.

## Composition and container model

- Workspace canvas is a cool, cloudy blue surround, never cream or warm beige.
- Shared desktop shell: fixed academic-green sidebar and one large opaque pearl-white content panel with the same outer offsets and proportions on Today, Research, and Materials.
- Sidebar selection uses a pale translucent row plus a slim green/teal left accent; it is not a detached white pill.
- Header includes one title, one horizontal tab row, and at most one contextual primary action.
- Today uses an open two-column split: chronological timeline left, actionable rows right.
- Research uses open sections separated by hairlines; it is not a card grid.
- Materials uses folder rail, row-based file table, and opaque inspector; scrolling content never uses glass.
- Weather is a full-bleed atmospheric background with one tall left frosted information surface and small floating controls. The left-edge reveal affordance must be shorter and quieter than the concept draft.

## Design tokens

- Canvas/sky family: cool blue gray sampled visually around `#b8ccca`, `#8eaca9`, and deeper teal sky values.
- Sidebar: deep academic green around `#0f6657` to `#0b5a4d`; selected row around translucent `#9fc4ba`.
- Accent: academic teal/green around `#087d68`; active rule 2px.
- Main surface: cool pearl white around `#f8faf9`; secondary surface `#f1f5f4`.
- Text: near-black cool navy `#13202b`; muted blue gray `#71808e`; hairline `#dbe3e4`.
- Semantic colors are restrained: amber weather sun, red PDF/destructive, green success.
- Spacing follows an 8px rhythm. Main shell gaps are approximately 24px.
- Radii: controls 10px, small panels 14px, main shell 20px.
- One soft shell shadow and one lighter floating-control shadow; no stacked elevations.
- Motion: 140ms control feedback, 200ms chrome, 220ms panel transition; remove motion under reduced-motion.
- Glass: 14–20px blur with cool translucent white/green tint, one hairline border; opaque token fallback when reduced transparency is enabled.

## Typography and icons

- Font stack: `Inter`, `PingFang SC`, `Microsoft YaHei`, system sans-serif.
- Page titles approximately 28–32px/700; section titles 15–17px/650; body and controls 13–15px; captions 11–12px.
- Controls must define explicit size, weight, and line-height; no browser-default typography.
- Icons use one rounded-line SVG family, 24×24 viewBox, 1.8px stroke, round caps/joins, and `currentColor`.
- Selected icons and labels remain white/light; content icons use cool navy or academic green.

## Component families

- App shell, expanded/collapsed sidebar, primary nav row, workspace header, horizontal tab row.
- Primary/quiet icon buttons, glass search, quick action, floating status, weather return/reveal controls.
- Timeline entries, todo rows, research disclosure rows, folder-tree rows, file-table rows, inspector metadata/actions.
- Visible keyboard focus, hover, selected, disabled, and reduced-transparency variants.

## Core interaction inventory

- Primary and secondary navigation preserve independent tab state.
- Weather is entered only by explicit action and Escape/Return restores the previous workspace/tab.
- Sidebar collapse is manual and persists while moving between workspaces.
- Research sections expand/collapse locally; AI remains a single restrained action.
- Material selection updates the inspector and persists across Materials tabs.
- Reduced-transparency control immediately converts glass to opaque surfaces.

## Responsive continuation

- Desktop acceptance: 1280×800, preserving shared shell anatomy.
- Compact acceptance: approximately 980px; sidebar collapses, content remains usable, no page-level horizontal overflow.
- Materials may narrow or hide the inspector at compact width, but the folder/file workflow remains legible.

## Fidelity constraints

- No marketing hero, fake metrics, badges, filler copy, repeated cards, cloud/sync/account claims, real names, local paths, or backend-connected behavior.
- The accepted concepts contain no hero overlay treatment. The cloudy surround/background remains visually separate from the opaque workspace surface.
- All app UI labels remain code-native; raster concepts are references only and are never shipped as the interface.
