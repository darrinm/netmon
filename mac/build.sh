#!/usr/bin/env bash
# Build the Netmon.app bundle from the SPM target.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Netmon"
BUNDLE_ID="com.massena.netmon"
CONFIG="${CONFIG:-release}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/$CONFIG/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

cp "Netmon/App/Info.plist" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}"  "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME}"        "${CONTENTS_DIR}/Info.plist"

if [ -f "Netmon/Resources/AppIcon.icns" ]; then
    cp "Netmon/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Prefer Developer ID for distributable builds; fall back to local Apple Development;
# ad-hoc sign as a last resort so the binary still runs locally.
SIGN_IDENTITY=""
if [ "${SIGN:-}" = "developer-id" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')
fi

if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --options runtime --sign "$SIGN_IDENTITY" \
        --entitlements "Netmon/App/Netmon.entitlements" "$APP_DIR"
    echo "Signed with: $SIGN_IDENTITY"
else
    codesign --force --sign - --entitlements "Netmon/App/Netmon.entitlements" "$APP_DIR"
    echo "Signed ad-hoc (no codesigning identity found)"
fi

echo
echo "Build complete: $APP_DIR"
echo "Run:  open \"$APP_DIR\""
