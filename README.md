# 研究生活 (Research Life)

以研究生日常管理为主的综合性 Windows 桌面应用，集成虚拟桌宠陪伴功能。

## 项目构成

本项目由两个子项目组成，通过本地 IPC (HTTP, 端口 18765) 互联：

| 子项目 | 说明  | 技术栈 |
| --- | --- | --- |
| **研究生活 (应用/)** | Flutter 桌面应用，负责日常记录、周报分析、日历管理、PDF 阅读等 | Flutter / Dart / Drift (SQLite) |
| **虚拟桌宠 (VPet-main/)** | WPF 桌宠模拟器，提供互动投喂、动画陪伴、Steam 创意工坊支持 | C# / WPF / .NET 8.0 |

## 功能概览

### 研究生活

* **首页** — 实时时钟、农历显示、天气信息、图片墙
* **周分析** — 自然语言输入自动提取事项、人物和时间，支持 txt/md/docx 文件拖放导入，可对接 Ollama 本地 LLM
* **日历** — 统一日历视图，支持分析记录、手动事件、校历导入
* **校园地图** — 校园地点标注与管理
* **PDF 阅读** — 文献阅读、标注、阅读时长记录
* **人物管理** — 人物关系、合并、别名管理
* **历史记录** — 考古所有历史分析记录
* **设置** — 主题、天气、桌宠、数据备份等偏好

### 虚拟桌宠模拟器

* 32 种 × 4 状态 × 3 类型的丰富动画
* 摸头、提起、喂食等多种互动
* Steam 创意工坊支持，可自定义形象
* 通过 IPC 接收来自研究生活的消息提醒

## 项目结构

    .
    ├── 应用/               # 研究生活 Flutter 应用（主应用）
    │   ├── lib/            #   Dart 源代码
    │   │   ├── main.dart   #     入口
    │   │   ├── app/        #     应用层（Shell、路由）
    │   │   ├── core/       #     核心基础设施（模型、主题、工具）
    │   │   ├── state/      #     全局状态管理
    │   │   ├── features/   #     8 大功能模块
    │   │   ├── services/   #     服务层（数据库、分析、导入、天气、桌宠集成等）
    │   │   └── shared/     #     共享组件
    │   ├── assets/         #   静态资源（Logo、地图底图等）
    │   ├── test/           #   单元测试
    │   └── windows/        #   Windows 原生配置
    ├── VPet-main/          # 虚拟桌宠 WPF 应用
    │   ├── VPet-Simulator.Core/       # 核心库（图形动画）
    │   ├── VPet-Simulator.Windows/    # 桌面端主程序
    │   └── VPet-Simulator.Tool/       # MOD 制作工具
    ├── home_images/        # 首页图片资源
    ├── 桌宠形象/           # 桌宠形象素材
    ├── 周报/               # 周报存档
    └── 资料/               # 个人资料

## 快速开始

### 环境要求

* Windows 10 / 11 (x64)
* [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (Dart SDK ^3.11.4)
* Visual Studio 2022，安装「使用 C++ 的桌面开发」工作负载
* [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)（仅 VPet 需要）

### 运行研究生活

    # 进入应用目录
    cd 应用
    
    # 安装依赖
    flutter pub get
    
    # 运行
    flutter run -d windows

### 构建 Release 包

    cd 应用
    flutter build windows --release

构建产物位于 `应用\build\windows\x64\runner\Release\`，将整个目录打包即可分发。

### 运行虚拟桌宠

用 Visual Studio 打开 `VPet-main\VPet.sln`，选择 `VPet-Simulator.Windows` 项目，按 F5 运行。

## 数据存储

应用运行时数据存储在项目根目录下的 `.research_life/` 中：

* `research_life.sqlite` — SQLite 数据库
* `preferences.json` — 偏好设置
* `database_backups/` — 数据库备份

迁移数据时，请在关闭应用后复制整个 `.research_life/` 目录。

## 主要依赖

### 研究生活 (Flutter)

| 依赖  | 用途  |
| --- | --- |
| drift | ORM / SQLite 数据库 |
| pdfrx | PDF 阅读与标注 |
| archive | 文件归档 |
| charset_converter | 多编码文本导入 |
| desktop_drop | 文件拖放 |

### 虚拟桌宠 (WPF)

| 依赖  | 用途  |
| --- | --- |
| SkiaSharp | 2D 图形渲染 |
| NAudio | 音频播放 |
| LinePutScript | MOD 脚本解析 |
| Panuon.WPF.UI | WPF UI 组件 |

## 更多信息

* 研究生活部署细节见 [应用/README.md](应用/README.md)
* 虚拟桌宠详情见 [VPet-main/README.md](VPet-main/README.md)
