#!/usr/bin/env bash
# 打包 SysPulse 为 .app（本地自用，无遥测、无权限申请）
set -euo pipefail
cd "$(dirname "$0")"

# 缓存重定向到项目内（受限环境需要，普通终端无副作用）
mkdir -p .tmp .build
export TMPDIR="$PWD/.tmp" TMP="$PWD/.tmp"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
export SWIFTPM_CACHEDIR_OVERRIDE="$PWD/.swiftpm-cache"

APP="SysPulse.app"
BIN=".build/release/SysPulse"

echo "==> 编译 release ..."
swift build --disable-sandbox -c release --scratch-path .build

echo "==> 打包 $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SysPulse"

# 应用图标（若已生成）
ICON="Resources/AppIcon.icns"
if [ -f "$ICON" ]; then
  cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SysPulse</string>
    <key>CFBundleDisplayName</key><string>SysPulse</string>
    <key>CFBundleIdentifier</key><string>local.syspulse</string>
    <key>CFBundleExecutable</key><string>SysPulse</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>1.0.0</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Apple Silicon 二进制必须签名（临时签名，本机运行即可）
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "完成：$APP"
echo "运行：open \"$PWD/$APP\"   （或直接双击）"
