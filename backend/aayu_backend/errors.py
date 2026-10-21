"""Errors the helper reports to the app, and logging them safely.

A ``UserError`` carries a message written for the person using the app plus a
machine-readable ``Code``; the server sends both in its error reply. Anything
else that escapes is a bug: the app gets a generic message, the log gets the
details.
"""

import logging
import os
import traceback
from enum import StrEnum


class Code(StrEnum):
    """Error codes, sent as an error reply's ``code`` (and a status's ``error_code``)."""

    NO_FOLDER = "no_folder"            # no export folder is open
    FOLDER_MISSING = "folder_missing"  # the open folder doesn't exist (any more)
    NO_DATA = "no_data"                # the folder holds no usable Zepp data
    UNREADABLE = "unreadable"          # a CSV couldn't be read or parsed
    BAD_REQUEST = "bad_request"        # the line isn't a valid request object
    UNKNOWN_METHOD = "unknown_method"  # the method isn't in ``Server.METHODS``
    BAD_PARAMS = "bad_params"          # missing, unexpected or invalid params
    INTERNAL = "internal"              # a bug; the details are in the log


class UserError(Exception):
    """A failure whose message is meant for the UI."""

    def __init__(self, message: str, code: Code) -> None:
        """Wrap `message` (shown to the user) with its `code`."""
        super().__init__(message)
        self.message = message
        self.code = code


def where(exc: BaseException) -> str:
    """Where `exc` was raised, as ``file.py:123 in func`` — the innermost frame in this package."""
    frames = traceback.extract_tb(exc.__traceback__)
    ours = [f for f in frames if f"{os.sep}aayu_backend{os.sep}" in f.filename]
    if not (ours or frames):
        return "unknown location"
    frame = (ours or frames)[-1]
    return f"{os.path.basename(frame.filename)}:{frame.lineno} in {frame.name}"


def log_failure(log: logging.Logger, what: str, exc: BaseException) -> None:
    """Log an unexpected exception without its message.

    pandas errors can quote CSV cells (health data), so levels that are on by
    default get only the exception type and location; the message and full
    traceback go out at DEBUG.
    """
    log.error("%s failed: %s at %s", what, type(exc).__name__, where(exc))
    log.debug("%s failure details", what, exc_info=exc)
