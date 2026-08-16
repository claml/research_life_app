# Research Life 项目咨询介绍文档

更新时间：2026-05-14

本文档用于把当前项目背景快速交代给外部技术顾问、开发者或模型助手，方便讨论技术问题、架构调整和新功能选型。若要对外发送，建议只发送源码和本文档，不要发送真实的 `.research_life` 数据库、个人资料文件或未脱敏周记内容。

## 1. 项目一句话

Research Life 是一个本地优先的 Flutter Windows 桌面应用，用于管理研究生日常记录、周分析、日历事项、人物关系、PDF 阅读、校园地图地点、主页天气和内置桌宠陪伴。

## 2. 项目概况

- 项目路径：`D:\桌面\研究生活\应用`
- 应用名称：`research_life`
- 当前版本：`0.1.0+1`
- 目标平台：Windows 10 / Windows 11 桌面端
- 开发框架：Flutter + Dart
- 本地数据：SQLite / Drift，默认数据目录是 `D:\桌面\研究生活\.research_life`
- 项目形态：单机本地应用，没有账号系统、后端服务或云同步
- 主要用户：研究生或需要把学习、科研、生活记录整合管理的个人用户
- 当前项目使用 Git 管理，向外协作前建议只提交源码、测试和脱敏文档，不提交本地运行数据

## 3. 快速运行

环境要求：

- Flutter SDK，启用 Windows 桌面开发
- Dart SDK 满足 `^3.11.4`
- Visual Studio 2022，安装 `Desktop development with C++`
- Windows 自带或可用的 `winsqlite3.dll`

常用命令：

```powershell
cd D:\桌面\研究生活\应用
flutter pub get
flutter test
flutter run -d windows
flutter build windows --release
```

如果修改 Drift 表结构，需要重新生成：

```powershell
dart run build_runner build --delete-conflicting-outputs
```

## 4. 技术栈和依赖

| 类型 | 当前选择 | 用途 |
| --- | --- | --- |
| UI 框架 | Flutter / Material | Windows 桌面应用界面 |
| 状态管理 | `ChangeNotifier` + `InheritedNotifier` | 全局控制器 `ResearchLifeController` 驱动 UI |
| 数据库 | Drift + SQLite | 会话、日历事件、人物、地点、PDF 文献和标注、偏好设置 |
| 文件导入 | `file_selector`、`desktop_drop` | 选择文件、拖拽导入 |
| 文档解析 | `archive`、`xml` | 解压并解析 `.docx` |
| 编码处理 | `charset_converter` | 支持 UTF-8、UTF-16、GBK 文本导入 |
| PDF 阅读 | `pdfrx` | PDF 打开、阅读、搜索、缩略图、标注 |
| 本地路径 | `path_provider`、`path` | 数据目录和文件路径处理 |
| 网络 | Dart `HttpClient` | 天气服务 |

## 5. 目录结构

```text
应用
├─ lib
│  ├─ main.dart
│  ├─ app
│  │  ├─ research_life_app.dart
│  │  ├─ research_life_scope.dart
│  │  ├─ app_shell.dart
│  │  └─ app_section.dart
│  ├─ state
│  │  └─ research_life_controller.dart
│  ├─ core
│  │  ├─ models
│  │  ├─ theme
│  │  └─ utils
│  ├─ features
│  │  ├─ home
│  │  ├─ calendar
│  │  ├─ campus_map
│  │  ├─ reading
│  │  ├─ analysis
│  │  ├─ persons
│  │  ├─ history
│  │  ├─ settings
│  │  └─ pet_overlay
│  ├─ services
│  │  ├─ analysis
│  │  ├─ calendar
│  │  ├─ database
│  │  ├─ export
│  │  ├─ import
│  │  ├─ pet
│  │  ├─ review
│  │  ├─ storage
│  │  └─ weather
│  └─ shared
├─ assets
│  ├─ logo
│  ├─ campus_map
│  └─ pets
├─ docs
├─ test
└─ windows
```

工作区里还有几个相关目录：

- `D:\桌面\研究生活\.research_life`：应用运行数据，包含 SQLite 数据库和偏好设置
- `D:\桌面\研究生活\资料`：PDF 文献归档目录，阅读模块会按分类复制 PDF 到这里
- `D:\桌面\研究生活\home_images`：主页图片目录，使用 `research_wall.*` 和 `life_wall.*`
- `D:\桌面\研究生活\应用\assets\pets`：内置桌宠资源，包含 `pet.json` 和 `spritesheet.webp`

## 6. 应用架构

启动链路：

