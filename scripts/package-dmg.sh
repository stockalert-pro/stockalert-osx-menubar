#!/usr/bin/env bash
# Developer ID app + drag-to-Applications DMG + Apple notarization.
#
# Secrets stay off git:
#   ~/Library/Developer/StockAlert/StockAlert.DeveloperID.provisionprofile
#   Keychain profile stockalert-notary
#   Sparkle EdDSA private key in Keychain account stockalert.pro
#
# ./scripts/package-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/secrets.sh
source "$ROOT/scripts/secrets.sh"

IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Adanos Software GmbH (39945LJS7U)}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
APP_NAME="StockAlert.pro"
VOL_NAME="StockAlert.pro"
DMG_NAME="StockAlert.pro-${VERSION}.dmg"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"

export SIGN_MODE="${SIGN_MODE:-developer-id}"
export TIMESTAMP="${TIMESTAMP:-1}"
export NOTARY_PROFILE="${NOTARY_PROFILE:-$STOCKALERT_NOTARY_PROFILE}"
export STOCKALERT_PROVISION_PROFILE="$(resolve_provision_profile)"

if [[ ! -f "$STOCKALERT_PROVISION_PROFILE" ]]; then
  echo "Missing Developer ID profile at $STOCKALERT_PROVISION_PROFILE" >&2
  echo "Copy it to $STOCKALERT_SECRETS_DIR or set STOCKALERT_PROVISION_PROFILE." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notary profile '$NOTARY_PROFILE' is not in the Keychain." >&2
  echo "Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\"" >&2
  exit 1
fi

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

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

if [[ -x "$SPARKLE_BIN/generate_appcast" ]]; then
  ARCHIVES="$STAGE/sparkle-archives"
  mkdir -p "$ARCHIVES"
  cp "$DMG" "$ARCHIVES/"
  "$SPARKLE_BIN/generate_appcast" \
    --account stockalert.pro \
    --download-url-prefix "https://github.com/stockalert-pro/stockalert-osx-menubar/releases/download/v${VERSION}/" \
    "$ARCHIVES"
  if [[ -f "$ARCHIVES/appcast.xml" ]]; then
    cp "$ARCHIVES/appcast.xml" "$ROOT/out/appcast.xml"
    echo "Wrote $ROOT/out/appcast.xml"
  fi
fi

shasum -a 256 "$DMG" | tee "$ROOT/out/${DMG_NAME}.sha256"
echo "Packaged $DMG"
