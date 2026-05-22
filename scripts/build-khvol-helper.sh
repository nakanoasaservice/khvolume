#!/usr/bin/env bash
# Build PyInstaller onedir helper and install into KhVolume/Helpers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_SRC="$ROOT/KhVolume/Helper"
cd "$ROOT"

PYTHON=""
for candidate in python3.12 python3.13 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PYTHON="$candidate"
    break
  fi
done

if [[ -z "$PYTHON" ]]; then
  echo "build-khvol-helper: python3.12 or python3 not found" >&2
  exit 1
fi

VENV="$ROOT/build/venv"
DIST="$ROOT/dist"
HELPERS="$ROOT/KhVolume/Helpers"
BUNDLE_DIR="$HELPERS/khvol-bundle"
WRAPPER="$HELPERS/khvol"

echo "Using Python: $($PYTHON --version 2>&1)"

if [[ ! -d "$VENV" ]]; then
  "$PYTHON" -m venv "$VENV"
fi

# shellcheck source=/dev/null
source "$VENV/bin/activate"

python -m pip install --upgrade pip
python -m pip install -r "$HELPER_SRC/requirements.txt"

rm -rf "$ROOT/build/pyinstaller" "$DIST" "$BUNDLE_DIR" "$WRAPPER"

pyinstaller \
  --noconfirm \
  --clean \
  --onedir \
  --name khvol \
  --distpath "$ROOT/dist" \
  --workpath "$ROOT/build/pyinstaller" \
  --specpath "$ROOT/build/pyinstaller" \
  --paths "$HELPER_SRC" \
  --add-data "$HELPER_SRC/vendor/khtool.py:khtool" \
  --hidden-import pyssc \
  --hidden-import zeroconf \
  --collect-submodules zeroconf \
  "$HELPER_SRC/khvol_cli.py"

BUILT_DIR="$DIST/khvol"
BUILT_BIN="$BUILT_DIR/khvol"
if [[ ! -x "$BUILT_BIN" ]]; then
  echo "build-khvol-helper: expected executable at $BUILT_BIN" >&2
  exit 1
fi

mkdir -p "$HELPERS"
cp -R "$BUILT_DIR" "$BUNDLE_DIR"

cat >"$WRAPPER" <<'EOF'
#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/khvol-bundle/khvol" "$@"
EOF
chmod 755 "$WRAPPER" "$BUNDLE_DIR/khvol"

echo "Installed helper wrapper: $WRAPPER"
echo "Installed helper bundle:  $BUNDLE_DIR"
echo "Done."
