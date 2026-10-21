"""
Chart series and KPIs — the numbers behind each dashboard chart.

Same filtering, sleep-clock maths, week bucketing and rolling averages as the
old Plotly chart builders, but the output is plain JSON-ready values: the
SwiftUI app draws them with Swift Charts. Nothing here knows how they look.

Timestamps go out as naive local ISO strings (``2026-05-01T00:00:00``); the
app parses them in the Mac's timezone, so a midnight stays a midnight.
"""

from dataclasses import dataclass

import pandas as pd

from aayu_backend.data import Data

KG_TO_LBS = 2.20462

# Local timezone the UTC sleep timestamps are displayed in.
TZ = "America/New_York"

# A night's stage minutes run on through gaps up to NIGHT_GAP, looking at most
# NIGHT_REACH beyond the recorded bedtime and wake time.
NIGHT_GAP = pd.Timedelta(minutes=30)
NIGHT_REACH = pd.Timedelta(hours=6)

# Sleep stages, deepest first, with their SLEEP column (nightly minutes).
STAGES = [("Deep", "deepSleepTime"), ("REM", "REMTime"), ("Light", "shallowSleepTime"), ("Awake", "wakeTime")]


@dataclass(frozen=True)
class Window:
    """The date span the charts show: a calendar month or the last N days."""

    start: pd.Timestamp        # first day shown (midnight)
    end: pd.Timestamp          # last day shown (midnight)
    month: str | None = None   # 'YYYY-MM' when the window is a calendar month

    @classmethod
    def for_month(cls, month: str) -> "Window":
        period = pd.Period(month, freq="M")
        return cls(period.start_time, period.end_time.normalize(), month)

    @classmethod
    def last_days(cls, end: pd.Timestamp, days: int = 30) -> "Window":
        return cls(end - pd.Timedelta(days=days - 1), end)

    def clip(self, df: pd.DataFrame) -> pd.DataFrame:
        """Rows whose ``date`` falls on a day inside the window."""
        return df[(df["date"] >= self.start) & (df["date"] < self.end + pd.Timedelta(days=1))]


def _ts(t: pd.Timestamp) -> str:
    return t.strftime("%Y-%m-%dT%H:%M:%S")


