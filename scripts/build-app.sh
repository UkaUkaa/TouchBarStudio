#!/bin/zsh
# Builds "TouchBar Studio.app" into ./build using SwiftPM (works with the Command Line
# Tools alone; full Xcode is not required). Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/TouchBar Studio.app"

swift build -c "$CONFIG" --product TouchBarStudio
BIN="$(swift build -c "$CONFIG" --show-bin-path)/TouchBarStudio"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TouchBarStudio"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature (no Developer ID available). Use your own identity with:
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
