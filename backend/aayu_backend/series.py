"""Chart series and KPIs — the numbers behind each dashboard chart.

Same filtering, sleep-clock maths, week bucketing and rolling averages as the
old Plotly chart builders, but the output is plain JSON-ready values: the
SwiftUI app draws them with Swift Charts. Nothing here knows how they look.
The maths was verified against that old code; tests/test_golden.py pins it.

Timestamps go out as naive local ISO strings (``2026-05-01T00:00:00``); the
app parses them in the Mac's timezone, so a midnight stays a midnight.
"""

import logging
import math
from collections.abc import Callable
from dataclasses import dataclass
from datetime import time

import pandas as pd

from aayu_backend.data import Data
from aayu_backend.errors import Code, UserError, log_failure
from aayu_backend.payload import (
    CalorieDay,
    Dashboard,
    Hypnogram,
    KPIs,
    SleepScore,
    StageShare,
    StageSpan,
    Units,
    WeightPoint,
    Workouts,
    WorkoutWeek,
)

log = logging.getLogger(__name__)

KG_TO_LBS = 2.20462

# Local timezone the UTC sleep timestamps are displayed in.
TZ = "America/New_York"

LAST_DAYS = 30           # the 'last30' window
MARKERS_PER_WINDOW = 14  # dots drawn on a line chart, roughly
MINUTE = pd.Timedelta(minutes=1)

# A night's stage minutes run on through gaps up to NIGHT_GAP, looking at most
# NIGHT_REACH beyond the recorded bedtime and wake time.
NIGHT_GAP = pd.Timedelta(minutes=30)
NIGHT_REACH = pd.Timedelta(hours=6)

# Sleep stages, deepest first, with their SLEEP column (nightly minutes).
STAGES = [("Deep", "deepSleepTime"), ("REM", "REMTime"), ("Light", "shallowSleepTime"), ("Awake", "wakeTime")]

# Workouts: the last WORKOUT_WEEKS weeks with a session, over a two-month axis.
WORKOUT_WEEKS = 8
WORKOUT_TYPES = ("Strength", "Running")
AXIS_MONTHS = 2

CALORIE_AVG_DAYS = 7   # the calories chart's rolling average

# On the night-centred clock, hours before this are the morning (positive);
# from it on, the evening before (negative).
_CLOCK_SPLIT_H = 14


@dataclass(frozen=True)
class Window:
    """The date span the charts show: a calendar month or the last N days."""

    start: pd.Timestamp        # first day shown (midnight)
    end: pd.Timestamp          # last day shown (midnight)
    month: str | None = None   # 'YYYY-MM' when the window is a calendar month

    @classmethod
    def for_month(cls, month: str) -> "Window":
        """The calendar month 'YYYY-MM'."""
        period = pd.Period(month, freq="M")
        return cls(period.start_time, period.end_time.normalize(), month)

    @classmethod
    def last_days(cls, end: pd.Timestamp, days: int = LAST_DAYS) -> "Window":
        """The `days` days ending on (and including) `end`."""
        return cls(end - pd.Timedelta(days=days - 1), end)

    def clip(self, df: pd.DataFrame) -> pd.DataFrame:
        """Rows whose ``date`` falls on a day inside the window."""
        return df[(df["date"] >= self.start) & (df["date"] < self.end + pd.Timedelta(days=1))]


def _ts(t: pd.Timestamp) -> str:
    return t.strftime("%Y-%m-%dT%H:%M:%S")


