import datetime
import io
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

import numpy as np
import pytest

from aayu_backend import data, series, server
from aayu_backend.server import Server
from tests.conftest import write_csv

BACKEND = Path(__file__).resolve().parents[1]


class Client:
    """A Server writing into a StringIO; ``call`` returns the one reply line, parsed."""

    def __init__(self):
        self.out = io.StringIO()
        self.server = Server(self.out)
        self.next_id = 0

    def lines(self):
        return [json.loads(line) for line in self.out.getvalue().splitlines()]

    def raw(self, line):
        before = len(self.out.getvalue().splitlines())
        self.server.handle(line)
        lines = self.out.getvalue().splitlines()
        assert len(lines) == before + 1, "exactly one reply line per request"
        return json.loads(lines[-1])

    def call(self, method, **params):
        self.next_id += 1
        reply = self.raw(json.dumps({"id": self.next_id, "method": method, "params": params}))
        assert reply["id"] == self.next_id
        return reply


@pytest.fixture
def client():
    return Client()


def test_metric_names_cover_every_metric():
    assert set(server._LABELS) == set(data._COLUMNS) == set(server.METRIC_NAMES)


def test_open_then_dashboard(client, export):
    status = client.call("open", folder=str(export))["result"]
    assert status == {"exists": True, "found": list(server.METRIC_NAMES.values()), "total": 6,
                      "error": None, "error_code": None}
    result = client.call("dashboard", selection=None, units="kg", default_range="month", night=None)["result"]
    assert result["selection"] == "2026-05" and result["units"] == "kg"
    assert client.call("dashboard")["result"]["units"] == "lbs"
    assert client.call("reload")["result"]["exists"] is True
    assert client.call("watch", enabled=True) == {"id": client.next_id, "result": None}


def test_dashboard_scores_against_the_targets(client, export):
    client.call("open", folder=str(export))
    default = client.call("dashboard")["result"]["kpis"]
    assert client.call("dashboard", bedtime="23:30", wake_time="06:30")["result"]["kpis"] == default
    assert series.SleepTargets(datetime.time(23, 30), datetime.time(6, 30)) == series.DEFAULT_TARGETS
    late = client.call("dashboard", bedtime="03:00", wake_time="11:00")["result"]["kpis"]
    assert late["sleep_score_parts"]["timing"] < default["sleep_score_parts"]["timing"]


@pytest.mark.parametrize("method", ["_load", "handle", "__init__", "poll_once", "watch_loop", "_read", "nope"])
def test_only_protocol_methods_are_callable(client, method):
    reply = client.call(method)
    assert reply["code"] == "unknown_method" and "result" not in reply


@pytest.mark.parametrize(("line", "code"), [
    ("not json", "bad_request"),
    ("[1, 2]", "bad_request"),
    ('"open"', "bad_request"),
    ('{"id": 1}', "bad_request"),
    ('{"id": 1, "method": 5}', "bad_request"),
    ('{"id": NaN, "method": "reload"}', "bad_request"),
    ('{"id": [1], "method": "reload"}', "bad_request"),
    ('{"id": 1, "method": "reload", "params": [1]}', "bad_params"),
    ('{"id": 1, "method": "open", "params": {"path": "/tmp"}}', "bad_params"),
    ('{"id": 1, "method": "open", "params": {}}', "bad_params"),
    ('{"id": 1, "method": "open", "params": {"folder": "relative/path"}}', "bad_params"),
    ('{"id": 1, "method": "open", "params": {"folder": 3}}', "bad_params"),
    ('{"id": 1, "method": "watch", "params": {"enabled": "yes"}}', "bad_params"),
    ('{"id": 1, "method": "dashboard", "params": {"units": "stone"}}', "bad_params"),
    ('{"id": 1, "method": "dashboard", "params": {"default_range": "year"}}', "bad_params"),
    ('{"id": 1, "method": "dashboard", "params": {"night": 20260501}}', "bad_params"),
    ('{"id": 1, "method": "dashboard", "params": {"bedtime": "11:30 PM"}}', "bad_params"),
    ('{"id": 1, "method": "dashboard", "params": {"bedtime": "24:00"}}', "bad_params"),
    ('{"id": 1, "method": "dashboard", "params": {"wake_time": "6:30"}}', "bad_params"),
    ('{"id": 1, "method": "dashboard", "params": {"wake_time": 630}}', "bad_params"),
])
def test_bad_requests_get_one_error_line(client, line, code):
    reply = client.raw(line)
    assert reply["code"] == code and isinstance(reply["error"], str) and "result" not in reply


