#!/usr/bin/env python3
"""CLI for Neumann KH speakers via khtool (SSC over IPv6)."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_DEVICE = 2
EXIT_MISMATCH = 3

BALANCE_TOLERANCE = 0.05
DEFAULT_STEP = 1.0
DEFAULT_MAX_LEVEL = 120.0
MISSING_INTERFACE_MESSAGE = (
    "network interface not configured; use -i/--interface, "
    "KHVOL_INTERFACE, or config interface"
)


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
    flat = root / "vendor" / "khtool.py"
    if flat.is_file():
        return flat
    return root / "vendor" / "khtool" / "khtool.py"


def python_executable() -> str:
    return os.environ.get("KHVOL_PYTHON", sys.executable)


@dataclass
class Settings:
    config_dir: Path
    interface: str | None
    step: float
    max_level: float
    force: bool
    khtool: Path
    repo_root: Path

    @property
    def khtool_json(self) -> Path:
        return self.config_dir / "khtool.json"


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
                if "volumeStep" in loaded:
                    config.setdefault("step", loaded["volumeStep"])
        except json.JSONDecodeError:
            pass

    for env_name in ("khvolume.local.env", "khvol.env"):
        env_path = config_dir / env_name
        if not env_path.is_file() and env_name == "khvolume.local.env":
            env_path = config_dir.parent / env_name
        env_values = load_env_file(env_path)
        if env_values.get("KHVOL_INTERFACE"):
            config["interface"] = env_values["KHVOL_INTERFACE"]
        if env_values.get("KHVOL_STEP"):
            config["step"] = env_values["KHVOL_STEP"]
        if env_values.get("KHVOL_MAX_LEVEL"):
            config["max_level"] = env_values["KHVOL_MAX_LEVEL"]

    return config


def build_settings(args: argparse.Namespace) -> Settings:
    root = repo_root()
    config_dir = Path(args.config_dir).resolve() if args.config_dir else root
    config = load_config(config_dir)

    interface = (
        args.interface
        or os.environ.get("KHVOL_INTERFACE")
        or config.get("interface")
    )
    cli_step = getattr(args, "step", None)
    step = float(
        cli_step
        if cli_step is not None
        else os.environ.get("KHVOL_STEP", config.get("step", DEFAULT_STEP))
    )
    max_level = float(
        args.max_level
        if args.max_level is not None
        else os.environ.get("KHVOL_MAX_LEVEL", config.get("max_level", DEFAULT_MAX_LEVEL))
    )
    khtool = Path(args.khtool).resolve() if args.khtool else default_khtool_path(root)

    return Settings(
        config_dir=config_dir,
        interface=str(interface) if interface else None,
        step=step,
        max_level=max_level,
        force=bool(args.force),
        khtool=khtool,
        repo_root=root,
    )


class KhvolError(Exception):
    def __init__(self, message: str, code: int = EXIT_ERROR) -> None:
        super().__init__(message)
        self.code = code


def eprint(message: str) -> None:
    print(message, file=sys.stderr)


def require_interface(settings: Settings) -> str:
    if not settings.interface:
        raise KhvolError(MISSING_INTERFACE_MESSAGE, EXIT_ERROR)
    return settings.interface


def khtool_run(settings: Settings, *extra_args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    iface = require_interface(settings)
    if not settings.khtool.is_file():
        raise KhvolError(f"khtool not found: {settings.khtool}", EXIT_ERROR)

    if extra_args and extra_args[0] == "--scan":
        from khtool_session import invalidate_session

        invalidate_session()
        return _khtool_run_subprocess(settings, iface, extra_args, check)

    from khtool_session import get_session, session_available

    if session_available(settings):
        try:
            session = get_session(settings)
            result = session.run(extra_args, check=check)
        except RuntimeError as exc:
            raise KhvolError(str(exc), EXIT_ERROR) from exc
        return subprocess.CompletedProcess(
            args=[*extra_args],
            returncode=result.returncode,
            stdout=result.stdout,
            stderr=result.stderr,
        )

    return _khtool_run_subprocess(settings, iface, extra_args, check)


def _khtool_run_subprocess(
    settings: Settings, interface: str, extra_args: tuple[str, ...], check: bool
) -> subprocess.CompletedProcess[str]:
    if getattr(sys, "frozen", False):
        cmd = [
            sys.executable,
            "--run-khtool",
            "-i",
            interface,
            "-t",
            "all",
            *extra_args,
        ]
    else:
        cmd = [
            python_executable(),
            str(settings.khtool),
            "-i",
            interface,
            "-t",
            "all",
            *extra_args,
        ]
    settings.config_dir.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(
            cmd,
            cwd=settings.config_dir,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        raise KhvolError(f"failed to run khtool: {exc}", EXIT_ERROR) from exc

    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise KhvolError(
            detail or f"khtool exited with code {result.returncode}",
            EXIT_ERROR,
        )
    return result


def _khtool_payload_has_devices(data: Any) -> bool:
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
    return _khtool_payload_has_devices(data)


def parse_khtool_status(output: str) -> dict[str, Any]:
    devices: dict[str, dict[str, Any]] = {}
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
        entry = devices.setdefault(current, {})
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


def read_status(settings: Settings) -> dict[str, Any]:
    if not khtool_json_has_devices(settings.khtool_json):
        raise KhvolError("no speakers configured; run scan", EXIT_DEVICE)
    level = khtool_run(
        settings,
        "--expert",
        '{"audio":{"out":{"level":null}}}',
    )
    mute = khtool_run(
        settings,
        "--expert",
        '{"audio":{"out":{"mute":null}}}',
    )
    return parse_khtool_status(level.stdout + "\n" + mute.stdout)


def levels_balanced(status: dict[str, Any]) -> bool:
    levels = status["levels"]
    return max(levels) - min(levels) < BALANCE_TOLERANCE


def clamp_level(value: float, max_level: float) -> float:
    return max(0.0, min(max_level, value))


def require_balanced(settings: Settings, status: dict[str, Any]) -> None:
    if settings.force or levels_balanced(status):
        return
    raise KhvolError(
        "Left/Right levels differ; fix in MA1 or use --force",
        EXIT_MISMATCH,
    )


def status_json_document(status: dict[str, Any]) -> dict[str, Any]:
    return {
        "devices": status["devices"],
        "levels": status["levels"],
        "muted": status["muted"],
        "balanced": levels_balanced(status),
    }


def emit_status_json(status: dict[str, Any]) -> int:
    print(json.dumps(status_json_document(status), separators=(",", ":")))
    return EXIT_OK


def cmd_json(settings: Settings) -> int:
    status = read_status(settings)
    return emit_status_json(status)


def parse_networksetup_ports(text: str) -> list[tuple[str, str]]:
    # Parse networksetup -listallhardwareports into (hardware_port, device) pairs.
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
    # macOS ifconfig: status active/inactive.
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




def list_hardware_interfaces() -> list[dict[str, str]]:
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

    rows: list[dict[str, str]] = []
    for hw, dev in parse_networksetup_ports(proc.stdout):
        state = "active" if interface_is_active(dev) else "inactive"
        rows.append({"name": dev, "label": hw, "status": state})
    return rows


def cmd_interfaces(settings: Settings) -> int:
    del settings
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
    from khtool_session import invalidate_session

    invalidate_session()
    previous: str | None = None
    had_devices = False
    if settings.khtool_json.is_file():
        previous = settings.khtool_json.read_text(encoding="utf-8")
        try:
            had_devices = _khtool_payload_has_devices(json.loads(previous))
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

    print(json.dumps({"speakerCount": count}, separators=(",", ":")))
    return EXIT_OK if count > 0 else EXIT_DEVICE


def cmd_status(settings: Settings) -> int:
    status = read_status(settings)
    for name in sorted(status["devices"].keys()):
        info = status["devices"][name]
        level = info.get("level")
        muted = bool(info.get("mute", False))
        icon = "🔇" if muted else "🔊"
        if level is not None:
            print(f"{name}: {level:.1f} dB {icon}")
        else:
            print(f"{name}: (unknown level) {icon}")
    return EXIT_OK


def cmd_status_oneline(settings: Settings) -> int:
    try:
        status = read_status(settings)
    except KhvolError:
        print("KH ?")
        return EXIT_OK
    icon = "🔇" if status["muted"] else "🔊"
    levels = status["levels"]
    if levels_balanced(status):
        avg = sum(levels) / len(levels)
        print(f"{icon} {avg:.1f}")
    else:
        print(f"{icon} {min(levels):.1f}–{max(levels):.1f}")
    return EXIT_OK


def apply_level(settings: Settings, level: float) -> None:
    clamped = clamp_level(level, settings.max_level)
    payload = json.dumps({"audio": {"out": {"level": clamped}}}, separators=(",", ":"))
    khtool_run(settings, "--expert", payload)


def cmd_up(settings: Settings, step: float | None) -> int:
    delta = settings.step if step is None else step
    status = read_status(settings)
    require_balanced(settings, status)
    apply_level(settings, max(status["levels"]) + delta)
    return cmd_status_oneline(settings)


def cmd_down(settings: Settings, step: float | None) -> int:
    delta = settings.step if step is None else step
    status = read_status(settings)
    require_balanced(settings, status)
    apply_level(settings, min(status["levels"]) - delta)
    return cmd_status_oneline(settings)


def cmd_set(settings: Settings, level: float, apply_only: bool = False, emit_json: bool = False) -> int:
    clamped = clamp_level(level, settings.max_level)
    if not apply_only:
        status = read_status(settings)
        require_balanced(settings, status)
    apply_level(settings, clamped)
    if emit_json:
        return emit_status_json(read_status(settings))
    return cmd_status_oneline(settings)




def cmd_mute(settings: Settings) -> int:
    khtool_run(settings, "--mute")
    return cmd_status_oneline(settings)


def cmd_unmute(settings: Settings) -> int:
    khtool_run(settings, "--unmute")
    return cmd_status_oneline(settings)


def cmd_toggle_mute(settings: Settings, emit_json: bool = False) -> int:
    status = read_status(settings)
    if status["muted"]:
        khtool_run(settings, "--unmute")
    else:
        khtool_run(settings, "--mute")
    if emit_json:
        return emit_status_json(read_status(settings))
    return cmd_status_oneline(settings)


def usage_text() -> str:
    return (
        "commands:\n"
        "  status           show per-speaker level and mute state\n"
        "  status-oneline   compact menubar summary (mute/speaker emoji)\n"
        "  json             machine-readable status JSON\n"
        "  scan             rescan LAN and refresh khtool.json (khtool --scan)\n"
        "  interfaces       list hardware ports and link activity (macOS networksetup)\n"
        "  up [--step N]    increase level by step (default from config / env)\n"
        "  down [--step N]  decrease level by step\n"
        "  set LEVEL        set absolute level (dB)\n"
        "  set --apply-only skip pre-read balance check (UI already validated)\n"
        "  set --json       emit status JSON after set (for KhVolume.app)\n"
        "  mute | unmute | toggle-mute\n"
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
    parser.add_argument("-i", "--interface", type=str, default=None, help="network interface (e.g. en15)")
    parser.add_argument("--step", type=float, default=None, help="default dB step (overrides config / env)")
    parser.add_argument("--max-level", type=float, default=None, help="maximum level in dB")
    parser.add_argument("--force", action="store_true", help="allow commands when L/R levels differ")
    parser.add_argument("--khtool", type=str, default=None, help="path to khtool.py")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status", help="show status for each device")
    sub.add_parser("status-oneline", help="single-line status with mute emoji")
    sub.add_parser("json", help="emit JSON status")
    sub.add_parser("scan", help="run khtool network scan")
    sub.add_parser("interfaces", help="list interfaces via networksetup")
    p_up = sub.add_parser("up", help="raise volume")
    p_up.add_argument("--step", type=float, default=None, help="dB step override")
    p_down = sub.add_parser("down", help="lower volume")
    p_down.add_argument("--step", type=float, default=None, help="dB step override")
    p_set = sub.add_parser("set", help="set absolute level (dB)")
    p_set.add_argument("level", type=float)
    p_set.add_argument(
        "--apply-only",
        action="store_true",
        help="skip pre-read; trust caller balance rules (faster)",
    )
    p_set.add_argument(
        "--json",
        action="store_true",
        help="print status JSON on stdout instead of status-oneline",
    )
    p_toggle = sub.add_parser("toggle-mute", help="toggle mute state")
    p_toggle.add_argument(
        "--json",
        action="store_true",
        help="print status JSON on stdout instead of status-oneline",
    )
    sub.add_parser("mute", help="mute all targets")
    sub.add_parser("unmute", help="unmute all targets")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    settings = build_settings(args)
    cmd = args.command
    try:
        if cmd == "status":
            return cmd_status(settings)
        if cmd == "status-oneline":
            return cmd_status_oneline(settings)
        if cmd == "json":
            return cmd_json(settings)
        if cmd == "scan":
            return cmd_scan(settings)
        if cmd == "interfaces":
            return cmd_interfaces(settings)
        if cmd == "up":
            return cmd_up(settings, getattr(args, "step", None))
        if cmd == "down":
            return cmd_down(settings, getattr(args, "step", None))
        if cmd == "set":
            return cmd_set(
                settings,
                args.level,
                apply_only=bool(getattr(args, "apply_only", False)),
                emit_json=bool(getattr(args, "json", False)),
            )
        if cmd == "mute":
            return cmd_mute(settings)
        if cmd == "unmute":
            return cmd_unmute(settings)
        if cmd == "toggle-mute":
            return cmd_toggle_mute(settings, emit_json=bool(getattr(args, "json", False)))
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
