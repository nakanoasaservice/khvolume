"""Parse and format KH speaker status."""

from __future__ import annotations

import json
import re
from typing import TypedDict

from khvol.errors import EXIT_DEVICE, KhvolError

BALANCE_TOLERANCE = 0.05


class DeviceStatus(TypedDict, total=False):
    level: float
    mute: bool


class SpeakerStatus(TypedDict):
    devices: dict[str, DeviceStatus]
    levels: list[float]
    muted: bool


class StatusJSON(TypedDict):
    devices: dict[str, DeviceStatus]
    levels: list[float]
    muted: bool
    balanced: bool


def levels_balanced(status: SpeakerStatus) -> bool:
    levels = status["levels"]
    return max(levels) - min(levels) < BALANCE_TOLERANCE


def status_json_document(status: SpeakerStatus) -> StatusJSON:
    return {
        "devices": status["devices"],
        "levels": status["levels"],
        "muted": status["muted"],
        "balanced": levels_balanced(status),
    }


def parse_khtool_status(output: str) -> SpeakerStatus:
    devices: dict[str, DeviceStatus] = {}
    current: str | None = None
    for line in output.splitlines():
        match = re.match(r"Used Device:\s+(.+)", line)
        if match:
            current = match.group(1).strip()
            continue
        stripped = line.strip()
        if not current or not stripped.startswith("{"):
            continue
        data = json.loads(stripped)
        out = data.get("audio", {}).get("out", {})
        entry: DeviceStatus = devices.setdefault(current, {})
        if "level" in out:
            entry["level"] = float(out["level"])
        if "mute" in out:
            entry["mute"] = bool(out["mute"])

    if not devices:
        raise KhvolError("no devices found", EXIT_DEVICE)

    levels = [info["level"] for info in devices.values() if "level" in info]
    if len(levels) != len(devices):
        raise KhvolError("missing level from one or more devices", EXIT_DEVICE)

    return {
        "devices": devices,
        "levels": levels,
        "muted": any(info.get("mute", False) for info in devices.values()),
    }
