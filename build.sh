#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/Touch Bar Playground.app"
BUILD="$PWD/.build"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun clang -fobjc-arc -mmacosx-version-min=13.0 -isysroot "$SDK" -c Sources/TouchBarBridge.m -o "$BUILD/TouchBarBridge.o"
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macosx13.0 -sdk "$SDK" -framework AppKit -framework CryptoKit -import-objc-header Sources/TouchBarBridge.h Sources/Actions.swift Sources/Model.swift Sources/GeminiSprite.swift Sources/PlaygroundView.swift Sources/Battle.swift Sources/App.swift Sources/main.swift "$BUILD/TouchBarBridge.o" -o "$APP/Contents/MacOS/TouchBarPlayground"
cp Assets/gemini-chan.png Assets/gemini-chan.json Assets/antigravity-pet-LICENSE.txt "$APP/Contents/Resources/"
cp Assets/README.md "$APP/Contents/Resources/Gemini-chan-Credits.md"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TouchBarPlayground</string>
<key>CFBundleIdentifier</key><string>local.moses.touchbarplayground</string>
<key>CFBundleName</key><string>Touch Bar Playground</string>
<key>CFBundleDisplayName</key><string>Touch Bar Playground</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/TouchBarPlayground" --self-test
echo "Built: $APP"
