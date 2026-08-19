#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

BUILD_BINARY=""
if swift build -c release --product AIUsageBar; then
    BUILD_BINARY="$(swift build -c release --show-bin-path)/AIUsageBar"
else
    echo "SwiftPM 构建未完成，尝试使用本机 Swift 直接编译菜单栏应用。" >&2
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
    FALLBACK_BINARY="$PROJECT_ROOT/.build/AIUsageBar-direct"
    mkdir -p "$PROJECT_ROOT/.build-module-cache"
    swiftc \
        -target arm64-apple-macosx13.0 \
        -sdk "$SDK_PATH" \
        -module-cache-path "$PROJECT_ROOT/.build-module-cache" \
        -parse-as-library \
        Sources/AIUsageBar/*.swift \
        -o "$FALLBACK_BINARY"
    BUILD_BINARY="$FALLBACK_BINARY"
fi

APP_PATH="$PROJECT_ROOT/dist/AIUsageBar.app"

if [[ ! -x "$BUILD_BINARY" ]]; then
    echo "找不到 Release 构建产物：$BUILD_BINARY" >&2
    exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_BINARY" "$APP_PATH/Contents/MacOS/AIUsageBar"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
xattr -cr "$APP_PATH" 2>/dev/null || true
# 某些 macOS 文件同步目录会在应用包的多个层级保留 Finder 元数据，
# codesign 会将其误判为资源分叉；签名前递归移除这些属性。
find "$APP_PATH" -print0 | while IFS= read -r -d '' entry_path; do
    xattr -d com.apple.FinderInfo "$entry_path" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$entry_path" 2>/dev/null || true
    xattr -d com.apple.provenance "$entry_path" 2>/dev/null || true
done
codesign --force --deep --sign - "$APP_PATH" >/dev/null

echo "已生成：$APP_PATH"
echo "启动命令：open \"$APP_PATH\""
