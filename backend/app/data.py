"""
Data loading and processing (backend).

Reads the Zepp CSV exports from the repo-root ``data/`` folder, cleans them into
a handful of pandas DataFrames, and pre-computes the KPI scalars shown in the
dashboard banner. Framework-agnostic — no FastAPI imports — so it can be reused
or tested independently of the web layer that serves it (``app.main``).

Everything here is computed once at import. The module exposes exactly what the
dashboard consumes: the ``sleep``/``activity``/``body``/``sport`` frames and the
four banner KPIs. Nothing is loaded "just in case".
"""

import os

import pandas as pd

# This file lives at <repo>/backend/app/data.py, so data/ is three levels up.
_BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_DATA = os.path.join(_BASE, "data")


def _load(folder: str, **kwargs) -> pd.DataFrame:
    """Read the first CSV found in ``data/<folder>`` (Zepp exports carry a BOM)."""
    path = os.path.join(_DATA, folder)
    for name in os.listdir(path):
        if name.endswith(".csv"):
            return pd.read_csv(os.path.join(path, name), encoding="utf-8-sig", **kwargs)
    return pd.DataFrame()


# ── Sleep ────────────────────────────────────────────────────────────────────
sleep = _load(
    "SLEEP",
    usecols=["date", "deepSleepTime", "shallowSleepTime", "wakeTime", "start", "stop", "REMTime"],
)
sleep["date"] = pd.to_datetime(sleep["date"])
sleep = sleep[sleep["deepSleepTime"] + sleep["shallowSleepTime"] + sleep["REMTime"] > 0].copy()
sleep["totalHours"] = (
    (sleep["deepSleepTime"] + sleep["shallowSleepTime"] + sleep["REMTime"]) / 60
).round(2)

# ── Activity ─────────────────────────────────────────────────────────────────
activity = _load("ACTIVITY")
activity["date"] = pd.to_datetime(activity["date"])
activity = activity[activity["steps"] > 0]

# ── Body ─────────────────────────────────────────────────────────────────────
body = _load("BODY")
body["date"] = pd.to_datetime(body["time"]).dt.tz_localize(None)
body = body[body["weight"].notna() & (body["weight"] > 0)]

# ── Sport ────────────────────────────────────────────────────────────────────
SPORT_NAMES = {1: "Running", 6: "Outdoor Walk", 8: "Running", 52: "Strength", 54: "Indoor Walk"}

sport = _load("SPORT")
sport["date"] = pd.to_datetime(sport["startTime"], utc=True).dt.normalize().dt.tz_localize(None)
sport["sportName"] = sport["type"].map(SPORT_NAMES).fillna("Other")

# ── Resting heart rate (drives the avg_resting_hr KPI; no HR chart) ──────────
_hr = _load("HEARTRATE_AUTO")
_hr["date"] = pd.to_datetime(_hr["date"])
_resting_hr = _hr.groupby("date")["heartRate"].quantile(0.05)

# ── KPIs — the four banner stats (the sleep score is computed client-side) ───
avg_steps      = int(activity["steps"].mean())
avg_sleep_h    = round(float(sleep["totalHours"].mean()), 1)
avg_resting_hr = int(_resting_hr.mean())
latest_weight  = round(float(body["weight"].iloc[-1]), 1) if not body.empty else None
