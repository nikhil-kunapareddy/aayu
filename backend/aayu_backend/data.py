"""Zepp export loading.

Reads the CSVs from a Zepp export folder (one subfolder per metric: ``SLEEP/``,
``ACTIVITY/``, ``BODY/``, ``SPORT/``, ``HEARTRATE_AUTO/``, ``SLEEP_MINUTE/`` …)
and cleans them into pandas DataFrames.

Pure data — no I/O protocol here — so series.py and the server build on top of
it and it can be tested on its own. ``load(folder)`` returns an immutable
``Data`` snapshot; reloading means building a new one.

Cleaning drops rows the dashboard can't use (unparseable dates, nights with no
sleep, days with no steps, weigh-ins of 0 or blank, unknown sleep stages) and
turns non-numeric cells in numeric columns into NaN, so one bad row never
fails a whole load. Columns a metric needs but its CSV lacks do fail it, with
an ``ExportError`` naming the columns.
"""

import logging
import os
import time
from collections.abc import Callable
from dataclasses import dataclass

import pandas as pd

log = logging.getLogger(__name__)

# Columns each metric's frame needs, so a missing CSV still yields an empty
# frame the charts can handle. Metric folders not listed here are ignored.
_COLUMNS: dict[str, list[str]] = {
    "SLEEP":          ["date", "deepSleepTime", "shallowSleepTime", "wakeTime", "start", "stop", "REMTime"],
    "ACTIVITY":       ["date", "steps", "calories"],
    "BODY":           ["time", "weight"],
    "SPORT":          ["type", "startTime"],
    "HEARTRATE_AUTO": ["date", "heartRate"],
    "SLEEP_MINUTE":   ["date", "time", "stage"],
}
METRICS = tuple(_COLUMNS)

# Columns read as numbers; anything else in them becomes NaN.
_NUMERIC = frozenset({"deepSleepTime", "shallowSleepTime", "wakeTime", "REMTime",
                      "steps", "calories", "weight", "type", "heartRate"})

SPORT_NAMES = {1: "Running", 6: "Outdoor Walk", 8: "Running", 52: "Strength", 54: "Indoor Walk"}
OTHER_SPORT = "Other"
STAGE_NAMES = {"DEEP": "Deep", "LIGHT": "Light", "REM": "REM", "WAKE": "Awake"}

RESTING_HR_QUANTILE = 0.05          # a day's resting heart rate: its 5th-percentile reading
MINUTE_FORMAT = "%Y-%m-%d %H:%M"    # SLEEP_MINUTE date + time


class ExportError(Exception):
    """A metric's CSV couldn't be read, or lacks columns the dashboard needs.

    ``reason`` never quotes cell values, so it is safe to show and to log.
    """

    def __init__(self, metric: str, reason: str) -> None:
        """Record which `metric` failed and why."""
        super().__init__(f"{metric}: {reason}")
        self.metric = metric
        self.reason = reason


# ── Files ─────────────────────────────────────────────────────────────────────
def csv_files(folder: str, metric: str) -> list[tuple[str, os.stat_result]]:
    """``(path, stat)`` for each CSV the dashboard may read in ``<folder>/<metric>``.

    Only regular, non-hidden ``.csv`` files count (macOS ``._*`` files on
    external drives end in .csv too). Entries that vanish while being listed —
    an export mid-copy — or can't be inspected are skipped.
    """
    try:
        with os.scandir(os.path.join(folder, metric)) as it:
            entries = list(it)
    except OSError:
        return []
    found = []
    for entry in entries:
        if entry.name.startswith(".") or not entry.name.endswith(".csv"):
            continue
        try:
            if entry.is_file():
                found.append((entry.path, entry.stat()))
        except OSError:
            continue
    return found