```text
main.dart
  -> ResearchLifeApp
    -> 初始化 LocalWorkspaceService、AppDatabase、各 Repository、ResearchLifeController
    -> ResearchLifeScope 提供全局 controller
    -> AppShell 负责侧边栏和页面切换
    -> 各 feature page 通过 ResearchLifeScope.of(context) 读写状态
```

核心架构特点：

- `ResearchLifeController` 是主要应用服务和状态容器，负责分析、保存、导入、人物合并、日历事件、PDF 阅读记录、天气、桌宠、主页图片等大部分流程。
- `features/*` 主要是 UI 页面，业务动作基本委托给 controller。
- `services/*` 放具体能力：规则分析、导入解析、校历解析、天气请求、本地工作区、桌宠资源、备份导出、数据库仓储。
- 数据持久化通过 `services/database/repositories/*` 封装，底层 schema 在 `services/database/app_database.dart`。
- 应用关闭时会等待 pending persistence，并按设置清理桌宠浮层状态。

## 7. 当前工作台导航（2026-08-16）

当前信息架构以 `docs/superpowers/specs/2026-08-16-workbench-navigation-ai-finish-design.md` 为准：

- 全局入口：天气、AI 助手、日历
- 今日：今日时间线、未完成待办、优先级和已完成事项
- 科研：概览、文献、笔记、统计
- 生活：校园、周分析、人物
- 资料：资料库、PDF 工具
- 设置：设置概览

天气、AI 助手和日历互斥；选择任何工作区或其页签会关闭这些全局入口，并恢复该工作区上次选择的页签。AI 页面以工作台内容嵌入：本地保存会话历史和用户可见的生成进度，但不展示服务提供商的内部推理原文。

本节只记录当前实现。`2026-08-09` 和 `2026-08-11` 的历史规格保持原样；其被替代的条款已在上述 `2026-08-16` 设计文档中明确记录。

## 8. 功能模块

| 导航区域 | 页面 / 文件 | 当前能力 |
| --- | --- | --- |
| 全局入口 | 天气：`lib/features/home/home_page.dart`；AI：`lib/features/agent/agent_page.dart`；日历：`lib/features/calendar/calendar_page.dart` | 三个互斥的侧栏目的地；AI 以嵌入模式呈现，日历提供月视图、事项和周报提示词 |
| 今日 | `lib/features/workbench/today_workspace.dart` | 一个整合页面，包含今日时间线、未完成待办、优先级控制、完成切换、快速记录和默认折叠的已完成事项 |
| 科研 | `lib/features/workbench/research_workspace.dart` | 概览、文献、笔记、统计；不承载 AI、周分析或人物 |
| 资料 | `lib/features/workbench/materials_workspace.dart` | 资料库和 PDF 工具；可按上下文渲染请求的文档而不暴露额外页签 |
| 生活 | `lib/features/workbench/life_workspace.dart`；`campus_map`、`analysis`、`persons` 功能页 | 校园、周分析、人物三个页签 |
| 设置 | `lib/features/settings/settings_page.dart` | 主题色、桌宠、数据目录、数据库备份、咨询包导出、主页图片、校历固定格式导入、周报提示词模板 |

## 9. 核心数据模型

主要模型在 `lib/core/models/app_models.dart`：

- `AnalysisInput`：原始输入文本、来源类型、来源路径
- `AnalysisDraft`：分析草稿，包含事项、人物、摘要和警告
- `ExtractedTaskDraft`：识别出的事项，包含分类、记录/计划、置信度、人物、时间提示
- `ExtractedPersonDraft`：识别出的人物，包含角色、别名、关联事项索引
- `ReviewPreview`：分析结果预览，把事项分为已完成和未来计划
- `SessionRecord`：确认后的历史记录，是周分析和校历导入的核心持久化单位
- `EventItem`：日历事件，可来自规则分析、手动添加、校历、节假日
- `PersonProfile`：确认后的人物资料
- `CampusPlace`：校园地图地点
- `PdfLibraryDocument`：PDF 文献条目
- `PdfTextAnnotation`：PDF 文本标注
- `WeatherLocation` / `WeatherSnapshot`：天气位置和天气快照

主要枚举：

- `ItemCategory`：study / work / life / health / social / other
- `EventType`：record / plan
- `EventOrigin`：analysis / manual / institutionCalendar / holiday
- `PersonRole`：teacher / classmate / friend / partner / family / other
- `PlaceCategory`：study / dining / dormitory / lab / sports / social / errands / other
- `PdfAnnotationKind`：bookmark / highlight / underline / strikethrough / wavyUnderline / note

## 10. 数据库和本地文件

数据库定义在 `lib/services/database/app_database.dart`，当前 `schemaVersion = 4`。

主要表：