def _markers(n: int) -> list[bool]:
    """Every k-th point (~14 per window) gets a dot on the line."""
    step = max(1, n // 14)
    return [i % step == 0 for i in range(n)]


def _clock(ts: pd.Series) -> pd.Series:
    """Fractional clock-hour on a night-centred axis: evenings go negative, mornings positive."""
    h = ts.dt.hour + ts.dt.minute / 60
    return h.where(h < 14, h - 24)


# ── Sleep score ──────────────────────────────────────────────────────────────────
# Targets on the night-centred clock: 11:30 PM (-0.5) bed, 6:30 AM (6.5) wake.
_IDEAL_BED, _IDEAL_WAKE = -0.5, 6.5
_IDEAL_RATIOS = {"deep": 0.20, "rem": 0.22, "light": 0.53, "awake": 0.05}
_TARGET_SLEEP_H = 7.5


def _closeness(dev: float, full: float, zero: float) -> float:
    """1.0 when deviation ≤ `full` hours, fading linearly to 0.0 at `zero`."""
    if dev <= full:
        return 1.0
    if dev >= zero:
        return 0.0
    return 1 - (dev - full) / (zero - full)


def sleep_score(d: Data, asof=None) -> int | None:
    """
    0–100 sleep score for the latest day (or `asof`), over the trailing 14 nights.

    Timing 30% · Stage ratios 35% · Duration 20% · Consistency 15%.
    """
    parts = sleep_score_parts(d, asof)
    return None if parts is None else parts["score"]


def sleep_score_parts(d: Data, asof=None) -> dict | None:
    """The sleep score plus its four parts, each 0–1 (1 = on target)."""
    df = d.sleep.sort_values("date")
    if df.empty:
        return None
    last = asof if asof is not None else df["date"].max()
    win = df[(df["date"] > last - pd.Timedelta(days=14)) & (df["date"] <= last)]
    if win.empty:
        return None

    start = pd.to_datetime(win["start"], utc=True).dt.tz_convert(TZ)
    stop  = pd.to_datetime(win["stop"],  utc=True).dt.tz_convert(TZ)
    bed, wake = _clock(start), _clock(stop)

    # Timing (30%) — average bed/wake vs ideal
    timing = (_closeness(abs(bed.mean()  - _IDEAL_BED),  1 / 3, 2.0)
              + _closeness(abs(wake.mean() - _IDEAL_WAKE), 1 / 3, 2.0)) / 2

    # Consistency (15%) — tightness of the schedule
    consistency = (_closeness(bed.std(ddof=0),  1 / 3, 1.5)
                   + _closeness(wake.std(ddof=0), 1 / 3, 1.5)) / 2

    # Stage ratios (35%) — closeness to the magic ratio (awake only penalised when high)
    deep, rem, light, awake = (win["deepSleepTime"].sum(), win["REMTime"].sum(),
                               win["shallowSleepTime"].sum(), win["wakeTime"].sum())
    total = deep + rem + light + awake
    ratios = {"deep": deep / total, "rem": rem / total, "light": light / total, "awake": awake / total}

    def stage_pts(k: str) -> float:
        dev = ratios[k] - _IDEAL_RATIOS[k]
        if k == "awake":
            dev = max(0.0, dev)
        return max(0.0, 1 - abs(dev) / 0.15)

    stages = sum(stage_pts(k) for k in _IDEAL_RATIOS) / len(_IDEAL_RATIOS)

    # Duration (20%) — average time asleep vs target
    avg_asleep_h = (deep + rem + light) / 60 / len(win)
    duration = _closeness(abs(avg_asleep_h - _TARGET_SLEEP_H), 0.5, 3.0)

    score = 100 * (0.30 * timing + 0.15 * consistency + 0.35 * stages + 0.20 * duration)
    return {"score": int(round(score)), "timing": round(float(timing), 2),
            "consistency": round(float(consistency), 2), "stages": round(float(stages), 2),
            "duration": round(float(duration), 2)}


# ── Chart series ─────────────────────────────────────────────────────────────────
def _local(ts) -> pd.Timestamp:
    """A UTC timestamp from SLEEP as naive local time (matching SLEEP_MINUTE)."""
    return pd.to_datetime(ts, utc=True).tz_convert(TZ).tz_localize(None)


def hypnogram(d: Data, w: Window, night: str | None = None) -> dict | None:
    """One night's sleep stages over time, for the Sleep Breakdown card.

    `night` is a sleep date ('YYYY-MM-DD') inside the window; anything else
    means the window's last night. The night's minutes are every run of
    SLEEP_MINUTE rows that overlaps bedtime–wake time, followed outward across
    gaps of up to NIGHT_GAP — the watch often keeps scoring stages past the
    recorded times — and ``start``/``end`` widen to cover them. Consecutive
    minutes in the same stage merge into one segment. ``nights`` lists every
    night in the window, for stepping.
    """
    rows = w.clip(d.sleep.sort_values("date")).drop_duplicates("date", keep="last")
    if rows.empty:
        return None
    dates = [t.strftime("%Y-%m-%d") for t in rows["date"]]
    pick = night if night in dates else dates[-1]
    row = rows.iloc[dates.index(pick)]
    start, stop = _local(row["start"]), _local(row["stop"])

    m = d.sleep_minutes
    m = m[(m["ts"] >= start - NIGHT_REACH) & (m["ts"] <= stop + NIGHT_REACH)]
    run = (m["ts"].diff() > NIGHT_GAP).cumsum()
    m = m[run.isin(run[(m["ts"] >= start.floor("min")) & (m["ts"] <= stop)].unique())]
    if not m.empty:
        start, stop = min(start, m["ts"].iloc[0]), max(stop, m["ts"].iloc[-1] + pd.Timedelta(minutes=1))
    segments, totals = [], {stage: 0 for stage, _ in STAGES}
    if not m.empty:
        new_run = (m["stage"] != m["stage"].shift()) | (m["ts"].diff() != pd.Timedelta(minutes=1))
        runs = m.groupby(new_run.cumsum()).agg(stage=("stage", "first"), first=("ts", "first"),
                                               last=("ts", "last"), minutes=("ts", "size"))
        for r in runs.itertuples():
            segments.append({"stage": r.stage, "start": _ts(r.first),
                             "end": _ts(r.last + pd.Timedelta(minutes=1))})
            totals[r.stage] += int(r.minutes)
    total = sum(totals.values())
    return {
        "night": pick,
        "nights": dates,
        "start": _ts(start),
        "end": _ts(stop),
        "segments": segments,
        "totals": [{"stage": k, "minutes": v, "share": round(v / total, 4) if total else 0.0}
                   for k, v in totals.items()],
        "asleep": total - totals["Awake"],                          # minutes in a sleep stage
        "duration": int((stop - start).total_seconds() // 60),      # start to end, minutes
    }


def stage_shares(d: Data, w: Window) -> list[dict]:
    """Each stage's share of all sleep minutes (awake included) in the window."""
    df = w.clip(d.sleep)
    minutes = {stage: float(df[col].fillna(0).sum()) for stage, col in STAGES}
    total = sum(minutes.values())
    return [
        {"stage": stage, "minutes": int(round(m)), "share": round(m / total, 4) if total else 0.0}
        for stage, m in minutes.items()
    ]


def workouts(d: Data, w: Window) -> dict:
    """Weekly Strength and Running session counts for the last 8 weeks ending at
    the window's last day, framed over a two-month axis (``start`` → ``end``)."""
    sp = d.sport.copy()
    sp["week"] = sp["date"].dt.to_period("W")

    # Two-month axis: the prior month's start for a calendar month, else the
    # same span back from the window's last day.
    if w.month:
        axis_start = (pd.Period(w.month, freq="M") - 1).start_time
    else:
        axis_start = w.end - pd.DateOffset(months=2) + pd.Timedelta(days=1)

    # Last 8 weeks (that had any session) whose start falls on or before the window's last day.
    weeks = [wk for wk in sorted(sp["week"].dropna().unique())
             if wk.start_time <= w.end][-8:]
    rows = [
        {"week": _ts(wk.start_time), "type": name,
         "count": int(((sp["week"] == wk) & (sp["sportName"] == name)).sum())}
        for wk in weeks for name in ("Strength", "Running")
    ]
    return {"start": _ts(axis_start), "end": _ts(w.end), "weeks": rows}


def calories(d: Data, w: Window) -> list[dict]:
    """Daily activity calories plus a 7-day average (rolled on the full series,
    so the window's first days still average over the week before)."""
    df = d.activity.sort_values("date").copy()
    df["roll7"] = df["calories"].rolling(7, min_periods=1).mean().round(0)
    df = w.clip(df)
    return [
        {"date": _ts(t), "calories": float(c), "avg7": float(a), "marker": m}
        for t, c, a, m in zip(df["date"], df["calories"], df["roll7"], _markers(len(df)))
    ]


def weight(d: Data, w: Window, units: str = "lbs") -> list[dict]:
    """Weigh-ins inside the window, in `units` ('lbs' or 'kg')."""
    df = w.clip(d.body.sort_values("date"))
    factor = KG_TO_LBS if units == "lbs" else 1
    return [
        {"date": _ts(t), "value": round(float(kg) * factor, 1), "marker": m}
        for t, kg, m in zip(df["date"], df["weight"], _markers(len(df)))
    ]


def _previous(w: Window) -> Window:
    """The span just before `w`: the prior month, or the same number of days."""
    if w.month:
        return Window.for_month(str(pd.Period(w.month, freq="M") - 1))
    return Window.last_days(w.start - pd.Timedelta(days=1), (w.end - w.start).days + 1)


def _mean(df: pd.DataFrame, col: str, w: Window) -> float | None:
    x = w.clip(df)[col].dropna()
    return None if x.empty else float(x.mean())


def _diff(now: float | None, before: float | None, digits: int = 1) -> float | None:
    return None if now is None or before is None else round(now - before, digits)


def kpis(d: Data, w: Window, units: str) -> dict:
    """The header numbers for the window, each with its change vs the span before.

    The sleep score is for the 14 nights up to the window's last night (vs the
    14 before those); the averages cover the window (vs the previous window);
    weight is the last weigh-in by the window's end, and its change across the
    window's weigh-ins.
    """
    prev = _previous(w)

    nights = w.clip(d.sleep)
    parts = sleep_score_parts(d, asof=nights["date"].max()) if not nights.empty else None
    before = sleep_score(d, asof=nights["date"].max() - pd.Timedelta(days=14)) if parts else None

    steps, steps_before = _mean(d.activity, "steps", w), _mean(d.activity, "steps", prev)
    sleep_h, sleep_before = _mean(d.sleep, "totalHours", w), _mean(d.sleep, "totalHours", prev)
    hr, hr_before = _mean(d.resting_hr, "hr", w), _mean(d.resting_hr, "hr", prev)

    factor = KG_TO_LBS if units == "lbs" else 1
    body = d.body[d.body["date"] < w.end + pd.Timedelta(days=1)]
    in_window = w.clip(body)["weight"]
    weight_now = round(float(body["weight"].iloc[-1]) * factor, 1) if not body.empty else None
    weight_change = (round(float(in_window.iloc[-1] - in_window.iloc[0]) * factor, 1)
                     if len(in_window) > 1 else None)

    return {
        "sleep_score": parts["score"] if parts else None,
        "sleep_score_change": parts["score"] - before if parts and before is not None else None,
        "sleep_score_parts": {k: v for k, v in parts.items() if k != "score"} if parts else None,
        "avg_steps": None if steps is None else int(round(steps)),
        "avg_steps_change_pct": (round((steps - steps_before) / steps_before * 100, 1)
                                 if steps is not None and steps_before else None),
        "avg_sleep_h": None if sleep_h is None else round(sleep_h, 1),
        "avg_sleep_h_change": _diff(sleep_h, sleep_before),
        "avg_resting_hr": None if hr is None else int(round(hr)),
        "avg_resting_hr_change": None if hr is None or hr_before is None else int(round(hr - hr_before)),
        "weight": weight_now,
        "weight_change": weight_change,
    }


def dashboard(d: Data, selection: str | None, units: str, default_range: str,
              night: str | None = None) -> dict:
    """Everything the dashboard shows, for a month ('YYYY-MM') or 'last30'.

    An unknown or missing `selection` falls back to `default_range`: the latest
    month, or 'last30'. `night` picks the Sleep Breakdown night (see hypnogram).
    """
    months = d.months()
    if not months:
        raise ValueError("No sleep, activity or weight data in this export.")
    options = ["last30", *reversed(months)]   # newest → oldest
    if selection not in options:
        selection = "last30" if default_range == "last30" else months[-1]
    w = Window.last_days(d.latest_date()) if selection == "last30" else Window.for_month(selection)

    return {
        "selection": selection,
        "options": options,
        "window": {"start": _ts(w.start), "end": _ts(w.end)},
        "units": units,
        "kpis": kpis(d, w, units),
        "stages": stage_shares(d, w),
        "hypnogram": hypnogram(d, w, night),
        "workouts": workouts(d, w),
        "calories": calories(d, w),
        "weight": None if d.body.empty else weight(d, w, units),
    }
