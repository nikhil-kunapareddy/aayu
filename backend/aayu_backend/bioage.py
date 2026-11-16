"""Bio age and pace of aging: a risk-equivalent age from wearable markers.

Each marker's average over the 90 days up to a date becomes a relative risk of
death, from a published dose-response measured from a reference value at which
the marker counts zero. The Gompertz law turns a relative risk into years:
adult mortality rises about 8.5% a year (it doubles every ~8 years), so a
relative risk RR carries the same risk as ``ln(RR) / 0.085`` years of age.
Bio age is the calendar age plus each marker's years, each capped at ±3 (the
published fits are straight lines that don't hold far outside the ranges
studied). It needs at least three of the five markers.

Pace of aging is years of bio age gained per calendar year: 1 + the slope of
(bio age - age) over up to 26 weekly points, using the markers scored now.

This is an estimate from observational studies, not a lab test, and the
markers overlap (active people tend to have lower heart rates), so adding them
somewhat overstates the total. The app's info popover says so. Sources:

- Steps: Banach et al. 2023, Eur J Prev Cardiol: HR 0.85 per +1,000 steps a day.
- Sleep regularity: Windred et al., UK Biobank: hazard -20.4% per +10.7 SRI
  points (1 SD); the cohort's median SRI is 81.
- BMI: Global BMI Mortality Collaboration 2016, Lancet: HR 1.29 per +5 kg/m²
  above 25 (North America); 18.5–25 is the low-risk range.
- Sleep duration: Yin et al. 2017, JAHA: RR 1.06 per hour below 7 h and 1.13
  per hour above (counted here from 8 h, so 7–8 h is neutral).
- Resting heart rate: Zhang et al. 2016, CMAJ: RR 1.09 per +10 bpm.
"""

import math
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date

import numpy as np
import pandas as pd

from aayu_backend.data import Data
from aayu_backend.payload import BioAge, BioMarker, BioMarkerKey, BirthSource

GOMPERTZ = 0.085           # yearly rise in ln(adult mortality): a doubling every ~8 years
DAYS_PER_YEAR = 365.2425
WINDOW_DAYS = 90           # each marker averages the 90 days up to the date
CAP_YEARS = 3.0            # most one marker can add or take away
MIN_DAYS = 14              # days, nights or day pairs a daily marker needs in the window
MIN_MARKERS = 3            # markers needed for a bio age
PACE_WEEKS = 26            # weekly points the pace is fitted over, at most…
PACE_MIN_POINTS = 13       # …and at least (about three months)
PACE_MIN, PACE_MAX = -1.0, 3.0
ZEPP_BIRTH_DAY = 15        # the Zepp profile has only a birth month: assume mid-month

MINUTE = pd.Timedelta(minutes=1)
DAY = pd.Timedelta(days=1)
MINUTES_A_DAY = 1440


def _years_per_unit(relative_risk: float, per: float) -> float:
    """Years of age per unit of a marker whose relative risk is `relative_risk` per `per` units."""
    return math.log(relative_risk) / per / GOMPERTZ


STEPS_REF, STEPS_CAP = 7000.0, 10000.0
STEPS_YEARS = _years_per_unit(0.85, 1000)        # per step a day: -1.9 per 1,000
SRI_REF = 81.0
SRI_YEARS = _years_per_unit(1 - 0.204, 10.7)     # per SRI point: -0.25
BMI_REF, BMI_MIN = 25.0, 18.5
BMI_YEARS = _years_per_unit(1.29, 5)             # per kg/m² above 25: +0.6
SLEEP_SHORT_H, SLEEP_LONG_H = 7.0, 8.0
SLEEP_SHORT_YEARS = _years_per_unit(1.06, 1)     # per hour below 7: +0.7
SLEEP_LONG_YEARS = _years_per_unit(1.13, 1)      # per hour above 8: +1.4
HR_REF = 60.0
HR_YEARS = _years_per_unit(1.09, 10)             # per bpm above 60: +0.1


def _cap(years: float) -> float:
    return max(-CAP_YEARS, min(CAP_YEARS, years))


