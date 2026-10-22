import json
import logging
from datetime import time

import pandas as pd
import pytest

from aayu_backend import data, series, server
from aayu_backend.errors import UserError
from aayu_backend.series import Window
from tests.conftest import make_export, make_night

T = pd.Timestamp


# ── Window ──────────────────────────────────────────────────────────────────────
def test_month_window_ends_on_last_day():
    assert Window.for_month("2026-02") == Window(T("2026-02-01"), T("2026-02-28"), "2026-02")
    assert Window.for_month("2028-02").end == T("2028-02-29")
    assert Window.for_month("2026-12").end == T("2026-12-31")


def test_last_days_is_inclusive():
    w = Window.last_days(T("2026-05-30"))
    assert (w.start, w.end, w.month) == (T("2026-05-01"), T("2026-05-30"), None)
    assert Window.last_days(T("2026-05-30"), 1).start == T("2026-05-30")


def test_clip_keeps_whole_last_day():
    df = pd.DataFrame({"date": [T("2026-04-30 23:59"), T("2026-05-01"), T("2026-05-31 23:59"), T("2026-06-01")]})
    assert len(Window.for_month("2026-05").clip(df)) == 2


def test_previous_window():
    assert series._previous(Window.for_month("2026-01")) == Window.for_month("2025-12")
    prev = series._previous(Window.last_days(T("2026-05-30")))
    assert (prev.start, prev.end) == (T("2026-04-01"), T("2026-04-30"))


# ── Hypnogram ───────────────────────────────────────────────────────────────────
def _hyp(tmp_path, nights, month="2026-05", night=None):
    d = data.load(str(make_export(tmp_path, nights=nights)))
    return series.hypnogram(d, Window.for_month(month), night)


def _spans(h):
    return [(s["stage"], s["start"][11:16], s["end"][11:16]) for s in h["segments"]]


BED, WAKE = "2026-05-01 23:00", "2026-05-02 07:00"


def test_run_overlapping_night_is_included_and_widens(tmp_path):
    h = _hyp(tmp_path, [make_night("2026-05-02", BED, WAKE, [("LIGHT", 20), ("DEEP", 480), ("LIGHT", 10)],
                                   first="2026-05-01 22:40")])
    assert (h["start"], h["end"]) == ("2026-05-01T22:40:00", "2026-05-02T07:10:00")
    assert _spans(h) == [("Light", "22:40", "23:00"), ("Deep", "23:00", "07:00"), ("Light", "07:00", "07:10")]
    assert h["duration"] == 510 and h["asleep"] == 510


@pytest.mark.parametrize(("gap", "end"), [(30, "07:34"), (31, "07:00")])
def test_gap_of_30_minutes_is_followed_31_is_not(tmp_path, gap, end):
    h = _hyp(tmp_path, [make_night("2026-05-02", BED, WAKE, [("DEEP", 480), ("GAP", gap), ("LIGHT", 5)])])
    assert h["end"][11:16] == end


def test_six_hour_reach(tmp_path):
    h = _hyp(tmp_path, [make_night("2026-05-02", BED, WAKE, [("LIGHT", 480), ("DEEP", 480)],
                                   first="2026-05-01 15:00")])
    assert h["start"] == "2026-05-01T17:00:00"
    assert h["totals"][2] == {"stage": "Light", "minutes": 360, "share": round(360 / 840, 4)}


def test_same_stage_merges_and_two_minute_gap_splits(tmp_path):
    h = _hyp(tmp_path, [make_night("2026-05-02", BED, WAKE, [("DEEP", 100), ("DEEP", 100), ("GAP", 2), ("DEEP", 279)])])
    assert _spans(h) == [("Deep", "23:00", "02:20"), ("Deep", "02:21", "07:00")]
    assert h["asleep"] == 479


