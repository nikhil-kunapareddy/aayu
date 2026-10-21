"""
The backend process: JSON lines over stdin/stdout.

The SwiftUI app starts this as a hidden helper (no network port). Each request
is one line, ``{"id": 1, "method": "dashboard", "params": {...}}``, answered by
one line with the same id and either ``"result"`` or ``"error"``. When
auto-reload notices a new export it reloads and sends ``{"event": "reloaded"}``.

stdout carries protocol lines only; logs and tracebacks go to stderr. EOF on
stdin (the app quit or crashed) ends the process.
"""

import json
import os
import sys
import threading
import time
import traceback

from aayu_backend import data, series

POLL_SECONDS = 3

# How each metric folder is named in the Settings status line.
METRIC_NAMES = {
    "SLEEP": "Sleep", "ACTIVITY": "Activity", "BODY": "Weight",
    "SPORT": "Workouts", "HEARTRATE_AUTO": "Heart rate", "SLEEP_MINUTE": "Sleep stages",
}


def signature(folder: str) -> tuple:
    """(metric, file, mtime, size) for every CSV the dashboard reads under
    ``folder`` — changes whenever an export is added or replaced."""
    sig = []
    for metric in data.METRICS:
        try:
            entries = list(os.scandir(os.path.join(folder, metric)))
        except OSError:
            continue
        for e in entries:
            if e.name.endswith(".csv"):
                st = e.stat()
                sig.append((metric, e.name, st.st_mtime_ns, st.st_size))
    return tuple(sorted(sig))


class Server:
    """Holds the loaded export and answers requests. Public methods are the
    protocol: ``METHODS`` lists what the app may call."""

    METHODS = ("open", "reload", "status", "dashboard", "watch")

    def __init__(self, out=sys.stdout) -> None:
        self._out = out
        self._write_lock = threading.Lock()
        self._load_lock = threading.Lock()
        self._folder = ""
        self._data = None    # data.Data for _folder
        self._error = None   # why _folder couldn't be loaded
        self._sig = None     # folder signature the data was loaded from
        self._watch = False

    # ── Protocol methods ─────────────────────────────────────────────────────
    def open(self, folder: str) -> dict:
        """Load the export at `folder`; returns its status (with any load error)."""
        self._folder = folder
        self._load()
        return self.status(folder)

    def reload(self) -> dict:
        """Re-read the current folder (⌘R)."""
        self._load()
        return self.status(self._folder)

    def status(self, folder: str) -> dict:
        """Which metrics a folder has, for the Settings status line. `error` is
        set when it's the open folder and loading it failed."""
        exists = bool(folder) and os.path.isdir(folder)
        return {
            "exists": exists,
            "found": [METRIC_NAMES[m] for m in data.found_metrics(folder)] if exists else [],
            "total": len(data.METRICS),
            "error": self._error if folder == self._folder else None,
        }

    def dashboard(self, selection: str | None = None, units: str = "lbs", default_range: str = "month",
                  night: str | None = None) -> dict:
        d = self._data
        if d is None:
            raise RuntimeError(self._error or "No folder is open.")
        return series.dashboard(d, selection, units, default_range, night)

    def watch(self, enabled: bool) -> None:
        """Turn auto-reload on or off."""
        self._watch = enabled

    # ── Internals ────────────────────────────────────────────────────────────
    def _load(self) -> None:
        """Build the new state first and swap it in at the end, so a request
        mid-reload sees the old data rather than none."""
        with self._load_lock:
            folder = self._folder
            loaded, error, sig = None, None, None
            if folder:
                sig = signature(folder)
                if not os.path.isdir(folder):
                    error = f"The folder {folder} doesn't exist any more."
                elif not data.found_metrics(folder):
                    error = (f"No Zepp data in {folder}. Choose the folder that "
                             "contains SLEEP, ACTIVITY, BODY and the other data folders.")
                else:
                    try:
                        loaded = data.load(folder)
                    except Exception as e:  # a malformed or unexpected CSV
                        traceback.print_exc(file=sys.stderr)
                        error = f"Couldn't read the export: {e}"
            self._data, self._error, self._sig = loaded, error, sig

    def _send(self, message: dict) -> None:
        line = json.dumps(message, allow_nan=False, separators=(",", ":"),
                          default=lambda o: o.item() if hasattr(o, "item") else str(o))
        with self._write_lock:
            self._out.write(line + "\n")
            self._out.flush()

    def handle(self, line: str) -> None:
        """Answer one request line."""
        req_id = None
        try:
            req = json.loads(line)
            req_id = req["id"]
            if req["method"] not in self.METHODS:
                raise ValueError(f"unknown method {req['method']!r}")
            result = getattr(self, req["method"])(**req.get("params", {}))
            self._send({"id": req_id, "result": result})
        except Exception as e:
            traceback.print_exc(file=sys.stderr)
            self._send({"id": req_id, "error": str(e)})

    def watch_loop(self) -> None:
        """Poll the folder; reload once a changed export has held still for one
        poll (so a half-copied export isn't read), then tell the app."""
        pending = None
        while True:
            time.sleep(POLL_SECONDS)
            if not (self._watch and self._folder):
                pending = None
                continue
            sig = signature(self._folder)
            if sig == self._sig:
                pending = None
            elif sig == pending:
                self._load()
                self._send({"event": "reloaded"})
                pending = None
            else:
                pending = sig


def main() -> None:
    server = Server()
    threading.Thread(target=server.watch_loop, daemon=True).start()
    for line in sys.stdin:
        if line.strip():
            server.handle(line)