def test_invalid_utf8_is_a_bad_request(client):
    assert client.raw(b'{"id": 1, "method": "\xff"}')["code"] == "bad_request"


def test_params_null_means_none(client):
    assert client.raw('{"id": 7, "method": "reload", "params": null}')["id"] == 7
    assert "result" in client.raw('{"id": 8, "method": "reload"}')


def test_dashboard_before_open(client):
    assert client.call("dashboard")["code"] == "no_folder"


def test_nonexistent_and_empty_folders(client, tmp_path):
    missing = client.call("open", folder=str(tmp_path / "gone"))["result"]
    assert missing["exists"] is False and missing["error_code"] == "folder_missing"
    assert "doesn't exist" in missing["error"]
    assert client.call("dashboard")["code"] == "folder_missing"

    empty = client.call("open", folder=str(tmp_path))["result"]
    assert empty["exists"] is True and empty["found"] == [] and empty["error_code"] == "no_data"
    assert client.call("dashboard")["code"] == "no_data"


def test_status_of_other_folders(client, export, tmp_path):
    client.call("open", folder=str(tmp_path / "gone"))
    assert client.call("status", folder=str(export))["result"]["error"] is None
    assert client.call("status", folder="relative")["result"]["exists"] is False
    assert client.call("status", folder=str(tmp_path / "gone"))["result"]["error_code"] == "folder_missing"


def test_reload_without_folder_returns_status(client):
    assert client.call("reload")["result"] == {"exists": False, "found": [], "total": 6, "error": None,
                                               "error_code": None}


def test_unreadable_export(client, tmp_path):
    write_csv(tmp_path / "SLEEP" / "s.csv", ["date", "deepSleepTime"], [{"date": "2026-05-01", "deepSleepTime": 1}])
    status = client.call("open", folder=str(tmp_path))["result"]
    assert status["error_code"] == "unreadable" and "Sleep" in status["error"]
    assert client.call("dashboard")["code"] == "unreadable"


def test_nan_never_produces_invalid_json(client, export, monkeypatch):
    client.call("open", folder=str(export))
    monkeypatch.setattr(server.series, "dashboard", lambda *a: {"value": float("nan")})
    reply = client.call("dashboard")
    assert reply["code"] == "internal" and "nan" not in json.dumps(reply).lower()


def test_unexpected_errors_get_generic_text(client, export, monkeypatch):
    client.call("open", folder=str(export))

    def boom(*_):
        raise RuntimeError("secret cell 72.4")

    monkeypatch.setattr(server.series, "dashboard", boom)
    reply = client.call("dashboard")
    assert reply == {"id": client.next_id, "error": server.INTERNAL_MESSAGE, "code": "internal"}


def test_encode_numpy_scalars_and_rejects_others():
    assert server.encode({"a": np.int64(3), "b": np.float32(0.5), "c": np.bool_(True)}) == '{"a":3,"b":0.5,"c":true}'
    with pytest.raises(TypeError):
        server.encode({"a": object()})
    with pytest.raises(ValueError, match="JSON"):
        server.encode({"a": np.float64("nan")})


def test_broken_pipe_is_quiet():
    class Broken(io.StringIO):
        def write(self, s):
            raise BrokenPipeError

    s = Server(Broken())
    s.handle('{"id": 1, "method": "reload"}')
    assert s.closed.is_set()
    s.send_event("reloaded")   # no raise


# ── Watcher ─────────────────────────────────────────────────────────────────────
def test_poll_once_reloads_after_export_holds_still(client, export):
    client.call("open", folder=str(export))
    s = client.server
    assert s.poll_once() is False   # watch is off
    client.call("watch", enabled=True)
    assert s.poll_once() is False   # unchanged
    csv = next((export / "ACTIVITY").glob("*.csv"))
    write_csv(export / "ACTIVITY" / "ACTIVITY_2.csv", data._COLUMNS["ACTIVITY"],
              [{"date": "2026-06-01", "steps": 10, "calories": 1}], mtime=csv.stat().st_mtime + 10)
    assert s.poll_once() is False   # changed: wait one poll
    assert s.poll_once() is True    # held still: reload
    assert client.lines()[-1] == {"event": "reloaded"}
    assert client.call("dashboard")["result"]["selection"] == "2026-06"
    assert s.poll_once() is False


