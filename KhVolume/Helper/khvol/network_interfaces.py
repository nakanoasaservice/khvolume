"""List macOS network interfaces for KhVolume."""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import TypedDict

from khvol.errors import EXIT_ERROR, EXIT_OK, KhvolError


class HardwareInterface(TypedDict):
    name: str
    label: str
    status: str


def parse_networksetup_ports(text: str) -> list[tuple[str, str]]:
    ports: list[tuple[str, str]] = []
    current_hw: str | None = None
    for raw in text.splitlines():
        line = raw.strip()
        m_hw = re.match(r"Hardware Port:\s*(.+)", line)
        if m_hw:
            current_hw = m_hw.group(1).strip()
            continue
        m_dev = re.match(r"Device:\s*(\S+)", line)
        if m_dev and current_hw:
            ports.append((current_hw, m_dev.group(1)))
            current_hw = None
    return ports


def interface_is_active(interface: str) -> bool:
    try:
        proc = subprocess.run(
            ["ifconfig", interface],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    if proc.returncode != 0:
        return False
    out = proc.stdout
    if "status: active" in out:
        return True
    if "status: inactive" in out:
        return False
    if "LOOPBACK" in out:
        return False
    return bool(re.search(r"<[^>]*UP[^>]*RUNNING[^>]*>", out))


def list_hardware_interfaces() -> list[HardwareInterface]:
    setup = Path("/usr/sbin/networksetup")
    if not setup.is_file():
        raise KhvolError("networksetup not found (macOS only)", EXIT_ERROR)
    try:
        proc = subprocess.run(
            [str(setup), "-listallhardwareports"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise KhvolError(f"networksetup failed: {exc}", EXIT_ERROR) from exc
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise KhvolError(detail or "networksetup exited with error", EXIT_ERROR)

    rows: list[HardwareInterface] = []
    for hw, dev in parse_networksetup_ports(proc.stdout):
        state = "active" if interface_is_active(dev) else "inactive"
        rows.append({"name": dev, "label": hw, "status": state})
    return rows


def interfaces_json() -> str:
    return json.dumps(list_hardware_interfaces(), separators=(",", ":"))


def emit_interfaces_json() -> int:
    print(interfaces_json())
    return EXIT_OK
