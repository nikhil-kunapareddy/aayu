"""The backend process: JSON lines over stdin/stdout.

The SwiftUI app starts this as a hidden helper (no network port). Each request
is one line, ``{"id": 1, "method": "dashboard", "params": {...}}``, answered by
exactly one line with the same id and either ``"result"`` or ``"error"`` (a
message for the UI) plus ``"code"`` (an ``errors.Code``). A line that can't be
parsed far enough to find its id is answered with ``"id": null``. When
auto-reload notices a new export it reloads and sends ``{"event": "reloaded"}``.

stdout carries protocol lines only: ``main()`` keeps a private copy of fd 1 for
them and points fd 1 and ``sys.stdout`` at stderr, so a stray print or a C
library's write can't corrupt the stream. Logs go to stderr (``AAYU_LOG_LEVEL``,
default WARNING). EOF on stdin, or the app closing its end of stdout, ends the
process.
"""

import contextlib
import datetime
import inspect
import json
import logging
import os
import re
import sys
import threading
import time
from collections.abc import Callable, Mapping
from typing import Final, TextIO, cast

import numpy as np

from aayu_backend import data, series
from aayu_backend.errors import Code, UserError, log_failure
from aayu_backend.payload import DEFAULT_RANGES, UNITS, Dashboard, FolderStatus, Units

log = logging.getLogger(__name__)

POLL_SECONDS: Final = 3.0   # folder watcher interval
STOP_SECONDS: Final = 1.0   # how long shutdown waits for the watcher
LOG_LEVEL_ENV: Final = "AAYU_LOG_LEVEL"

# How each metric folder is named in the Settings status line. Built from
# data.METRICS, so adding a metric there without a label fails at import.
_LABELS = {
    "SLEEP": "Sleep", "ACTIVITY": "Activity", "BODY": "Weight",
    "SPORT": "Workouts", "HEARTRATE_AUTO": "Heart rate", "SLEEP_MINUTE": "Sleep stages",
}
METRIC_NAMES: Final = {metric: _LABELS[metric] for metric in data.METRICS}

INTERNAL_MESSAGE: Final = "Something went wrong in Aayu's data helper. Try again, or reload the data (⌘R)."

Signature = tuple[tuple[str, str, int, int], ...]


def signature(folder: str) -> Signature:
    """(metric, file, mtime, size) for every CSV the dashboard may read under ``folder``.

    Changes whenever an export is added or replaced. Files that vanish while
    being listed are skipped, so this never raises for a missing folder.
    """
    return tuple(sorted(
        (metric, os.path.basename(path), st.st_mtime_ns, st.st_size)
        for metric in data.METRICS
        for path, st in data.csv_files(folder, metric)
    ))


# ── JSON ──────────────────────────────────────────────────────────────────────
def _jsonable(o: object) -> object:
    """``json.dumps`` fallback: numpy scalars become Python ones; anything else is a bug."""
    if isinstance(o, np.generic):
        return o.item()
    raise TypeError(f"{type(o).__name__} isn't JSON serializable")


def encode(message: Mapping[str, object]) -> str:
    """One protocol line (without the newline). Raises ValueError on NaN/inf, TypeError on odd types."""
    return json.dumps(message, allow_nan=False, separators=(",", ":"), default=_jsonable)


def _reject_constant(name: str) -> object:
    raise ValueError(f"{name} isn't valid JSON")


# ── Params ────────────────────────────────────────────────────────────────────
def _bad(message: str) -> UserError:
    return UserError(message, Code.BAD_PARAMS)


def _str(name: str, value: object) -> str:
    if not isinstance(value, str):
        raise _bad(f"'{name}' must be a string.")
    if "\0" in value:
        raise _bad(f"'{name}' mustn't contain NUL characters.")
    return value


def _optional_str(name: str, value: object) -> str | None:
    return None if value is None else _str(name, value)


def _choice[T: str](name: str, value: object, allowed: tuple[T, ...]) -> T:
    if value not in allowed:
        raise _bad(f"'{name}' must be one of {', '.join(allowed)}.")
    return value  # `value in allowed` narrows it to T


_HH_MM: Final = re.compile(r"([01][0-9]|2[0-3]):([0-5][0-9])")


def _clock_time(name: str, value: object) -> datetime.time:
    """A time of day sent as 'HH:MM' (24-hour), e.g. '23:30'."""
    match = _HH_MM.fullmatch(_str(name, value))
    if match is None:
        raise _bad(f"'{name}' must be a 24-hour time, HH:MM.")
    return datetime.time(int(match[1]), int(match[2]))


def _folder(value: object) -> str:
    folder = _str("folder", value)
    if not os.path.isabs(folder):
        raise _bad("'folder' must be an absolute path.")
    return folder


