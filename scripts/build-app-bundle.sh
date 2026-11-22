#!/usr/bin/env bash
# Build "KH Volume.app" (Release) into dist/.
# Usage: ./scripts/build-app-bundle.sh [--install]
#   --install   also copy the app to /Applications, replacing the one there
set -euo pipefail

INSTALL=false
case "${1:-}" in
  "") ;;
  --install) INSTALL=true ;;
  *) echo "usage: $0 [--install]" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE_NAME="KH Volume"
DERIVED_DATA="$ROOT/build/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/${APP_BUNDLE_NAME}.app"
APP_DIR="$ROOT/dist/${APP_BUNDLE_NAME}.app"

echo "Building release app with xcodebuild..."
xcodebuild \
  -project "$ROOT/KhVolume.xcodeproj" \
  -scheme KhVolume \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "build-app-bundle: missing $BUILT_APP" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$ROOT/dist"
ditto "$BUILT_APP" "$APP_DIR"

echo "Built $APP_DIR"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Signing with $SIGN_IDENTITY ..."
  "$ROOT/scripts/sign-app.sh" "$APP_DIR"
fi

if $INSTALL; then
  INSTALLED_APP="/Applications/${APP_BUNDLE_NAME}.app"
  # A running copy (from anywhere) keeps the old code and the hotkeys; stop it and start the
  # installed one in its place.
  RESTART=false
  if pkill -x KhVolume; then RESTART=true; fi
  rm -rf "$INSTALLED_APP"
  ditto "$APP_DIR" "$INSTALLED_APP"
  echo "Installed $INSTALLED_APP"
  if $RESTART; then open "$INSTALLED_APP"; fi
else
  echo "Run: open \"$APP_DIR\""
fi
