"""High-level speaker scan command support."""

from __future__ import annotations

import json
from typing import TypedDict

from khvol.errors import EXIT_DEVICE, EXIT_OK
from khvol.settings import Settings
from khvol.khtool_json import khtool_payload_has_devices
from khvol.ssc_scan import scan_ssc_setup


class ScanResult(TypedDict):
    speakerCount: int


def scan_device_count(settings: Settings) -> int:
    settings.config_dir.mkdir(parents=True, exist_ok=True)
    iface = settings.interface
    setup = scan_ssc_setup(scan_time_seconds=12.0, interface=iface)
    if not setup.ssc_devices and iface is not None:
        setup = scan_ssc_setup(scan_time_seconds=12.0, interface=None)
    if setup.ssc_devices:
        setup.to_json(str(settings.khtool_json))
    return len(setup.ssc_devices)


def run_scan_command(settings: Settings) -> int:
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