def steps_years(steps: float) -> float:
    """Years for a daily step average: zero at 7,000, no further credit past 10,000."""
    return _cap((min(steps, STEPS_CAP) - STEPS_REF) * STEPS_YEARS)


def regularity_years(sri: float) -> float:
    """Years for a Sleep Regularity Index: zero at the UK Biobank median, 81."""
    return _cap((sri - SRI_REF) * SRI_YEARS)


def bmi_years(bmi: float) -> float | None:
    """Years for a BMI: zero from 18.5 to 25, rising above; None below 18.5 (not modelled)."""
    if bmi < BMI_MIN:
        return None
    return _cap(max(0.0, bmi - BMI_REF) * BMI_YEARS)


def sleep_years(hours: float) -> float:
    """Years for a nightly sleep average: zero from 7 to 8 hours."""
    if hours < SLEEP_SHORT_H:
        return _cap((SLEEP_SHORT_H - hours) * SLEEP_SHORT_YEARS)
    if hours > SLEEP_LONG_H:
        return _cap((hours - SLEEP_LONG_H) * SLEEP_LONG_YEARS)
    return 0.0


def resting_hr_years(bpm: float) -> float:
    """Years for a resting heart rate (the day's 5th-percentile reading): zero at 60 bpm."""
    return _cap((bpm - HR_REF) * HR_YEARS)


# ── Marker values over a window ──────────────────────────────────────────────────
@dataclass(frozen=True)
class _Span:
    """The days `start` … `end` (midnights, inclusive)."""

    start: pd.Timestamp
    end: pd.Timestamp

    @classmethod
    def ending(cls, end: pd.Timestamp) -> "_Span":
        return cls(end - pd.Timedelta(days=WINDOW_DAYS - 1), end)

    def clip(self, df: pd.DataFrame) -> pd.DataFrame:
        return df[(df["date"] >= self.start) & (df["date"] < self.end + DAY)]


def _daily_mean(df: pd.DataFrame, col: str, span: _Span, at_least: int = MIN_DAYS) -> float | None:
    x = span.clip(df)[col].dropna()
    return float(x.mean()) if len(x) >= at_least else None


