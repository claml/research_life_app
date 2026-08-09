# 研LIFE 前端风格设计规范（Design System）

| 字段 | 内容 |
| --- | --- |
| 文档版本 | V1.0 |
| 状态 | 草案 · 待评审 |
| 适用端 | Flutter Windows 桌面端（兼顾后续 Android） |
| 关联文档 | `PRD.md`、`settings_page_guidelines.md`、`style_preview.html`（可视化预览） |
| 代码落点 | `lib/core/theme/app_tokens.dart`、`lib/core/theme/app_theme.dart`、`lib/shared/widgets/` |

---

## 1. 设计定位

### 1.1 产品气质

研LIFE 是「科研 + 生活」一体化桌面平台（PRD 定位为 Research OS 雏形）。界面气质由两组关键词定义：

```text
学术面：  沉稳 · 清晰 · 可信赖      —— 阅读、分析、文献、日程
生活面：  温度 · 陪伴 · 松弛感      —— 天气、桌宠、首页、校园地图
```

两组气质不是两套皮肤，而是**同一套令牌下的语境切换**：功能页克制，生活页允许氛围表达（渐变、动效、暖色点缀）。

### 1.2 设计原则

1. **内容优先**：装饰服务于信息层级。面板用留白和细分隔线分区，不靠重色块。
2. **纸感层次**：浅色多层背景（canvas → panel → inset）模拟纸张叠放，层次靠明度差而非强投影。
3. **深色导航锚点**：侧边栏是全App唯一大面积深色区域，承担「导航锚点」角色；内容区保持浅色（暗色主题除外）。
4. **克制的圆角与阴影**：圆角偏大（12–24）营造亲和感，阴影轻而少，仅壳层面板与浮层使用。
5. **桌面优先**：为键鼠设计 —— hover 态完备、点击目标 ≥ 32px、信息密度高于移动端；后续 Android 适配通过降低密度实现，而非重做。

---

## 2. 色彩系统

### 2.1 主题族（现状保留 6 套）

| 主题 | 定位 | 主强调色 | 场景 |
| --- | --- | --- | --- |
| green 学术绿 | **默认主题** | `#2F6B4B` | 沉静、护眼，契合科研长时使用 |
| pink 樱粉 | 个性化 | `#B23C72` | 生活化偏好 |
| blue 雾蓝 | 个性化 | `#256AA6` | 冷静理性偏好 |
| ojBlue 蓝白 | 高对比办公风 | `#165DFF` | 接近主流效率工具（Arco 系），圆角更小（10/12/16/22） |
| white 素白 | 极简 | `#30363D` | 近无色彩，打印/专注友好 |
| black 墨黑 | 唯一暗色 | `#63758A` | 夜间使用 |

> 所有主题共享同一套令牌结构，仅取值不同。新增主题 = 在 `AppTokens` 增加一个 `static const` 实例 + 枚举项 + 设置页入口，**不允许**在页面里为主题写条件分支。

### 2.2 令牌分层（从底到顶）

```text
backdropTop/Middle/Bottom   窗口级渐变底色（最底层）
canvas                      Scaffold 背景
shellSurface / shellBorder  内容壳大面板（圆角 28）
sidebarSurface → Strong     侧边栏深色渐变
panelSurface / Subtle / Accent   卡片三级面板
insetSurface                内嵌控件底（输入框、chip、图标按钮）
borderSoft / borderFaint    边框两档（可交互 / 纯装饰）
textPrimary / Secondary / Muted  文本三档
accent / accentHover / accentSoft  强调色三态
warmAccent                  暖色点缀（生活语境专用）
```

**使用规则：**

- 任何页面背景只允许取 `canvas`/`backdrop*`/`panel*`，禁止新建"页面专属底色"。
- `panelAccent`（强调色淡底）用于「当前激活/推荐」面，如选中日历格、当前分析会话。
- 层级关系 `inset < panelSubtle < panelSurface`：内嵌控件最深（明度最低），承载内容的面板最亮。

### 2.3 暖色点缀（warmAccent）使用边界

`warmAccent`（各主题均为金棕色系）是全App唯一暖色，**只**允许出现在生活语境：

