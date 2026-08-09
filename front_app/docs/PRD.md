# 研LIFE / Research Life 产品需求文档（PRD）

| 字段 | 内容 |
| --- | --- |
| 文档版本 | V2.0（大迁移版） |
| 状态 | 草案 · 待评审 |
| 更新日期 | 2026-05-15 |
| 产品代号 | `research_life` |
| 关联文档 | `user_guide.md`、`project_context_for_consulting.md`、`settings_page_guidelines.md`、`local_weekly_analysis_ollama.md`、研LIFE SRS V1.0 |
| 后端语言 | **Java 8**（JDK 1.8） |

---

## 1. 文档目的

本文档在既有 **本地 Windows 单机版**（`0.1.0+1`）与 **研LIFE 软件需求规格说明书（SRS）** 基础上，定义 **云端大迁移** 阶段的产品目标、功能边界、技术架构与验收标准。

**读者：** 产品、Flutter 客户端、Java 后端、测试、运维。

**不在本文范围：** 具体接口 Swagger、DDL 脚本、UI 高保真稿（由后续技术设计文档承接）。

---

## 2. 背景与迁移动因

### 2.1 现状摘要

当前应用为 **本地优先** 的 Flutter Windows 桌面端：

- 无账号、无后端、无多设备同步。
- 数据：`Drift + SQLite`（`.research_life/research_life.sqlite`）+ 磁盘目录（`资料/`、`home_images/` 等）。
- 状态：`ResearchLifeController` 集中承载分析、日历、PDF、天气、桌宠等流程（参见 `project_context_for_consulting.md`）。
- 周分析：**规则分析** 为主；已实现 **Ollama 本地 LLM 优先 + 规则兜底**（参见 `local_weekly_analysis_ollama.md` 与当前代码）。
- PDF：元数据在 SQLite，`path` 为 **本地绝对路径**，不具备跨端同步能力。

### 2.2 迁移目标

将产品从「单机科研生活记录工具」演进为 SRS 定义的 **科研操作系统（Research OS）** 雏形，第一阶段（MVP）聚焦：

```text
用户认证
  + 科研文件系统（文献 / PDF / 元数据 / 批注）
  + 增量同步（离线优先）
  + 保留现有核心体验（周分析、日历、阅读、设置）
```

**原则：**

1. **离线优先（Offline-first）**：本地 SQLite 可独立使用；联网后增量同步。
2. **Blob 与 Metadata 分离**：MySQL 管索引与同步；MinIO 管文件字节。
3. **渐进迁移**：不中断现有用户数据；提供一次性上传与双 ID 过渡期。
4. **本地 AI 与云端 AI 分轨**：周分析继续支持 Ollama；云端 AI（摘要/OCR）为二阶段。

---

## 3. 产品定位

### 3.1 一句话

**研LIFE** —— 面向研究生的科研与生活一体化效率平台：打通「文献 → 笔记 → 思考 → 任务 → 输出」，支持多端同步与本地隐私能力。

### 3.2 与当前 Research Life 的关系

| 维度 | 当前（V0.1 本地版） | 迁移后（V1.0 云同步版） |
| --- | --- | --- |
| 品牌/包名 | `research_life` | 延续，对外可称「研LIFE」 |
| 主平台 | Windows 桌面 | Windows + **Android**（SRS）；Web 暂不开发 |
| 数据主权 | 本机目录 | 用户云端空间 + 本地缓存 |
| 账号 | 无 | 用户名/邮箱 + JWT |
| 文件 | `资料/{分类}/*.pdf` + 路径字段 | MinIO 对象 + `storage_key` + 本地 cache |
| 分析 AI | Ollama 本地（可选）+ 规则兜底 | 同上；云端 AI 服务后置 |

### 3.3 目标用户

- 研究生、科研工作者：文献阅读、周记分析、日程与人物关系管理。
- 重视隐私：周记/文献可本地处理；同步需加密传输与权限隔离。

---

## 4. 平台与版本规划

| 平台 | V1.0 MVP | 后续 |
| --- | --- | --- |
| Windows 10+ | ✓ | 持续维护 |
| Android | ✓（同步与文件只读/上传 MVP） | 功能对齐桌面 |
| Web | ✗ | 暂不开发 |
| macOS / iOS | ✗ | 后续评估 |

