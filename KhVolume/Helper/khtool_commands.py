"""Typed khtool command definitions."""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import Enum, auto
from typing import Literal, TypeAlias

KhtoolTarget = Literal["all"]


class ExpertQuery(Enum):
    LEVEL = auto()
    MUTE = auto()

    @property
    def payload(self) -> str:
        match self:
            case ExpertQuery.LEVEL:
                return '{"audio":{"out":{"level":null}}}'
            case ExpertQuery.MUTE:
                return '{"audio":{"out":{"mute":null}}}'


@dataclass(frozen=True, slots=True)
class ExpertSetLevel:
    level: float

    @property
    def payload(self) -> str:
        return json.dumps(
            {"audio": {"out": {"level": self.level}}},
            separators=(",", ":"),
        )


@dataclass(frozen=True, slots=True)
class MuteCommand:
    muted: bool


@dataclass(frozen=True, slots=True)
class KhtoolInvocation:
    interface: str
    target: KhtoolTarget
    command: KhtoolCommand

    def argv(self) -> tuple[str, ...]:
        match self.command:
            case ExpertQuery.LEVEL | ExpertQuery.MUTE | ExpertSetLevel() as command:
                return ("--expert", command.payload)
            case MuteCommand(muted=True):
                return ("--mute",)
            case MuteCommand(muted=False):
                return ("--unmute",)


KhtoolCommand: TypeAlias = ExpertQuery | ExpertSetLevel | MuteCommand
