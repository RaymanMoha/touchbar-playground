#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x "Touch Bar Playground.app/Contents/MacOS/TouchBarPlayground" ]; then
  ./build.sh
fi
DEST="$HOME/Applications/Touch Bar Playground.app"
mkdir -p "$HOME/Applications"
ditto "Touch Bar Playground.app" "$DEST"
python3 scripts/connect-tools.py --app "$DEST"
open "$DEST"
echo "Installed: $DEST"