def test_night_outside_window_means_last_night(tmp_path):
    nights = [make_night(f"2026-05-0{d}", f"2026-05-0{d - 1} 23:00", f"2026-05-0{d} 07:00", [("DEEP", 60)])
              for d in (2, 3, 4)]
    assert _hyp(tmp_path, nights, night="2026-05-03")["night"] == "2026-05-03"
    h = _hyp(tmp_path / "b", nights, night="2026-04-30")
    assert h["night"] == "2026-05-04" and h["nights"] == ["2026-05-02", "2026-05-03", "2026-05-04"]
    assert _hyp(tmp_path / "c", nights, night=None)["night"] == "2026-05-04"


def test_duplicate_dates_keep_last(tmp_path):
    nights = [make_night("2026-05-02", "2026-05-01 22:00", WAKE, deepSleepTime=60),
              make_night("2026-05-02", "2026-05-01 23:30", WAKE, deepSleepTime=60)]
    h = _hyp(tmp_path, nights)
    assert h["nights"] == ["2026-05-02"] and h["start"] == "2026-05-01T23:30:00"


def test_spring_forward_night(tmp_path):
    h = _hyp(tmp_path, [make_night("2026-03-08", "2026-03-07 23:00", "2026-03-08 07:00", [("LIGHT", 420)])],
             month="2026-03")
    # The local clock skips 02:00–02:59: 420 real minutes on a naive 8-hour axis.
    assert (h["start"], h["end"]) == ("2026-03-07T23:00:00", "2026-03-08T07:00:00")
    assert _spans(h) == [("Light", "23:00", "02:00"), ("Light", "03:00", "07:00")]
    assert h["asleep"] == 420 and h["duration"] == 480


def test_fall_back_night_has_no_overlapping_segments(tmp_path):
    h = _hyp(tmp_path, [make_night("2026-11-01", "2026-10-31 23:00", "2026-11-01 07:00", [("LIGHT", 540)])],
             month="2026-11")
    # 01:00–01:59 happens twice; the repeat is dropped so spans stay ordered and distinct.
    assert (h["start"], h["end"]) == ("2026-10-31T23:00:00", "2026-11-01T07:00:00")
    assert _spans(h) == [("Light", "23:00", "07:00")]
    assert h["asleep"] == 480 and h["duration"] == 480


def test_awakenings_are_breaks_between_sleep(tmp_path):
    # Leading and trailing Awake don't count; a gap inside an Awake run or between sleep doesn't split or add one.
    stages = [("WAKE", 5), ("LIGHT", 60), ("WAKE", 3), ("DEEP", 60), ("WAKE", 1), ("GAP", 5), ("WAKE", 2),
              ("REM", 30), ("LIGHT", 20), ("GAP", 10), ("LIGHT", 20), ("WAKE", 10)]
    assert _hyp(tmp_path, [make_night("2026-05-02", BED, WAKE, stages)])["awakenings"] == 2
    awake_only = make_night("2026-05-02", BED, WAKE, [("WAKE", 30)], deepSleepTime=60)
    assert _hyp(tmp_path / "b", [awake_only])["awakenings"] is None
    assert _hyp(tmp_path / "c", [make_night("2026-05-02", BED, WAKE, deepSleepTime=60)])["awakenings"] is None


def test_nights_without_times_are_skipped(tmp_path):
    nights = [make_night("2026-05-02", BED, WAKE, [("DEEP", 60)]),
              make_night("2026-05-03", "2026-05-02 23:00", "2026-05-03 07:00", start="", deepSleepTime=60)]
    h = _hyp(tmp_path, nights)
    assert h["nights"] == ["2026-05-02"]
    assert _hyp(tmp_path / "b", nights[1:]) is None


# ── Sleep score ─────────────────────────────────────────────────────────────────
IDEAL = {"deepSleepTime": 100, "REMTime": 110, "shallowSleepTime": 265, "wakeTime": 25}