**客户端版本号建议：** `1.0.0` 标示云同步里程碑；`0.1.x` 为迁移前本地版维护线。

---

## 5. 功能需求

### 5.1 功能地图（迁移后）

```text
研LIFE V1.0
├── 用户与设备
│   ├── 注册 / 登录（用户名密码、邮箱验证码）
│   ├── JWT（Access + Refresh）
│   ├── 多设备登录与设备列表
│   └── 未登录：仅本地模式（可选，见 §12 决策项）
├── 科研文件系统 ★核心
│   ├── 文献库（文件夹 / 列表）
│   ├── 文件类型：PDF（MVP）；Word/PPT/Excel/MD/图片（元数据先行，打开方式分期）
│   ├── 上传：小文件直传；大文件分片 + 断点续传
│   ├── PDF 阅读：高亮、批注、书签、页面定位（延续现有 pdfrx 能力）
│   ├── 标签 / 分类（延续 category，扩展 tags）
│   └── 收藏（MVP 可沿用书签；通用收藏二阶段）
├── 同步引擎 ★核心
│   ├── 增量 Pull / Push
│   ├── 软删除、版本号、设备 ID
│   └── 冲突策略（见 §8.4）
├── 笔记系统（MVP 子集）
│   ├── 独立 Markdown 笔记（非 PDF 批注 note）
│   └── 与文献双向链接（二阶段）
├── 日程与提醒（MVP 子集）
│   ├── 同步：手动事项、分析产生事项（events）
│   └── 课程表 Excel / OCR（二阶段）
├── 周分析（保留并增强）
│   ├── 文本 / TXT / MD / DOCX 导入
│   ├── Ollama 本地 LLM 优先 + 规则兜底
│   └── 分析结果 Sessions/Events/Persons 可选上云
├── 人物关系 / 历史 / 校园地图 / 首页天气 / 桌宠
│   ├── V1.0：以 **本地为主**，云端同步 **可选或二阶段**
│   └── 设置页结构遵循 `settings_page_guidelines.md`
└── 设置与数据
    ├── 账号与同步状态
    ├── 存储路径（改为 cache 根目录，取消硬编码盘符）
    ├── 本地备份（保留 BackupService）
    └── 一次性「迁移到云端」向导
```

### 5.2 用户认证（P0）

| ID | 需求 | 优先级 | 说明 |
| --- | --- | --- | --- |
| AUTH-01 | 用户名密码登录 | P0 | `POST /api/v1/user/login` |
| AUTH-02 | 邮箱验证码登录 | P1 | MVP 可先密码，验证码紧随其后 |
| AUTH-03 | Access Token + Refresh Token | P0 | Access 短期；Refresh 存 Redis |
| AUTH-04 | 自动登录 | P0 | 安全存储 Refresh；启动刷新 Access |
| AUTH-05 | 多设备登录 | P1 | `user_device` 表记录 device_id |
| AUTH-06 | 登出与 Token 吊销 | P0 | Access 黑名单或版本号机制 |

**安全：** Spring Security + JWT；HTTPS；密码 BCrypt；接口限流（Redis）。

### 5.3 科研文件系统（P0）

#### 5.3.1 文献管理

| ID | 需求 | 优先级 |
| --- | --- | --- |
| FILE-01 | 用户文件树（文件夹 + 文件条目） | P0 |
| FILE-02 | 按分类/标签筛选 PDF | P0 |
| FILE-03 | 导入 PDF：复制到 cache + 上传 MinIO | P0 |
| FILE-04 | 删除：软删除并同步 | P0 |
| FILE-05 | 重命名、移动目录 | P1 |
| FILE-06 | 支持 Word/PPT/Excel/MD/图片元数据 | P2 |
| FILE-07 | 同用户 content_hash 去重 | P1 |

**与现状映射：**

- `PdfLibraryDocument` → `file_entry` + `document_profile`
- 磁盘 `资料/{category}/` → MinIO + `local_cache_path`
- 禁止将 Windows 绝对路径写入云端

#### 5.3.2 PDF 阅读器

