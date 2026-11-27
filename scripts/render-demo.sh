#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/demo docs/images
cp scripts/DemoRenderer.swift .build/demo/main.swift
SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macosx13.0 -sdk "$SDK" \
  -framework AppKit -framework CryptoKit -framework ImageIO \
  Sources/Actions.swift Sources/Model.swift Sources/GeminiSprite.swift Sources/PlaygroundView.swift Sources/Battle.swift \
  .build/demo/main.swift -o .build/demo/render-demo
.build/demo/render-demo "$PWD/docs/images"
