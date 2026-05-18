#!/usr/bin/env bash
# Build "KH Volume.app" with bundled khvol helper (Release).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="KhVolume"
APP_BUNDLE_NAME="KH Volume"
BUNDLE_ID="com.khvolume.app"
BUILD_DIR="$ROOT/KhVolume/.build/release"
APP_DIR="$ROOT/dist/${APP_BUNDLE_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
HELPERS="$CONTENTS/Helpers"
RESOURCES="$CONTENTS/Resources"

if [[ ! -x "$ROOT/KhVolume/Helpers/khvol-bundle/khvol" ]]; then
  echo "build-app-bundle: building khvol helper..." >&2
  "$ROOT/scripts/build-khvol-helper.sh"
fi

if [[ ! -x "$ROOT/KhVolume/Helpers/khvol-bundle/khvol" ]]; then
  echo "build-app-bundle: khvol helper missing; run scripts/build-khvol-helper.sh" >&2
  exit 1
fi

echo "Building Swift release binary..."
(
  cd "$ROOT/KhVolume"
  swift build -c release
)

BIN="$BUILD_DIR/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
  echo "build-app-bundle: missing $BIN" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$HELPERS" "$RESOURCES"

cp "$BIN" "$MACOS/$APP_NAME"
chmod 755 "$MACOS/$APP_NAME"

cp -R "$ROOT/KhVolume/Helpers/"* "$HELPERS/"
chmod -R 755 "$HELPERS"
chmod +x "$HELPERS/khvol" "$HELPERS/khvol-bundle/khvol"
# Make bundled PyInstaller dependency libraries executable
find "$HELPERS/khvol-bundle" -type f \( -name "*.so" -o -name "*.dylib" \) -exec chmod +x {} + 2>/dev/null || true

PLIST_SRC="$ROOT/KhVolume/Sources/KhVolume/Resources/Info.plist"
if [[ -f "$PLIST_SRC" ]]; then
  cp "$PLIST_SRC" "$CONTENTS/Info.plist"
else
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$CONTENTS/Info.plist" 2>/dev/null || true
fi

echo "Built $APP_DIR"
echo "Run: open \"$APP_DIR\""

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Signing with $SIGN_IDENTITY ..."
  "$ROOT/scripts/sign-app.sh" "$APP_DIR"
fi