| ID | 需求 | 优先级 |
| --- | --- | --- |
| PDF-01 | 打开 PDF：优先本地 cache，否则下载 | P0 |
| PDF-02 | 高亮、下划线、删除线、波浪线、笔记、书签 | P0 |
| PDF-03 | 全文搜索（文档内） | P0 |
| PDF-04 | 记住 lastPage、pageCount、lastOpenedAt | P0 |
| PDF-05 | 阅读时长同步日历（本地已有，云端可选） | P1 |
| PDF-06 | AI 总结 | P3（云端 AI 二阶段） |

**体验基线：** 不低于当前 `user_guide.md` §4.4 描述能力。

#### 5.3.3 笔记系统（独立）

| ID | 需求 | 优先级 |
| --- | --- | --- |
| NOTE-01 | 创建/编辑/删除 Markdown 笔记 | P0 |
| NOTE-02 | 标题 + markdown_content 同步 | P0 |
| NOTE-03 | LaTeX 公式渲染 | P1 |
| NOTE-04 | 图片插入（对象存 MinIO） | P1 |
| NOTE-05 | 与 PDF 批注分离存储 | P0 |

**区分：** `document_annotation.note`（PDF 批注）≠ `note` 表（独立笔记）。

#### 5.3.4 文件同步（P0）

| ID | 需求 | 优先级 |
| --- | --- | --- |
| SYNC-01 | 本地变更写入 Outbox，后台 Push | P0 |
| SYNC-02 | 定时/手动 Pull 增量变更 | P0 |
| SYNC-03 | 同步字段：version、updated_at、device_id、is_deleted | P0 |
| SYNC-04 | 首次登录「迁移向导」：扫描本地 PDF + 批注上传 | P0 |
| SYNC-05 | 同步状态 UI（设置页 §5.8） | P0 |
| SYNC-06 | 冲突提示与自动策略 | P0 |

### 5.4 周分析（P0 保留，P1 可选上云）

| ID | 需求 | 优先级 |
| --- | --- | --- |
| ANA-01 | 粘贴/导入 TXT、MD、DOCX | P0 |
| ANA-02 | Ollama 本地分析（qwen3:8b 等） | P0 |
| ANA-03 | 规则分析兜底 | P0 |
| ANA-04 | 确认后写入 Sessions/Events/Persons | P0 |
| ANA-05 | 设置页可配 Ollama 地址、模型、超时、兜底开关 | P0 |
| ANA-06 | Sessions 快照上云 | P2 |
| ANA-07 | 云端 LLM 分析 | P3 |

**约束（来自 `local_weekly_analysis_ollama.md`）：**

- 模型输出必须为 **结构化 JSON**；客户端校验后映射 `AnalysisDraft`。
- 超时：首次 45s，常规 20s；失败明确提示并 fallback。
- V1.0 不把分析过程本身作为独立云 API；仍以客户端为主。

### 5.5 日程与日历（P1）

| ID | 需求 | 优先级 |
| --- | --- | --- |
| CAL-01 | 手动事项增删改查本地 | P0（已有） |
| CAL-02 | 分析/校历/节假日合并展示 | P0（已有） |
| CAL-03 | 手动事项与 events 表上云同步 | P1 |
| CAL-04 | 课程表 Excel 导入 | P2 |
| CAL-05 | 实验室打卡、GPS | P3 |

### 5.6 人物关系 / 历史 / 校园地图 / 首页 / 桌宠（P2 云端）

V1.0 **不阻塞发版**；保持本地 Drift 存储。若资源允许，可仅同步 `persons` + `sessions` 元数据。

| 模块 | 本地 | 云端 V1.0 |
| --- | --- | --- |
| 人物关系 | ✓ | 可选 |
| 历史 Sessions | ✓ | 可选 |
| 校园地图 | ✓ | 否 |
| 天气 | 公网 API，不经后端 | 否 |
| 桌宠 | 本地资源 | 否 |
| 主页图片 | 本地 | P2 对象存储 |

### 5.7 设置页（P0 结构需求）

遵循 `settings_page_guidelines.md`：

**新增/调整 Section（须注册 `_SettingsSectionSpec`）：**

