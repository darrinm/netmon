#!/usr/bin/env bash
# Submit a DMG to Apple notary service and staple the ticket on success.
#
# Requires a keychain profile created once with:
#   xcrun notarytool store-credentials NetmonNotary \
#       --apple-id you@example.com \
#       --team-id YOURTEAMID \
#       --password APP_SPECIFIC_PASSWORD
#
# Profile name can be overridden with NOTARY_PROFILE.
set -euo pipefail

DMG="${1:-}"
if [ -z "$DMG" ] || [ ! -f "$DMG" ]; then
  echo "Usage: $0 path/to/Netmon-X.Y.Z.dmg" >&2
  exit 1
fi

PROFILE="${NOTARY_PROFILE:-NetmonNotary}"

echo "==> notarytool submit $DMG (profile: $PROFILE)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> stapler staple $DMG"
xcrun stapler staple "$DMG"

echo "==> spctl assess (Gatekeeper)"
spctl -a -t open --context context:primary-signature -v "$DMG"

echo
echo "Notarized + stapled: $DMG"