- 允许：天气组件、桌宠相关、首页时钟装饰、农历/节日标注、校园地图点位。
- 禁止：按钮主色、链接、表单强调、错误/成功提示、学术功能页的装饰。

### 2.4 语义色（现状缺口 → 规划补齐）

当前 `ColorScheme.fromSeed` 自动派生的 error/success 未统一，各页自行其是。规划在 `AppTokens` 增加语义令牌：

| 令牌 | 浅色取值基准 | 用途 |
| --- | --- | --- |
| `success` / `successSoft` | `#2E7D4F` 系 | 同步成功、备份完成、分析写入成功 |
| `warning` / `warningSoft` | `#C98A2D` 系 | 同步冲突、存储不足、Ollama 未启动 |
| `danger` / `dangerSoft` | `#C04545` 系 | 删除确认、同步失败、登录过期 |
| `info` / `infoSoft` | 复用 `accent` 系 | 普通提示条 |

规则：**语义色独立于主题强调色**——切主题时 success/warning/danger 不跟随 accent 变化（仅暗色主题做明度适配），保证状态含义稳定。

### 2.5 硬编码颜色收敛（已完成 2026-08-05）

`features/` 下已清零裸露 `Color(0x` 字面量，存量按三类归位：

- 天气/地图的**数据语义色**（晴天黄、雨雪蓝、POI 分类色）→ 独立调色板文件：`features/home/weather_palette.dart`、`features/campus_map/map_palette.dart`。这些颜色表达数据含义，刻意独立于主题令牌。
- 装饰性硬编码 → 已替换为最近令牌（含 `panelSubtle`、`borderFaint`、`danger`、`backdropMiddle`、`shadowSm/Md.first.color`）。
- 零星功能色（人名高亮、PDF 搜索匹配、记录类型标识）→ 文件级命名常量并注释语义。
- lint 防线（待做 P2）：后续在 `analysis_options.yaml` 引入自定义规则或 code review 清单项 —— `features/` 下新增 `Color(0x` 字面量需在 PR 说明原因。

---

## 3. 字体排印

### 3.1 字阶（沿用现有 8 级，语义化命名）

| 令牌 | 字号/字重/行高 | 用途 |
| --- | --- | --- |
| headlineMedium | 28 · w600 · 1.15 | 页面主标题（一级页面） |
| headlineSmall | 22 · w600 · 1.2 | 页面副标题 / 大数字展示 |
| titleLarge | 17 · w600 · 1.25 | 卡片标题（SectionCard title） |
| titleMedium | 15 · w500 · 1.25 | 区块小标题 / 按钮文字 |
| bodyLarge | 14 · w400 · 1.55 | 正文（桌面端基准字号） |
| bodyMedium | 13 · w400 · 1.55 | 次级正文、列表行 |
| bodySmall | 12 · w400 · 1.45 | 辅助说明、时间戳 |
| labelLarge | 12 · w600 · 1.2 | 标签、徽标、侧栏导航项 |

### 3.2 规则

- 桌面端正文基准 **14px**，不低于 12px；12px 仅用于辅助信息。
- 标题字重 w600，正文 w400，不引入 w300/w800 制造层级。
- 负字距仅允许 headline 两级（-0.5 / -0.3），正文不加字距。
- 数字展示场景（首页时钟、统计数字、倒计时）后续可引入 `fontFeatures: tabularFigures` 或等宽数字字体，保证跳动时不抖动。
- 阅读页（reading / document_view）正文行高可放宽至 1.7，属于页面级覆盖，不改全局字阶。

---

## 4. 间距 · 圆角 · 阴影 · 布局

### 4.1 间距令牌（现状缺口 → 规划补齐）

现状 padding/margin 字面量散落（20、16、12、8…）。规划新增 `AppSpacing`，以 4 为基数：

```text
x1=4   x2=8   x3=12   x4=16   x5=20   x6=24   x8=32
```

约定俗成的对应关系（与现有代码对齐）：

| 场景 | 值 |
| --- | --- |
| 窗口外边距 / 壳层内边距 | 20 (x5) |
| 卡片内边距 | 20 (x5) |
| 卡片之间间距 | 16–20 (x4–x5) |
| 标题与内容间距 | 16 (x4) |
| 行内元素间距 | 8–12 (x2–x3) |
| 紧凑列表行距 | 4–8 (x1–x2) |