| id | category | 标题 | 内容 |
| --- | --- | --- | --- |
| `account.profile` | storage | 账号 | 登录态、昵称、退出 |
| `sync.status` | storage | 同步 | 上次同步时间、立即同步、冲突数 |
| `sync.migration` | storage | 云端迁移 | 一键上传本地文库、进度、失败重试 |
| `analysis.local_llm` | analysis | 本地 LLM | 已有：Ollama 配置（保留） |
| `storage.paths` | storage | 文件位置 | cache 目录；取消仅显示 `D:\桌面\...` |
| `storage.backup` | storage | 备份 | 本地 BackupService 保留 |

**分类边界不变：** appearance / analysis / companion / storage / calendar。

### 5.8 用户可见行为变更说明（迁移告知）

需在首次升级弹窗与 `user_guide.md` 后续版本中说明：

1. 登录后可多设备访问文献；PDF 首次打开可能需下载。
2. 导入 PDF 后 **云端为权威副本**；本地为缓存。
3. 未登录可继续使用本地模式（若产品决策保留，见 §12）。
4. 换机流程：登录 → 自动 Pull → 无需手动复制 `资料/`（MVP 验证后写入用户文档）。

---

## 6. 非功能需求

| 类别 | 要求 |
| --- | --- |
| 性能 | API P95 < 500ms（不含上传）；PDF 打开 cache 命中 < 2s |
| 可用性 | 核心 API 99.5%（MVP 单机部署） |
| 安全 | 全站 HTTPS；JWT；用户数据按 user_id 隔离；MinIO 私有桶 + 预签名 |
| 隐私 | 周记默认本地 LLM；上传需用户确认（迁移向导） |
| 兼容 | 后端 **Java 8**；客户端 Dart ^3.11.4 |
| 可维护 | DB 迁移 Flyway；API 版本 `/api/v1` |
| 可观测 | 登录、上传、同步失败率监控（二阶段 Grafana） |

---

## 7. 技术架构

### 7.1 总体架构

```text
┌─────────────────────────────────────────────────────────┐
│  Flutter Client (Windows / Android)                      │
│  presentation → domain → data → core                     │
│  Drift(SQLite) + SyncEngine + FileCache                  │
└───────────────────────────┬─────────────────────────────┘
                            │ HTTPS
┌───────────────────────────▼─────────────────────────────┐
│  Nginx                                                     │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  research-life-api（Java 8 · Spring Boot 2.7 单体）       │
│  ├─ auth          JWT / Refresh / Redis                    │
│  ├─ file-metadata   file_entry / file_object             │
│  ├─ upload        分片会话 / MinIO complete                │
│  ├─ sync          pull / push / change_log               │
│  ├─ note          Markdown 笔记                           │
│  └─ schedule      日程（P1）                              │
└──────┬──────────────┬──────────────┬────────────────────┘
       │              │              │
┌──────▼──────┐ ┌─────▼─────┐ ┌──────▼──────┐
│  MySQL 8.0  │ │  Redis 7  │ │   MinIO     │
│  utf8mb4    │ │  会话/锁  │ │  对象存储   │
└─────────────┘ └───────────┘ └─────────────┘
       │
       │  （二阶段）
┌──────▼──────────────┐
│  RabbitMQ + AI Worker│
└─────────────────────┘
```

### 7.2 后端技术栈（Java 8）

| 组件 | 选型 | 说明 |
| --- | --- | --- |
| 语言 | **Java 8**（1.8） | 项目约束；不使用 Java 17+ 语法 |
| 框架 | **Spring Boot 2.7.x** | 2.x 末代支持 Java 8；**不得使用 Spring Boot 3** |
| 安全 | Spring Security 5.x + JWT | |
| ORM | MyBatis-Plus 3.x | 与 SRS 一致 |
| 连接池 | HikariCP | |
| 迁移 | Flyway | |
| 构建 | Maven | 建议多模块：`common` / `api` |
| API 风格 | REST `/api/v1` | 统一响应体（见 §9） |

### 7.3 中间件（MVP）

| 中间件 | MVP | 用途 |
| --- | --- | --- |
| **MySQL 8.0** | 必须 | 用户、文件元数据、笔记、同步流水、上传会话 |
| **MinIO** | 必须 | PDF 等二进制；S3 协议；客户端预签名直传 |
| **Redis 7** | 必须 | Refresh Token、上传进度、同步 push 锁、限流 |
| **Nginx** | 必须 | TLS、反向代理、上传大小限制 |
| **RabbitMQ** | 否 | 二阶段：AI/OCR/异步任务；MVP 可用 DB 任务表 |
| **Elasticsearch** | 否 | 二阶段全文检索；MVP MySQL FULLTEXT + 客户端本地搜 |

