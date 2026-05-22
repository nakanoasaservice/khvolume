"""Type-safe wrapper around khtool execution."""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass

from khvol_common import (
    EXIT_ERROR,
    KhvolError,
    Settings,
    clamp_level,
    python_executable,
    require_interface,
)
from khtool_commands import ExpertQuery, ExpertSetLevel, KhtoolCommand, KhtoolInvocation, MuteCommand
from khtool_session import get_session, session_available


@dataclass(frozen=True, slots=True)
class KhtoolRunOutput:
    stdout: str
    stderr: str
    returncode: int


class KhtoolRunner:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def run(self, command: KhtoolCommand, *, check: bool = True) -> KhtoolRunOutput:
        invocation = self._invocation(command)
        if session_available(self._settings):
            try:
                session = get_session(self._settings)
                result = session.run(command, check=check)
            except RuntimeError as exc:
                raise KhvolError(str(exc), EXIT_ERROR) from exc
            return KhtoolRunOutput(result.stdout, result.stderr, result.returncode)

        result = self._run_subprocess(invocation, check=check)
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

    def _invocation(self, command: KhtoolCommand) -> KhtoolInvocation:
        return KhtoolInvocation(
            interface=require_interface(self._settings),
            target="all",
            command=command,
        )

    def _run_subprocess(
        self,
        invocation: KhtoolInvocation,
        *,
        check: bool,
    ) -> subprocess.CompletedProcess[str]:
        settings = self._settings
        if not settings.khtool.is_file():
            raise KhvolError(f"khtool not found: {settings.khtool}", EXIT_ERROR)

        argv = invocation.argv()
        if getattr(sys, "frozen", False):
            cmd = [
                sys.executable,
                "--run-khtool",
                "-i",
                invocation.interface,
                "-t",
                invocation.target,
                *argv,
            ]
        else:
            cmd = [
                python_executable(),
                str(settings.khtool),
                "-i",
                invocation.interface,
                "-t",
                invocation.target,
                *argv,
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