def test_poll_once_survives_vanished_folder(client, export):
    client.call("open", folder=str(export))
    client.call("watch", enabled=True)
    for p in sorted(export.rglob("*"), reverse=True):
        p.rmdir() if p.is_dir() else p.unlink()
    export.rmdir()
    assert server.signature(str(export)) == ()
    assert [client.server.poll_once(), client.server.poll_once()] == [False, True]
    assert client.call("dashboard")["code"] == "folder_missing"


def test_signature_skips_files_that_vanish(export, monkeypatch):
    real = os.DirEntry.stat
    calls = []

    def flaky(self, *a, **k):
        calls.append(self.name)
        if len(calls) == 1:
            raise FileNotFoundError(self.path)
        return real(self, *a, **k)

    monkeypatch.setattr(os.DirEntry, "stat", flaky)
    sig = server.signature(str(export))
    assert len(sig) == len(data.METRICS) - 1


def test_watch_loop_survives_failures_and_stops(client):
    s = client.server
    polls = []

    def bad_poll():
        polls.append(1)
        raise OSError("disk went away")

    s.poll_once = bad_poll
    stop = threading.Event()
    t = threading.Thread(target=s.watch_loop, args=(stop, 0.01))
    t.start()
    time.sleep(0.1)
    stop.set()
    t.join(1)
    assert not t.is_alive() and len(polls) > 1


# ── The real process ────────────────────────────────────────────────────────────
def test_subprocess_protocol_and_clean_exit(export):
    env = {**os.environ, "PYTHONPATH": str(BACKEND), "AAYU_LOG_LEVEL": "DEBUG"}
    proc = subprocess.Popen([sys.executable, "-m", "aayu_backend"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env, cwd=BACKEND)
    requests = [
        {"id": 1, "method": "open", "params": {"folder": str(export)}},
        {"id": 2, "method": "dashboard", "params": {"selection": None, "units": "lbs", "default_range": "month",
                                                     "night": None}},
        {"id": 3, "method": "nope", "params": {}},
    ]
    payload = "".join(json.dumps(r) + "\n" for r in requests) + "garbage\n\n"
    began = time.monotonic()
    out, err = proc.communicate(payload.encode(), timeout=10)
    lines = [json.loads(line) for line in out.decode().splitlines()]
    assert proc.returncode == 0
    assert [r.get("id") for r in lines] == [1, 2, 3, None]
    assert "result" in lines[1] and lines[1]["result"]["kpis"]["avg_steps"] is not None
    assert lines[2]["code"] == "unknown_method" and lines[3]["code"] == "bad_request"
    assert b"dashboard id=2 ok" in err
    assert time.monotonic() - began < 10


def test_subprocess_exits_on_eof_quickly():
    env = {**os.environ, "PYTHONPATH": str(BACKEND)}
    proc = subprocess.Popen([sys.executable, "-m", "aayu_backend"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env, cwd=BACKEND)
    time.sleep(0.5)   # let it start up and block on stdin
    began = time.monotonic()
    proc.stdin.close()
    assert proc.wait(timeout=2) == 0
    assert time.monotonic() - began < 2
    assert proc.stdout.read() == b""
    proc.stdout.close()
    proc.stderr.close()


def test_subprocess_stray_writes_go_to_stderr(tmp_path):
    script = ("import os, sys; from aayu_backend import server; out = server.claim_stdout(); "
              "print('stray'); os.write(1, b'c-level\\n'); out.write('{}\\n'); out.flush()")
    done = subprocess.run([sys.executable, "-c", script], capture_output=True, timeout=10,
                          env={**os.environ, "PYTHONPATH": str(BACKEND)}, check=True)
    assert done.stdout == b"{}\n"
    assert b"stray" in done.stderr and b"c-level" in done.stderr
