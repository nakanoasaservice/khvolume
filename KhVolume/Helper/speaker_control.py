"""High-level speaker control commands."""

from __future__ import annotations

import json

from khvol_errors import (
    EXIT_OK,
)
from khvol_settings import Settings
from khtool_runner import KhtoolRunner
from speaker_status import SpeakerStatus, parse_khtool_status, status_json_document


def read_status(runner: KhtoolRunner) -> SpeakerStatus:
    return parse_khtool_status(runner.read_status_output())


def emit_status_json(status: SpeakerStatus) -> int:
    print(json.dumps(status_json_document(status), separators=(",", ":")))
    return EXIT_OK


def emit_current_status_json(settings: Settings) -> int:
    runner = KhtoolRunner(settings)
    return emit_status_json(read_status(runner))


def set_level_and_emit_status(settings: Settings, level: float) -> int:
    runner = KhtoolRunner(settings)
    runner.set_level(level)
    return emit_status_json(read_status(runner))


def set_muted_and_emit_status(settings: Settings, muted: bool) -> int:
    runner = KhtoolRunner(settings)
    runner.set_muted(muted)
    return emit_status_json(read_status(runner))
