"""Reuse khtool device connections within a single khvol process."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from khvol_cli import Settings

_CACHE: dict[tuple[str, str], "KhtoolSession"] = {}


@dataclass
class _KhtoolRunResult:
    returncode: int
    stdout: str
    stderr: str


def invalidate_session() -> None:
    for session in _CACHE.values():
        session.close()
    _CACHE.clear()


def get_session(settings: Settings) -> "KhtoolSession":
    if not settings.interface:
        raise RuntimeError("network interface not configured")
    key = (str(settings.config_dir.resolve()), settings.interface)
    cached = _CACHE.get(key)
    if cached is not None:
        return cached

    config_key = key[0]
    for existing_key, existing_session in list(_CACHE.items()):
        if existing_key[0] == config_key and existing_key != key:
            existing_session.close()
            del _CACHE[existing_key]

    session = KhtoolSession(settings)
    session.connect()
    _CACHE[key] = session
    return session


def session_available(settings: Settings) -> bool:
    from khvol_cli import khtool_json_has_devices

    return khtool_json_has_devices(settings.khtool_json)


class KhtoolSession:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._khtool = _load_khtool_module(settings.khtool)
        self._previous_cwd = os.getcwd()
        self.devices: list[Any] = []
        self._interface_suffix = "%" + settings.interface

    def close(self) -> None:
        try:
            os.chdir(self._previous_cwd)
        except OSError:
            pass

    def connect(self) -> None:
        self.settings.config_dir.mkdir(parents=True, exist_ok=True)
        os.chdir(self.settings.config_dir)
        self._khtool.interface = self._interface_suffix

        if not self.settings.khtool_json.is_file():
            raise RuntimeError("khtool.json missing; run scan first")

        import pyssc as ssc

        found_setup = ssc.Ssc_device_setup()
        found_setup.from_json(str(self.settings.khtool_json))
        self.devices = list(found_setup.ssc_devices)

        for device in self.devices:
            device.connect(interface=self._khtool.get_interface(device))
            if hasattr(device, "connected") and not device.connected:
                raise RuntimeError(f"device {device.ip} is not online")

    def run(self, extra_args: tuple[str, ...], check: bool = True) -> _KhtoolRunResult:
        args = list(extra_args)
        if not args:
            raise RuntimeError("empty khtool args")

        try:
            if args[0] == "--expert" and len(args) >= 2:
                stdout = self._run_expert_all(args[1])
            elif args == ["--mute"]:
                stdout = self._run_mute(True)
            elif args == ["--unmute"]:
                stdout = self._run_mute(False)
            else:
                return _subprocess_khtool(self.settings, extra_args, check)
        except RuntimeError as exc:
            if check:
                raise
            return _KhtoolRunResult(1, "", str(exc))

        return _KhtoolRunResult(0, stdout, "")

    def _device_lines(self, device: Any, response: str) -> list[str]:
        name = self._device_display_name(device)
        return [f"Used Device:  {name}", response.strip()]

    def _device_display_name(self, device: Any) -> str:
        iface = self._khtool.get_interface(device)
        tx = device.send_ssc('{"device":{"name":null}}', interface=iface)
        if hasattr(tx, "RX"):
            payload = json.loads(tx.RX)
            return str(payload["device"]["name"])
        return str(device.ip)

    def _send_expert(self, device: Any, payload: str) -> str:
        iface = self._khtool.get_interface(device)
        tx = device.send_ssc(payload, interface=iface)
        if not hasattr(tx, "RX"):
            raise RuntimeError(f"no response from {device.ip}")
        return tx.RX.replace("\r\n", "")

    def _run_expert_all(self, payload: str) -> str:
        chunks: list[str] = []
        for device in self.devices:
            response = self._send_expert(device, payload)
            chunks.extend(self._device_lines(device, response))
        return "\n".join(chunks) + "\n"

    def _run_mute(self, muted: bool) -> str:
        chunks: list[str] = []
        for device in self.devices:
            args = argparse.Namespace(
                query=False,
                brightness=None,
                delay=None,
                dimm=None,
                level=None,
                mute=muted,
                unmute=not muted,
                expert=None,
                save=False,
            )
            lines: list[str] = []
            name = self._device_display_name(device)
            lines.append(f"Used Device:  {name}")

            import io
            from contextlib import redirect_stdout

            buffer = io.StringIO()
            with redirect_stdout(buffer):
                self._khtool.handle_device(args, device)
            body = buffer.getvalue().strip()
            if body:
                lines.append(body)
            chunks.extend(lines)
        return "\n".join(chunks) + "\n"


def _load_khtool_module(khtool_path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location("khtool_embedded", khtool_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load khtool from {khtool_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["khtool_embedded"] = module
    spec.loader.exec_module(module)
    return module


def _subprocess_khtool(
    settings: Settings, extra_args: tuple[str, ...], check: bool
) -> _KhtoolRunResult:
    from khvol_cli import python_executable, require_interface

    interface = require_interface(settings)
    if getattr(sys, "frozen", False):
        cmd = [sys.executable, "--run-khtool", "-i", interface, "-t", "all", *extra_args]
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
    result = subprocess.run(
        cmd,
        cwd=settings.config_dir,
        capture_output=True,
        text=True,
        check=False,
    )
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(detail or f"khtool exited with code {result.returncode}")
    return _KhtoolRunResult(result.returncode, result.stdout, result.stderr)
