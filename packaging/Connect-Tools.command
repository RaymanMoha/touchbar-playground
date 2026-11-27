#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="/Applications/Touch Bar Playground.app"
if [ ! -x "$APP/Contents/MacOS/TouchBarPlayground" ]; then
  APP="$HOME/Applications/Touch Bar Playground.app"
fi
if [ ! -x "$APP/Contents/MacOS/TouchBarPlayground" ]; then
  echo 'First drag Touch Bar Playground.app to Applications, then run this again.'
  read -r -p 'Press Return to close. ' unused
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1 || ! python3 --version >/dev/null 2>&1; then
  echo 'Optional Claude/Antigravity connections require Python 3: https://www.python.org/downloads/macos/'
  read -r -p 'Press Return to close. ' unused
  exit 1
fi
python3 connect-tools.py --app "$APP"
echo 'Connected. Restart existing Claude Code and Antigravity sessions to load the hooks.'
read -r -p 'Press Return to close. ' unused
