#!/bin/zsh
# Builds "TouchBar Studio.app" into ./build using SwiftPM (works with the Command Line
# Tools alone; full Xcode is not required). Usage: scripts/build-app.sh [debug|release]
# UNIVERSAL=1 builds arm64 + x86_64 (Intel MacBook Pros with a Touch Bar) and merges them.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/TouchBar Studio.app"

if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  # Each architecture gets its own scratch path; lipo merges the two executables.
  for ARCH in arm64 x86_64; do
    swift build -c "$CONFIG" --product TouchBarStudio \
      --triple "$ARCH-apple-macosx14.0" --scratch-path ".build/$ARCH"
  done
  BIN="build/TouchBarStudio-universal"
  mkdir -p build
  lipo -create -output "$BIN" \
    ".build/arm64/$CONFIG/TouchBarStudio" ".build/x86_64/$CONFIG/TouchBarStudio"
else
  swift build -c "$CONFIG" --product TouchBarStudio
  BIN="$(swift build -c "$CONFIG" --show-bin-path)/TouchBarStudio"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TouchBarStudio"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"

# Ad-hoc signature (no Developer ID available). Use your own identity with:
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
