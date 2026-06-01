#!/bin/bash
set -e

cd "$(dirname "$0")"

BINARY=".build/release/cc-usage-widget"
APP="CCUsageWidget.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# 이전 빌드 정리
rm -rf "$APP"

# .app 번들 구조 생성
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# 바이너리 복사
cp "$BINARY" "$MACOS/"

# Info.plist 생성
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>CC Usage Widget</string>
    <key>CFBundleExecutable</key>
    <string>cc-usage-widget</string>
    <key>CFBundleIdentifier</key>
    <string>com.yhzion.cc-usage-widget</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CCUsageWidget</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSBackgroundOnly</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
</dict>
</plist>
PLIST

# PkgInfo 생성
printf 'APPL????' > "$CONTENTS/PkgInfo"

# 아이콘 생성 (SF Symbols 기반, 터미널에서 텍스트 아이콘 대신 간단한 플레이스홀더)
# 실제로는 .icns 파일이 필요하지만, 여기서는 system default 사용

# 서명 (Ad-hoc)
codesign --force --deep --sign - "$APP"

# Gatekeeper 우회
xattr -cr "$APP"

echo "✅ Packaged: $APP"
echo ""
echo "🚀 Run:"
echo "   open $APP"
