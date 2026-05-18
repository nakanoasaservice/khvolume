#!/usr/bin/env bash
# Quick smoke tests for the bundled or dev khvol helper.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG_DIR="${KHVOL_CONFIG_DIR:-$ROOT/.smoke-config}"
mkdir -p "$CONFIG_DIR"

KHVOL="${KHVOL_BIN:-}"
if [[ -z "$KHVOL" ]]; then
  if [[ -x "$ROOT/KhVolume/Helpers/khvol" ]]; then
    KHVOL="$ROOT/KhVolume/Helpers/khvol"
  elif [[ -x "$ROOT/KhVolume/Scripts/khvol-dev" ]]; then
    KHVOL="$ROOT/KhVolume/Scripts/khvol-dev"
  else
    echo "smoke-test: no khvol binary found (run scripts/build-khvol-helper.sh)" >&2
    exit 1
  fi
fi

IFACE="${KHVOL_INTERFACE:?Set KHVOL_INTERFACE to your USB-LAN interface name (e.g. export KHVOL_INTERFACE=en0)}"
COMMON=(--config-dir "$CONFIG_DIR" --interface "$IFACE")

echo "== interfaces JSON =="
"$KHVOL" "${COMMON[@]}" interfaces | python3 -c 'import json,sys; json.load(sys.stdin); print("ok")'

echo "== scan JSON =="
set +e
"$KHVOL" "${COMMON[@]}" scan
SCAN_RC=$?
set -e
if [[ $SCAN_RC -eq 0 ]]; then
  echo "scan: speakers found"
elif [[ $SCAN_RC -eq 2 ]]; then
  echo "scan: no speakers (device error) — acceptable offline"
else
  echo "scan failed with code $SCAN_RC" >&2
  exit 1
fi

if [[ -f "$CONFIG_DIR/khtool.json" ]]; then
  echo "== json status =="
  "$KHVOL" "${COMMON[@]}" json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "balanced" in d; print("ok", d.get("levels"))'
fi

echo "smoke-test: passed"