def _nights(days, bed="23:30", wake="06:30", **totals):
    out = []
    for day in days:
        d = T(day)
        prev = (d - pd.Timedelta(days=1)).strftime("%Y-%m-%d")
        bed_day = prev if bed > "12:00" else day
        out.append(make_night(day, f"{bed_day} {bed}", f"{day} {wake}", **{**IDEAL, **totals}))
    return out


def _days(first, n):
    return [(T(first) + pd.Timedelta(days=i)).strftime("%Y-%m-%d") for i in range(n)]


def _load(tmp_path, nights):
    return data.load(str(make_export(tmp_path, nights=nights)))


def test_fourteen_on_target_nights_score_100(tmp_path):
    parts = series.sleep_score_parts(_load(tmp_path, _nights(_days("2026-05-01", 14))))
    assert parts == {"score": 100, "timing": 1.0, "consistency": 1.0, "stages": 1.0, "duration": 1.0,
                     "awakenings": None}


def test_late_bedtime_fades_timing(tmp_path):
    parts = series.sleep_score_parts(_load(tmp_path, _nights(_days("2026-05-01", 14), bed="00:30")))
    assert parts["timing"] == 0.8 and parts["score"] == 93   # no stage minutes: the other four, reweighted


def test_timing_aims_for_the_targets(tmp_path):
    d = _load(tmp_path, _nights(_days("2026-05-01", 14), bed="00:30", wake="07:30"))
    late = series.SleepTargets(time(0, 30), time(7, 30))
    assert series.sleep_score_parts(d, targets=late)["timing"] == 1.0
    assert series.sleep_score_parts(d)["timing"] == 0.6


@pytest.mark.parametrize(("t", "hours"), [(time(23, 30), -0.5), (time(6, 30), 6.5), (time(0, 0), 0.0),
                                          (time(13, 59), 13 + 59 / 60), (time(14, 0), -10.0)])
def test_clock_time_is_night_centred(t, hours):
    assert series._clock_time(t) == pytest.approx(hours)


def _broken(days, awakenings):
    """On-target nights (as `_nights` makes them) whose stage minutes break `awakenings` times."""
    return [make_night(day, f"{T(day) - pd.Timedelta(days=1):%Y-%m-%d} 23:30", f"{day} 06:30",
                       [("LIGHT", 30), ("WAKE", 1)] * awakenings + [("LIGHT", 30)], **IDEAL) for day in days]


@pytest.mark.parametrize(("awakenings", "part", "score"), [(2, 1.0, 100), (4, 0.5, 95), (6, 0.0, 90)])
def test_awakenings_fade_from_two_to_six_a_night(tmp_path, awakenings, part, score):
    parts = series.sleep_score_parts(_load(tmp_path, _broken(_days("2026-05-01", 14), awakenings)))
    assert (parts["awakenings"], parts["score"]) == (part, score)


def test_awakenings_average_only_nights_with_stage_minutes(tmp_path):
    nights = _broken(_days("2026-05-01", 7), 4) + _nights(_days("2026-05-08", 7))
    assert series.sleep_score_parts(_load(tmp_path, nights))["awakenings"] == 0.5


def test_score_window_edges(tmp_path):
    bad = {"deepSleepTime": 5, "REMTime": 5, "shallowSleepTime": 5, "wakeTime": 300}
    nights = _nights(["2026-04-30"], bed="21:00", **bad) + _nights(_days("2026-05-01", 14))
    nights += _nights(["2026-05-15"], bed="21:00", **bad)
    d = _load(tmp_path, nights)
    assert series.sleep_score(d, asof=T("2026-05-14")) == 100
    assert series.sleep_score(d, asof=T("2026-05-15")) < 100
    assert series.sleep_score(d) == series.sleep_score(d, asof=T("2026-05-15"))


def test_single_night(tmp_path):
    parts = series.sleep_score_parts(_load(tmp_path, _nights(["2026-05-01"])))
    assert parts["score"] == 100 and parts["consistency"] == 1.0


