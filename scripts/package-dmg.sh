#!/usr/bin/env bash
# Developer ID app + drag-to-Applications DMG.
# TIMESTAMP=1 is required for Apple notarization.
#
# STOCKALERT_PROVISION_PROFILE=/path/to/profile \
#   ./scripts/package-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Adanos Software GmbH (39945LJS7U)}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
APP_NAME="StockAlert"
VOL_NAME="StockAlert.pro"
DMG_NAME="StockAlert.pro-${VERSION}.dmg"

export SIGN_MODE="${SIGN_MODE:-developer-id}"
export TIMESTAMP="${TIMESTAMP:-1}"

"$ROOT/build.sh"

APP="$ROOT/out/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
  echo "Missing $APP" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/dmg"
ditto "$APP" "$STAGE/dmg/${APP_NAME}.app"
ln -s /Applications "$STAGE/dmg/Applications"

DMG="$ROOT/out/${DMG_NAME}"
rm -f "$DMG"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE/dmg" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG"

codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --strict "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
fi

shasum -a 256 "$DMG" | tee "$ROOT/out/${DMG_NAME}.sha256"
echo "Packaged $DMG"