### 7.4 客户端技术栈（演进目标）

| 组件 | 当前 | 迁移目标 |
| --- | --- | --- |
| 状态管理 | ChangeNotifier + InheritedNotifier | 逐步引入 **Riverpod**（新模块优先） |
| 架构 | 扁平 services + 巨型 Controller | **Clean Architecture** 分层 |
| 数据库 | Drift schema v4 | schema v5+：增加 sync 列、outbox 表 |
| HTTP | 仅天气/Ollama | **dio** + 鉴权拦截器 + 统一 ApiResult |
| PDF | pdfrx | 不变；改为 cache 路径打开 |

### 7.5 本地工作区演进

| 路径（现状） | 迁移后 |
| --- | --- |
| `D:\桌面\研究生活\.research_life\` | `{appData}/.research_life/`（`path_provider`，可配置） |
| `D:\桌面\研究生活\资料\` | `{cache}/files/` 本地缓存，非权威 |
| `preferences.json` | **废弃**，统一进 SQLite `preferences` 表 |
| `research_life.sqlite` | 保留 + 同步列 + `sync_outbox` |

---

## 8. 数据设计（后端 MySQL）

### 8.1 设计原则

1. **file_entry（逻辑文件）与 file_object（物理对象）分离**。
2. 所有可同步实体包含：`version`、`updated_at`、`device_id`、`is_deleted`、`client_id`（迁移用 UUID）。
3. 服务端维护 `sync_change_log` 支持按用户增量 Pull。
4. 时间存 **UTC**；`DATETIME(3)`；字符集 `utf8mb4_unicode_ci`。

### 8.2 核心表（逻辑模型）

```text
user                    -- 用户
user_device             -- 设备

file_object             -- content_hash, size, mime, storage_key, upload_status
file_entry              -- 树形条目：user_id, parent_id, name, type, file_object_id, 同步字段
document_profile        -- last_page, page_count, category, tags_json

document_annotation     -- PDF 批注（ rects_json, kind, note, 同步字段）

note                    -- 独立 Markdown 笔记

upload_session          -- 分片上传会话
upload_part             -- 分片 etag

sync_change_log         -- entity_type, entity_id, change_type, version, changed_at
user_sync_cursor        -- 每设备拉取游标（或 Redis 缓存）

schedule                -- 日程（P1）
```

### 8.3 客户端 Drift 扩展（概要）

在现有表基础上增加（所有可同步表）：

- `server_id`（nullable）
- `sync_version`、`sync_state`（clean/dirty/syncing/conflict/error）
- `device_id`、`is_deleted`
- 新表 `sync_outbox`（payload_json, retry_count, created_at）

**PDF 表变更：**

- `path` → `local_cache_path`（可空）
- 新增 `storage_key`、`content_hash`

### 8.4 同步冲突策略（默认）

| 数据类型 | 策略 |
| --- | --- |
| 文件元数据（标题、分类） | Last-Write-Wins（version + updated_at） |
| 阅读进度 last_page | 取较大页码或 LWW |
| PDF 批注 | 按 annotation id 合并；同 id 比 version |
| 二进制 | content_hash 相同跳过上传；不同则新 file_object 版本 |
| 删除 | 软删除优先，多端传播 |

---

## 9. 接口规范

### 9.1 统一响应

```json
{
  "code": 200,
  "msg": "success",
  "data": {}
}
```

### 9.2 MVP 接口清单

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/v1/user/login` | 登录 |
| POST | `/api/v1/user/refresh` | 刷新 Token |
| POST | `/api/v1/user/logout` | 登出 |
| GET | `/api/v1/files` | 列表/子目录 |
| GET | `/api/v1/files/changes` | 增量 Pull（since 游标） |
| POST | `/api/v1/files/sync-push` | 批量 Push |
| POST | `/api/v1/files` | 创建条目 |
| PATCH | `/api/v1/files/{id}` | 更新元数据 |
| DELETE | `/api/v1/files/{id}` | 软删除 |
| POST | `/api/v1/file/upload/init` | 分片上传初始化 |
| POST | `/api/v1/file/upload/complete` | 完成上传 |
| GET | `/api/v1/file/{id}/download-url` | 预签名下载 |
| GET/POST/PATCH/DELETE | `/api/v1/notes...` | 笔记 CRUD |
| GET/POST | `/api/v1/documents/{id}/annotations` | 批注同步 |

