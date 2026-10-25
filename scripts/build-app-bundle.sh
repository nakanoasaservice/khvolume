#!/usr/bin/env bash
# Build "KH Volume.app" (Release).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE_NAME="KH Volume"
DERIVED_DATA="$ROOT/build/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/${APP_BUNDLE_NAME}.app"
APP_DIR="$ROOT/dist/${APP_BUNDLE_NAME}.app"

echo "Building release app with xcodebuild..."
xcodebuild \
  -project "$ROOT/KhVolume/KhVolume.xcodeproj" \
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
echo "Run: open \"$APP_DIR\""

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Signing with $SIGN_IDENTITY ..."
  "$ROOT/scripts/sign-app.sh" "$APP_DIR"
fi
