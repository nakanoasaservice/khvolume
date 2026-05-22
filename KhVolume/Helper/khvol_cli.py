#!/usr/bin/env python3
"""CLI for Neumann KH speakers via khtool (SSC over IPv6)."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import TypedDict

from khvol_common import (
    EXIT_DEVICE,
    EXIT_ERROR,
    EXIT_OK,
    KhvolError,
    Settings,
    SpeakerStatus,
    build_settings,
    default_khtool_path,
    eprint,
    khtool_json_has_devices,
    khtool_payload_has_devices,
    parse_khtool_status,
    repo_root,
    status_json_document,
)
from khtool_runner import KhtoolRunner
from khtool_session import invalidate_session


class HardwareInterface(TypedDict):
    name: str
    label: str
    status: str


class ScanResult(TypedDict):
    speakerCount: int


def read_status(settings: Settings) -> SpeakerStatus:
    if not khtool_json_has_devices(settings.khtool_json):
        raise KhvolError("no speakers configured; run scan", EXIT_DEVICE)
    return parse_khtool_status(KhtoolRunner(settings).read_status_output())


def emit_status_json(status: SpeakerStatus) -> int:
    print(json.dumps(status_json_document(status), separators=(",", ":")))
    return EXIT_OK


def cmd_json(settings: Settings) -> int:
    return emit_status_json(read_status(settings))


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


def cmd_interfaces() -> int:
    print(json.dumps(list_hardware_interfaces(), separators=(",", ":")))
    return EXIT_OK


def scan_device_count(settings: Settings) -> int:
    from ssc_scan import scan_ssc_setup

    settings.config_dir.mkdir(parents=True, exist_ok=True)
    iface = settings.interface
    setup = scan_ssc_setup(scan_time_seconds=12.0, interface=iface)
    if not setup.ssc_devices and iface is not None:
        setup = scan_ssc_setup(scan_time_seconds=12.0, interface=None)
    if setup.ssc_devices:
        setup.to_json(str(settings.khtool_json))
    return len(setup.ssc_devices)


def cmd_scan(settings: Settings) -> int:
    invalidate_session()
    previous: str | None = None
    had_devices = False
    if settings.khtool_json.is_file():
        previous = settings.khtool_json.read_text(encoding="utf-8")
        try:
            had_devices = khtool_payload_has_devices(json.loads(previous))
        except json.JSONDecodeError:
            had_devices = False

    count = scan_device_count(settings)

    if count == 0:
        if had_devices and previous is not None:
            settings.khtool_json.write_text(previous, encoding="utf-8")
        else:
            try:
                settings.khtool_json.unlink(missing_ok=True)
            except OSError:
                pass

    result: ScanResult = {"speakerCount": count}
    print(json.dumps(result, separators=(",", ":")))
    return EXIT_OK if count > 0 else EXIT_DEVICE


def apply_level(settings: Settings, level: float) -> None:
    KhtoolRunner(settings).set_level(level)


def cmd_set(settings: Settings, level: float) -> int:
    apply_level(settings, level)
    return emit_status_json(read_status(settings))


def cmd_toggle_mute(settings: Settings) -> int:
    runner = KhtoolRunner(settings)
    status = read_status(settings)
    runner.set_muted(not status["muted"])
    return emit_status_json(read_status(settings))


def usage_text() -> str:
    return (
        "commands:\n"
        "  json             machine-readable status JSON\n"
        "  scan             rescan LAN and refresh khtool.json\n"
        "  interfaces       list hardware ports and link activity (macOS networksetup)\n"
        "  set LEVEL        set absolute level (dB) and emit status JSON\n"
        "  toggle-mute      toggle mute state and emit status JSON\n"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="khvol",
        description="Control Neumann KH speakers via khtool (SSC over IPv6).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=usage_text(),
    )
    parser.add_argument(
        "--config-dir",
        type=str,
        default=None,
        help="directory for khtool.json / config",
    )
    parser.add_argument(
        "-i",
        "--interface",
        type=str,
        default=None,
        help="network interface (e.g. en15)",
    )
    parser.add_argument(
        "--max-level",
        type=float,
        default=None,
        help="maximum level in dB",
    )

    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("json", help="emit JSON status")
    sub.add_parser("scan", help="run network scan")
    sub.add_parser("interfaces", help="list interfaces via networksetup")
    p_set = sub.add_parser("set", help="set absolute level (dB)")
    p_set.add_argument("level", type=float)
    sub.add_parser("toggle-mute", help="toggle mute state")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    settings = build_settings(
        config_dir=args.config_dir,
        interface=args.interface,
        max_level=args.max_level,
    )
    cmd = args.command
    try:
        match cmd:
            case "json":
                return cmd_json(settings)
            case "scan":
                return cmd_scan(settings)
            case "interfaces":
                return cmd_interfaces()
            case "set":
                return cmd_set(settings, args.level)
            case "toggle-mute":
                return cmd_toggle_mute(settings)
            case _:
                raise KhvolError(f"unhandled command: {cmd}", EXIT_ERROR)
    except KhvolError as exc:
        eprint(str(exc))
        return exc.code


def run_khtool_internal() -> None:
    import builtins
    import runpy

    builtins.exit = sys.exit

    khtool = default_khtool_path(repo_root())
    if not khtool.is_file():
        eprint(f"khtool not found: {khtool}")
        raise SystemExit(EXIT_ERROR)
    sys.argv = ["khtool", *sys.argv[2:]]
    runpy.run_path(str(khtool), run_name="__main__")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--run-khtool":
        run_khtool_internal()
        raise SystemExit(EXIT_OK)
    sys.exit(main())