### 4.2 圆角（已有，固定四档）

| 令牌 | 值 | 用途 |
| --- | --- | --- |
| radiusSmall | 12 | 按钮、图标按钮、tooltip |
| radiusMedium | 16 | 输入框、侧栏导航项、logo 容器 |
| radiusLarge | 20 | 卡片（SectionCard、Card） |
| radiusXLarge | 24 | 对话框；壳层面板用 `radiusXLarge + 4`（28） |

chip 保持全圆角（999）。ojBlue 主题四档整体减小（10/12/16/22），属主题特性，保留。

### 4.3 阴影（已有两档，补一档浮层）

| 令牌 | 用途 |
| --- | --- |
| shadowSm | 卡片微浮起 |
| shadowMd | 壳层面板、侧栏 |
| shadowLg（规划） | 对话框、下拉浮层、桌宠气泡等**叠加在内容之上**的浮层 |

原则：同一屏内投影层级不超过 2 层；不靠阴影表达"可点击"，可点击性由 hover 背景变化表达。

### 4.4 断点统一（现状散落 → 收敛为三档）

现状字面量：620（SectionCard）、760（home）、980/1100/1280（shell metrics）。收敛为：

| 断点 | 值 | 含义 |
| --- | --- | --- |
| compact | < 760 | 单栏堆叠，侧栏折叠 |
| medium | 760 – 1199 | 常规桌面窗口 |
| wide | ≥ 1200 | 宽屏，内容最大宽度限宽居中 |

组件内部的小断点（如 SectionCard 的 620）允许存在，但应注释说明用途；页面级布局只允许引用上面三档（后续可抽到 `core/utils/breakpoints.dart`）。

---

## 5. 动效规范（现状缺口 → 新增）

### 5.1 时长与曲线

```text
durationFast    120ms   hover、press、tooltip
durationNormal  200ms   面板展开收起、tab 切换、导航选中
durationSlow    320ms   页面级过渡、对话框进出
curve: Curves.easeOutCubic（默认） / Curves.easeInOut（循环氛围动画）
```

### 5.2 两类动效的边界

| 类型 | 示例 | 规则 |
| --- | --- | --- |
| 功能动效 | hover、展开、切换 | 快（≤200ms）、不循环、不打断操作 |
| 氛围动效 | 天气背景动画（18s 循环）、桌宠动作 | 慢、可循环、**必须可被设置关闭**（沿用 `weatherAnimationEnabled` 模式） |

原则：氛围动效是"生活面"气质的表达，全部走独立开关；系统减少动态效果（`MediaQuery.disableAnimations`）时自动降级为静态。

---

## 6. 组件库规划

### 6.1 现状

`lib/shared/widgets/` 仅 4 个：`section_card`、`empty_state`、`month_calendar`、`status_badge`。大量通用模式（设置行、统计卡、列表行）散在各 feature 内私有实现。

### 6.2 目标分层

```text
shared/widgets/
├── basic/        按钮扩展、标签、徽标(status_badge✓)、开关行
├── feedback/     空态(empty_state✓)、加载骨架、结果提示条(banner)、确认对话框
├── data/         统计数字卡、键值行、列表行、月历(month_calendar✓)
├── layout/       分区卡(section_card✓)、页面脚手架(page_scaffold)、双栏分割
└── business/     天气胶囊、设置行(_SettingsToggleRow 上提)、分析状态徽标
```

### 6.3 组件规则

1. **上提标准**：同一模式在 2 个 feature 出现第 3 次前，必须上提到 `shared/`。首批候选：设置页的 `_SettingsToggleRow` / `_InfoBanner` / `_PathRow`、各页私有的统计卡。
2. 组件只依赖 `AppTokens` + `ThemeData`，不依赖具体 feature 的 model；业务组件例外但需命名前缀（如 `WeatherPill`）。
3. 每个共享组件必须支持 6 套主题下自查一遍（令牌化天然满足，禁止写死颜色）。
4. 命名：纯 UI 用通用名（`StatCard`），带业务语义的用领域前缀（`WeatherStatusPill`）。
5. 新增组件在 PR 描述里附 6 主题中至少 green + black 两套的截图。

