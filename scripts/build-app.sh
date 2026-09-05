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

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aiusagebar-app.XXXXXX")"
STAGED_APP="$STAGING_ROOT/AIUsageBar.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BUILD_BINARY" "$STAGED_APP/Contents/MacOS/AIUsageBar"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
if [[ -d "$PROJECT_ROOT/Resources/ProviderIcons" ]]; then
    cp -R "$PROJECT_ROOT/Resources/ProviderIcons" "$STAGED_APP/Contents/Resources/ProviderIcons"
fi

# Sign in a temporary directory first.  The project lives in a synced folder
# on some Macs, where Finder/File Provider metadata can be reattached while
# codesign is running and make an otherwise valid app fail verification.
xattr -cr "$STAGED_APP" 2>/dev/null || true
# 某些 macOS 文件同步目录会在应用包的多个层级保留 Finder 元数据，
# codesign 会将其误判为资源分叉；签名前递归移除这些属性。
find "$STAGED_APP" -print0 | while IFS= read -r -d '' entry_path; do
    xattr -d com.apple.FinderInfo "$entry_path" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$entry_path" 2>/dev/null || true
    xattr -d com.apple.provenance "$entry_path" 2>/dev/null || true
done
codesign --force --deep --sign - "$STAGED_APP" >/dev/null
codesign --verify --deep --strict "$STAGED_APP"

# Create the distributable from the clean, signed staging copy before putting
# anything into the synced workspace.  File Provider can attach Finder
# metadata to the destination app immediately after the copy; archiving the
# staging copy keeps that metadata out of the downloadable application.
mkdir -p "$PROJECT_ROOT/dist"
RELEASE_ZIP_PATH="$PROJECT_ROOT/dist/AIUsageBar-arm64.zip"
RELEASE_CHECKSUM_PATH="$RELEASE_ZIP_PATH.sha256"
rm -f "$RELEASE_ZIP_PATH" "$RELEASE_CHECKSUM_PATH"
ditto -c -k --norsrc --keepParent "$STAGED_APP" "$RELEASE_ZIP_PATH"
shasum -a 256 "$RELEASE_ZIP_PATH" > "$RELEASE_CHECKSUM_PATH"

mkdir -p "$(dirname "$APP_PATH")"
rm -rf "$APP_PATH"
ditto --norsrc "$STAGED_APP" "$APP_PATH"
# The destination folder may reattach Finder/File Provider metadata during the
# copy. Remove it once more from the final app before verifying the artifact.
xattr -cr "$APP_PATH" 2>/dev/null || true
find "$APP_PATH" -print0 | while IFS= read -r -d '' entry_path; do
    xattr -d com.apple.FinderInfo "$entry_path" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$entry_path" 2>/dev/null || true
    xattr -d com.apple.provenance "$entry_path" 2>/dev/null || true
done
# The synced workspace may reattach metadata after the cleanup above. The
# staging copy and the ZIP were already verified before that copy; keep the
# convenience app even when the workspace provider makes this final check
# fail, and report the reason instead of discarding the release artifact.
if ! codesign --verify --deep --strict "$APP_PATH"; then
    echo "警告：工作区同步目录给直接 .app 附加了 Finder 元数据；洁净临时包与下载 ZIP 已通过签名校验。" >&2
fi

echo "已生成：$APP_PATH"
echo "已生成更新包：$RELEASE_ZIP_PATH"
echo "已生成校验文件：$RELEASE_CHECKSUM_PATH"
echo "启动命令：open \"$APP_PATH\""