def test_score_none_without_nights_or_times(tmp_path):
    assert series.sleep_score(data.load(str(tmp_path))) is None
    d = _load(tmp_path / "b", [make_night("2026-05-02", BED, WAKE, start="", stop="", **IDEAL)])
    assert series.sleep_score(d) is None


# ── KPIs ────────────────────────────────────────────────────────────────────────
def _activity(month, days, steps):
    return [{"date": f"{month}-{d:02d}", "steps": steps, "calories": 100} for d in days]


def test_kpi_changes_vs_previous_window(tmp_path):
    folder = make_export(
        tmp_path,
        nights=_nights(_days("2026-04-01", 30), wake="06:00") + _nights(_days("2026-05-01", 31)),
        activity=_activity("2026-04", range(1, 31), 1000) + _activity("2026-05", range(1, 32), 1500),
        heartrate=[{"date": f"2026-04-{d:02d}", "heartRate": 60} for d in range(1, 31)]
        + [{"date": f"2026-05-{d:02d}", "heartRate": 57} for d in range(1, 32)],
    )
    k = series.kpis(data.load(str(folder)), Window.for_month("2026-05"), "lbs")
    assert (k["avg_steps"], k["avg_steps_change_pct"]) == (1500, 50.0)
    assert (k["avg_resting_hr"], k["avg_resting_hr_change"]) == (57, -3)
    assert (k["avg_sleep_h"], k["avg_sleep_h_change"]) == (7.9, 0.0)
    assert k["sleep_score"] == 100 and k["sleep_score_change"] == 0
    assert k["sleep_score_parts"] == {"timing": 1.0, "consistency": 1.0, "stages": 1.0, "duration": 1.0,
                                      "awakenings": None}


def test_kpis_score_both_spans_against_the_targets(tmp_path):
    folder = make_export(tmp_path, nights=_nights(_days("2026-04-01", 30) + _days("2026-05-01", 31), bed="22:00"))
    early = series.SleepTargets(time(22, 0), time(6, 30))
    k = series.kpis(data.load(str(folder)), Window.for_month("2026-05"), "lbs", early)
    assert k["sleep_score"] == 100 and k["sleep_score_change"] == 0
    assert series.kpis(data.load(str(folder)), Window.for_month("2026-05"), "lbs")["sleep_score"] < 100


def test_steps_change_none_without_previous(tmp_path):
    folder = make_export(tmp_path, activity=_activity("2026-05", range(1, 5), 1500))
    k = series.kpis(data.load(str(folder)), Window.for_month("2026-05"), "lbs")
    assert k["avg_steps"] == 1500 and k["avg_steps_change_pct"] is None
    assert k["sleep_score"] is None and k["avg_resting_hr"] is None


@pytest.mark.parametrize(("units", "now", "change"), [("lbs", 158.7, 2.2), ("kg", 72.0, 1.0)])
def test_weight_is_last_weigh_in(tmp_path, units, now, change):
    body = [{"time": f"{day} 12:00:00+0000", "weight": kg}
            for day, kg in (("2026-04-10", 70), ("2026-05-03", 71), ("2026-05-20", 72), ("2026-06-02", 80))]
    d = data.load(str(make_export(tmp_path, body=body)))
    k = series.kpis(d, Window.for_month("2026-05"), units)
    assert (k["weight"], k["weight_change"]) == (now, change)
    assert series.kpis(d, Window.for_month("2026-04"), units)["weight_change"] is None   # one weigh-in