class Server:
    """Holds the loaded export and answers requests.

    Public methods named in ``METHODS`` are the protocol; nothing else can be
    called from a request line.
    """

    METHODS: Final = ("open", "reload", "status", "dashboard", "watch")

    def __init__(self, out: TextIO) -> None:
        """Answer on `out` (the protocol stream)."""
        self._out = out
        self._write_lock = threading.Lock()
        self._load_lock = threading.Lock()
        self._folder = ""
        self._data: data.Data | None = None    # the export loaded from _folder
        self._error: UserError | None = None   # why _folder couldn't be loaded
        self._sig: Signature | None = None     # folder signature the data was loaded from
        self._pending: Signature | None = None  # a changed signature waiting to hold still
        self._watch = False
        self.closed = threading.Event()        # set once the app stops reading our output

    # ── Protocol methods ─────────────────────────────────────────────────────
    def open(self, folder: object) -> FolderStatus:
        """Load the export at `folder` (an absolute path); returns its status, with any load error."""
        self._folder = _folder(folder)
        self._load()
        return self.status(self._folder)

    def reload(self) -> FolderStatus:
        """Re-read the current folder (⌘R)."""
        self._load()
        return self.status(self._folder)

    def status(self, folder: object) -> FolderStatus:
        """Which metrics a folder has, for the Settings status line.

        ``error`` (and ``error_code``) are set when it's the open folder and
        loading it failed. A relative or missing path just doesn't exist.
        """
        folder = _str("folder", folder)
        exists = os.path.isabs(folder) and os.path.isdir(folder)
        error = self._error if folder == self._folder else None
        return {
            "exists": exists,
            "found": [METRIC_NAMES[m] for m in data.found_metrics(folder)] if exists else [],
            "total": len(data.METRICS),
            "error": error.message if error else None,
            "error_code": error.code if error else None,
        }

    def dashboard(self, selection: object = None, units: object = "lbs", default_range: object = "month",
                  night: object = None, bedtime: object = "23:30", wake_time: object = "06:30") -> Dashboard:
        """Everything the dashboard shows (see ``series.dashboard``).

        The sleep score's timing aims for `bedtime` and `wake_time` ('HH:MM', 24-hour).
        """
        checked_units: Units = _choice("units", units, UNITS)
        checked_range = _choice("default_range", default_range, DEFAULT_RANGES)
        checked_selection, checked_night = _optional_str("selection", selection), _optional_str("night", night)
        targets = series.SleepTargets(_clock_time("bedtime", bedtime), _clock_time("wake_time", wake_time))
        d, error = self._data, self._error
        if d is None:
            if error is not None:
                raise UserError(error.message, error.code)
            raise UserError("No folder is open.", Code.NO_FOLDER)
        return series.dashboard(d, checked_selection, checked_units, checked_range, checked_night, targets)

    def watch(self, enabled: object) -> None:
        """Turn auto-reload on or off."""
        if not isinstance(enabled, bool):
            raise _bad("'enabled' must be true or false.")
        self._watch = enabled

    # ── Loading ──────────────────────────────────────────────────────────────
    def _load(self) -> None:
        """Load the current folder.

        Builds the new state first and swaps it in at the end, so a request
        mid-reload sees the old data rather than none.
        """
        with self._load_lock:
            folder = self._folder
            loaded: data.Data | None = None
            error: UserError | None = None
            sig: Signature | None = None
            if folder:
                sig = signature(folder)
                try:
                    loaded = self._read(folder)
                except UserError as e:
                    log.info("loading the export failed: %s", e.code)
                    error = e
            self._data, self._error, self._sig = loaded, error, sig

    @staticmethod
    def _read(folder: str) -> data.Data:
        """``data.load(folder)``, with failures turned into a ``UserError`` for the UI."""
        if not os.path.isdir(folder):
            raise UserError(f"The folder {folder} doesn't exist any more.", Code.FOLDER_MISSING)
        if not data.found_metrics(folder):
            raise UserError(f"No Zepp data in {folder}. Choose the folder that contains SLEEP, ACTIVITY, "
                            "BODY and the other data folders.", Code.NO_DATA)
        try:
            return data.load(folder)
        except data.ExportError as e:
            log.warning("couldn't read %s: %s", e.metric, e.reason)
            raise UserError(f"Couldn't read the {METRIC_NAMES[e.metric]} data in this export: {e.reason}.",
                            Code.UNREADABLE) from e
        except Exception as e:  # an odd CSV shouldn't look like a crash
            log_failure(log, "loading the export", e)
            raise UserError("Couldn't read the export. One of its CSV files may be damaged or in an "
                            "unexpected format.", Code.UNREADABLE) from e

    # ── Lines ────────────────────────────────────────────────────────────────
    def _write(self, line: str) -> None:
        """Send one line; if the app has stopped reading, note it and stay quiet."""
        with self._write_lock:
            if self.closed.is_set():
                return
            try:
                self._out.write(line + "\n")
                self._out.flush()
            except BrokenPipeError:
                log.info("the app closed the pipe; stopping")
                self.closed.set()

    def send_event(self, event: str) -> None:
        """Push ``{"event": event}`` to the app."""
        self._write(encode({"event": event}))

    def _call(self, method: str, params: dict[str, object]) -> object:
        """Run protocol method `method` with `params` (checked against its signature)."""
        fn = cast(Callable[..., object], getattr(self, method))
        try:
            bound = inspect.signature(fn).bind(**params)
        except TypeError as e:
            raise _bad(f"Bad parameters for {method}: {e}.") from e
        return fn(*bound.args, **bound.kwargs)

    def handle(self, line: str | bytes) -> None:
        """Answer one request line with exactly one reply line."""
        began = time.perf_counter()
        req_id: int | str | None = None
        method = "?"
        try:
            if isinstance(line, bytes):
                try:
                    line = line.decode("utf-8")
                except UnicodeDecodeError as e:
                    raise UserError("The request isn't UTF-8 text.", Code.BAD_REQUEST) from e
            try:
                req = json.loads(line, parse_constant=_reject_constant)
            except ValueError as e:
                raise UserError("The request isn't valid JSON.", Code.BAD_REQUEST) from e
            if not isinstance(req, dict):
                raise UserError("A request must be a JSON object.", Code.BAD_REQUEST)
            raw_id = req.get("id")
            if raw_id is not None and (isinstance(raw_id, bool) or not isinstance(raw_id, int | str)):
                raise UserError("A request's id must be a number or a string.", Code.BAD_REQUEST)
            req_id = raw_id
            raw_method = req.get("method")
            if not isinstance(raw_method, str):
                raise UserError("A request needs a method name.", Code.BAD_REQUEST)
            if raw_method not in self.METHODS:
                raise UserError(f"Unknown method {raw_method[:40]!r}.", Code.UNKNOWN_METHOD)
            method = raw_method
            params = req.get("params")
            if params is None:
                params = {}
            if not isinstance(params, dict):
                raise _bad("'params' must be an object.")
            reply = encode({"id": req_id, "result": self._call(method, params)})
            outcome = "ok"
        except UserError as e:
            reply = encode({"id": req_id, "error": e.message, "code": e.code})
            outcome = e.code
        except Exception as e:  # noqa: BLE001 — logged; the app always gets its one reply
            log_failure(log, f"request {method!r}", e)
            reply = encode({"id": req_id, "error": INTERNAL_MESSAGE, "code": Code.INTERNAL})
            outcome = Code.INTERNAL
        self._write(reply)
        log.debug("%s id=%s %s in %.1f ms", method, req_id, outcome, (time.perf_counter() - began) * 1000)

    # ── Folder watcher ───────────────────────────────────────────────────────
    def poll_once(self) -> bool:
        """One watcher step; True when it reloaded (and told the app).

        A changed export is reloaded once it has held still for one poll, so
        a half-copied export isn't read.
        """
        folder = self._folder
        if not (self._watch and folder):
            self._pending = None
            return False
        sig = signature(folder)
        if sig == self._sig:
            self._pending = None
            return False
        if sig != self._pending:
            self._pending = sig
            return False
        self._pending = None
        log.info("the export changed; reloading")
        self._load()
        self.send_event("reloaded")
        return True

    def watch_loop(self, stop: threading.Event, interval: float = POLL_SECONDS) -> None:
        """Poll every `interval` seconds until `stop` is set; a failed poll is logged and retried."""
        while not stop.wait(interval):
            try:
                self.poll_once()
            except Exception as e:  # noqa: BLE001 — the watcher must never die
                log_failure(log, "watching the folder", e)


