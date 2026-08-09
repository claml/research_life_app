# Task 5 Report — Materials, Life, and Settings Views

## Status

`DONE_WITH_CONCERNS`

Materials 的文件/文档查看/PDF 工具三个标签页、六行资料列表、文件夹树、不透明详情检查器、资料选择交互，以及 Life 和 Settings 的简洁预览均已实现。聚焦测试与完整 Node 预览测试通过。Browser 视觉验收未完成，因此不声明 1280×800 最终视觉接受。

## Files changed

| File | Final bytes | Change |
|---|---:|---|
| `docs/workbench_preview/scripts/demo-data.js` | 7,284 | 增加虚构中文文件夹树、六份资料元数据与详情，以及 Campus、Companion、Personalization 的简短预览数据 |
| `docs/workbench_preview/scripts/render.js` | 25,171 | 增加 Materials 三栏工作台、两个资料工具视图、Life 三标签页和 Settings 外观/辅助功能视图 |
| `docs/workbench_preview/scripts/app.js` | 2,772 | 将资料行的 `data-material` 映射到既有 `SELECT_MATERIAL` reducer action |
| `docs/workbench_preview/styles/views.css` | 29,615 | 增加不透明资料三栏/表格/检查器、工具视图、Life、Settings 和紧凑宽度续接样式 |
| `docs/workbench_preview/tests/state.test.mjs` | 9,533 | 增加资料有效/空选择回归、动作映射、三栏输出、标签持久化、Life 和 Settings 测试 |

没有修改 `scripts/state.js`：Task 2 已经实现 `SELECT_MATERIAL`，本任务只增加回归覆盖。没有修改 Flutter 文件、安装依赖、初始化 Git，或重做 Task 3/4 已审阅的 shell、Today、Research、Weather 视图。

## TDD evidence

### Cross-task selection fact

按 brief 首先增加了以下 reducer 回归：

- `SELECT_MATERIAL` 使用 `paper-hci` 时令 `selectedMaterialId === 'paper-hci'`；
- 返回新 state，不修改原 state；
- 在已选 state 上传入空 ID 时返回同一个 state 对象。

该测试第一次运行即通过。原因是 Task 2 被要求提前实现所有 action contracts，生产 reducer 已经包含字符串非空校验。本任务没有删除或破坏正确代码以制造人工 RED。这也完成了 Task 2 延后的 valid/empty selection 覆盖。

### RED — missing Task 5 behavior

Command:

```powershell
node --test tests\state.test.mjs
```

首次聚焦运行结果：

```text
tests 13
pass 9
fail 4
```

四个预期失败组为：

1. 资料行尚未把 `select-material` 映射到 `SELECT_MATERIAL`；同一测试中随后保护 folder/table/inspector 和选中检查器输出的断言尚未执行到。
2. Materials 的 `document-viewer` 与 `pdf-tools` 仍渲染 quiet placeholder，没有各自结构化视图或持久化选中资料。
3. Life 的 Campus、Companion、Personalization 三个标签仍渲染 quiet placeholder。
4. Settings 仍渲染 quiet placeholder，没有外观、辅助功能或透明度状态控件。

这些测试均在生产实现之前写入并在既有代码上失败；失败原因是缺少本任务行为，而非语法错误或测试夹具错误。

### GREEN — focused behavior

Command:

```powershell
node --test tests\state.test.mjs
```

Result:

```text
tests 13
pass 13
fail 0
```

测试保护以下用户可见契约：

- 六行资料呈现在 folder/tree、opaque table/list、inspector 三栏结构中；
- 初始 `paper-gnss` 行有选中态，选择 `paper-hci` 后选中态和检查器标题同时更新；
- 资料行点击映射到真实 reducer action；
- `document-viewer` 和 `pdf-tools` 输出不同结构，且切换标签后仍展示 `paper-hci`；
- 资料动作只使用 `导出` 或 `另存为`，输出不出现 `下载`、云端、同步或账户声明；
- Life 三标签页分别输出校园日程、专注桌宠和界面主题，而不是通用占位；
- Settings 有短版外观/辅助功能列表，降低透明度控件准确反映 false/true 状态。

## Fresh full Node preview suite