def csv_path(folder: str, metric: str) -> str | None:
    """Newest CSV in ``<folder>/<metric>``, or None.

    Newest (by modification time, then name) wins, so a fresh export dropped
    next to an old one is the one that gets read.
    """
    files = csv_files(folder, metric)
    if not files:
        return None
    return max(files, key=lambda f: (f[1].st_mtime_ns, f[0]))[0]


def found_metrics(folder: str) -> list[str]:
    """The metrics in ``METRICS`` that have a CSV under ``folder``."""
    return [m for m in METRICS if csv_files(folder, m)]


def _read(folder: str, metric: str) -> pd.DataFrame:
    """Read a metric's CSV (Zepp exports carry a BOM), or an empty frame if absent."""
    columns = _COLUMNS[metric]
    path = csv_path(folder, metric)
    if path is None:
        return pd.DataFrame({c: pd.Series(dtype="float64") for c in columns})
    try:
        df = pd.read_csv(path, encoding="utf-8-sig", usecols=lambda c: c in columns)
    except UnicodeDecodeError as e:
        raise ExportError(metric, "the CSV isn't UTF-8 text") from e
    except pd.errors.EmptyDataError as e:
        raise ExportError(metric, "the CSV is empty") from e
    except OSError as e:
        raise ExportError(metric, f"the CSV couldn't be opened ({type(e).__name__})") from e
    except ValueError as e:  # pandas' ParserError and friends
        raise ExportError(metric, "the CSV is malformed") from e
    missing = [c for c in columns if c not in df.columns]
    if missing:
        raise ExportError(metric, f"the CSV has no {', '.join(missing)} column{'s' if len(missing) > 1 else ''}")
    for c in _NUMERIC.intersection(df.columns):
        if not pd.api.types.is_numeric_dtype(df[c]):
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


# ── Cleaning, one function per metric ─────────────────────────────────────────
def _dates(s: pd.Series) -> pd.Series:
    """Parse a 'YYYY-MM-DD' column; anything unparseable becomes NaT."""
    return pd.to_datetime(s, errors="coerce")


def _utc(s: pd.Series) -> pd.Series:
    """Parse a UTC timestamp column (e.g. ``2026-05-01 03:12:00+0000``) as tz-aware UTC; bad cells → NaT."""
    return pd.to_datetime(s, utc=True, errors="coerce")


def _clean_sleep(sleep: pd.DataFrame) -> pd.DataFrame:
    """Nights with some sleep; ``start``/``stop`` become tz-aware UTC (NaT when blank)."""
    sleep["date"] = _dates(sleep["date"])
    sleep["start"] = _utc(sleep["start"])
    sleep["stop"] = _utc(sleep["stop"])
    asleep = sleep["deepSleepTime"] + sleep["shallowSleepTime"] + sleep["REMTime"]
    sleep = sleep[sleep["date"].notna() & (asleep > 0)].copy()
    sleep["totalHours"] = (
        (sleep["deepSleepTime"] + sleep["shallowSleepTime"] + sleep["REMTime"]) / 60
    ).round(2)
    return sleep


def _clean_activity(activity: pd.DataFrame) -> pd.DataFrame:
    """Days with steps (calories may still be blank)."""
    activity["date"] = _dates(activity["date"])
    return activity[activity["date"].notna() & (activity["steps"] > 0)]


def _clean_body(body: pd.DataFrame) -> pd.DataFrame:
    """Weigh-ins above 0, oldest first; ``date`` is the UTC time, made naive."""
    body["date"] = _utc(body["time"]).dt.tz_localize(None)
    keep = body["date"].notna() & body["weight"].notna() & (body["weight"] > 0)
    return body[keep].sort_values("date", kind="stable")


def _clean_sport(sport: pd.DataFrame) -> pd.DataFrame:
    """Sessions with a ``date`` (the UTC day, made naive) and a ``sportName``."""
    sport["date"] = _utc(sport["startTime"]).dt.normalize().dt.tz_localize(None)
    sport["sportName"] = sport["type"].map(SPORT_NAMES).fillna(OTHER_SPORT)
    return sport[sport["date"].notna()]


