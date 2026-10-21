"""
Zepp export loading.

Reads the CSVs from a Zepp export folder (one subfolder per metric: ``SLEEP/``,
``ACTIVITY/``, ``BODY/``, ``SPORT/``, ``HEARTRATE_AUTO/``, ``SLEEP_MINUTE/`` …)
and cleans them into pandas DataFrames.

Pure data — no I/O protocol here — so series.py and the server build on top of
it and it can be tested on its own. ``load(folder)`` returns an immutable
``Data`` snapshot; reloading means building a new one.
"""

import os
from dataclasses import dataclass

import pandas as pd

# Columns each metric's frame needs, so a missing CSV still yields an empty
# frame the charts can handle. Metric folders not listed here are ignored.
_COLUMNS = {
    "SLEEP":          ["date", "deepSleepTime", "shallowSleepTime", "wakeTime", "start", "stop", "REMTime"],
    "ACTIVITY":       ["date", "steps", "calories"],
    "BODY":           ["time", "weight"],
    "SPORT":          ["type", "startTime"],
    "HEARTRATE_AUTO": ["date", "heartRate"],
    "SLEEP_MINUTE":   ["date", "time", "stage"],
}
METRICS = tuple(_COLUMNS)

SPORT_NAMES = {1: "Running", 6: "Outdoor Walk", 8: "Running", 52: "Strength", 54: "Indoor Walk"}
STAGE_NAMES = {"DEEP": "Deep", "LIGHT": "Light", "REM": "REM", "WAKE": "Awake"}


def csv_path(folder: str, metric: str) -> str | None:
    """Newest CSV in ``<folder>/<metric>``, or None.

    Newest (by modification time) wins, so a fresh export dropped next to an
    old one is the one that gets read.
    """
    path = os.path.join(folder, metric)
    try:
        names = [n for n in os.listdir(path) if n.endswith(".csv")]
    except OSError:
        return None
    if not names:
        return None
    return max((os.path.join(path, n) for n in names), key=os.path.getmtime)


def found_metrics(folder: str) -> list[str]:
    """The metrics in ``METRICS`` that have a CSV under ``folder``."""
    return [m for m in METRICS if csv_path(folder, m)]


def _load(folder: str, metric: str) -> pd.DataFrame:
    """Read a metric's CSV (Zepp exports carry a BOM), or an empty frame if absent."""
    path = csv_path(folder, metric)
    if path is None:
        return pd.DataFrame({c: pd.Series(dtype="float64") for c in _COLUMNS[metric]})
    return pd.read_csv(path, encoding="utf-8-sig", usecols=_COLUMNS[metric])


@dataclass(frozen=True)
class Data:
    """One loaded Zepp export: the cleaned frames. KPIs and chart series are
    computed per date window in series.py."""

    folder: str
    sleep: pd.DataFrame
    activity: pd.DataFrame
    body: pd.DataFrame
    sport: pd.DataFrame
    resting_hr: pd.DataFrame      # date, hr — per-day 5th-percentile heart rate
    sleep_minutes: pd.DataFrame   # ts (naive local time), stage — one row per minute asleep

    # ── Date coverage ────────────────────────────────────────────────────────
    def months(self) -> list[str]:
        """Year-months with sleep, activity or body data, oldest → newest, as 'YYYY-MM'."""
        frames = (self.sleep, self.activity, self.body)
        return sorted({str(p) for f in frames for p in f["date"].dt.to_period("M").unique()})

    def latest_date(self) -> pd.Timestamp | None:
        """The last day with sleep, activity or body data (midnight)."""
        ends = [f["date"].max() for f in (self.sleep, self.activity, self.body) if not f.empty]
        return max(ends).normalize() if ends else None


def load(folder: str) -> Data:
    """Read and clean every metric under a Zepp export folder."""
    # ── Sleep ────────────────────────────────────────────────────────────────
    sleep = _load(folder, "SLEEP")
    sleep["date"] = pd.to_datetime(sleep["date"])
    sleep = sleep[sleep["deepSleepTime"] + sleep["shallowSleepTime"] + sleep["REMTime"] > 0].copy()
    sleep["totalHours"] = (
        (sleep["deepSleepTime"] + sleep["shallowSleepTime"] + sleep["REMTime"]) / 60
    ).round(2)

    # ── Activity ─────────────────────────────────────────────────────────────
    activity = _load(folder, "ACTIVITY")
    activity["date"] = pd.to_datetime(activity["date"])
    activity = activity[activity["steps"] > 0]

    # ── Body ─────────────────────────────────────────────────────────────────
    body = _load(folder, "BODY")
    body["date"] = pd.to_datetime(body["time"], utc=True).dt.tz_localize(None)
    body = body[body["weight"].notna() & (body["weight"] > 0)].sort_values("date")

    # ── Sport ────────────────────────────────────────────────────────────────
    sport = _load(folder, "SPORT")
    sport["date"] = pd.to_datetime(sport["startTime"], utc=True).dt.normalize().dt.tz_localize(None)
    sport["sportName"] = sport["type"].map(SPORT_NAMES).fillna("Other")

    # ── Resting heart rate (drives the resting-HR KPI; no HR chart) ──────────
    hr = _load(folder, "HEARTRATE_AUTO")
    hr["date"] = pd.to_datetime(hr["date"])
    resting_hr = hr.groupby("date")["heartRate"].quantile(0.05).rename("hr").reset_index()

    # ── Sleep stages by minute (the hypnogram) ───────────────────────────────
    # Zepp stamps these in the watch's local time, not UTC like SLEEP.
    minutes = _load(folder, "SLEEP_MINUTE")
    sleep_minutes = pd.DataFrame({
        "ts": pd.to_datetime(minutes["date"].astype(str) + " " + minutes["time"].astype(str),
                             format="%Y-%m-%d %H:%M", errors="coerce"),
        "stage": minutes["stage"].map(STAGE_NAMES),
    }).dropna().sort_values("ts", ignore_index=True)

    return Data(folder, sleep, activity, body, sport, resting_hr, sleep_minutes)
