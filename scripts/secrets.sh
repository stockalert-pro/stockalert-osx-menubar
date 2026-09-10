#!/usr/bin/env bash
# Local secrets live outside git. Override with STOCKALERT_SECRETS_DIR.
STOCKALERT_SECRETS_DIR="${STOCKALERT_SECRETS_DIR:-$HOME/Library/Developer/StockAlert}"
STOCKALERT_DEFAULT_PROFILE="$STOCKALERT_SECRETS_DIR/StockAlert.DeveloperID.provisionprofile"
STOCKALERT_NOTARY_PROFILE="${NOTARY_PROFILE:-stockalert-notary}"

resolve_provision_profile() {
  if [[ -n "${STOCKALERT_PROVISION_PROFILE:-}" ]]; then
    printf '%s\n' "$STOCKALERT_PROVISION_PROFILE"
    return
  fi
  if [[ -f "$STOCKALERT_DEFAULT_PROFILE" ]]; then
    printf '%s\n' "$STOCKALERT_DEFAULT_PROFILE"
    return
  fi
  printf '%s\n' "$ROOT/Resources/StockAlert.DeveloperID.provisionprofile"
}
