"""Bio age and pace of aging (bioage.py), on fabricated frames and exports."""

from __future__ import annotations

import math
from collections.abc import Callable
from datetime import date
from pathlib import Path

import pandas as pd
import pytest

from aayu_backend import bioage, data, series
from aayu_backend.payload import BioAge
from tests.conftest import make_export, write_csv

END = pd.Timestamp("2026-05-31")
BORN = date(1990, 6, 1)


def make_data(days: int = 120, *, steps: Callable[[int], float] = lambda i: 7000,
              hours: float = 7.5, bmi: float | None = 23.0, hr: float = 60,
              bed_shift: Callable[[int], int] = lambda i: 0, birth_month: str | None = None) -> data.Data:
    """`days` days ending on END, every metric present; `i` counts days from the first.

    Each night runs 23:00 (+ `bed_shift(i)` minutes) for `hours`, all Light.
    """
    dates = pd.date_range(end=END, periods=days, freq="D")
    minutes = []
    for i, morning in enumerate(dates):
        bed = morning - pd.Timedelta(hours=1) + pd.Timedelta(minutes=bed_shift(i))
        minutes.append(pd.DataFrame({"ts": pd.date_range(bed, periods=round(hours * 60), freq="min"),
                                     "stage": "Light"}))
    return data.Data(
        folder="/fake",
        sleep=pd.DataFrame({"date": dates, "totalHours": hours}),
        activity=pd.DataFrame({"date": dates, "steps": [float(steps(i)) for i in range(days)]}),
        body=pd.DataFrame({"date": dates, "weight": 70.0, "bmi": math.nan if bmi is None else bmi}),
        sport=pd.DataFrame({"date": pd.Series(dtype="datetime64[ns]")}),
        resting_hr=pd.DataFrame({"date": dates, "hr": float(hr)}),
        sleep_minutes=pd.concat(minutes, ignore_index=True),
        birth_month=birth_month,
    )


def years(result: BioAge | None) -> dict[str, float | None]:
    assert result is not None
    return {m["key"]: m["years"] for m in result["markers"]}


# ── Each marker's years ─────────────────────────────────────────────────────────
def test_risk_ratios_become_years_by_the_gompertz_slope():
    assert bioage.steps_years(7000) == 0
    assert bioage.steps_years(8000) == pytest.approx(math.log(0.85) / 0.085)        # -1.9
    assert bioage.steps_years(12000) == bioage.steps_years(10000) == -bioage.CAP_YEARS
    assert bioage.steps_years(2000) == bioage.CAP_YEARS
    assert bioage.regularity_years(81) == 0
    assert bioage.regularity_years(91.7) == pytest.approx(math.log(0.796) / 0.085)  # -2.7
    assert bioage.resting_hr_years(70) == pytest.approx(math.log(1.09) / 0.085)     # +1.0


def test_bmi_and_sleep_have_a_neutral_range():
    assert bioage.bmi_years(18.5) == bioage.bmi_years(25) == 0
    assert bioage.bmi_years(30) == pytest.approx(math.log(1.29) / 0.085)            # +3.0
    assert bioage.bmi_years(18) is None
    assert bioage.sleep_years(7) == bioage.sleep_years(8) == 0
    assert bioage.sleep_years(6) == pytest.approx(math.log(1.06) / 0.085)           # +0.7
    assert bioage.sleep_years(9) == pytest.approx(math.log(1.13) / 0.085)           # +1.4


# ── Sleep regularity ────────────────────────────────────────────────────────────
def test_the_same_night_every_night_is_perfectly_regular():
    grid = bioage.SleepGrid.of(make_data().sleep_minutes)
    assert grid.regularity(bioage._Span.ending(END)) == 100


def test_shifting_bedtimes_lower_regularity():
    # Alternate nights start and end 3 h later: 360 of each day's 1440 minutes differ.
    grid = bioage.SleepGrid.of(make_data(bed_shift=lambda i: 180 * (i % 2)).sleep_minutes)
    assert grid.regularity(bioage._Span.ending(END)) == pytest.approx(200 * (1 - 360 / 1440) - 100)


def test_regularity_needs_consecutive_nights():
    every_other = make_data()
    minutes = every_other.sleep_minutes
    minutes = minutes[(minutes["ts"] + pd.Timedelta(hours=12)).dt.day % 2 == 0]
    assert bioage.SleepGrid.of(minutes).regularity(bioage._Span.ending(END)) is None
    assert bioage.SleepGrid.of(minutes.iloc[:0]).regularity(bioage._Span.ending(END)) is None


# ── Bio age ─────────────────────────────────────────────────────────────────────
def test_reference_values_count_zero():
    result = bioage.bio_age(make_data(steps=lambda i: 7000, hr=60), END, BORN)
    assert result is not None
    assert result["age"] == round((END - pd.Timestamp(BORN)).days / 365.2425, 1)
    y = years(result)
    assert y == {"steps": 0.0, "regularity": -3.0, "bmi": 0.0, "sleep": 0.0, "resting_hr": 0.0}   # SRI 100: capped
    assert result["bio_age"] == round(result["age"] - 3.0, 1)
    assert result["birth_source"] == "settings" and result["end"] == "2026-05-31T00:00:00"
    assert [m["key"] for m in result["markers"]] == ["steps", "regularity", "bmi", "sleep", "resting_hr"]