def _markers(n: int) -> list[bool]:
    """Every k-th point (~14 per window) gets a dot on the line."""
    step = max(1, n // MARKERS_PER_WINDOW)
    return [i % step == 0 for i in range(n)]


def _clock(ts: pd.Series) -> pd.Series:
    """Fractional clock-hour on a night-centred axis: evenings go negative, mornings positive."""
    h: pd.Series = ts.dt.hour + ts.dt.minute / 60
    return h.where(h < _CLOCK_SPLIT_H, h - 24)


def _finite(x: float | None) -> float | None:
    """`x`, or None when it is missing, NaN or infinite (for fields Swift declares optional)."""
    return x if x is not None and math.isfinite(x) else None


# ── Sleep score ──────────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class SleepTargets:
    """The bed and wake times the score's timing aims for (set in the app's Settings)."""

    bedtime: time
    wake_time: time


DEFAULT_TARGETS = SleepTargets(time(23, 30), time(6, 30))   # 11:30 PM bed, 6:30 AM wake
_IDEAL_RATIOS = {"deep": 0.20, "rem": 0.22, "light": 0.53, "awake": 0.05}
_TARGET_SLEEP_H = 7.5
SCORE_NIGHTS = 14   # the score covers the trailing 14 nights

# Each part is full marks within its first bound and fades to zero at its second.
_TIMING_FULL_H, _TIMING_ZERO_H = 1 / 3, 2.0            # mean bed/wake time vs ideal
_CONSISTENCY_FULL_H, _CONSISTENCY_ZERO_H = 1 / 3, 1.5  # spread of bed/wake times
_STAGE_ZERO = 0.15                                     # stage ratio vs ideal
_DURATION_FULL_H, _DURATION_ZERO_H = 0.5, 3.0          # mean time asleep vs target
_AWAKENINGS_FULL, _AWAKENINGS_ZERO = 2.0, 6.0          # mean awakenings a night

# Weights of the parts in the 0–100 score.
_W_TIMING, _W_CONSISTENCY, _W_STAGES, _W_DURATION, _W_AWAKENINGS = 0.30, 0.15, 0.25, 0.20, 0.10


def _closeness(dev: float, full: float, zero: float) -> float:
    """1.0 when deviation ≤ `full` hours, fading linearly to 0.0 at `zero`."""
    if dev <= full:
        return 1.0
    if dev >= zero:
        return 0.0
    return 1 - (dev - full) / (zero - full)


def _clock_time(t: time) -> float:
    """`t` on the night-centred clock of `_clock`: 11:30 PM → -0.5, 6:30 AM → 6.5."""
    h = t.hour + t.minute / 60
    return h if h < _CLOCK_SPLIT_H else h - 24


def _awakenings(m: pd.DataFrame) -> int | None:
    """Times a night's sleep broke: runs of Awake minutes between its first and last minute asleep.

    `m` is the night's stage minutes (see `_night_minutes`); None when none of them is asleep.
    """
    asleep = (m["stage"] != "Awake").to_numpy()
    if not asleep.any():
        return None
    awake = ~asleep[asleep.argmax():len(asleep) - asleep[::-1].argmax()]
    return int((awake[1:] & ~awake[:-1]).sum())


def sleep_score(d: Data, asof: pd.Timestamp | None = None,
                targets: SleepTargets = DEFAULT_TARGETS) -> int | None:
    """0–100 sleep score for the latest day (or `asof`), over the trailing 14 nights.

    Timing 30% · Stage ratios 25% · Duration 20% · Consistency 15% · Awakenings 10%.
    """
    parts = sleep_score_parts(d, asof, targets)
    return None if parts is None else parts["score"]


def sleep_score_parts(d: Data, asof: pd.Timestamp | None = None,
                      targets: SleepTargets = DEFAULT_TARGETS) -> SleepScore | None:
    """The sleep score plus its five parts, each 0–1 (1 = on target).

    Nights without a bedtime or wake time are left out; None when no night is left.
    Awakenings come from SLEEP_MINUTE: when no night has stage minutes, that part
    is None and the score comes from the other four, reweighted to sum to 100%.
    """
    df = d.sleep.sort_values("date")
    if df.empty:
        return None
    last = asof if asof is not None else pd.Timestamp(df["date"].max())
    win = df[(df["date"] > last - pd.Timedelta(days=SCORE_NIGHTS)) & (df["date"] <= last)]
    win = win[win["start"].notna() & win["stop"].notna()]
    if win.empty:
        return None

    bed, wake = _clock(win["start"].dt.tz_convert(TZ)), _clock(win["stop"].dt.tz_convert(TZ))

    # Timing (30%) — average bed/wake vs the targets
    timing = (_closeness(abs(bed.mean() - _clock_time(targets.bedtime)), _TIMING_FULL_H, _TIMING_ZERO_H)
              + _closeness(abs(wake.mean() - _clock_time(targets.wake_time)), _TIMING_FULL_H, _TIMING_ZERO_H)) / 2

    # Consistency (15%) — tightness of the schedule
    consistency = (_closeness(bed.std(ddof=0), _CONSISTENCY_FULL_H, _CONSISTENCY_ZERO_H)
                   + _closeness(wake.std(ddof=0), _CONSISTENCY_FULL_H, _CONSISTENCY_ZERO_H)) / 2

    # Stage ratios (25%) — closeness to the magic ratio (awake only penalised when high)
    deep, rem, light, awake = (win["deepSleepTime"].sum(), win["REMTime"].sum(),
                               win["shallowSleepTime"].sum(), win["wakeTime"].sum())
    total = deep + rem + light + awake
    ratios = {"deep": deep / total, "rem": rem / total, "light": light / total, "awake": awake / total}

    def stage_pts(k: str) -> float:
        dev = ratios[k] - _IDEAL_RATIOS[k]
        if k == "awake":
            dev = max(0.0, dev)
        return max(0.0, 1 - abs(dev) / _STAGE_ZERO)

    stages = sum(stage_pts(k) for k in _IDEAL_RATIOS) / len(_IDEAL_RATIOS)

    # Duration (20%) — average time asleep vs target
    avg_asleep_h = (deep + rem + light) / 60 / len(win)
    duration = _closeness(abs(avg_asleep_h - _TARGET_SLEEP_H), _DURATION_FULL_H, _DURATION_ZERO_H)

    # Awakenings (10%) — average times a night that sleep broke, over the nights with stage minutes
    counts = [n for start, stop in zip(win["start"], win["stop"], strict=True)
              if (n := _awakenings(_night_minutes(d.sleep_minutes, _local(start), _local(stop)))) is not None]
    awakenings = (_closeness(sum(counts) / len(counts), _AWAKENINGS_FULL, _AWAKENINGS_ZERO)
                  if counts else None)

    points = _W_TIMING * timing + _W_CONSISTENCY * consistency + _W_STAGES * stages + _W_DURATION * duration
    score = (100 * (points + _W_AWAKENINGS * awakenings) if awakenings is not None
             else 100 * points / (1 - _W_AWAKENINGS))
    if not math.isfinite(score):
        return None
    return {"score": round(score), "timing": round(float(timing), 2),
            "consistency": round(float(consistency), 2), "stages": round(float(stages), 2),
            "duration": round(float(duration), 2),
            "awakenings": None if awakenings is None else round(awakenings, 2)}


# ── Sleep Breakdown (hypnogram) ──────────────────────────────────────────────────
def _local(ts: pd.Timestamp) -> pd.Timestamp:
    """A UTC timestamp from SLEEP as naive local time (matching SLEEP_MINUTE)."""
    return ts.tz_convert(TZ).tz_localize(None)


def _window_nights(d: Data, w: Window) -> pd.DataFrame:
    """The window's nights with a bedtime and wake time, oldest first; a repeated date keeps its last row."""
    rows = w.clip(d.sleep.sort_values("date", kind="stable"))
    rows = rows[rows["start"].notna() & rows["stop"].notna()]
    return rows.drop_duplicates("date", keep="last")


def _pick_night(dates: list[str], night: str | None) -> int:
    """Index of `night` in `dates`, or of the last night when it isn't there."""
    return dates.index(night) if night in dates else len(dates) - 1


def _night_minutes(minutes: pd.DataFrame, bed: pd.Timestamp, wake: pd.Timestamp) -> pd.DataFrame:
    """The stage minutes of the night slept `bed` → `wake` (naive local times).

    Every run of minutes (consecutive stamps at most NIGHT_GAP apart) with a
    minute inside bedtime–wake time, cut at NIGHT_REACH beyond either end.
    """
    m = minutes[(minutes["ts"] >= bed - NIGHT_REACH) & (minutes["ts"] <= wake + NIGHT_REACH)]
    run = (m["ts"].diff() > NIGHT_GAP).cumsum()
    return m[run.isin(run[(m["ts"] >= bed.floor("min")) & (m["ts"] <= wake)].unique())]


def _segments(m: pd.DataFrame) -> tuple[list[StageSpan], dict[str, int]]:
    """Merge consecutive same-stage minutes into spans; also each stage's minutes (in ``STAGES`` order)."""
    totals = {stage: 0 for stage, _ in STAGES}
    if m.empty:
        return [], totals
    new_run = (m["stage"] != m["stage"].shift()) | (m["ts"].diff() != MINUTE)
    runs = m.groupby(new_run.cumsum()).agg(stage=("stage", "first"), first=("ts", "first"),
                                           last=("ts", "last"), minutes=("ts", "size"))
    segments: list[StageSpan] = []
    for stage, first, last, n in zip(runs["stage"], runs["first"], runs["last"], runs["minutes"], strict=True):
        segments.append({"stage": stage, "start": _ts(first), "end": _ts(last + MINUTE)})
        totals[stage] += int(n)
    return segments, totals


def hypnogram(d: Data, w: Window, night: str | None = None) -> Hypnogram | None:
    """One night's sleep stages over time, for the Sleep Breakdown card.

    `night` is a sleep date ('YYYY-MM-DD') inside the window; anything else
    means the window's last night. The night's minutes are every run of
    SLEEP_MINUTE rows that overlaps bedtime–wake time, followed outward across
    gaps of up to NIGHT_GAP — the watch often keeps scoring stages past the
    recorded times — and ``start``/``end`` widen to cover them. Consecutive
    minutes in the same stage merge into one segment. ``nights`` lists every
    night in the window, for stepping.
    """
    rows = _window_nights(d, w)
    if rows.empty:
        return None
    dates = [t.strftime("%Y-%m-%d") for t in rows["date"]]
    i = _pick_night(dates, night)
    start, stop = _local(rows["start"].iloc[i]), _local(rows["stop"].iloc[i])

    m = _night_minutes(d.sleep_minutes, start, stop)
    if not m.empty:
        start, stop = min(start, m["ts"].iloc[0]), max(stop, m["ts"].iloc[-1] + MINUTE)
    segments, totals = _segments(m)
    total = sum(totals.values())
    return {
        "night": dates[i],
        "nights": dates,
        "start": _ts(start),
        "end": _ts(stop),
        "segments": segments,
        "totals": [{"stage": k, "minutes": v, "share": round(v / total, 4) if total else 0.0}
                   for k, v in totals.items()],
        "asleep": total - totals["Awake"],                          # minutes in a sleep stage
        "duration": int((stop - start).total_seconds() // 60),      # start to end, minutes
        "awakenings": _awakenings(m),
    }


# ── Other charts ─────────────────────────────────────────────────────────────────
def stage_shares(d: Data, w: Window) -> list[StageShare]:
    """Each stage's share of all sleep minutes (awake included) in the window."""
    df = w.clip(d.sleep)
    minutes = {stage: float(df[col].fillna(0).sum()) for stage, col in STAGES}
    total = sum(minutes.values())
    return [
        {"stage": stage, "minutes": round(m), "share": round(m / total, 4) if total else 0.0}
        for stage, m in minutes.items()
    ]


def _axis_start(w: Window) -> pd.Timestamp:
    """The workouts axis start: the prior month's start for a calendar month, else two months back."""
    if w.month:
        return (pd.Period(w.month, freq="M") - (AXIS_MONTHS - 1)).start_time
    return w.end - pd.DateOffset(months=AXIS_MONTHS) + pd.Timedelta(days=1)


def workouts(d: Data, w: Window) -> Workouts:
    """Weekly Strength and Running session counts for the last 8 weeks ending at the window's last day.

    They are framed over a two-month axis (``start`` → ``end``).
    """
    sp = d.sport.copy()
    sp["week"] = sp["date"].dt.to_period("W")

    # Last 8 weeks (that had any session) whose start falls on or before the window's last day.
    weeks = [wk for wk in sorted(sp["week"].dropna().unique()) if wk.start_time <= w.end][-WORKOUT_WEEKS:]
    rows: list[WorkoutWeek] = [
        {"week": _ts(wk.start_time), "type": name,
         "count": int(((sp["week"] == wk) & (sp["sportName"] == name)).sum())}
        for wk in weeks for name in WORKOUT_TYPES
    ]
    return {"start": _ts(_axis_start(w)), "end": _ts(w.end), "weeks": rows}


def calories(d: Data, w: Window) -> list[CalorieDay]:
    """Daily activity calories plus a 7-day average.

    The average is rolled on the full series, so the window's first days still
    average over the week before. Days with no calories figure are left out.
    """
    df = d.activity.sort_values("date", kind="stable").copy()
    df["roll7"] = df["calories"].rolling(CALORIE_AVG_DAYS, min_periods=1).mean().round(0)
    df = w.clip(df)
    df = df[df["calories"].notna() & df["roll7"].notna()]
    return [
        {"date": _ts(t), "calories": float(c), "avg7": float(a), "marker": m}
        for t, c, a, m in zip(df["date"], df["calories"], df["roll7"], _markers(len(df)), strict=True)
    ]


def _factor(units: Units) -> float:
    return KG_TO_LBS if units == "lbs" else 1


def weight(d: Data, w: Window, units: Units = "lbs") -> list[WeightPoint]:
    """Weigh-ins inside the window, in `units` ('lbs' or 'kg')."""
    df = w.clip(d.body.sort_values("date", kind="stable"))
    factor = _factor(units)
    return [
        {"date": _ts(t), "value": round(float(kg) * factor, 1), "marker": m}
        for t, kg, m in zip(df["date"], df["weight"], _markers(len(df)), strict=True)
    ]


# ── KPIs ─────────────────────────────────────────────────────────────────────────
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


def kpis(d: Data, w: Window, units: Units, targets: SleepTargets = DEFAULT_TARGETS) -> KPIs:
    """The header numbers for the window, each with its change vs the span before.

    The sleep score is for the 14 nights up to the window's last night (vs the
    14 before those), timed against `targets`; the averages cover the window (vs the previous window);
    weight is the last weigh-in by the window's end, and its change across the
    window's weigh-ins.
    """
    prev = _previous(w)

    nights = w.clip(d.sleep)
    last_night = pd.Timestamp(nights["date"].max()) if not nights.empty else None
    parts = sleep_score_parts(d, last_night, targets) if last_night is not None else None
    before = (sleep_score(d, last_night - pd.Timedelta(days=SCORE_NIGHTS), targets)
              if parts and last_night is not None else None)

    steps, steps_before = _mean(d.activity, "steps", w), _mean(d.activity, "steps", prev)
    sleep_h, sleep_before = _mean(d.sleep, "totalHours", w), _mean(d.sleep, "totalHours", prev)
    hr, hr_before = _mean(d.resting_hr, "hr", w), _mean(d.resting_hr, "hr", prev)

    factor = _factor(units)
    body = d.body[d.body["date"] < w.end + pd.Timedelta(days=1)]
    in_window = w.clip(body)["weight"]
    weight_now = round(float(body["weight"].iloc[-1]) * factor, 1) if not body.empty else None
    weight_change = (round(float(in_window.iloc[-1] - in_window.iloc[0]) * factor, 1)
                     if len(in_window) > 1 else None)

    return {
        "sleep_score": parts["score"] if parts else None,
        "sleep_score_change": parts["score"] - before if parts and before is not None else None,
        "sleep_score_parts": ({"timing": parts["timing"], "consistency": parts["consistency"],
                               "stages": parts["stages"], "duration": parts["duration"],
                               "awakenings": parts["awakenings"]} if parts else None),
        "avg_steps": None if steps is None else round(steps),
        "avg_steps_change_pct": _finite(round((steps - steps_before) / steps_before * 100, 1)
                                        if steps is not None and steps_before else None),
        "avg_sleep_h": None if sleep_h is None else round(sleep_h, 1),
        "avg_sleep_h_change": _diff(sleep_h, sleep_before),
        "avg_resting_hr": None if hr is None else round(hr),
        "avg_resting_hr_change": None if hr is None or hr_before is None else round(hr - hr_before),
        "weight": _finite(weight_now),
        "weight_change": _finite(weight_change),
    }


_EMPTY_KPIS: KPIs = {
    "sleep_score": None, "sleep_score_change": None, "sleep_score_parts": None,
    "avg_steps": None, "avg_steps_change_pct": None, "avg_sleep_h": None, "avg_sleep_h_change": None,
    "avg_resting_hr": None, "avg_resting_hr_change": None, "weight": None, "weight_change": None,
}

def _section[T](name: str, compute: Callable[[], T], fallback: T) -> T:
    """`compute()`, or `fallback` (logged) if it fails — one broken chart mustn't blank the dashboard."""
    try:
        return compute()
    except Exception as e:  # noqa: BLE001 — logged; the rest of the dashboard still renders
        log_failure(log, f"dashboard section {name!r}", e)
        return fallback


# ── The whole dashboard ──────────────────────────────────────────────────────────
def dashboard(d: Data, selection: str | None, units: Units, default_range: str,
              night: str | None = None, targets: SleepTargets = DEFAULT_TARGETS) -> Dashboard:
    """Everything the dashboard shows, for a month ('YYYY-MM') or 'last30'.

    An unknown or missing `selection` falls back to `default_range`: the latest
    month, or 'last30'. `night` picks the Sleep Breakdown night (see hypnogram);
    `targets` are the bed and wake times the sleep score aims for.
    A section that fails is logged and sent empty (``[]``, or null where the
    app allows it) rather than failing the whole dashboard.
    """
    months = d.months()
    latest = d.latest_date()
    if not months or latest is None:
        raise UserError("No sleep, activity or weight data in this export.", Code.NO_DATA)
    options = ["last30", *reversed(months)]   # newest → oldest
    if selection is None or selection not in options:
        selection = "last30" if default_range == "last30" else months[-1]
    w = Window.last_days(latest) if selection == "last30" else Window.for_month(selection)
    no_workouts: Workouts = {"start": _ts(_axis_start(w)), "end": _ts(w.end), "weeks": []}

    return {
        "selection": selection,
        "options": options,
        "window": {"start": _ts(w.start), "end": _ts(w.end)},
        "units": units,
        "kpis": _section("kpis", lambda: kpis(d, w, units, targets), _EMPTY_KPIS),
        "stages": _section("stages", lambda: stage_shares(d, w), []),
        "hypnogram": _section("hypnogram", lambda: hypnogram(d, w, night), None),
        "workouts": _section("workouts", lambda: workouts(d, w), no_workouts),
        "calories": _section("calories", lambda: calories(d, w), []),
        "weight": None if d.body.empty else _section("weight", lambda: weight(d, w, units), None),
    }