### 9.3 文件上传流程

```text
1. Client → init（文件名、大小、hash）→ upload_id + presigned URLs
2. Client → MinIO PUT parts
3. Client → complete → 绑定 file_object → 返回 file_entry
4. 写 sync_change_log
```

小文件（如 < 10MB）允许单步 presigned PUT（配置项）。

---

## 10. 客户端架构重构需求

### 10.1 必须拆分的模块

| 现状 | 目标 |
| --- | --- |
| `ResearchLifeController` 3300+ 行 | 按域拆分：`AuthController`、`SyncController`、`PdfLibraryController`、`AnalysisController` 等 |
| UI 直接 `File(document.path)` | `PdfReaderRepository.open(entry)` → cache 或下载 |
| 无 Repository 接口 | `FileRepository`、`NoteRepository`、`AuthRepository` 抽象 local/remote |

### 10.2 新增 core 模块

```text
lib/core/
  network/     api_client, interceptors, api_result
  auth/        token_storage, session
  sync/        outbox, pull_scheduler, conflict_resolver
```

### 10.3 依赖新增（规划）

- `dio`（HTTP）
- `flutter_secure_storage`（Token）
- `connectivity_plus`（联网状态，可选）
- 保留：`drift`、`pdfrx`、`http`（Ollama 可用 dio 统一）

---

## 11. 数据迁移方案

### 11.1 迁移阶段

| 阶段 | 内容 | 产出 |
| --- | --- | --- |
| **0** | API 契约 + Drift sync 列 + Repository 接口 | 可联调骨架 |
| **1** | 登录 + Pull 只读云文件列表 | 验证模型 |
| **2** | 迁移向导：上传本地 PDF + 批注 | 用户数据上云 |
| **3** | 双向增量同步 | 多设备 |
| **4** | 笔记/日程上云 | MVP 完整 |
| **5** | Android 客户端 | 平台扩展 |

### 11.2 一次性迁移向导（FILE/SYNC）

**触发：** 设置 →「云端迁移」或首次登录后。

**步骤：**

1. 扫描本地 `PdfLibraryDocuments` + `资料/**/*.pdf`。
2. 对每个文件：计算 SHA-256 → `upload/init` → 上传 → `complete`。
3. 若云端已有同 hash：仅绑定 `server_id`。
4. 迁移 `PdfLibraryAnnotations`（映射新 `file_entry_id`）。
5. 写本地 `server_id`、`storage_key`、`local_cache_path`。
6. 生成报告：成功 / 跳过 / 失败（可重试）。
7. **迁移前强制本地备份**（现有 `BackupService`）。

### 11.3 回滚

- 保留迁移前 SQLite 与 `资料/` 快照。
- 设置页提供「仅使用本地数据」开关（若保留离线模式）。

---

## 12. 待决策项（评审时确认）

| # | 议题 | 建议默认 |
| --- | --- | --- |
| D1 | 未登录是否保留完整本地模式 | **是**（科研离线场景） |
| D2 | 同用户文件 content_hash 去重 | **是** |
| D3 | MinIO 对象物理删除延迟 | 软删后 **30～90 天** GC |
| D4 | Sessions/周记是否上云 | V1.0 **否**；仅文件+笔记 |
| D5 | 产品对外名称 | 对内 `research_life`，对外「研LIFE」 |
| D6 | Spring Boot 2.7 锁定 Java 8 | **是**；升级 Java 11+ 单独立项 |

---

## 13. 里程碑与交付物

### 13.1 里程碑

| 里程碑 | 时间（建议） | 交付 |
| --- | --- | --- |
| M0 | 第 1-2 周 | PRD 评审、API 草案、DDL 草案、Drift v5 设计 |
| M1 | 第 3-5 周 | 后端 auth + file CRUD + MinIO 上传；客户端登录 + Repository 抽象 |
| M2 | 第 6-8 周 | 迁移向导 + PDF 同步 + 阅读 cache；Windows 发版 |
| M3 | 第 9-10 周 | 笔记 API + 客户端笔记页；增量同步稳定化 |
| M4 | 第 11-12 周 | Android MVP、日程同步（可选）、文档与测试 |

