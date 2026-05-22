"""Reuse khtool device connections within a single khvol process."""

from __future__ import annotations

import argparse
import importlib.util
import io
import json
import sys
from contextlib import redirect_stdout
from pathlib import Path
from types import ModuleType
from typing import Any

from khvol.errors import EXIT_DEVICE, EXIT_ERROR, KhvolError
from khvol.khtool_json import khtool_json_has_devices
from khvol.settings import Settings
from khvol.khtool_commands import ExpertQuery, ExpertSetLevel, KhtoolCommand, MuteCommand


class KhtoolSession:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._khtool = _load_khtool_module(settings.khtool)
        self.devices: list[Any] = []
        if not settings.interface:
            raise KhvolError("network interface not configured", EXIT_ERROR)
        self._interface_suffix = "%" + settings.interface

    def connect(self) -> None:
        self.settings.config_dir.mkdir(parents=True, exist_ok=True)
        self._khtool.interface = self._interface_suffix

        if not khtool_json_has_devices(self.settings.khtool_json):
            raise KhvolError("no speakers configured; run scan", EXIT_DEVICE)

        import pyssc as ssc

        found_setup = ssc.Ssc_device_setup()
        found_setup.from_json(str(self.settings.khtool_json))
        self.devices = list(found_setup.ssc_devices)

        for device in self.devices:
            device.connect(interface=self._khtool.get_interface(device))
            if hasattr(device, "connected") and not device.connected:
                raise RuntimeError(f"device {device.ip} is not online")

    def run(self, command: KhtoolCommand) -> str:
        match command:
            case ExpertQuery.LEVEL | ExpertQuery.MUTE | ExpertSetLevel() as expert:
                return self._run_expert_all(expert.payload)
            case MuteCommand(muted=muted):
                return self._run_mute(muted)

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
            lines: list[str] = []
            name = self._device_display_name(device)
            lines.append(f"Used Device:  {name}")

            buffer = io.StringIO()
            with redirect_stdout(buffer):
                self._khtool.handle_device(self._mute_args(muted), device)
            body = buffer.getvalue().strip()
            if body:
                lines.append(body)
            chunks.extend(lines)
        return "\n".join(chunks) + "\n"

    def _mute_args(self, muted: bool) -> argparse.Namespace:
        return argparse.Namespace(
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


def _load_khtool_module(khtool_path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location("khtool_embedded", khtool_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load khtool from {khtool_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["khtool_embedded"] = module
    spec.loader.exec_module(module)
    return module
