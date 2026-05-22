"""SSC device discovery via mDNS (_ssc._tcp).

Upstream pyssc scans all ZeroconfServiceTypes, which often omits _ssc._tcp on macOS.
Browse that service type directly instead (same approach as MA1).
"""

from __future__ import annotations

import socket
import time
from typing import Any, Protocol

SSC_SERVICE_TYPE = "_ssc._tcp.local."


class SscSetup(Protocol):
    ssc_devices: list[Any]

    def to_json(self, path: str) -> None:
        ...


def scan_ssc_setup(
    scan_time_seconds: float = 12.0,
    interface: str | None = None,
) -> SscSetup:
    from pyssc.ssc_device import Ssc_device
    from pyssc.ssc_device_setup import Ssc_device_setup
    from zeroconf import IPVersion, ServiceBrowser, ServiceStateChange, Zeroconf

    found: list[Ssc_device] = []

    def on_service_state_change(
        zeroconf: Zeroconf,
        service_type: str,
        name: str,
        state_change: ServiceStateChange,
    ) -> None:
        if state_change is not ServiceStateChange.Added:
            return
        if service_type != SSC_SERVICE_TYPE:
            return
        info = zeroconf.get_service_info(service_type, name)
        if not info:
            return
        addresses = info.parsed_addresses()
        if not addresses:
            return
        device_name = info.name.replace(f".{SSC_SERVICE_TYPE}", "")
        found.append(Ssc_device(device_name, addresses[0]))

    zc_kwargs: dict[str, Any] = {"ip_version": IPVersion.V6Only}
    if interface:
        try:
            zc_kwargs["interfaces"] = [socket.if_nametoindex(interface)]
        except OSError:
            pass

    zeroconf = Zeroconf(**zc_kwargs)
    try:
        ServiceBrowser(zeroconf, [SSC_SERVICE_TYPE], handlers=[on_service_state_change])
        time.sleep(scan_time_seconds)
    finally:
        zeroconf.close()
    return Ssc_device_setup(found)