### 13.2 文档交付物

| 文档 | 负责人 |
| --- | --- |
| API 设计（OpenAPI） | 后端 |
| 数据库 DDL + Flyway | 后端 |
| 客户端同步状态机 | Flutter |
| 更新 `user_guide.md` | 产品 |
| 部署手册（Docker Compose） | 运维 |

---

## 14. 验收标准

### 14.1 认证

- [ ] 注册/登录/刷新/登出全流程通过
- [ ] 多设备登录可列举设备并踢下线（P1）

### 14.2 文件与阅读

- [ ] Windows 导入 PDF → 上传 MinIO → 另一台设备登录 Pull 后可下载阅读
- [ ] 批注在一端新增，另一端 Pull 后可见
- [ ] 离线编辑 PDF 元数据，联网后 Push 成功
- [ ] 删除为软删除，多端一致

### 14.3 迁移

- [ ] 现有本地库（≥10 个 PDF）迁移向导成功率 ≥ 99%
- [ ] 迁移失败可重试且不损坏本地库
- [ ] 迁移前备份可恢复

### 14.4 周分析（回归）

- [ ] Ollama 可用时本地 LLM 分析成功
- [ ] Ollama 不可用时规则兜底，提示明确
- [ ] 确认结果后日历/人物/历史正常（本地）

### 14.5 设置页

- [ ] 新 section 可搜索、可目录跳转（符合 guidelines）
- [ ] 同步状态、迁移入口可见

### 14.6 非功能

- [ ] 核心 API 在 Java 8 环境部署运行
- [ ] 全链路 HTTPS；Token 不在日志明文打印

---

## 15. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| `ResearchLifeController` 拆分工作量大 | 延期 | 按域渐进拆；新功能只写新层 |
| Java 8 / Spring Boot 2.7 生态老化 | 安全与依赖 | 锁定版本；规划 Java 11 升级路线 |
| 大 PDF 上传失败 | 数据丢失 | 分片+断点；迁移可重试；保留本地副本 |
| 路径绑定历史数据 | 迁移失败 | 双 ID；迁移向导；不删旧 path 直至成功 |
| preferences 双轨 | 设置丢失 | 迁移脚本合并到 SQLite |
| pdfrx 跨平台差异 | Android 体验 | Android 列入 M4，提前 spike |

---

## 16. 附录

### 16.1 现有功能基线（用户文档摘要）

详见 `user_guide.md`：首页天气、日历周报、校园地图、PDF 阅读标注、周分析、人物关系、历史、设置（含 Ollama、桌宠、备份）。

### 16.2 本地 LLM 周分析规范摘要

详见 `local_weekly_analysis_ollama.md`：

- Ollama `http://localhost:11434/api/chat`
- 默认模型 `qwen3:8b`；结构化 JSON 输出；Dart 端校验；规则兜底。

### 16.3 设置页规范摘要

详见 `settings_page_guidelines.md`：Section 注册表、五类 category、搜索与目录联动。

### 16.4 项目技术上下文

详见 `project_context_for_consulting.md`：目录结构、schema v4、表清单、测试建议。

### 16.5 部署组件（Docker Compose MVP）

```text
services:
  nginx
  research-life-api   # Java 8
  mysql:8.0
  redis:7
  minio
```

### 16.6 术语表

| 术语 | 含义 |
| --- | --- |
| file_entry | 用户可见文件/文件夹节点 |
| file_object | MinIO 中二进制对象 |
| Outbox | 待同步的本地写操作队列 |
| client_id | 客户端生成的 UUID，用于首次 Push 幂等 |
| storage_key | MinIO 对象键，非文件系统路径 |

---

## 17. 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| V2.0 | 2026-05-15 | 初版：整合 SRS、架构讨论、现有 docs，定义云迁移 PRD；后端 Java 8 |

---

**下一步建议：** 评审 §12 决策项 → 输出《API 设计说明书》与《Drift Schema V5 迁移说明》→ 启动 M0。