### 6.4 页面脚手架（关键补齐项）

各 feature 页面头部结构（标题 + 副标题 + 操作区）目前各自实现。规划 `PageScaffold`：

```text
PageScaffold
├── header: title / subtitle / actions（≤3 个主操作）
├── body: 内容区（默认单栏滚动，可切双栏）
└── 统一 padding：宽屏 32，常规 24，compact 16
```

目标：所有一级页面（home 除外，它是特殊仪表盘）使用同一脚手架，消灭"每页一套头部"。

---

## 7. 页面风格模式（Pattern）

| 模式 | 适用页 | 布局特征 |
| --- | --- | --- |
| 仪表盘 | 首页 | 无面板全幅背景 + 浮动元素（时钟居中、天气胶囊右上）；允许氛围动效 |
| 工作面板 | 分析、日历、人物、历史 | PageScaffold + SectionCard 流式堆叠；内容最大宽度 1080 居中 |
| 阅读沉浸 | 阅读、文档查看 | 内容区最大化，工具栏可收起；正文行高 1.7；背景用 `insetSurface` 降低刺激 |
| 工具台 | PDF 工具、文件 | 左列表右详情的双栏；列表栏宽 280–320，分割线 `borderFaint` |
| 表单/目录 | 设置、登录 | 遵循 `settings_page_guidelines.md` 的注册表模式；登录页居中单卡 ≤ 420 宽 |
| 覆盖层 | 桌宠、对话框 | 独立于壳层之上，shadowLg，不打断主流程 |

---

## 8. 主题策略

### 8.1 新增主题 checklist

1. `AppTokens` 新增 `static const` 实例（对照 green 逐项取色）。
2. `AppColorTheme` 枚举 + `label`（≤4 汉字）+ `tokens` 映射。
3. 六类自查：侧栏对比度、accent 按钮白字对比度 ≥ 4.5、panel 三层明度差可辨、warmAccent 不刺眼、暗色下 shadow 加强、截图存档。
4. 设置页外观分类注册入口。

### 8.2 已知后续方向

- 暗色目前只有 black 一套且 accent 偏灰（`#63758A`），后续可补"暗色学术绿"满足夜间阅读。
- Android 端适配时保持令牌不变，仅调整密度（padding ×0.8、字号基准 13）与导航模式（侧栏 → 抽屉/底栏）。

---

## 9. 落地路线（按优先级）

| 优先级 | 事项 | 影响面 | 状态 |
| --- | --- | --- | --- |
| P0 | 补语义色令牌（success/warning/danger/info） | `app_tokens.dart` + 全量主题实例 | ✅ 2026-08-02 已落地，含 `ColorScheme.error` 接入 |
| P0 | 补间距令牌 `AppSpacing` + 断点收敛 `breakpoints.dart` | 新代码直接用，旧代码渐进替换 | ✅ 2026-08-02 已落地（`app_spacing.dart`、`core/utils/breakpoints.dart`） |
| P0 | 硬编码颜色收敛（campus_map / home / history）+ 调色板文件 | 3 个 feature | ✅ 2026-08-05 已落地：`weather_palette.dart`、`map_palette.dart`；history/analysis/reading 为命名常量；`features/` 下无裸露字面量 |
| P1 | `PageScaffold` 与首批共享组件上提（设置行三件套、统计卡） | shared/widgets + 设置页先行 | 待开工 |
| P1 | 动效令牌（duration/curve 常量）+ 氛围动效统一开关检查 | core/theme | 🟡 令牌已建（`app_motion.dart`），页面接入待做 |
| P2 | 语义色 lint 防线、组件截图走查清单纳入 PR 模板 | 工程规范 | 待开工 |
| P2 | 暗色主题增强、Android 密度方案 | 跟随 PRD 里程碑 M4 | 待开工 |

**验收方式**：本规范配套的 `style_preview.html` 作为视觉评审基线；每个 P0/P1 项完成后在 PR 中附对应主题截图。
