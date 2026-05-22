"""Shared khvol exit codes and errors."""

from __future__ import annotations

import sys

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_DEVICE = 2


class KhvolError(Exception):
    def __init__(self, message: str, code: int = EXIT_ERROR) -> None:
        super().__init__(message)
        self.code = code


def eprint(message: str) -> None:
    print(message, file=sys.stderr)
