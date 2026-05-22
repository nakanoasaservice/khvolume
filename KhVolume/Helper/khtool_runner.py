"""Type-safe wrapper around khtool execution."""

from __future__ import annotations

from dataclasses import dataclass

from khvol_common import (
    EXIT_DEVICE,
    EXIT_ERROR,
    KhvolError,
    Settings,
    clamp_level,
    khtool_json_has_devices,
)
from khtool_commands import ExpertQuery, ExpertSetLevel, KhtoolCommand, MuteCommand
from khtool_session import get_session


@dataclass(frozen=True, slots=True)
class KhtoolRunOutput:
    stdout: str
    stderr: str
    returncode: int


class KhtoolRunner:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def run(self, command: KhtoolCommand) -> KhtoolRunOutput:
        self._require_device_cache()
        try:
            session = get_session(self._settings)
            result = session.run(command)
        except RuntimeError as exc:
            raise KhvolError(str(exc), EXIT_ERROR) from exc
        return KhtoolRunOutput(result.stdout, result.stderr, result.returncode)

    def query_levels(self) -> KhtoolRunOutput:
        return self.run(ExpertQuery.LEVEL)

    def query_mute(self) -> KhtoolRunOutput:
        return self.run(ExpertQuery.MUTE)

    def set_level(self, level: float) -> KhtoolRunOutput:
        clamped = clamp_level(level, self._settings.max_level)
        return self.run(ExpertSetLevel(clamped))

    def set_muted(self, muted: bool) -> KhtoolRunOutput:
        return self.run(MuteCommand(muted))

    def read_status_output(self) -> str:
        level = self.query_levels().stdout
        mute = self.query_mute().stdout
        return level + "\n" + mute

    def _require_device_cache(self) -> None:
        if not khtool_json_has_devices(self._settings.khtool_json):
            raise KhvolError("no speakers configured; run scan", EXIT_DEVICE)
