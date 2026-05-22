#!/usr/bin/env python3
"""CLI for Neumann KH speakers via khtool (SSC over IPv6)."""

from __future__ import annotations

import argparse
import sys

from khvol_errors import (
    EXIT_ERROR,
    KhvolError,
    eprint,
)
from khvol_settings import build_settings
from network_interfaces import emit_interfaces_json
from speaker_control import (
    emit_current_status_json,
    set_level_and_emit_status,
    set_muted_and_emit_status,
)
from speaker_scan import run_scan_command


def usage_text() -> str:
    return (
        "commands:\n"
        "  json             machine-readable status JSON\n"
        "  scan             rescan LAN and refresh khtool.json\n"
        "  interfaces       list hardware ports and link activity (macOS networksetup)\n"
        "  set LEVEL        set absolute level (dB) and emit status JSON\n"
        "  mute             mute speakers and emit status JSON\n"
        "  unmute           unmute speakers and emit status JSON\n"
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

    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("json", help="emit JSON status")
    sub.add_parser("scan", help="run network scan")
    sub.add_parser("interfaces", help="list interfaces via networksetup")
    p_set = sub.add_parser("set", help="set absolute level (dB)")
    p_set.add_argument("level", type=float)
    sub.add_parser("mute", help="mute speakers")
    sub.add_parser("unmute", help="unmute speakers")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    settings = build_settings(
        config_dir=args.config_dir,
        interface=args.interface,
    )
    cmd = args.command
    try:
        match cmd:
            case "json":
                return emit_current_status_json(settings)
            case "scan":
                return run_scan_command(settings)
            case "interfaces":
                return emit_interfaces_json()
            case "set":
                return set_level_and_emit_status(settings, args.level)
            case "mute":
                return set_muted_and_emit_status(settings, True)
            case "unmute":
                return set_muted_and_emit_status(settings, False)
            case _:
                raise KhvolError(f"unhandled command: {cmd}", EXIT_ERROR)
    except KhvolError as exc:
        eprint(str(exc))
        return exc.code


if __name__ == "__main__":
    sys.exit(main())
