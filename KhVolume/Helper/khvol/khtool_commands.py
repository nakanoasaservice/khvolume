"""Typed khtool command definitions."""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import Enum, auto
from typing import TypeAlias


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


KhtoolCommand: TypeAlias = ExpertQuery | ExpertSetLevel | MuteCommand
