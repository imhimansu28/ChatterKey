#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="dist/ChatterKey.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ChatterKey "$APP/Contents/MacOS/ChatterKey"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ChatterKey</string>
  <key>CFBundleIdentifier</key><string>app.chatterkey.macos</string>
  <key>CFBundleName</key><string>ChatterKey</string>
  <key>CFBundleDisplayName</key><string>ChatterKey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.4</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>ChatterKey needs microphone access to turn your voice into text.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - --requirements '=designated => identifier "app.chatterkey.macos"' "$APP"
echo "Created $APP"
