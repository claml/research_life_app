# Research Life 快速部署说明

Research Life 是一个 Flutter Windows 桌面应用，用于整理研究生日常记录、周报事项、人物关系、历史记录和校园地图数据。

本文档面向“尽快在 Windows 机器上跑起来并打包给别人用”的场景。

## 1. 环境要求

- 操作系统：Windows 10 / Windows 11，建议 x64
- Flutter：已安装 Flutter SDK，并启用 Windows 桌面开发
- Dart SDK：满足 `pubspec.yaml` 中的 `^3.11.4`
- 构建工具：Visual Studio 2022，安装 `Desktop development with C++` 工作负载
- 运行时：Windows 自带 `winsqlite3.dll`，建议使用较新的 Windows 10/11

检查环境：

```powershell
flutter doctor
flutter config --enable-windows-desktop
flutter devices
```

`flutter doctor` 中 Windows toolchain 不应有阻塞性错误。

## 2. 获取依赖

在项目根目录执行：

```powershell
cd D:\桌面\研究生活\应用
flutter pub get
```

协作开发时注意：

- 日常同步代码后只执行 `flutter pub get`，不要随手执行 `flutter pub upgrade`。
- `pubspec.lock` 必须提交到仓库，保证团队解析到同一套依赖。
- `pdfrx` 涉及 Windows native/PDFium 构建，当前固定为 `2.2.24`，不要改回 `^2.2.24` 或升级到新版本后直接提交。
- 不要提交 `build/`、`.dart_tool/`、`.flutter-plugins-dependencies` 等本机生成文件。
- 修改 `pubspec.yaml` 或 `pubspec.lock` 后，至少执行一次 `flutter build windows --debug` 验证 Windows 构建。

如果修改过 Drift 数据库表结构，重新生成数据库代码：

```powershell
dart run build_runner build --delete-conflicting-outputs
```

当前仓库已经包含 `lib/services/database/app_database.g.dart`，正常部署通常不需要重新生成。

## 3. 本地运行

```powershell
flutter run -d windows
```

如果需要先跑测试：

```powershell
flutter test
```

## 4. 构建 Release 包

```powershell
flutter build windows --release
```

构建完成后，发布目录为：

```text
build\windows\x64\runner\Release
```

主程序为：

```text
build\windows\x64\runner\Release\research_life.exe
```

## 5. 部署给其他 Windows 电脑

不要只复制 `research_life.exe`。Flutter Windows 应用依赖同目录下的 DLL、`data` 资源目录和插件产物。

推荐做法：

1. 构建 Release：

   ```powershell
   flutter build windows --release
   ```

2. 打包整个 Release 目录：

   ```powershell
   Compress-Archive `
     -Path build\windows\x64\runner\Release\* `
     -DestinationPath research_life_windows_release.zip `
     -Force
   ```

3. 在目标电脑上解压 `research_life_windows_release.zip`
4. 双击运行 `research_life.exe`

如果目标电脑提示缺少运行库，安装 Microsoft Visual C++ Redistributable 2015-2022 x64 后重试。

## 6. 本地数据目录

应用数据默认写入：

```text
D:\桌面\研究生活\.research_life
```

主要文件：

- `research_life.sqlite`：SQLite 数据库
- `research_life.sqlite-wal` / `research_life.sqlite-shm`：SQLite 运行辅助文件
- `preferences.json`：本地偏好设置
- `database_backups\`：数据库备份目录

迁移电脑时，如果需要带走历史记录，请在关闭应用后复制整个目录：

```text
D:\桌面\研究生活\.research_life
```

注意：复制数据库时应同时复制 `.sqlite`、`.sqlite-wal`、`.sqlite-shm` 文件。

## 7. 首页图片资源

内置资源位于：

```text
assets\logo\searchlife_logo.png
assets\campus_map\
```

应用运行后会在本地数据目录中维护首页图片文件夹。支持的首页图片命名：

```text
research_wall.png / .jpg / .jpeg / .webp / .bmp
life_wall.png / .jpg / .jpeg / .webp / .bmp
```

## 8. 可导入文件

当前导入服务支持：

- `.txt`
- `.md`
- `.docx`

暂不支持：

- `.doc`
- `.xls`
- `.xlsx`

文本文件支持 UTF-8、UTF-16 和 GBK 编码。

## 9. 常见问题

### 找不到 Windows 设备

执行：

```powershell
flutter config --enable-windows-desktop
flutter doctor
```

确认 Visual Studio C++ 桌面开发环境已安装。

### Release 包在别人电脑上打不开

确认复制的是整个目录：

```text
build\windows\x64\runner\Release
```

不要只复制 exe。必要时安装 Microsoft Visual C++ Redistributable 2015-2022 x64。

### 数据没有同步到新电脑

确认已复制：

```text
D:\桌面\研究生活\.research_life
```

并且复制时应用已经关闭。

### 修改数据库后编译报错

重新生成 Drift 代码：

```powershell
dart run build_runner build --delete-conflicting-outputs
```

然后重新构建：

```powershell
flutter build windows --release
```

### PDFium / native assets 构建报错

如果出现类似下面的错误：

```text
Building native assets failed
file COPY cannot find ... pdfium.dll: File exists.
file COPY cannot find ... include: File exists.
```

通常是本机 Windows 构建缓存中的 PDFium 文件状态冲突，不是业务代码问题。关闭正在运行的应用和 IDE 构建任务后，在 `应用` 目录执行：

```powershell
flutter clean
Remove-Item -Recurse -Force build\windows\x64\pdfium -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force build\windows\x64\.lib -ErrorAction SilentlyContinue
flutter pub get
flutter run -d windows
```

如果错误提示需要创建符号链接，请在 Windows 设置中开启“开发者模式”，重启终端后重新构建。

如果错误提示下载 PDFium 失败，先确认没有把 `pdfrx` 升级到未验证的新版本；本项目当前使用 `pdfrx 2.2.24`。

## 10. 最短部署流程

只想快速打包发布时，执行：

```powershell
cd D:\桌面\研究生活\应用
flutter pub get
flutter test
flutter build windows --release
Compress-Archive `
  -Path build\windows\x64\runner\Release\* `
  -DestinationPath research_life_windows_release.zip `
  -Force
```

把生成的 `research_life_windows_release.zip` 发给目标电脑，解压后运行 `research_life.exe`。