def test_bio_age_is_age_plus_the_markers_years():
    result = bioage.bio_age(make_data(steps=lambda i: 8000, hr=70, hours=6, bmi=30), END, BORN)
    assert result is not None
    y = years(result)
    assert y == {"steps": -1.9, "regularity": -3.0, "bmi": 3.0, "sleep": 0.7, "resting_hr": 1.0}
    assert result["bio_age"] == pytest.approx(result["age"] + sum(v for v in y.values() if v is not None))


def test_missing_markers_are_left_out_until_fewer_than_three():
    full = make_data(bmi=None)
    steps_only = data.Data(full.folder, full.sleep.iloc[:0], full.activity, full.body,
                           full.sport, full.resting_hr.iloc[:0], full.sleep_minutes.iloc[:0])
    result = bioage.bio_age(steps_only, END, BORN)
    assert result is not None
    assert years(result) == {"steps": 0.0, "regularity": None, "bmi": None, "sleep": None, "resting_hr": None}
    assert result["bio_age"] is None and result["pace"] is None

    too_short = bioage.bio_age(make_data(bmi=None, days=13), END, BORN)   # 13 days: too few for the daily markers
    assert too_short is not None and too_short["bio_age"] is None
    assert bioage.bio_age(make_data(bmi=17), END, BORN) is not None   # BMI below 18.5: value, no years


def test_no_birth_date_means_no_bio_age_and_the_zepp_month_is_a_fallback():
    assert bioage.bio_age(make_data(), END, None) is None
    zepp = bioage.bio_age(make_data(birth_month="1990-06"), END, None)
    assert zepp is not None and zepp["birth_source"] == "zepp" and zepp["birth_date"] == "1990-06-15"
    assert zepp["age"] == round((END - pd.Timestamp("1990-06-15")).days / 365.2425, 1)
    assert bioage.bio_age(make_data(), END, date(2026, 6, 1)) is None   # born after the window


# ── Pace of aging ───────────────────────────────────────────────────────────────
def test_steady_habits_age_at_one_year_per_year():
    result = bioage.bio_age(make_data(days=300, steps=lambda i: 7500), END, BORN)
    assert result is not None and result["pace"] == 1.0


def test_improving_habits_slow_the_pace():
    # Steps climb 5 a day: the 90-day mean climbs ~1,825 a year → -3.5 years a year, so pace -1 (clamped).
    fast = bioage.bio_age(make_data(days=300, steps=lambda i: 6500 + 5 * i), END, BORN)
    # 0.5 a day → ~-0.35 years a year.
    slow = bioage.bio_age(make_data(days=300, steps=lambda i: 6500 + 0.5 * i), END, BORN)
    assert fast is not None and fast["pace"] == bioage.PACE_MIN
    assert slow is not None and slow["pace"] == pytest.approx(1 + 0.5 * 365.2425 * bioage.STEPS_YEARS, abs=0.02)


def test_pace_needs_about_three_months_of_points():
    # A point needs 15 days of data in its window (regularity: 14 pairs of nights), so
    # 98 days give points back 11 weeks (12 points, one short) and 99 days give 13.
    short, enough = (bioage.bio_age(make_data(days=n), END, BORN) for n in (98, 99))
    assert short is not None and short["pace"] is None
    assert enough is not None and enough["pace"] == 1.0


# ── Through the dashboard and the export ────────────────────────────────────────
def test_dashboard_sends_bio_age_only_with_a_birth_date(export: Path):
    d = data.load(str(export))
    assert series.dashboard(d, "2026-05", "kg", "month")["bio_age"] is None
    sent = series.dashboard(d, "2026-05", "kg", "month", born=BORN)["bio_age"]
    assert sent is not None   # as of the last day with data (the 28th), not the month's end
    assert sent["age"] == round((pd.Timestamp("2026-05-28") - pd.Timestamp(BORN)).days / 365.2425, 1)
    assert [m["years"] is None for m in sent["markers"]] == [False, True, True, False, False]


@pytest.mark.parametrize(("cell", "month"), [
    ("1987-03", "1987-03"), ("1987-03-14", "1987-03"), ("", None), ("03/1987", None), ("1987-13", None),
])
def test_birth_month_comes_from_the_zepp_profile(tmp_path: Path, cell: str, month: str | None):
    root = make_export(tmp_path / "export", activity=[{"date": "2026-05-01", "steps": 100}])
    write_csv(root / "USER" / "USER_1.csv", ["userId", "gender", "height", "birthday"],
              [{"userId": 1, "gender": 1, "height": 170, "birthday": cell}])
    assert data.load(str(root)).birth_month == month
    assert data.birth_month(str(tmp_path / "nowhere")) is None


def test_bmi_comes_from_the_scale_or_from_height(tmp_path: Path):
    root = make_export(tmp_path / "export", activity=[{"date": "2026-05-01", "steps": 100}])
    write_csv(root / "BODY" / "BODY_1.csv", ["time", "weight", "height", "bmi"], [
        {"time": "2026-05-01 12:00:00+0000", "weight": 72.25, "height": 170, "bmi": 24.9},
        {"time": "2026-05-02 12:00:00+0000", "weight": 72.25, "height": 170, "bmi": 0},
        {"time": "2026-05-03 12:00:00+0000", "weight": 72.25, "height": "", "bmi": ""},
    ])
    bmi = data.load(str(root)).body["bmi"].tolist()
    assert bmi[:2] == [24.9, pytest.approx(25.0)]
    assert math.isnan(bmi[2])
