#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP="ClaudeWatchBar"
BUNDLE="${APP}.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/${APP}"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"
[ -f assets/anthropic.png ] && cp assets/anthropic.png "$BUNDLE/Contents/Resources/anthropic.png"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeWatchBar</string>
  <key>CFBundleExecutable</key><string>ClaudeWatchBar</string>
  <key>CFBundleIdentifier</key><string>com.claudewatch.menubar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

# Ad-hoc sign so UNUserNotificationCenter (tappable notifications) works.
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null \
  && echo "Ad-hoc signed ${BUNDLE}" || echo "codesign skipped"

echo "Built ${BUNDLE}"
echo "Run: open ${BUNDLE}"
