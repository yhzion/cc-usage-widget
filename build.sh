#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "🔨 Generating Xcode project..."
xcodegen generate -q

echo "🔨 Building all targets..."
xcodebuild -project CCUsageWidget.xcodeproj \
  -alltargets \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP="build/Debug/CCUsageWidget.app"
APPEX="build/Debug/CCUsageWidgetExtension.appex"
PLUGINS="$APP/Contents/PlugIns"

echo "📦 Embedding Widget Extension..."
mkdir -p "$PLUGINS"
cp -R "$APPEX" "$PLUGINS/"

echo "✅ Done: $APP"
echo ""
echo "🚀 Launch the host app once to sync the OAuth token:"
echo "   open \"$APP\""
echo ""
echo "🖥️  Then add the widget to your desktop via System Settings > Desktop & Dock > Widgets"
