"""Type-safe wrapper around khtool execution."""

from __future__ import annotations

from khvol_errors import (
    EXIT_ERROR,
    KhvolError,
)
from khvol_settings import Settings
from khtool_commands import ExpertQuery, ExpertSetLevel, KhtoolCommand, MuteCommand
from khtool_session import KhtoolSession

MAX_KHTOOL_LEVEL = 120.0


class KhtoolRunner:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._session: KhtoolSession | None = None

    def run(self, command: KhtoolCommand) -> str:
        try:
            return self._get_session().run(command)
        except RuntimeError as exc:
            raise KhvolError(str(exc), EXIT_ERROR) from exc

    def query_levels(self) -> str:
        return self.run(ExpertQuery.LEVEL)

    def query_mute(self) -> str:
        return self.run(ExpertQuery.MUTE)

    def set_level(self, level: float) -> str:
        clamped = max(0.0, min(MAX_KHTOOL_LEVEL, level))
        return self.run(ExpertSetLevel(clamped))

    def set_muted(self, muted: bool) -> str:
        return self.run(MuteCommand(muted))

    def read_status_output(self) -> str:
        level = self.query_levels()
        mute = self.query_mute()
        return level + "\n" + mute

    def _get_session(self) -> KhtoolSession:
        if self._session is not None:
            return self._session
        session = KhtoolSession(self._settings)
        session.connect()
        self._session = session
        return session
