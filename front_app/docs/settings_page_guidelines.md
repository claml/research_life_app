# 设置页开发规范

设置页采用“分类 + 搜索 + 目录 + 内容块”的结构。新增设置不要直接把控件追加到页面末尾，必须先定义清晰的信息归属，再进入统一的 section 注册表。

## 结构原则

1. 每个设置块只服务一个明确主题，例如“本地 LLM 周分析”或“主页图片”。
2. 所有设置块必须注册为 `_SettingsSectionSpec`，由注册表驱动搜索、分类计数、目录和内容渲染。
3. 不新增孤立标题、分割线或临时按钮。设置入口必须落在某个 section 内。
4. 高频操作放在 section 的 `trailingBuilder` 或块内首屏区域，低频说明放在块内下方。
5. 新功能优先复用现有行组件，例如 `_SettingsToggleRow`、`_PathRow`、`_ImageManageRow`、`_InfoBanner`、`_CopyableBlock`。

## Section 注册字段

新增 section 时必须填写这些字段：

- `id`：稳定唯一，不随展示文案变化，例如 `analysis.local_llm`。
- `category`：只能从现有 `_SettingsCategory` 中选择；确实需要新增分类时，同时更新分类枚举、图标和规范文档。
- `icon`：使用 Material 图标表达功能语义。
- `title`：短标题，避免超过 8 个汉字。
- `subtitle`：说明当前块负责什么，不写操作教程。
- `keywords`：覆盖用户可能搜索的中文、英文、缩写和内部名称。
- `childBuilder`：渲染实际设置控件。
- `trailingBuilder`：可选，只放当前 section 的主要动作。

## 分类边界

- `appearance`：主题、布局、视觉偏好。
- `analysis`：模型、分析、AI、自动化推理能力。
- `companion`：桌宠和伴随提醒。
- `storage`：路径、文件、数据库、导入导出、本地资源。
- `calendar`：校历、日程来源、校历文本导入。

## 新增设置清单

提交前检查：

1. 新设置能通过标题、同义词和内部名称搜索到。
2. 目录点击能滚动到对应 section。
3. 小屏下搜索栏、分类、目录和设置内容不横向溢出。
4. 异步操作沿用 `_runAsyncAction` 或 `_runSyncAction` 显示反馈。
5. 按钮使用图标加文本；二元选项使用 `_SettingsToggleRow`。
6. 同一 section 内不要混入另一个分类的功能。

## 维护规则

当设置项超过 10 个 section 时，优先拆分大 section，而不是新增二级嵌套卡片。若某个分类超过 5 个 section，再评估是否需要新增分类或拆到独立功能页。
