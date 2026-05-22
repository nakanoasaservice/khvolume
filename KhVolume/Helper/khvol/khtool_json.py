"""Helpers for reading khtool.json device setup files."""

from __future__ import annotations

import json
from pathlib import Path


def khtool_payload_has_devices(data: object) -> bool:
    if not isinstance(data, dict) or not data:
        return False
    for key in ("ssc_devices", "devices"):
        devices = data.get(key)
        if isinstance(devices, list):
            return len(devices) > 0
    return True


def khtool_json_has_devices(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        if path.stat().st_size <= 2:
            return False
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return False
    return khtool_payload_has_devices(data)
