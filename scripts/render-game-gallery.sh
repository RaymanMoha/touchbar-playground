#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/game-gallery docs/images
cp scripts/GameGallery.swift .build/game-gallery/main.swift
SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macosx13.0 -sdk "$SDK" \
  -framework AppKit -framework CryptoKit -framework ImageIO \
  Sources/Actions.swift Sources/Model.swift Sources/GeminiSprite.swift Sources/PlaygroundView.swift Sources/Battle.swift \
  .build/game-gallery/main.swift -o .build/game-gallery/render-game-gallery
.build/game-gallery/render-game-gallery "$PWD/docs/images"
