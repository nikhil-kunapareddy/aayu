"""Golden snapshot of ``series.dashboard()`` on fabricated exports.

The chart maths was verified against the old Plotly implementation, so its
output must not drift: ``golden/dashboard.json`` was written from the code as
it stood before the production-hardening refactor. Regenerate it only for an
intended maths change: ``AAYU_UPDATE_GOLDEN=1 pytest tests/test_golden.py``.

The exports cover four months (with a DST night), stage minutes before bedtime
and after wake time, gaps of 30 and 31 minutes, a 2-minute gap, the 6-hour
reach, unknown stages and bad minute rows, zero-stage nights, zero-step days,
0/empty weights, every sport code, and exports missing most metrics.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest

from aayu_backend import data, series
from tests.conftest import Night, make_export, make_night

GOLDEN = Path(__file__).parent / "golden" / "dashboard.json"


def _days(first: date, last: date) -> list[date]:
    return [first + timedelta(days=i) for i in range((last - first).days + 1)]


def _hm(d: date, hour: int, minute: int) -> str:
    return (datetime(d.year, d.month, d.day) + timedelta(hours=hour, minutes=minute)).strftime("%Y-%m-%d %H:%M")  # noqa: DTZ001


def _plain_nights(first: date, last: date, skip_every: int = 9) -> list[Night]:
    """One night per day (some skipped) with SLEEP totals only, no minutes."""
    nights = []
    for i, d in enumerate(_days(first, last)):
        if i % skip_every == 4:
            continue
        prev = d - timedelta(days=1)
        nights.append(make_night(
            d.isoformat(), _hm(prev, 22, 30 + i * 17 % 120), _hm(d, 6, i * 23 % 90),
            deepSleepTime=50 + i * 7 % 40, shallowSleepTime=200 + i * 11 % 80,
            REMTime=60 + i * 5 % 50, wakeTime=5 + i * 3 % 30,
        ))
    return nights


def _special_nights() -> dict[str, Night]:
    """Nights with SLEEP_MINUTE rows exercising the night-span rule."""
    return {
        # 20 minutes before bed; a 30-minute gap after wake is followed, a 45 isn't.
        "2026-01-31": make_night(
            "2026-01-31", "2026-01-30 23:10", "2026-01-31 06:40",
            [("LIGHT", 25), ("DEEP", 80), ("LIGHT", 100), ("REM", 60), ("LIGHT", 70), ("WAKE", 5),
             ("LIGHT", 60), ("REM", 40), ("DEEP", 30), ("GAP", 30), ("LIGHT", 15), ("GAP", 45), ("REM", 10)],
            first="2026-01-30 22:50"),
        # A run 32 minutes before bed and one 31 minutes after wake are left out;
        # a 2-minute gap splits a LIGHT run.
        "2026-02-28": make_night(
            "2026-02-28", "2026-02-27 23:30", "2026-02-28 07:00",
            [("LIGHT", 20), ("GAP", 32), ("DEEP", 60), ("LIGHT", 120), ("GAP", 2), ("LIGHT", 50), ("REM", 70),
             ("LIGHT", 80), ("WAKE", 10), ("LIGHT", 59), ("GAP", 31), ("LIGHT", 20)],
            first="2026-02-27 22:39"),
        # Spring forward: the local clock jumps 01:59 → 03:00 mid-night.
        "2026-03-08": make_night(
            "2026-03-08", "2026-03-07 23:00", "2026-03-08 07:00",
            [("LIGHT", 50), ("DEEP", 90), ("LIGHT", 100), ("REM", 80), ("LIGHT", 90), ("WAKE", 10)]),
        # Stage minutes run on 12 minutes past wake time.
        "2026-03-31": make_night(
            "2026-03-31", "2026-03-30 23:45", "2026-03-31 07:15",
            [("LIGHT", 40), ("DEEP", 70), ("REM", 50), ("LIGHT", 120), ("WAKE", 3), ("LIGHT", 90), ("REM", 60),
             ("LIGHT", 29)]),
        # A 30-minute gap before bed is followed; unknown NAP minutes drop out.
        "2026-04-02": make_night(
            "2026-04-02", "2026-04-01 23:00", "2026-04-02 06:00",
            [("REM", 10), ("GAP", 30), ("LIGHT", 21), ("DEEP", 100), ("LIGHT", 70), ("NAP", 3), ("LIGHT", 77),
             ("REM", 100), ("LIGHT", 70)],
            first="2026-04-01 22:00"),
        # A contiguous run from 7h20m before bed: only the last 6 hours count.
        "2026-04-15": make_night(
            "2026-04-15", "2026-04-14 23:20", "2026-04-15 06:50",
            [("WAKE", 200), ("LIGHT", 240), ("DEEP", 90), ("LIGHT", 150), ("REM", 90), ("LIGHT", 120)],
            first="2026-04-14 16:00"),
    }


def build_full(root: Path) -> Path:
    """Export A: 2026-01-01 → 2026-04-15, every metric."""
    first, last = date(2026, 1, 1), date(2026, 4, 15)
    by_date = {str(n.sleep["date"]): n for n in _plain_nights(first + timedelta(days=1), last)}
    by_date.update(_special_nights())
    by_date["2026-02-10"].sleep.update(deepSleepTime=0, shallowSleepTime=0, REMTime=0)   # dropped
    nights = [by_date[k] for k in sorted(by_date)]

    days = _days(first, last)
    activity = [{"date": d.isoformat(), "steps": 0 if i % 11 == 3 else 3000 + (i * 37 % 50) * 150,
                 "calories": 150 + (i * 13 % 40) * 5 + (i % 3) * 0.5} for i, d in enumerate(days)]
    body = []
    for i, d in enumerate(days[::4]):
        weight: object = 72.0 + ((i * 7) % 20 - 10) / 10
        if i % 13 == 5:
            weight = 0
        elif i % 17 == 8:
            weight = ""
        body.append({"time": f"{d.isoformat()} {'02:30' if i % 5 == 1 else '13:15'}:00+0000", "weight": weight})
    codes = [52, 1, 8, 6, 54, 99, 52, 1, 52]
    sport = [{"type": codes[i // 3 % len(codes)],
              "startTime": f"{d.isoformat()} {'23:30' if i % 2 else '14:00'}:00+0000"}
             for i, d in enumerate(days) if i % 3 == 0]
    heartrate = [{"date": d.isoformat(), "heartRate": 50 + (i * k * 7) % 30} for i, d in enumerate(days)
                 for k in range(6)]
    bad_minutes = [{"date": "2026-04-03", "time": "25:61", "stage": "LIGHT"},
                   {"date": "2026-04-03", "time": "03:00", "stage": "NAP"},
                   {"date": "not-a-date", "time": "03:01", "stage": "DEEP"}]
    return make_export(root, nights=nights, sleep_minute=bad_minutes, activity=activity, body=body,
                       sport=sport, heartrate=heartrate)


def build_sleep_activity(root: Path) -> Path:
    """Export B: sleep totals and activity only (no minutes, weight, sport, HR)."""
    first, last = date(2026, 6, 1), date(2026, 7, 10)
    activity = [{"date": d.isoformat(), "steps": 4000 + i * 120, "calories": 180 + i % 7 * 9}
                for i, d in enumerate(_days(first, last))]
    return make_export(root, nights=_plain_nights(first, last, skip_every=5), activity=activity)


def build_body_only(root: Path) -> Path:
    """Export C: weigh-ins only."""
    body = [{"time": f"{d.isoformat()} 12:00:00+0000", "weight": 80 - i / 10}
            for i, d in enumerate(_days(date(2026, 8, 3), date(2026, 9, 20))[::3])]
    return make_export(root, body=body)


CASES: dict[str, tuple[Any, list[tuple[str, dict[str, Any]]]]] = {
    "full": (build_full, [
        ("default", {}),
        ("last30", {"default_range": "last30"}),
        ("jan", {"selection": "2026-01"}),
        ("jan-plain-night", {"selection": "2026-01", "night": "2026-01-16"}),
        ("feb-kg", {"selection": "2026-02", "units": "kg"}),
        ("mar-dst", {"selection": "2026-03", "night": "2026-03-08"}),
        ("mar-outside-night", {"selection": "2026-03", "night": "2026-02-15"}),
        ("apr-gap-before-bed", {"selection": "2026-04", "night": "2026-04-02"}),
        ("last30-kg-night", {"selection": "last30", "units": "kg", "night": "2026-03-31"}),
        ("unknown-selection", {"selection": "bogus", "default_range": "last30"}),
    ]),
    "sleep-activity": (build_sleep_activity, [
        ("default", {}),
        ("last30-kg", {"default_range": "last30", "units": "kg"}),
    ]),
    "body-only": (build_body_only, [
        ("default", {}),
    ]),
}


def _canonical(payload: object) -> str:
    return json.dumps(payload, sort_keys=True, indent=1, allow_nan=False, default=lambda o: o.item())


def _render(export: str, root: Path) -> dict[str, str]:
    build, cases = CASES[export]
    d = data.load(str(build(root / export)))
    out = {}
    for name, params in cases:
        kwargs = {"selection": None, "units": "lbs", "default_range": "month", "night": None, **params}
        out[name] = _canonical(series.dashboard(d, kwargs["selection"], kwargs["units"],
                                                kwargs["default_range"], kwargs["night"]))
    return out


def test_update_golden(tmp_path: Path) -> None:
    if not os.environ.get("AAYU_UPDATE_GOLDEN"):
        pytest.skip("set AAYU_UPDATE_GOLDEN=1 to rewrite the snapshot")
    snapshot = {export: {name: json.loads(text) for name, text in _render(export, tmp_path).items()}
                for export in CASES}
    GOLDEN.write_text(json.dumps(snapshot, sort_keys=True, indent=1) + "\n", encoding="utf-8")


@pytest.mark.parametrize("export", list(CASES))
def test_dashboard_matches_golden(export: str, tmp_path: Path, caplog: pytest.LogCaptureFixture) -> None:
    golden = json.loads(GOLDEN.read_text(encoding="utf-8"))[export]
    rendered = _render(export, tmp_path)
    assert not [r for r in caplog.records if r.levelno >= logging.WARNING], "no section may fail or warn"
    assert set(rendered) == set(golden)
    for name, text in rendered.items():
        assert text == _canonical(golden[name]), f"{export}/{name} drifted from the golden snapshot"
