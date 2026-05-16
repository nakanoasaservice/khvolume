#!/usr/bin/env bash
# Sign KhVolume.app and bundled khvol helper for distribution.
# Usage:
#   export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   ./scripts/sign-app.sh dist/KhVolume.app
# Optional notarization:
#   export NOTARY_APPLE_ID=...
#   export NOTARY_TEAM_ID=...
#   export NOTARY_APP_PASSWORD=...
#   ./scripts/sign-app.sh dist/KhVolume.app --notarize
set -euo pipefail

APP_PATH="${1:-}"
NOTARIZE=false
if [[ "${2:-}" == "--notarize" ]]; then
  NOTARIZE=true
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "usage: SIGN_IDENTITY='Developer ID Application: …' $0 path/to/KhVolume.app [--notarize]" >&2
  exit 1
fi

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  echo "Set SIGN_IDENTITY to your Developer ID Application certificate name." >&2
  exit 1
fi

HELPERS="$APP_PATH/Contents/Helpers"
ENTITLEMENTS="${ENTITLEMENTS:-}"

sign_file() {
  local target="$1"
  if [[ -n "$ENTITLEMENTS" && -f "$ENTITLEMENTS" ]]; then
    codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$target"
  else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$target"
  fi
}

if [[ -d "$HELPERS/khvol-bundle" ]]; then
  sign_file "$HELPERS/khvol-bundle/khvol"
  find "$HELPERS/khvol-bundle" -type f \( -name "*.so" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' lib; do
    sign_file "$lib"
  done
fi

if [[ -x "$HELPERS/khvol" ]]; then
  sign_file "$HELPERS/khvol"
fi

sign_file "$APP_PATH/Contents/MacOS/KhVolume"
sign_file "$APP_PATH"

echo "codesign verify:"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if $NOTARIZE; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  ZIP="$ROOT/dist/KhVolume-notarize.zip"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP"
  xcrun notarytool submit "$ZIP" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_APP_PASSWORD" \
    --wait
  xcrun stapler staple "$APP_PATH"
  echo "Notarized and stapled: $APP_PATH"
fi

echo "Signed: $APP_PATH"
