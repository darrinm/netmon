#!/usr/bin/env bash
# Package build/Netmon.app into a notarizable DMG.
# Usage: scripts/make-dmg.sh [VERSION]
#   VERSION defaults to whatever CFBundleShortVersionString is in the built app.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Netmon.app"
if [ ! -d "$APP" ]; then
  echo "No build/Netmon.app — run ./build.sh first" >&2
  exit 1
fi

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG_NAME="Netmon-${VERSION}.dmg"
DMG_PATH="build/${DMG_NAME}"

STAGE="$(mktemp -d -t netmon-dmg)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Netmon.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Netmon ${VERSION}" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Sign the DMG itself so notarytool accepts it.
SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -n "$SIGN_IDENTITY" ]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
else
  echo "WARNING: no Developer ID Application identity found — DMG is unsigned" >&2
fi

echo
echo "DMG: $DMG_PATH"
echo "Next: scripts/notarize.sh \"$DMG_PATH\""
