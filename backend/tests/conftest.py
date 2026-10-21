"""Shared fixtures: fabricated Zepp exports written into pytest's tmp_path.

Nothing here reads the repo's data/ folder. Headers come from
``data._COLUMNS`` and files carry a UTF-8 BOM, like real Zepp exports.

Times passed to ``make_night`` are local wall-clock times in ``series.TZ``;
SLEEP start/stop are written in UTC (as Zepp does), SLEEP_MINUTE rows in local
time. Stage minutes advance in real (UTC) time and are stamped with the local
clock, so DST nights skip or repeat an hour exactly as a watch would.
"""

from __future__ import annotations

import csv
import os
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import pytest

from aayu_backend import data

LOCAL = ZoneInfo("America/New_York")
UTC = ZoneInfo("UTC")
STAGE_COLUMN = {"DEEP": "deepSleepTime", "LIGHT": "shallowSleepTime", "REM": "REMTime", "WAKE": "wakeTime"}

Row = Mapping[str, object]


def local(text: str) -> datetime:
    """'YYYY-MM-DD HH:MM' local wall-clock time, as an aware datetime."""
    return datetime.fromisoformat(text).replace(tzinfo=LOCAL)


def utc_text(text: str) -> str:
    """A local 'YYYY-MM-DD HH:MM' as Zepp's UTC stamp ('… HH:MM:SS+0000')."""
    return local(text).astimezone(UTC).strftime("%Y-%m-%d %H:%M:%S+0000")


@dataclass
class Night:
    """One night's SLEEP row plus its SLEEP_MINUTE rows."""

    sleep: dict[str, object]
    minutes: list[dict[str, object]] = field(default_factory=list)


def make_night(
    date: str,
    bed: str,
    wake: str,
    stages: Sequence[tuple[str, int]] = (),
    *,
    first: str | None = None,
    start: object = None,
    stop: object = None,
    **totals: object,
) -> Night:
    """A night slept from `bed` to `wake` (local 'YYYY-MM-DD HH:MM').

    `stages` are runs of ``(code, minutes)`` — codes DEEP/LIGHT/REM/WAKE (or
    anything else, written verbatim) — starting at `first` (default `bed`).
    ``("GAP", n)`` jumps so the next minute stamp is n minutes after the
    previous one (n=1 would be no gap). The SLEEP row's stage totals are the
    minute counts unless overridden (``deepSleepTime=…`` etc.); `start`/`stop`
    override the UTC stamps (e.g. ``""`` for an empty cell).
    """
    counts = dict.fromkeys(STAGE_COLUMN.values(), 0)
    minutes: list[dict[str, object]] = []
    cursor = local(first or bed).astimezone(UTC)
    for code, n in stages:
        if code == "GAP":
            cursor += timedelta(minutes=n - 1)
            continue
        for _ in range(n):
            stamp = cursor.astimezone(LOCAL)
            minutes.append({"date": stamp.strftime("%Y-%m-%d"), "time": stamp.strftime("%H:%M"), "stage": code})
            cursor += timedelta(minutes=1)
        if code in STAGE_COLUMN:
            counts[STAGE_COLUMN[code]] += n
    row: dict[str, object] = {
        "date": date,
        **counts,
        "start": utc_text(bed) if start is None else start,
        "stop": utc_text(wake) if stop is None else stop,
    }
    row.update(totals)
    return Night(row, minutes)


def write_csv(path: Path, header: Sequence[str], rows: Iterable[Row], *, mtime: float | None = None) -> Path:
    """Write `rows` under `header` with a UTF-8 BOM; missing keys are empty cells."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(header), extrasaction="ignore")
        writer.writeheader()
        for r in rows:
            writer.writerow({k: "" if v is None else v for k, v in r.items()})
    if mtime is not None:
        os.utime(path, (mtime, mtime))
    return path


def make_export(
    root: Path,
    *,
    nights: Iterable[Night] = (),
    sleep: Iterable[Row] | None = None,
    sleep_minute: Iterable[Row] | None = None,
    activity: Iterable[Row] | None = None,
    body: Iterable[Row] | None = None,
    sport: Iterable[Row] | None = None,
    heartrate: Iterable[Row] | None = None,
    skip: Sequence[str] = (),
) -> Path:
    """Write a Zepp-style export under `root` and return its path.

    A metric is written when it has rows (``[]`` writes a header-only CSV);
    ``None`` leaves its folder out. `nights` add to SLEEP and SLEEP_MINUTE.
    Metrics in `skip` are never written.
    """
    nights = list(nights)
    rows: dict[str, list[Row] | None] = {
        "SLEEP": None if sleep is None else list(sleep),
        "SLEEP_MINUTE": None if sleep_minute is None else list(sleep_minute),
        "ACTIVITY": None if activity is None else list(activity),
        "BODY": None if body is None else list(body),
        "SPORT": None if sport is None else list(sport),
        "HEARTRATE_AUTO": None if heartrate is None else list(heartrate),
    }
    if nights:
        rows["SLEEP"] = [*(rows["SLEEP"] or []), *(n.sleep for n in nights)]
        rows["SLEEP_MINUTE"] = [*(rows["SLEEP_MINUTE"] or []), *(m for n in nights for m in n.minutes)]
    root.mkdir(parents=True, exist_ok=True)
    for metric, metric_rows in rows.items():
        if metric_rows is None or metric in skip:
            continue
        write_csv(root / metric / f"{metric}_1700000000000.csv", data._COLUMNS[metric], metric_rows)
    return root


@pytest.fixture
def export(tmp_path: Path) -> Path:
    """A small, complete export: two months of every metric."""
    return make_export(tmp_path / "export", **small_export_rows())


def small_export_rows() -> dict[str, Any]:
    """Rows for the `export` fixture (2026-04 and 2026-05)."""
    nights = [
        make_night(f"2026-{m:02d}-{d:02d}", f"2026-{m:02d}-{d - 1:02d} 23:00", f"2026-{m:02d}-{d:02d} 06:30",
                   [("LIGHT", 60), ("DEEP", 90), ("REM", 60), ("WAKE", 10), ("LIGHT", 150)])
        for m in (4, 5) for d in range(2, 29, 3)
    ]
    activity = [{"date": f"2026-{m:02d}-{d:02d}", "steps": 5000 + d * 100, "calories": 200 + d}
                for m in (4, 5) for d in range(1, 29)]
    body = [{"time": f"2026-{m:02d}-{d:02d} 12:00:00+0000", "weight": 70 + d / 10} for m in (4, 5) for d in (3, 17)]
    sport = [{"type": t, "startTime": f"2026-05-{d:02d} 15:00:00+0000"} for d, t in ((4, 52), (6, 1), (12, 52))]
    heartrate = [{"date": f"2026-{m:02d}-{d:02d}", "heartRate": 55 + i}
                 for m in (4, 5) for d in range(1, 29) for i in range(5)]
    return {"nights": nights, "activity": activity, "body": body, "sport": sport, "heartrate": heartrate}
