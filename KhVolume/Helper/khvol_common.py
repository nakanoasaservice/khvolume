"""Shared configuration, types, and khtool helpers for khvol."""

from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, TypedDict

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_DEVICE = 2
EXIT_MISMATCH = 3

BALANCE_TOLERANCE = 0.05
DEFAULT_MAX_LEVEL = 120.0
MISSING_INTERFACE_MESSAGE = (
    "network interface not configured; use -i/--interface, "
    "KHVOL_INTERFACE, or config interface"
)


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


@dataclass(frozen=True, slots=True)
class Settings:
    config_dir: Path
    interface: str | None
    max_level: float
    khtool: Path

    @property
    def khtool_json(self) -> Path:
        return self.config_dir / "khtool.json"


class KhvolError(Exception):
    def __init__(self, message: str, code: int = EXIT_ERROR) -> None:
        super().__init__(message)
        self.code = code


def repo_root() -> Path:
    env_root = os.environ.get("KHVOL_ROOT")
    if env_root:
        return Path(env_root).resolve()
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS).resolve()
    return Path(__file__).resolve().parent


def default_khtool_path(root: Path) -> Path:
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        bundled = Path(sys._MEIPASS) / "khtool" / "khtool.py"
        if bundled.is_file():
            return bundled
    match root / "vendor" / "khtool.py":
        case path if path.is_file():
            return path
        case _:
            return root / "vendor" / "khtool" / "khtool.py"


def load_env_file(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def load_config(config_dir: Path) -> dict[str, Any]:
    config: dict[str, Any] = {}
    config_json = config_dir / "config.json"
    if config_json.is_file():
        try:
            loaded = json.loads(config_json.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                config.update(loaded)
                if "maxVolumeLimit" in loaded:
                    config.setdefault("max_level", loaded["maxVolumeLimit"])
        except json.JSONDecodeError:
            pass

    for env_name in ("khvolume.local.env", "khvol.env"):
        env_path = config_dir / env_name
        if not env_path.is_file() and env_name == "khvolume.local.env":
            env_path = config_dir.parent / env_name
        env_values = load_env_file(env_path)
        if env_values.get("KHVOL_INTERFACE"):
            config["interface"] = env_values["KHVOL_INTERFACE"]
        if env_values.get("KHVOL_MAX_LEVEL"):
            config["max_level"] = env_values["KHVOL_MAX_LEVEL"]

    return config


def build_settings(
    *,
    config_dir: str | None,
    interface: str | None,
    max_level: float | None,
) -> Settings:
    root = repo_root()
    resolved_config_dir = Path(config_dir).resolve() if config_dir else root
    config = load_config(resolved_config_dir)

    resolved_interface = (
        interface
        or os.environ.get("KHVOL_INTERFACE")
        or config.get("interface")
    )
    resolved_max_level = float(
        max_level
        if max_level is not None
        else os.environ.get("KHVOL_MAX_LEVEL", config.get("max_level", DEFAULT_MAX_LEVEL))
    )

    return Settings(
        config_dir=resolved_config_dir,
        interface=str(resolved_interface) if resolved_interface else None,
        max_level=resolved_max_level,
        khtool=default_khtool_path(root),
    )


def eprint(message: str) -> None:
    print(message, file=sys.stderr)


def require_interface(settings: Settings) -> str:
    if not settings.interface:
        raise KhvolError(MISSING_INTERFACE_MESSAGE, EXIT_ERROR)
    return settings.interface


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


def clamp_level(value: float, max_level: float) -> float:
    return max(0.0, min(max_level, value))


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
