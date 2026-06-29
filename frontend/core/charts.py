"""
Plotly figure builders.

Each function returns a go.Figure ready to be dropped into a Streamlit chart.
"""

import pandas as pd
import plotly.graph_objects as go

from core import data as d
from core.theme import C, AXIS, plot_base


# Local timezone the UTC sleep timestamps are displayed in.
TZ = "America/New_York"


def sleep_months() -> list:
    """Year-months present in the sleep data, oldest → newest, as 'YYYY-MM' strings."""
    return [str(p) for p in sorted(d.sleep["date"].dt.to_period("M").unique())]


def all_months() -> list:
    """Union of year-months across sleep, activity and body data, oldest → newest."""
    return sorted(set(sleep_months()) | set(activity_months()) | set(body_months()))


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


def sleep_score(asof=None) -> int | None:
    """
    0–100 sleep score for the latest day, over the trailing 14 nights.

    Timing 30% · Stage ratios 35% · Duration 20% · Consistency 15%.
    """
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
    return round(score)


# Colour per sleep stage, used by the breakdown bars.
STAGE_COLORS = {
    "Deep":  C["purple"],   # purple
    "REM":   C["cyan"],     # cyan
    "Light": C["amber"],    # yellow
    "Awake": C["pink"],     # coral
}


def sleep_breakdown(month: str | None = None) -> go.Figure:
    """One bar per night spanning sleep → wake time, split into stage-coloured segments."""
    df = d.sleep.sort_values("date").copy()
    months = sleep_months()
    month = month or (months[-1] if months else None)
    if month:
        df = df[df["date"].dt.to_period("M") == pd.Period(month, freq="M")]

    start = pd.to_datetime(df["start"], utc=True).dt.tz_convert(TZ)
    stop  = pd.to_datetime(df["stop"],  utc=True).dt.tz_convert(TZ)
    bed, wake = _clock(start), _clock(stop)

    stages = [
        ("Deep",  df["deepSleepTime"]),
        ("REM",   df["REMTime"]),
        ("Light", df["shallowSleepTime"]),
        ("Awake", df["wakeTime"]),
    ]
    fig = go.Figure()
    base = bed.copy()
    for name, mins in stages:
        hrs = mins / 60
        fig.add_trace(go.Bar(
            x=df["date"], base=base, y=hrs, name=name,
            marker_color=STAGE_COLORS[name],
            customdata=mins,
            hovertemplate=f"{name}: " + "%{customdata:.0f} min<extra></extra>",
        ))
        base = base + hrs

    if not bed.empty:
        lo, hi = float(bed.min()), float(wake.max())
        ticks = list(range(int(lo // 2 * 2), int(hi // 2 * 2) + 3, 2))
        fig.update_yaxes(tickvals=ticks, ticktext=[f"{int(round(t)) % 24:02d}:00" for t in ticks])

    # X ticks: always mark the month's first and last day, plus weekly interior
    # ticks (dropping any that crowd the last-day tick).
    xaxis = {**AXIS, "showgrid": False, "automargin": True, "tickangle": 0}
    if month:
        period = pd.Period(month, freq="M")
        m_start, m_end = period.start_time, period.end_time.normalize()
        interior = [t for t in pd.date_range(m_start, m_end, freq="7D")
                    if t != m_start and (m_end - t).days >= 7]
        xticks = [m_start, *interior, m_end]
        xaxis.update(
            tickvals=xticks,
            ticktext=[f"{t.strftime('%b')} {t.day}" for t in xticks],
            range=[m_start - pd.Timedelta(hours=12), m_end + pd.Timedelta(hours=12)],
        )

    fig.update_layout(
        **plot_base(
            barmode="overlay",
            margin=dict(l=36, r=30, t=28, b=28),  # left: clock labels · right: month-end x-label
        ),
        bargap=0.72,
        xaxis=xaxis,
        yaxis=AXIS,
    )
    return fig


def workouts(month: str | None = None) -> go.Figure:
    """Grouped weekly session counts — the last 8 weeks ending at the selected
    month, framed over a two-month axis (prior month start → this month end).
    Two-tone Strength + solid Running."""
    sp = d.sport.copy()
    sp["week"] = sp["date"].dt.to_period("W")
    if month is None and sp["date"].notna().any():
        month = str(sp["date"].max().to_period("M"))

    # Last 8 weeks whose start falls on or before the selected month's end.
    weeks = []
    if month:
        period = pd.Period(month, freq="M")
        m_end = period.end_time.normalize()
        axis_start = (period - 1).start_time          # first day of the prior month
        weeks = [w for w in sorted(sp["week"].dropna().unique())
                 if w.start_time <= m_end][-8:]
    xs = [w.start_time for w in weeks]

    def counts_for(name):
        return [int(((sp["week"] == w) & (sp["sportName"] == name)).sum()) for w in weeks]

    LIFT = 0.05   # float bars just off the axis so all four corners round
    series = [("Strength", C["purple"]), ("Running", C["amber"])]
    fig = go.Figure()
    for name, color in series:
        counts = counts_for(name)
        fig.add_trace(go.Bar(
            x=xs,
            base=[LIFT if c else 0 for c in counts],
            y=[c - LIFT if c else 0 for c in counts],
            name=name, customdata=counts,
            marker=dict(color=color, cornerradius="40%"),
            hovertemplate="Wk of %{x|%b %d} · " + name + ": %{customdata}<extra></extra>",
        ))

    # X ticks: span the prior-month start through this month's end, marking the
    # first and last day plus weekly interior ticks (dropping any that crowd the
    # last-day tick).
    xaxis = {**AXIS, "showgrid": False, "automargin": True, "tickangle": 0}
    if month:
        # fortnightly interior ticks (~6 total over the two-month span) so the
        # horizontal labels don't crowd.
        interior = [t for t in pd.date_range(axis_start, m_end, freq="14D")
                    if t != axis_start and (m_end - t).days >= 7]
        xticks = [axis_start, *interior, m_end]
        xaxis.update(
            tickvals=xticks,
            ticktext=[f"{t.strftime('%b')} {t.day}" for t in xticks],
            range=[axis_start - pd.Timedelta(hours=12), m_end + pd.Timedelta(hours=12)],
        )

    fig.update_layout(
        **plot_base(barmode="group"),
        bargap=0.45, bargroupgap=0.18,
        xaxis=xaxis,
        yaxis={**AXIS, "dtick": 1},
    )
    return fig


def activity_months() -> list:
    """Year-months present in the activity data, oldest → newest, as 'YYYY-MM' strings."""
    return [str(p) for p in sorted(d.activity["date"].dt.to_period("M").unique())]


def calories(month: str | None = None) -> go.Figure:
    """Daily activity calories with a 7-day average drawn as a marker-dotted line, one month at a time."""
    df = d.activity.sort_values("date").copy()
    df["roll7"] = df["calories"].rolling(7, min_periods=1).mean().round(0)   # rolled on full series for context
    months = activity_months()
    month = month or (months[-1] if months else None)
    if month:
        df = df[df["date"].dt.to_period("M") == pd.Period(month, freq="M")]
    pts = df.iloc[:: max(1, len(df) // 14)]   # spaced points for the glow markers

    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=df["date"], y=df["calories"], name="Calories",
        line=dict(color=C["purple"], width=1), opacity=0.3,
        hovertemplate="%{x|%b %d}: %{y} kcal<extra></extra>",
    ))
    fig.add_trace(go.Scatter(
        x=df["date"], y=df["roll7"], name="7-day avg",
        line=dict(color=C["purple"], width=3, shape="linear"),
        hovertemplate="%{y:.0f} kcal<extra>7d avg</extra>",
    ))
    # Soft halo behind each marker, then the marker itself.
    fig.add_trace(go.Scatter(
        x=pts["date"], y=pts["roll7"], mode="markers", showlegend=False, hoverinfo="skip",
        marker=dict(size=22, color=C["purple"], opacity=0.16),
    ))
    fig.add_trace(go.Scatter(
        x=pts["date"], y=pts["roll7"], mode="markers", showlegend=False, hoverinfo="skip",
        marker=dict(size=8, color=C["purple"], line=dict(color=C["bg"], width=1.5)),
    ))

    # X ticks: always mark the month's first and last day, plus weekly interior
    # ticks (dropping any that crowd the last-day tick).
    xaxis = {**AXIS, "showgrid": False, "automargin": True, "tickangle": 0}
    if month:
        period = pd.Period(month, freq="M")
        m_start, m_end = period.start_time, period.end_time.normalize()
        interior = [t for t in pd.date_range(m_start, m_end, freq="7D")
                    if t != m_start and (m_end - t).days >= 7]
        xticks = [m_start, *interior, m_end]
        xaxis.update(
            tickvals=xticks,
            ticktext=[f"{t.strftime('%b')} {t.day}" for t in xticks],
            range=[m_start - pd.Timedelta(hours=12), m_end + pd.Timedelta(hours=12)],
        )

    fig.update_layout(
        **plot_base(),
        xaxis=xaxis, yaxis=AXIS,
    )
    return fig


def body_months() -> list:
    """Year-months present in the body/weight data, oldest → newest, as 'YYYY-MM' strings."""
    return [str(p) for p in sorted(d.body["date"].dt.to_period("M").unique())]


def weight(month: str | None = None) -> go.Figure:
    """Weight trend (lbs) as a marker-dotted line, one month at a time."""
    df = d.body.sort_values("date").copy()
    df["lbs"] = (df["weight"] * 2.20462).round(1)
    months = body_months()
    month = month or (months[-1] if months else None)
    if month:
        df = df[df["date"].dt.to_period("M") == pd.Period(month, freq="M")]
    pts = df.iloc[:: max(1, len(df) // 14)]   # spaced points for the glow markers

    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=df["date"], y=df["lbs"], name="Weight",
        line=dict(color=C["purple"], width=3, shape="linear"),
        hovertemplate="%{x|%b %d}: %{y} lbs<extra>Weight</extra>",
    ))
    # Soft halo behind each marker, then the marker itself.
    fig.add_trace(go.Scatter(
        x=pts["date"], y=pts["lbs"], mode="markers", showlegend=False, hoverinfo="skip",
        marker=dict(size=22, color=C["purple"], opacity=0.16),
    ))
    fig.add_trace(go.Scatter(
        x=pts["date"], y=pts["lbs"], mode="markers", showlegend=False, hoverinfo="skip",
        marker=dict(size=8, color=C["purple"], line=dict(color=C["bg"], width=1.5)),
    ))

    # X ticks: always mark the month's first and last day, plus weekly interior
    # ticks (dropping any that crowd the last-day tick).
    xaxis = {**AXIS, "showgrid": False, "automargin": True, "tickangle": 0}
    if month:
        period = pd.Period(month, freq="M")
        m_start, m_end = period.start_time, period.end_time.normalize()
        interior = [t for t in pd.date_range(m_start, m_end, freq="7D")
                    if t != m_start and (m_end - t).days >= 7]
        xticks = [m_start, *interior, m_end]
        xaxis.update(
            tickvals=xticks,
            ticktext=[f"{t.strftime('%b')} {t.day}" for t in xticks],
            range=[m_start - pd.Timedelta(hours=12), m_end + pd.Timedelta(hours=12)],
        )

    fig.update_layout(
        **plot_base(showlegend=False),
        xaxis=xaxis, yaxis=AXIS,
    )
    return fig