# ── Workouts, calories ──────────────────────────────────────────────────────────
def test_workouts_weekly_counts(tmp_path):
    sessions = [("2026-05-04", 52), ("2026-05-05", 52), ("2026-05-06", 1), ("2026-05-12", 8), ("2026-05-13", 6)]
    sessions += [(f"2026-0{m}-0{d}", 52) for m in (2, 3) for d in (2, 9)]
    folder = make_export(tmp_path, sport=[{"type": t, "startTime": f"{day} 12:00:00+0000"} for day, t in sessions])
    d = data.load(str(folder))
    wk = series.workouts(d, Window.for_month("2026-05"))
    assert (wk["start"], wk["end"]) == ("2026-04-01T00:00:00", "2026-05-31T00:00:00")
    weeks = {(r["week"][:10], r["type"]): r["count"] for r in wk["weeks"]}
    assert len(wk["weeks"]) == 2 * 6
    assert weeks[("2026-05-04", "Strength")] == 2 and weeks[("2026-05-04", "Running")] == 1
    assert weeks[("2026-05-11", "Running")] == 1 and weeks[("2026-05-11", "Strength")] == 0
    last30 = series.workouts(d, Window.last_days(T("2026-05-30")))
    assert last30["start"] == "2026-03-31T00:00:00"
    assert series.workouts(d, Window.for_month("2026-03"))["weeks"][-1]["week"] == "2026-03-09T00:00:00"


def test_workouts_keep_last_eight_weeks(tmp_path):
    days = pd.date_range("2026-01-05", periods=12, freq="7D")
    folder = make_export(tmp_path, sport=[{"type": 52, "startTime": f"{t:%Y-%m-%d} 12:00:00+0000"} for t in days])
    weeks = series.workouts(data.load(str(folder)), Window.for_month("2026-03"))["weeks"]
    assert weeks[0]["week"][:10] == "2026-02-02"
    assert len(weeks) == 16


def test_calories_avg7_rolls_over_previous_days(tmp_path):
    rows = [{"date": f"2026-04-{d}", "steps": 1, "calories": 100} for d in range(25, 31)]
    rows += [{"date": f"2026-05-0{d}", "steps": 1, "calories": 200} for d in range(1, 4)]
    cal = series.calories(data.load(str(make_export(tmp_path, activity=rows))), Window.for_month("2026-05"))
    assert [(c["date"][:10], c["calories"], c["avg7"]) for c in cal] == [
        ("2026-05-01", 200.0, 114.0), ("2026-05-02", 200.0, 129.0), ("2026-05-03", 200.0, 143.0)]
    assert all(c["marker"] for c in cal)


def test_calories_skip_blank_cells(tmp_path):
    rows = [{"date": "2026-05-01", "steps": 1, "calories": 100}, {"date": "2026-05-02", "steps": 1, "calories": ""}]
    cal = series.calories(data.load(str(make_export(tmp_path, activity=rows))), Window.for_month("2026-05"))
    assert [c["date"][:10] for c in cal] == ["2026-05-01"]


# ── The whole dashboard ─────────────────────────────────────────────────────────
def test_dashboard_with_blank_cells_is_valid_json(tmp_path):
    folder = make_export(
        tmp_path,
        nights=[make_night("2026-05-02", BED, WAKE, start="", stop="", **IDEAL)],
        activity=[{"date": "2026-05-01", "steps": 10, "calories": ""}],
        body=[{"time": "2026-05-01 12:00:00+0000", "weight": 70}],
    )
    payload = series.dashboard(data.load(str(folder)), None, "lbs", "month")
    json.loads(server.encode(payload))
    assert payload["hypnogram"] is None and payload["calories"] == [] and payload["kpis"]["sleep_score"] is None


def test_failed_section_is_logged_and_empty(export, monkeypatch, caplog):
    def boom(*_):
        raise ValueError("cell value 123")

    monkeypatch.setattr(series, "workouts", boom)
    monkeypatch.setattr(series, "hypnogram", boom)
    with caplog.at_level(logging.ERROR):
        payload = series.dashboard(data.load(str(export)), None, "kg", "month")
    assert payload["workouts"]["weeks"] == [] and payload["hypnogram"] is None
    assert payload["calories"]
    assert "ValueError" in caplog.text and "123" not in caplog.text


def test_no_data_is_a_user_error(tmp_path):
    with pytest.raises(UserError) as e:
        series.dashboard(data.load(str(tmp_path)), None, "lbs", "month")
    assert e.value.code == "no_data"
