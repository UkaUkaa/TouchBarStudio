#!/bin/zsh
# Builds a distributable release: a universal (Apple silicon + Intel) app packed as a
# DMG and a ZIP, plus SHA-256 checksums, in ./dist.
# Usage: scripts/release.sh [version]   (defaults to CFBundleShortVersionString)
set -euo pipefail
cd "$(dirname "$0")/.."
PLIST=Support/Info.plist
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")}"
NAME="TouchBar Studio"
APP="build/$NAME.app"
DIST="dist"
BASE="TouchBarStudio-$VERSION"

# Keep Info.plist in step with the requested version.
if [[ "$VERSION" != "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  BUILD=$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST") + 1 ))
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
fi

scripts/test.sh
UNIVERSAL=1 scripts/build-app.sh release
ARCHS="$(lipo -archs "$APP/Contents/MacOS/TouchBarStudio")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo "Not universal: $ARCHS" >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST"

# DMG: the app, a link to /Applications for drag-and-drop install, and the license.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp LICENSE "$STAGE/LICENSE.txt"
hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov "$DIST/$BASE.dmg"

# ZIP: ditto keeps the bundle's extended attributes and signature intact.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$BASE.zip"

(cd "$DIST" && shasum -a 256 "$BASE.dmg" "$BASE.zip" > SHA256SUMS.txt)
echo "Release $VERSION:"
ls -lh "$DIST"