- `preferences`：键值偏好设置
- `sessions`：确认后的分析/校历历史记录，并保存 `snapshotJson`
- `events`：会话下的日历事件
- `persons`：会话下的人物
- `event_persons`：事件和人物关联表
- `campus_places`：校园地图地点
- `pdf_library_documents`：PDF 文献库
- `pdf_library_annotations`：PDF 标注

本地文件布局：

```text
D:\桌面\研究生活\.research_life
├─ research_life.sqlite
├─ research_life.sqlite-wal
├─ research_life.sqlite-shm
├─ preferences.json
├─ backups
└─ pets

D:\桌面\研究生活\资料
└─ <PDF 分类>

D:\桌面\研究生活\home_images
├─ research_wall.png / .jpg / .jpeg / .webp / .bmp
└─ life_wall.png / .jpg / .jpeg / .webp / .bmp
```

注意：

- `preferences.json` 是早期偏好存储，部分偏好会迁移到 SQLite `preferences` 表。
- PDF 导入会复制到 `资料/<分类>`，数据库记录复制后的路径。
- 数据迁移或对外咨询时不要直接发送真实 SQLite 文件，建议提供脱敏样例或 schema。

## 11. 关键业务流程

### 周分析流程

1. 用户在周分析页输入文本，或导入 TXT/MD/DOCX。
2. `ImportService` 读取文件并转成 `AnalysisInput`。
3. `AnalysisService` 使用本地规则和正则识别事项、人物、计划、分类、时间提示。
4. `ReviewService` 把草稿拆成已完成事项、未来计划、人物关系标签。
5. 用户确认后，`confirmDraft()` 生成 `SessionRecord`、`EventItem`、`PersonProfile`。
6. `SessionsRepository` 保存到 SQLite，并写入 `sessions.snapshotJson`。
7. 日历、人物关系、历史页面从 controller 的 session history 派生展示。

### 校历导入流程

1. 设置页提供固定格式模板和导入提示词。
2. 用户或外部模型把学校校历整理成 `CALENDAR_IMPORT_V1` 格式。
3. `InstitutionCalendarService.parse()` 解析日期、标题、分类和类型。
4. controller 把校历保存成特殊的 `SessionRecord`，事件 origin 为 `institutionCalendar`。
5. 日历页合并展示校历事件，历史页可重新编辑或删除。

### PDF 阅读流程

1. 阅读页选择或拖入 PDF。
2. controller 调用 `LocalWorkspaceService.copyPdfIntoMaterials()` 复制到 `资料/<分类>`。
3. `PdfDocumentsRepository` 保存文献条目。
4. `pdfrx` 打开 PDF，页面记录 lastPage/pageCount/lastOpenedAt。
5. 用户添加标注，`PdfDocumentsRepository` 保存 annotation rects、文本、颜色、备注。
6. 阅读超过最短时长后，可生成一条 manual event，同步到日历。

### 天气流程

1. 启动时尝试读取已保存天气位置；没有则调用 `ipapi.co` 自动定位。
2. 城市搜索使用 Open-Meteo geocoding API。
3. 当前天气使用 Open-Meteo forecast API。
4. controller 每 15 分钟刷新一次天气。

### 内置桌宠流程

1. 启动时 `ResearchLifeController.ensurePetCompanionLoaded()` 加载可用桌宠资源。
2. `PetCompanionService` 从 `assets/pets` 和项目桌宠目录读取 `pet.json` 与 `spritesheet.webp`。
3. `PetOverlay` 在应用内显示桌宠图集帧、气泡文字和动画状态。
4. controller 可发送测试消息和当天任务提醒，退出时按设置隐藏桌宠状态。

## 12. 测试覆盖

当前测试在 `test/`：

- `analysis_service_test.dart`：周记规则分析、人物识别、计划识别、导入服务、预览拆分
- `research_life_controller_test.dart`：分析确认、历史编辑删除、日历去重、校历导入、手动事件、校园地点、提示词模板、主页图片
- `sessions_repository_test.dart`：历史记录持久化
- `manual_events_repository_test.dart`：手动事件持久化
- `campus_places_repository_test.dart`：校园地点持久化
- `database_preferences_repository_test.dart`：偏好设置持久化
- `pdf_documents_repository_test.dart` 未单独列出，PDF 相关能力主要在 controller 和 repository 文件中
- `weather_service_test.dart`、`research_life_controller_weather_test.dart`：天气解析和位置逻辑
- `institution_calendar_service_test.dart`：校历格式解析
- `local_workspace_service_test.dart`：本地目录、备份和 PDF 复制
- `backup_service_test.dart`：备份清单、数据库和偏好文件打包
- `consulting_package_service_test.dart`：脱敏咨询包导出
- `import_service_encoding_test.dart`：文本编码导入