@dataclass(frozen=True)
class SleepGrid:
    """Minutes asleep, one row per sleep day (noon to noon, named by its morning's date)."""

    days: pd.DatetimeIndex   # sleep days with any minute asleep, oldest first
    asleep: np.ndarray       # bool, len(days) x 1440; column 0 is noon the day before

    @classmethod
    def of(cls, minutes: pd.DataFrame) -> "SleepGrid":
        """From SLEEP_MINUTE (naive local ``ts``, ``stage``); Awake minutes count as awake."""
        m = minutes[minutes["stage"] != "Awake"]
        shifted = m["ts"] + pd.Timedelta(hours=12)
        day = shifted.dt.normalize()
        days = pd.DatetimeIndex(sorted(day.unique()))
        grid = np.zeros((len(days), MINUTES_A_DAY), dtype=bool)
        offset = ((shifted - day) // MINUTE).to_numpy(dtype=np.int64)
        grid[days.get_indexer(pd.DatetimeIndex(day)), np.clip(offset, 0, MINUTES_A_DAY - 1)] = True
        return cls(days, grid)

    def regularity(self, span: _Span) -> float | None:
        """The Sleep Regularity Index (-100–100) over `span`.

        The chance of being in the same state (asleep or awake) 24 hours apart,
        scaled so 100 is a perfectly repeated day; over pairs of consecutive
        sleep days that both have sleep recorded, at least MIN_DAYS of them.
        """
        rows = np.flatnonzero((self.days >= span.start) & (self.days <= span.end))
        if len(rows) <= MIN_DAYS:
            return None
        pairs = rows[:-1][np.diff(self.days[rows].to_numpy()) == np.timedelta64(1, "D")]   # any datetime unit
        if len(pairs) < MIN_DAYS:
            return None
        same = (self.asleep[pairs] == self.asleep[pairs + 1]).mean()
        return float(200 * same - 100)


_Reading = tuple[float | None, float | None]   # (value, years)


def _scored(value: float | None, years: Callable[[float], float | None]) -> _Reading:
    return (value, None if value is None else years(value))


def readings(d: Data, grid: SleepGrid, end: pd.Timestamp) -> dict[BioMarkerKey, _Reading]:
    """Each marker's value and years for the 90 days ending on `end`, in display order."""
    span = _Span.ending(end)
    return {
        "steps": _scored(_daily_mean(d.activity, "steps", span), steps_years),
        "regularity": _scored(grid.regularity(span), regularity_years),
        "bmi": _scored(_daily_mean(d.body, "bmi", span, at_least=1), bmi_years),
        "sleep": _scored(_daily_mean(d.sleep, "totalHours", span), sleep_years),
        "resting_hr": _scored(_daily_mean(d.resting_hr, "hr", span), resting_hr_years),
    }


# ── Bio age and pace ─────────────────────────────────────────────────────────────
_VALUE_DIGITS: dict[BioMarkerKey, int] = {"steps": 0, "regularity": 0, "bmi": 1, "sleep": 1, "resting_hr": 0}


def _tenths(x: float) -> float:
    return round(x, 1) + 0.0   # + 0.0 turns -0.0 into 0.0


def birth(given: date | None, d: Data) -> tuple[date, BirthSource] | None:
    """The birth date to use: the app's setting, else mid-month of the Zepp profile's birth month."""
    if given is not None:
        return given, "settings"
    if d.birth_month is None:
        return None
    year, month = (int(p) for p in d.birth_month.split("-"))
    return date(year, month, ZEPP_BIRTH_DAY), "zepp"


def pace(d: Data, grid: SleepGrid, end: pd.Timestamp, now: dict[BioMarkerKey, _Reading]) -> float | None:
    """Years of bio age gained per calendar year, from weekly points back from `end`.

    Uses the markers scored at `end`; walks back a week at a time while they are
    all still scored (at most PACE_WEEKS points) and fits a straight line to the
    gap (bio age - age, i.e. the markers' years). None with fewer than
    PACE_MIN_POINTS points; clamped to PACE_MIN…PACE_MAX.
    """
    keys = [k for k, (_, years) in now.items() if years is not None]
    if len(keys) < MIN_MARKERS:
        return None
    when: list[float] = []
    gap: list[float] = []
    for week in range(PACE_WEEKS):
        point = now if week == 0 else readings(d, grid, end - pd.Timedelta(weeks=week))
        years = [point[k][1] for k in keys]
        if any(y is None for y in years):
            break
        when.append(-week * 7 / DAYS_PER_YEAR)
        gap.append(sum(y for y in years if y is not None))
    if len(when) < PACE_MIN_POINTS:
        return None
    slope = float(np.polyfit(when, gap, 1)[0])
    return round(min(PACE_MAX, max(PACE_MIN, 1 + slope)), 2) + 0.0


def bio_age(d: Data, asof: pd.Timestamp, born: date | None) -> BioAge | None:
    """Bio age, pace and the markers behind them, for the 90 days ending on `asof`.

    `born` is the birth date from the app's Settings (None: use the Zepp
    profile's birth month). None when there's no birth date or `asof` is before it.
    """
    found = birth(born, d)
    end = asof.normalize()
    if found is None or end <= pd.Timestamp(found[0]):
        return None
    birth_date, source = found
    grid = SleepGrid.of(d.sleep_minutes)
    now = readings(d, grid, end)

    markers: list[BioMarker] = [
        {"key": key,
         "value": None if value is None else round(value, _VALUE_DIGITS[key]) + 0.0,
         "years": None if years is None else _tenths(years)}
        for key, (value, years) in now.items()
    ]
    age = _tenths((end - pd.Timestamp(birth_date)).days / DAYS_PER_YEAR)
    scored = [m["years"] for m in markers if m["years"] is not None]
    enough = len(scored) >= MIN_MARKERS
    return {
        "end": end.strftime("%Y-%m-%dT%H:%M:%S"),
        "age": age,
        "bio_age": _tenths(age + sum(scored)) if enough else None,
        "pace": pace(d, grid, end, now) if enough else None,
        "markers": markers,
        "birth_source": source,
        "birth_date": birth_date.isoformat(),
        "days": WINDOW_DAYS,
    }
