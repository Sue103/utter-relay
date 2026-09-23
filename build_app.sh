#!/bin/bash
# VoiceQuickRelay.app を組み立てるビルドスクリプト。
# SwiftPMでリリースビルドし、最小限の.appバンドル構造に詰めてアドホック署名する。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="VoiceQuickRelay"
BUNDLE_DISPLAY_NAME="Utter Relay"
BUNDLE_ID="com.voicequick.relay.mac"
BUILD_DIR=".build/release"
APP_DIR="dist/${BUNDLE_DISPLAY_NAME}.app"

echo "==> swift build -c release"
swift build -c release

echo "==> assembling ${APP_DIR}"
rm -rf "dist"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${BUNDLE_DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${BUNDLE_DISPLAY_NAME}</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>同じWi-Fi内のiPhone/Windowsとクリップボードを同期するために、ローカルネットワークでの通信を使います。</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "${APP_DIR}"

echo "==> done: ${APP_DIR}"