建议外部修改后至少执行：

```powershell
flutter test
```

涉及 Drift schema 修改时，还需要重新生成 `app_database.g.dart` 并跑全量测试。

## 13. 当前限制和风险点

- 平台强绑定 Windows，当前默认工作区路径硬编码为 `D:\桌面\研究生活`。
- 没有后端、账号、云同步和多设备冲突处理。
- `ResearchLifeController` 体积较大，承担了状态、业务流程和部分文件操作，后续复杂功能增加时可考虑拆分为更小的 controller 或 application service。
- 周分析目前是规则/正则驱动，对复杂中文表达、跨句指代、模糊时间和人物别名的理解有限。
- 天气依赖公网 API，网络不可用时需要优雅降级。
- 桌宠显示依赖固定图集格式，导入自定义桌宠时需要校验 `pet.json` 和 `spritesheet.webp` 是否匹配。
- PDF 标注依赖 `pdfrx` 的文本选择和坐标能力，不同 PDF 文本层质量会影响体验。
- SQLite 中同时有结构化表和 `sessions.snapshotJson` 快照，改模型时需要注意兼容旧数据。
- 应用目前没有插件化权限隔离；所有个人数据都在本机文件系统。

## 14. 已有新功能选型线索

已有文档：`docs/local_weekly_analysis_ollama.md`

该文档建议把“每周分析”从规则分析升级为：

- 本地模型运行器：Ollama
- 默认模型：`qwen3:8b`
- 兜底方案：保留当前 `AnalysisService` 规则分析
- 推荐接入点：`ResearchLifeController.analyzeCurrentInput()`
- 推荐新增文件：`local_llm_analysis_service.dart`、`local_llm_analysis_models.dart`

这说明项目后续 AI 能力的优先方向是“本地 LLM 优先，规则兜底”，适合保护个人周记隐私。

## 15. 适合向别人咨询的问题

技术问题可以按下面方向问：

- 周分析是否应该用本地 LLM、云 API，还是规则 + LLM 混合？
- `ResearchLifeController` 是否需要拆分？拆成哪些边界最合理？
- SQLite schema 和 `snapshotJson` 快照并存是否合适？后续迁移如何设计？
- 如果要做多设备同步，应选文件同步、WebDAV、SQLite sync、Supabase/Firebase，还是自建后端？
- PDF 标注数据结构是否适合长期维护？是否需要导出为标准格式？
- 桌宠资源格式是否需要版本化，后续是否应该支持更多交互或插件化？
- Windows-only 是否继续，还是迁移到跨平台桌面、移动端或 Web？
- 本地隐私数据如何备份、加密和脱敏？
- UI 是否需要分离成更独立的 feature controller，减少页面对全局 controller 的依赖？

## 16. 咨询时建议附上的文件

如果咨询具体技术问题，建议附：

- `pubspec.yaml`
- `lib/app/research_life_app.dart`
- `lib/app/app_shell.dart`
- `lib/state/research_life_controller.dart`
- `lib/core/models/app_models.dart`
- `lib/services/database/app_database.dart`
- 对应问题相关的 service/page 文件
- 对应测试文件
- 本文档

不要附：

- `D:\桌面\研究生活\.research_life\research_life.sqlite`
- 真实周记、真实人物关系、真实 PDF 文献
- `build/` 目录
- 大体积图片、PDF、备份包或本地运行生成的桌宠资源，除非问题明确需要这些素材

## 17. 可直接复制的咨询模板

```text
我有一个 Flutter Windows 桌面应用，叫 Research Life，用于本地管理研究生日常记录、周分析、日历事项、人物关系、PDF 阅读、校园地图和内置桌宠陪伴。

当前架构：
- Flutter + Dart，Windows-only
- ChangeNotifier + InheritedNotifier，全局 ResearchLifeController 管状态和业务流程
- Drift + SQLite 本地持久化，schemaVersion = 4
- 没有后端、账号和云同步
- 周分析目前是规则/正则提取，已有一个计划是接入 Ollama 本地 LLM 并保留规则兜底
- PDF 阅读用 pdfrx，天气用 Open-Meteo/ipapi，桌宠使用应用内 Hatch Pet 图集资源

我想咨询的问题是：
<在这里写具体问题>

请重点从以下角度给建议：
1. 这个方案在当前架构下是否合适
2. 需要改哪些模块和文件
3. 数据库或本地文件是否需要迁移
4. 主要风险和替代方案是什么
5. 第一版如何最小可行落地
6. 应该补哪些测试
```