def _clean_heartrate(hr: pd.DataFrame) -> pd.DataFrame:
    """Per-day resting heart rate: columns ``date``, ``hr``."""
    hr["date"] = _dates(hr["date"])
    return hr.groupby("date")["heartRate"].quantile(RESTING_HR_QUANTILE).rename("hr").reset_index()


def _clean_minutes(minutes: pd.DataFrame) -> pd.DataFrame:
    """One row per minute: ``ts`` (naive local time), ``stage`` (a ``STAGE_NAMES`` value).

    Zepp stamps these in the watch's local time, not UTC like SLEEP. Rows with
    a bad stamp or an unknown stage are dropped; a repeated stamp (the hour
    the clocks go back) keeps its first row, so segments never overlap.
    """
    stamps = minutes["date"].astype(str) + " " + minutes["time"].astype(str)
    out = pd.DataFrame({
        "ts": pd.to_datetime(stamps, format=MINUTE_FORMAT, errors="coerce"),
        "stage": minutes["stage"].map(STAGE_NAMES),
    }).dropna().sort_values("ts", kind="stable", ignore_index=True)
    return out.drop_duplicates("ts", keep="first", ignore_index=True)


_CLEANERS: dict[str, Callable[[pd.DataFrame], pd.DataFrame]] = {
    "SLEEP": _clean_sleep,
    "ACTIVITY": _clean_activity,
    "BODY": _clean_body,
    "SPORT": _clean_sport,
    "HEARTRATE_AUTO": _clean_heartrate,
    "SLEEP_MINUTE": _clean_minutes,
}


@dataclass(frozen=True)
class Data:
    """One loaded Zepp export: the cleaned frames.

    KPIs and chart series are computed per date window in series.py.
    """

    folder: str
    sleep: pd.DataFrame           # date, stage minutes, start/stop (UTC), totalHours
    activity: pd.DataFrame        # date, steps, calories
    body: pd.DataFrame            # date (naive UTC), weight in kg — oldest first
    sport: pd.DataFrame           # date (naive UTC day), type, sportName
    resting_hr: pd.DataFrame      # date, hr — per-day 5th-percentile heart rate
    sleep_minutes: pd.DataFrame   # ts (naive local time), stage — one row per minute asleep

    # ── Date coverage ────────────────────────────────────────────────────────
    def months(self) -> list[str]:
        """Year-months with sleep, activity or body data, oldest → newest, as 'YYYY-MM'."""
        frames = (self.sleep, self.activity, self.body)
        return sorted({str(p) for f in frames for p in f["date"].dt.to_period("M").unique()})

    def latest_date(self) -> pd.Timestamp | None:
        """The last day with sleep, activity or body data (midnight)."""
        ends = [pd.Timestamp(f["date"].max()) for f in (self.sleep, self.activity, self.body) if not f.empty]
        return max(ends).normalize() if ends else None


def load(folder: str) -> Data:
    """Read and clean every metric under a Zepp export folder.

    Raises ``ExportError`` when a metric's CSV can't be read or cleaned.
    """
    began = time.perf_counter()
    frames: dict[str, pd.DataFrame] = {}
    counts = []
    for metric in METRICS:
        raw = _read(folder, metric)
        try:
            frames[metric] = _CLEANERS[metric](raw)
        except (TypeError, ValueError, KeyError, AttributeError) as e:
            raise ExportError(metric, "the CSV has values in an unexpected format") from e
        counts.append(f"{metric} {len(raw)}→{len(frames[metric])}")
    log.info("loaded export in %.0f ms (rows read→kept: %s)", (time.perf_counter() - began) * 1000, ", ".join(counts))
    return Data(folder, frames["SLEEP"], frames["ACTIVITY"], frames["BODY"], frames["SPORT"],
                frames["HEARTRATE_AUTO"], frames["SLEEP_MINUTE"])
