"""
Data loading and processing.

Reads all CSV files from data/ and exposes cleaned DataFrames
and pre-computed KPI values used by the dashboard.
"""

import os
import pandas as pd

# ── Paths ──────────────────────────────────────────────────────────────────────

_BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DATA = os.path.join(_BASE, "data")


def _load(folder: str, **kwargs) -> pd.DataFrame:
    d = os.path.join(_DATA, folder)
    for f in os.listdir(d):
        if f.endswith(".csv"):
            return pd.read_csv(os.path.join(d, f), encoding="utf-8-sig", **kwargs)
    return pd.DataFrame()


# ── Raw loads ──────────────────────────────────────────────────────────────────

_sleep_raw = _load(
    "SLEEP",
    usecols=["date", "deepSleepTime", "shallowSleepTime", "wakeTime", "start", "stop", "REMTime"],
)
_activity_raw = _load("ACTIVITY")
_body_raw     = _load("BODY")
_sport_raw    = _load("SPORT")
_hr_raw       = _load("HEARTRATE_AUTO")
_sleep_min    = _load("SLEEP_MINUTE")
_user_raw     = _load("USER")

# ── Sleep ──────────────────────────────────────────────────────────────────────

_sleep_raw["date"] = pd.to_datetime(_sleep_raw["date"])
sleep = _sleep_raw[
    _sleep_raw["deepSleepTime"] + _sleep_raw["shallowSleepTime"] + _sleep_raw["REMTime"] > 0
].copy()
sleep["totalMin"]   = sleep["deepSleepTime"] + sleep["shallowSleepTime"] + sleep["REMTime"]
sleep["totalHours"] = (sleep["totalMin"] / 60).round(2)

# ── Activity ───────────────────────────────────────────────────────────────────

activity = _activity_raw.copy()
activity["date"]       = pd.to_datetime(activity["date"])
activity["distanceKm"] = (activity["distance"] / 1000).round(2)
activity = activity[activity["steps"] > 0]

# ── Body ───────────────────────────────────────────────────────────────────────

body = _body_raw.copy()
body["date"] = pd.to_datetime(body["time"]).dt.tz_localize(None)
body = body[body["weight"].notna() & (body["weight"] > 0)]

# ── Sport ──────────────────────────────────────────────────────────────────────

SPORT_NAMES = {1: "Running", 6: "Outdoor Walk", 8: "Running", 52: "Strength", 54: "Indoor Walk"}

sport = _sport_raw.copy()
sport["startTime"]    = pd.to_datetime(sport["startTime"], utc=True)
sport["date"]         = sport["startTime"].dt.normalize().dt.tz_localize(None)
sport["durationMin"]  = (sport["sportTime(s)"] / 60).round(1)
sport["cal"]          = sport["calories(kcal)"].round(1)
sport["sportName"]    = sport["type"].map(SPORT_NAMES).fillna("Other")

# ── Heart Rate ─────────────────────────────────────────────────────────────────

hr_raw = _hr_raw.copy()
hr_raw["date"] = pd.to_datetime(hr_raw["date"])
hr_raw["hour"] = hr_raw["time"].str.split(":").str[0].astype(int)

daily_hr = hr_raw.groupby("date")["heartRate"].agg(
    avg="mean",
    resting=lambda x: x.quantile(0.05),
    peak="max",
).reset_index()
daily_hr[["avg", "resting", "peak"]] = daily_hr[["avg", "resting", "peak"]].round(1)

hourly_hr = hr_raw.groupby("hour")["heartRate"].mean().reset_index().round(1)

# ── Sleep Minute ───────────────────────────────────────────────────────────────

sleep_min = _sleep_min.copy()
sleep_min["date"] = pd.to_datetime(sleep_min["date"])

# ── User ───────────────────────────────────────────────────────────────────────

user_name  = _user_raw["nickName"].iloc[0] if not _user_raw.empty else "User"
date_start = activity["date"].min().strftime("%b %Y")
date_end   = activity["date"].max().strftime("%b %Y")

# ── KPIs ───────────────────────────────────────────────────────────────────────

avg_steps      = int(activity["steps"].mean())
best_steps     = int(activity["steps"].max())
active_days    = int((activity["steps"] >= 8000).sum())
avg_sleep_h    = round(float(sleep["totalHours"].mean()), 1)
avg_deep_min   = int(sleep["deepSleepTime"].mean())
avg_rem_min    = int(sleep["REMTime"].mean())
avg_resting_hr = int(daily_hr["resting"].mean())
avg_peak_hr    = int(daily_hr["peak"].mean())
total_workouts = len(sport)
total_run_km   = round(float(sport[sport["sportName"] == "Running"]["distance(m)"].sum()) / 1000, 1)
avg_calories   = int(activity["calories"].mean())
latest_weight  = round(float(body["weight"].iloc[-1]), 1) if not body.empty else None
latest_bmi     = round(float(body["bmi"].iloc[-1]), 1)    if not body.empty else None
