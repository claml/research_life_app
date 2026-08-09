# Task 4 Report — Today and Research Views

## Status

`DONE_WITH_CONCERNS`

Today 的三个标签页、Research 概览/展开交互与五个次级标签页已实现，聚焦测试和完整 Node 预览测试均通过。未在本执行单元中完成 Browser 视觉验收，因此不声明 1280×800 的最终视觉接受。

## Files changed

| File | Final bytes | Change |
|---|---:|---|
| `docs/workbench_preview/scripts/demo-data.js` | 4,238 | 增加 Today 时间线、待办、月条、日程，以及 Research 阅读、笔记、计划、周分析、协作和统计的虚构中文数据 |
| `docs/workbench_preview/scripts/render.js` | 15,273 | 按持久化标签状态渲染 Today 三视图、Research 四个开放分区、展开详情与五个结构化次级预览 |
| `docs/workbench_preview/scripts/app.js` | 2,659 | 将 Research disclosure 的 `data-panel` 映射到既有 `TOGGLE_RESEARCH_PANEL` reducer action |
| `docs/workbench_preview/styles/views.css` | 15,267 | 增加 Today calendar/todos 和 Research open-section/compact-list 布局、状态与响应式续接 |
| `docs/workbench_preview/styles/components.css` | 7,321 | 增加唯一的 Research AI action 和 disclosure 控件样式 |
| `docs/workbench_preview/tests/state.test.mjs` | 5,339 | 扩展 reducer toggle 覆盖，并增加 Today/Research 聚焦渲染与动作映射测试 |

未修改 `scripts/state.js`：Task 2 已经实现了不可变的 `TOGGLE_RESEARCH_PANEL` toggle。未修改 Task 3 shell、Flutter 文件，也未安装依赖或初始化 Git。

## TDD evidence

### Cross-task state fact

按 Task 4 brief 增加了以下回归行为：

- 对 `recent-reading` 首次 toggle 后 `expandedResearchPanel === 'recent-reading'`；
- 再次 toggle 后恢复为 `null`；
- 原 state 与两个后继 state 均为不同对象。

该测试首次运行即通过，因为 Task 2 被明确要求提前实现所有 action contracts，且生产 reducer 已包含此动作。本任务没有删除或损坏正确生产代码来制造人为 RED。

### RED — missing render/view behavior

Command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

首次聚焦运行结果：

```text
tests 7
pass 4
fail 3
```

预期失败分别为：

- Today 缺少按 active tab 切换的 overview/calendar/todos 输出；
- Research 仍是 quiet placeholder，缺少开放分区、唯一 AI action 和 expanded detail；
- 五个 Research 次级标签仍是相同 placeholder，缺少结构化预览。

在增加 disclosure 动作映射测试后再次运行：

```text
tests 8
pass 4
fail 4
```

新增预期失败为 `toggle-research-panel` 尚未映射到既有 reducer action。

### GREEN — focused behavior

Command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Result:

```text
tests 8
pass 8
fail 0
```

测试保护以下用户可见行为：

- Today 概览恰有三条时间线和四条待办；
- Calendar 有紧凑月份条、选中日期与当日安排；
- Todos 显示优先级和完成态；
- Research 概览有最近阅读、待整理笔记、本周计划和周分析四个开放分区；
- Research 概览仅输出一次 `AI 助手`；
- disclosure 使用真实 action 映射，展开后输出与 panel ID 对应的 detail；
- Literature、Notes、Weekly Analysis、People、Statistics 都有各自结构化 compact preview，且无 “coming soon” 类占位文字或额外 AI action。

其中一个 Today 计数断言在首次 GREEN 检查时把 `todo-row__label` 也计入 `todo-row`，造成测试自身的 8/4 误报；断言随后收紧到 `<li class="todo-row...">` 的真实行边界，未放宽任何产品要求。

### Full Node preview suite

Command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs docs\workbench_preview\tests\shell.test.mjs
```

Fresh result:

```text
tests 13
pass 13
fail 0
cancelled 0
skipped 0
todo 0
```

## Data and interaction inventory

- Today: exactly three fictional timeline entries, four todos with high/medium/low priorities and one completed state, a seven-day August strip, and three selected-day agenda rows.
- Research: exactly three recent readings, three notes, three weekly plans, and three weekly-analysis rows; People and Statistics reuse distinct fictional compact row sets.
- Copy is concise fictional Chinese and contains no real names, IDs, addresses, email, phone, account, cloud/sync, or local path claims.
- `SELECT_TAB` continues to preserve independent Today and Research tabs through Task 2 state.
- All Research rows stay visible as open content separated by hairlines. The existing local panel state expands one restrained explanatory line rather than turning the page into a card accordion.
- AI appears once and only in Research Overview. Today retains one existing primary `快速记录` action and no dashboard metric row.
- Secondary Research tabs are domain-shaped lists: reading queue, note organizer, weekly-analysis summary, collaboration schedule, and weekly statistics. None uses generic placeholder copy.

## Accepted-concept comparison

Before editing, `design-inventory.md`, `concepts/today.png`, and `concepts/research.png` were inspected; both concepts were opened with `view_image` at original detail.

### Today

- Preserved the reviewed Task 3 academic-green sidebar, cool surround, pearl workspace, title/tab header anatomy, and single top-right quick-capture control.
- Kept the approved open two-column overview: chronological rail on the left and actionable hairline rows on the right.
- Retained the concept’s restrained type scale and whitespace; no hero, metric strip, repeated card grid, or warm surface was introduced.
- Calendar and Todos reuse the same workspace surface and row language rather than introducing a separate dashboard visual system.

### Research

- Preserved the same shell anatomy and six-tab order from the accepted concept.
- Matched the concept’s open horizontal sections, small leading document/status icons, right-aligned metadata, hairline separation, and restrained teal AI outline action.
- Added the required fourth `周分析` section while keeping section density compact enough for the shared content surface.
- Expansion adds inline detail beneath the existing open list; it does not convert sections into elevated cards.

## Self-review

- Rendering dispatches from primitive tab IDs and keeps helper functions at module scope; no render-time effects, duplicated navigation arrays, new dependency, or expensive computation was introduced.
- All demo strings pass through the existing HTML escape helper.
- New buttons use native `button`, explicit `type="button"`, labels, and `aria-expanded`; selected date uses `aria-current="date"`.
- Existing shell and weather renderer paths remain intact; the prior shell regression suite is green.
- Layouts retain `minmax(0, …)`/min-width-safe grids and provide compact continuation below 1040px and stacked continuation below 780px.
- `rg` found no real-identifier or generic-coming-soon terms in the changed demo/render source.
- The workspace is not a Git repository; no repository was initialized, matching the instruction.

## Deviations and concerns

1. `scripts/app.js` was not listed in the Task 4 file table but required a 5-line production change so the rendered disclosure can actually dispatch the already-existing `TOGGLE_RESEARCH_PANEL` action. Leaving it unchanged would produce visually clickable but nonfunctional controls. This is the only implementation-scope deviation.
2. Browser was intentionally not invoked in this subtask because the brief permits handing visual QA to the controller when it cannot be completed quickly, and Task 3’s previous Browser attempt was long-running/interrupted. Consequently 1280×800 comparison, compact-width overflow, live tab/disclosure clicks, and console inspection remain for controller QA.
3. Because no baseline screenshot was captured after Task 4, the concept comparison above is code/asset inspection, not a claim of pixel-level Browser acceptance.
