#!/usr/bin/env bash
# Local default: Developer ID plus the embedded push profile when both
# are present, otherwise ad-hoc without APS entitlements so the app
# still launches. Restricted entitlements such as aps-environment need
# that profile; without it, launchd refuses the app (POSIX 163).
#
# SIGN_MODE=adhoc ./build.sh
# SIGN_MODE=developer-id ./build.sh
# SIGN_MODE=none ./build.sh
# STOCKALERT_PROVISION_PROFILE=/path/to/StockAlert.DeveloperID.provisionprofile
# TIMESTAMP=1 ./build.sh   # required for notarization
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
CONFIGURATION="${CONFIGURATION:-release}"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Adanos Software GmbH (39945LJS7U)}"
APP_NAME="StockAlert.pro"
BIN_NAME="StockAlertMenuBar"
PROFILE="${STOCKALERT_PROVISION_PROFILE:-$ROOT/Resources/StockAlert.DeveloperID.provisionprofile}"
ENTITLEMENTS="$ROOT/Resources/StockAlert.entitlements"
PUSH_ENV="development"

export MACOSX_DEPLOYMENT_TARGET

identity_available() {
  security find-identity -v -p codesigning 2>/dev/null | grep -F "$IDENTITY" >/dev/null
}

if [[ -z "${SIGN_MODE:-}" ]]; then
  if identity_available && [[ -f "$PROFILE" ]]; then
    SIGN_MODE=developer-id
  else
    SIGN_MODE=adhoc
  fi
fi

cd "$ROOT"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "StockAlert.pro menu bar builds on Apple Silicon only." >&2
  exit 1
fi

swift build \
  -c "$CONFIGURATION" \
  --triple arm64-apple-macosx26.0

BIN_DIR="$(swift build -c "$CONFIGURATION" --triple arm64-apple-macosx26.0 --show-bin-path)"
BIN="$BIN_DIR/$BIN_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "Missing binary at $BIN" >&2
  exit 1
fi

STAGE="${TMPDIR:-/tmp}/stockalert-menubar-build"
APP="$STAGE/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
cp "$ROOT/Sources/StockAlertMenuBar/Resources/BellOnDark.png" "$APP/Contents/Resources/BellOnDark.png"
cp "$ROOT/Sources/StockAlertMenuBar/Resources/BellOnLight.png" "$APP/Contents/Resources/BellOnLight.png"

if [[ "$SIGN_MODE" == "developer-id" ]]; then
  ENTITLEMENTS="$ROOT/Resources/StockAlert.production.entitlements"
  PUSH_ENV="production"
fi
/usr/libexec/PlistBuddy -c "Set :StockAlertPushEnvironment $PUSH_ENV" "$APP/Contents/Info.plist" >/dev/null

codesign_app() {
  local app="$1"
  case "$SIGN_MODE" in
    none)
      echo "Skipping codesign (SIGN_MODE=none)."
      ;;
    developer-id)
      if ! identity_available; then
        echo "No signing identity '$IDENTITY'." >&2
        exit 1
      fi
      if [[ ! -f "$PROFILE" ]]; then
        echo "Missing Developer ID profile at $PROFILE." >&2
        exit 1
      fi
      cp "$PROFILE" "$app/Contents/embedded.provisionprofile"
      local extra=()
      if [[ "${TIMESTAMP:-0}" == "1" ]]; then
        extra+=(--timestamp)
      else
        extra+=(--timestamp=none)
      fi
      codesign \
        --force \
        --sign "$IDENTITY" \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        "${extra[@]}" \
        "$app"
      codesign --verify --deep --strict "$app"
      echo "Signed with $IDENTITY (production push)"
      ;;
    adhoc|*)
      codesign --force --sign - "$app"
      echo "Ad-hoc signed for local launch."
      ;;
  esac
}

codesign_app "$APP"

OUT="$ROOT/out"
mkdir -p "$OUT"
rm -rf "$OUT/$APP_NAME.app"
ditto "$APP" "$OUT/$APP_NAME.app"
codesign --verify --deep --strict "$OUT/$APP_NAME.app"

echo "Built $OUT/$APP_NAME.app"
file "$OUT/$APP_NAME.app/Contents/MacOS/$BIN_NAME"
lipo -archs "$OUT/$APP_NAME.app/Contents/MacOS/$BIN_NAME"
