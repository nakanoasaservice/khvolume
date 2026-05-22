"""Load khvol settings from CLI arguments, config, and environment."""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True, slots=True)
class Settings:
    config_dir: Path
    interface: str | None
    khtool: Path

    @property
    def khtool_json(self) -> Path:
        return self.config_dir / "khtool.json"


def repo_root() -> Path:
    env_root = os.environ.get("KHVOL_ROOT")
    if env_root:
        return Path(env_root).resolve()
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS).resolve()
    return Path(__file__).resolve().parent.parent


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
        except json.JSONDecodeError:
            pass

    for env_name in ("khvolume.local.env", "khvol.env"):
        env_path = config_dir / env_name
        if not env_path.is_file() and env_name == "khvolume.local.env":
            env_path = config_dir.parent / env_name
        env_values = load_env_file(env_path)
        if env_values.get("KHVOL_INTERFACE"):
            config["interface"] = env_values["KHVOL_INTERFACE"]

    return config


def build_settings(
    *,
    config_dir: str | None,
    interface: str | None,
) -> Settings:
    root = repo_root()
    resolved_config_dir = Path(config_dir).resolve() if config_dir else root
    config = load_config(resolved_config_dir)

    resolved_interface = (
        interface
        or os.environ.get("KHVOL_INTERFACE")
        or config.get("interface")
    )
    return Settings(
        config_dir=resolved_config_dir,
        interface=str(resolved_interface) if resolved_interface else None,
        khtool=default_khtool_path(root),
    )
