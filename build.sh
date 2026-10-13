#!/bin/bash
# Builds build/NoSleepLid.app from Sources/ (needs Xcode Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")"
APP="build/NoSleepLid.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O -o "$APP/Contents/MacOS/NoSleepLid" Sources/NoSleepLid.swift -framework AppKit -framework IOKit
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.nelsonfelipebueno.nosleeplid</string>
  <key>CFBundleName</key><string>NoSleepLid</string>
  <key>CFBundleExecutable</key><string>NoSleepLid</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" 2>/dev/null
echo "built: $APP"