Command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs docs\workbench_preview\tests\shell.test.mjs
```

Fresh result:

```text
tests 18
pass 18
fail 0
cancelled 0
skipped 0
todo 0
duration_ms 142.1
```

该完整运行同时覆盖 Task 1–4 的 shell、天气、侧栏、Today 和 Research 回归。

## Materials implementation

- 文件夹 rail 使用原生导航/树语义，提供全部资料、导航研究、阅读材料、观察记录、实验记录、图表与草图六个虚构分类节点。
- 中央区是 `role="table"` 的不透明滚动表格，表头固定，六行资料使用名称、类型、修改时间、大小列；没有卡片化资料行或玻璃滚动层。
- 右侧是同一 pearl surface 上的不透明 inspector，展示选中资料的类型、大小、分类位置、修改时间、短摘要、标签和上下文操作。
- 六份文件及所有标题、元数据和摘要均为虚构中文演示数据；未包含本地路径、用户名、邮箱、云 ID、真实论文题目或后端连接声明。
- 文件选择通过事件委托进入既有 reducer，重新渲染后 inspector 与 `aria-selected` 同步；选择 state 在 Materials 三标签间不被重置。
- 文档查看与 PDF 工具沿用同一 shell 和选中资料上下文，只提供预览/整理型静态演示，不宣称真实文件处理或连接能力。

## Life and Settings implementation

- Life 保留既有 `校园 / 桌宠 / 个性化` 标签顺序。Campus 是三行日程，Companion 是克制的专注场景，Personalization 是三个主题色预览；每个视图只有短标题、短状态和少量操作。
- Settings 不增加账户、同步或云设置，仅展示外观与辅助功能两组紧凑行。
- `降低透明度` 复用既有 `SET_REDUCED_TRANSPARENCY` action，按钮 `aria-pressed` 与 state 同步；没有新增重复状态源。
- 新视图沿用既有 typography、accent、hairline、surface 与 motion token；没有引入营销 hero、指标卡、badge 或长解释块。

## Accepted-concept comparison

实现前已阅读 `design-inventory.md`，并用 `view_image` 以 original detail 检查 `concepts/materials.png` 和共享 shell 的 `concepts/today.png`。

- 保留 Task 3 的深学术绿侧栏、cool cloudy surround、单一 pearl-white workspace panel、标题/标签页 header 和现有外边距。
- Materials 采用概念中的窄文件夹 rail、中央密集表格、右侧详情检查器比例，不把列表变成卡片。
- 选中行使用浅青绿色整行对比和细 accent，不使用 detached pill。
- inspector 密度保持克制，元数据用定义列表与 hairline 分隔；操作保持上下文式，不在 header 增加第二主操作。
- 980px 附近缩窄三栏；更窄时隐藏 inspector、保留 folder/file workflow，并压缩表格列，避免页面级横向溢出。

以上是代码与资产比对结论，不是完成的 Browser 像素级验收。

## Self-review

- 所有新演示字符串继续通过既有 `escapeHtml`；颜色值只进入受控 demo theme data 的 inline custom property。
- 新交互均使用原生 `button type="button"`，资料表与文件夹提供 table/tree 语义，选中行有 `aria-selected`，Settings toggle 有 `aria-pressed` 和明确 label。
- 渲染函数按 Materials/Life/Settings 边界拆分；没有 render-time side effect、异步请求、依赖注入或后端模拟。
- `selectedMaterial` 对未知/缺失 ID 安全回退到第一份演示资料；空资料集呈现简短选择提示，不抛错。
- Materials 的滚动 surface 明确使用 `var(--surface-main)`，未使用 `glass-surface` 或 backdrop filter。
- 响应式 CSS 在 1040、880、780px 续接现有断点；运动变化包含在 reduced-motion fallback 中。
- 生产 `demo-data.js` 与 `render.js` 的 policy scan 未发现 `下载`、云端、同步、账户/账号、本地盘符、Users 路径或邮箱模式。
- 新函数与分支由 real renderer/reducer/action mapping 测试覆盖，无 mocks。

## Deviations and concerns

1. `scripts/app.js` 不在 Task 5 brief 的原始文件表中，但资料行若不增加 5 行 action mapping 就会产生看似可点击、实际不更新检查器的 UI。该最小改动只接入 Task 2 已存在的 `SELECT_MATERIAL` contract。
2. Browser QA 未完成。一次有界的 in-app Browser 尝试在连接/截图阶段长时间无结果并被中断；按 controller 指示没有重试，也没有改用其他浏览器。因此 1280×800 的实时 row alignment、三栏比例、selection contrast、inspector density、滚动表现、交互点击和 console health 仍需 controller 验收。
3. 没有保存 Task 5 浏览器截图；任何视觉陈述均来自 accepted assets 原图检查、HTML/CSS 审查和自动化结构测试，不是浏览器截图证据。

## Fix Round 1 — Contextual PDF operations

### Scope

仅处理 `task-5-review.md` 的 Important finding：非 PDF 资料进入 `PDF 工具` 后不再显示 PDF 页面操作。按 controller 指示，没有处理 deferred Minor 的 `button role="row"` 语义问题，也没有尝试 Browser。

### Root cause

`renderMaterialsTool` 原先只根据 active tab 计算 `isViewer`。进入 `pdf-tools` 时，它无条件渲染 `合并页面`、`提取页面` 和 `另存为`，完全没有读取持久化选中资料的 `material.type`。因此选择 DOCX、XLSX、MD 或 PNG 后切换标签会得到错误的 PDF 操作上下文。

### RED

先增加真实 renderer 回归：选择非 PDF 的 `protocol-route`（DOCX），切换到 `pdf-tools`，验证当前资料标题仍然持久化，同时 PDF 页面操作不存在，并输出 `data-state="requires-pdf"` 与 `请选择 PDF 资料`。

Command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Result:

```text
tests 14
pass 13
fail 1
```

失败是预期的产品行为失败：DOCX 状态仍包含 `合并页面`、`提取页面` 和 `另存为`。测试没有 mock，也没有因语法或夹具错误失败。

### Fix

- `scripts/render.js` 增加严格的 `material?.type === 'PDF'` 分支。
- PDF 选择继续显示原有合并、提取和另存操作，保持既有 PDF happy path 测试。
- 非 PDF 选择只显示简短 `当前资料` rail，提示 `请选择 PDF 资料` 和当前文件类型，不渲染任何 PDF 页面操作。
- `styles/views.css` 只增加该 unsupported rail 的克制排版与 hairline；没有修改 Materials 布局或其他视图。
- `tests/state.test.mjs` 增加一条 focused non-PDF regression。

### GREEN — focused

Command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Result:

```text
tests 14
pass 14
fail 0
cancelled 0
skipped 0
todo 0
```

### GREEN — full Node preview suite

Command:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs docs\workbench_preview\tests\shell.test.mjs
```

Fresh result:

```text
tests 19
pass 19
fail 0
cancelled 0
skipped 0
todo 0
duration_ms 135.5398
```

### Remaining concern

Review 中的 Minor `button role="row"` 语义问题按本轮明确范围保留，未修改。Browser 按指示未运行。