# ── Process ───────────────────────────────────────────────────────────────────
def configure_logging() -> None:
    """Log to stderr at ``$AAYU_LOG_LEVEL`` (default WARNING), Python warnings included."""
    name = os.environ.get(LOG_LEVEL_ENV, "WARNING").strip().upper()
    level = logging.getLevelNamesMapping().get(name)
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter("%(asctime)s aayu-backend %(levelname)s %(name)s: %(message)s"))
    root = logging.getLogger()
    root.addHandler(handler)
    root.setLevel(logging.WARNING if level is None else level)
    logging.captureWarnings(True)
    if level is None:
        log.warning("%s=%r isn't a log level; using WARNING", LOG_LEVEL_ENV, name[:20])


def claim_stdout() -> TextIO:
    """Keep a private copy of fd 1 for the protocol; send fd 1 and ``sys.stdout`` to stderr."""
    sys.stdout.flush()
    fd = os.dup(1)   # not inheritable: child processes never see the protocol stream
    os.dup2(2, 1)
    sys.stdout = sys.stderr
    return os.fdopen(fd, "w", encoding="utf-8", newline="\n")


def main() -> int:
    """Serve requests from stdin until it closes; returns the exit status."""
    out = claim_stdout()
    configure_logging()
    server = Server(out)
    stop = threading.Event()
    watcher = threading.Thread(target=server.watch_loop, args=(stop,), name="aayu-watcher", daemon=True)
    watcher.start()
    log.debug("ready")
    try:
        for line in sys.stdin.buffer:
            if server.closed.is_set():
                break
            if line.strip():
                server.handle(line)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        watcher.join(STOP_SECONDS)
        with contextlib.suppress(OSError):   # a broken pipe's unflushed bytes
            out.close()
    log.debug("stdin closed; exiting")
    return 0
