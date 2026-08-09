#!/usr/bin/env bash
# ============================================================
# 研LIFE(研究生活) 一键打包脚本
# 用法: bash build-release.sh [版本号, 默认 v1.0]
# 产物:
#   - D:\桌面\研LIFE\            可直接双击的桌面版
#   - D:\Desktop\研LIFE.lnk      桌面快捷方式
#   - D:\Vibe Coding\研究生活\dist\研LIFE-桌面版-<版本>.tar.gz  备份包
# ============================================================
set -euo pipefail

VER="${1:-v1.0}"
SRC="/d/Vibe Coding/研究生活/research-life-app/front_app"
BUILD="/d/research_life_build"
DEST="/d/Desktop/研LIFE"
DIST="/d/Vibe Coding/研究生活/dist"
PROJ_ROOT="/d/Vibe Coding/研究生活"

echo "== [0/6] 关闭运行中的实例 =="
taskkill //F //IM research_life.exe > /dev/null 2>&1 || true
sleep 1

echo "== [1/6] 同步源码到英文构建路径(避免中文路径 MSVC 编码问题) =="
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$SRC"
for d in lib windows test assets; do
  cp -r "$d" "$BUILD/"
done
cp pubspec.yaml pubspec.lock analysis_options.yaml README.md CHANGELOG.md "$BUILD/"

echo "== [2/6] 恢复 pdfium 缓存(跳过重复下载) =="
mkdir -p "$BUILD/build/windows/x64"
cp -r "$SRC/build/windows/x64/pdfium" "$BUILD/build/windows/x64/"

echo "== [3/6] release 构建(约 1-2 分钟) =="
cd "$BUILD"
flutter build windows --release

echo "== [4/6] 更新桌面版 =="
rm -rf "$DEST"
cp -r "$BUILD/build/windows/x64/runner/Release" "$DEST"
cat > "$DEST/使用说明.txt" <<EOF
研LIFE(研究生活)桌面版 v${VER} 使用说明
========================================

【启动方式】
双击 research_life.exe 即可启动。
（可右键 research_life.exe → 发送到 → 桌面快捷方式，以后直接从桌面打开）

【数据位置】
所有数据保存在 D:\桌面\研究生活\ 目录下（.research_life 数据库、图片等），
与开发版共用，卸载/删除本文件夹不影响数据。

【系统要求】
Windows 10/11 64 位。
EOF

echo "== [5/6] 重建桌面快捷方式 =="
powershell -NoProfile -Command "
\$ws = New-Object -ComObject WScript.Shell
\$lnk = \$ws.CreateShortcut('D:\Desktop\研LIFE.lnk')
\$lnk.TargetPath = 'D:\桌面\研LIFE\research_life.exe'
\$lnk.WorkingDirectory = 'D:\桌面\研LIFE'
\$lnk.Description = '研LIFE 研究生活'
\$lnk.Save()
"

echo "== [6/6] 生成备份包 =="
mkdir -p "$DIST"
cd /d/桌面
tar -czf "$DIST/研LIFE-桌面版-$VER.tar.gz" 研LIFE

echo ""
echo "✅ 打包完成:"
echo "   桌面版:    $DEST\\research_life.exe"
echo "   快捷方式:  D:\\Desktop\\研LIFE.lnk"
echo "   备份包:    $DIST\\研LIFE-桌面版-$VER.tar.gz"
echo "   数据目录:  D:\\桌面\\研究生活\\(自动共用,无需备份)"
