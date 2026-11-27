#!/bin/bash
# Build release assets without changing any local tool settings or installed app.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--skip-build" ]; then
  shift
  codesign --verify --deep --strict "Touch Bar Playground.app"
  "Touch Bar Playground.app/Contents/MacOS/TouchBarPlayground" --self-test
else
  ./build.sh
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' 'Touch Bar Playground.app/Contents/Info.plist')
OUT="${1:-$PWD/.build/release}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/touchbar-release.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
NAME="Touch-Bar-Playground-${VERSION}-arm64"
PAYLOAD="$STAGE/$NAME"
mkdir -p "$PAYLOAD"
ditto 'Touch Bar Playground.app' "$PAYLOAD/Touch Bar Playground.app"
cp packaging/READ-ME.txt packaging/Connect-Tools.command scripts/connect-tools.py LICENSE THIRD_PARTY_NOTICES.md "$PAYLOAD/"
chmod +x "$PAYLOAD/Connect-Tools.command"
ln -s /Applications "$PAYLOAD/Applications"
codesign --verify --deep --strict --verbose=2 "$PAYLOAD/Touch Bar Playground.app"
hdiutil create -ov -volname "Touch Bar Playground $VERSION" -srcfolder "$PAYLOAD" -format UDZO "$OUT/$NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent "$PAYLOAD" "$OUT/$NAME.zip"
(cd "$OUT" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
echo "Release assets: $OUT"
