import os

import pandas as pd
import pytest

from aayu_backend import data
from tests.conftest import make_export, make_night, write_csv


def test_bom_header_is_read(tmp_path):
    folder = make_export(tmp_path, activity=[{"date": "2026-05-01", "steps": 100, "calories": 5}])
    raw = (folder / "ACTIVITY").glob("*.csv").__next__().read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf")
    d = data.load(str(folder))
    assert list(d.activity["steps"]) == [100]


def test_newest_csv_by_mtime_wins_and_non_csv_ignored(tmp_path):
    cols = data._COLUMNS["ACTIVITY"]
    write_csv(tmp_path / "ACTIVITY" / "b_old.csv", cols, [{"date": "2026-05-01", "steps": 1, "calories": 1}],
              mtime=1_000)
    write_csv(tmp_path / "ACTIVITY" / "a_new.csv", cols, [{"date": "2026-05-01", "steps": 2, "calories": 1}],
              mtime=2_000)
    write_csv(tmp_path / "ACTIVITY" / "z_newest.txt", cols, [{"date": "2026-05-01", "steps": 3, "calories": 1}],
              mtime=3_000)
    write_csv(tmp_path / "ACTIVITY" / "._z.csv", cols, [], mtime=4_000)   # macOS AppleDouble file
    (tmp_path / "ACTIVITY" / "dir.csv").mkdir()
    os.utime(tmp_path / "ACTIVITY" / "dir.csv", (5_000, 5_000))
    assert data.csv_path(str(tmp_path), "ACTIVITY") == str(tmp_path / "ACTIVITY" / "a_new.csv")
    assert list(data.load(str(tmp_path)).activity["steps"]) == [2]


def test_fifo_named_csv_is_not_read(tmp_path):
    (tmp_path / "SLEEP").mkdir()
    os.mkfifo(tmp_path / "SLEEP" / "pipe.csv")
    assert data.csv_path(str(tmp_path), "SLEEP") is None
    assert data.found_metrics(str(tmp_path)) == []


def test_empty_folder_gives_empty_frames(tmp_path):
    d = data.load(str(tmp_path))
    for frame in (d.sleep, d.activity, d.body, d.sport, d.resting_hr, d.sleep_minutes):
        assert frame.empty
    assert d.months() == []
    assert d.latest_date() is None
    assert data.found_metrics(str(tmp_path)) == []


def test_header_only_csvs_load_empty(tmp_path):
    folder = make_export(tmp_path, sleep=[], activity=[], body=[], sport=[], heartrate=[], sleep_minute=[])
    d = data.load(str(folder))
    assert d.sleep.empty and d.activity.empty and d.body.empty and d.sleep_minutes.empty
    assert sorted(data.found_metrics(str(folder))) == sorted(data.METRICS)


def test_dropped_rows(tmp_path):
    folder = make_export(
        tmp_path,
        nights=[make_night("2026-05-02", "2026-05-01 23:00", "2026-05-02 07:00",
                           deepSleepTime=60, shallowSleepTime=200, REMTime=80),
                make_night("2026-05-03", "2026-05-02 23:00", "2026-05-03 07:00",
                           deepSleepTime=0, shallowSleepTime=0, REMTime=0, wakeTime=30)],
        activity=[{"date": "2026-05-01", "steps": 0, "calories": 10},
                  {"date": "2026-05-02", "steps": 50, "calories": 10},
                  {"date": "garbage", "steps": 50, "calories": 10},
                  {"date": "2026-05-03", "steps": "n/a", "calories": 10}],
        body=[{"time": "2026-05-01 12:00:00+0000", "weight": 0},
              {"time": "2026-05-02 12:00:00+0000", "weight": ""},
              {"time": "2026-05-03 12:00:00+0000", "weight": 70.5},
              {"time": "", "weight": 71}],
    )
    d = data.load(str(folder))
    assert [t.strftime("%Y-%m-%d") for t in d.sleep["date"]] == ["2026-05-02"]
    assert d.sleep["totalHours"].tolist() == [5.67]
    assert d.activity["steps"].tolist() == [50]
    assert d.body["weight"].tolist() == [70.5]
    assert d.months() == ["2026-05"]


def test_body_and_sport_dates_are_naive_utc(tmp_path):
    # Stamps are UTC: a 02:30 UTC weigh-in (22:30 the evening before in New York) lands on the UTC day.
    folder = make_export(tmp_path, body=[{"time": "2026-05-02 02:30:00+0000", "weight": 70}],
                         sport=[{"type": 52, "startTime": "2026-05-02 01:00:00+0000"}])
    d = data.load(str(folder))
    assert d.body["date"].tolist() == [pd.Timestamp("2026-05-02 02:30:00")]
    assert d.body["date"].dt.tz is None
    assert d.sport["date"].tolist() == [pd.Timestamp("2026-05-02")]


def test_sport_code_mapping(tmp_path):
    codes = [1, 6, 8, 52, 54, 99]
    folder = make_export(tmp_path, sport=[{"type": c, "startTime": "2026-05-02 12:00:00+0000"} for c in codes])
    names = data.load(str(folder)).sport["sportName"].tolist()
    assert names == ["Running", "Outdoor Walk", "Running", "Strength", "Indoor Walk", "Other"]


def test_resting_hr_is_daily_5th_percentile(tmp_path):
    rows = [{"date": "2026-05-01", "heartRate": hr} for hr in range(50, 71)]   # 21 readings: 50..70
    rows += [{"date": "2026-05-02", "heartRate": 60}]
    d = data.load(str(make_export(tmp_path, heartrate=rows)))
    assert d.resting_hr["hr"].tolist() == [51.0, 60.0]


def test_bad_minute_rows_and_unknown_stages_dropped(tmp_path):
    rows = [{"date": "2026-05-02", "time": "01:00", "stage": "DEEP"},
            {"date": "2026-05-02", "time": "25:61", "stage": "LIGHT"},
            {"date": "2026-05-02", "time": "01:02", "stage": "NAP"},
            {"date": "bad", "time": "01:03", "stage": "REM"},
            {"date": "2026-05-02", "time": "00:59", "stage": "WAKE"},
            {"date": "2026-05-02", "time": "01:00", "stage": "REM"}]   # repeated stamp: first kept
    d = data.load(str(make_export(tmp_path, sleep_minute=rows)))
    assert d.sleep_minutes["stage"].tolist() == ["Awake", "Deep"]
    assert d.sleep_minutes["ts"].iloc[0] == pd.Timestamp("2026-05-02 00:59")


def test_blank_sleep_times_become_nat(tmp_path):
    folder = make_export(tmp_path, nights=[make_night("2026-05-02", "2026-05-01 23:00", "2026-05-02 07:00",
                                                      start="", stop="nonsense", deepSleepTime=60)])
    d = data.load(str(folder))
    assert len(d.sleep) == 1
    assert d.sleep["start"].isna().all() and d.sleep["stop"].isna().all()


def test_missing_column_is_an_export_error(tmp_path):
    write_csv(tmp_path / "SLEEP" / "s.csv", ["date", "deepSleepTime"], [{"date": "2026-05-01", "deepSleepTime": 1}])
    with pytest.raises(data.ExportError) as e:
        data.load(str(tmp_path))
    assert e.value.metric == "SLEEP"
    assert "REMTime" in e.value.reason and "2026" not in e.value.reason


def test_undecodable_csv_is_an_export_error(tmp_path):
    (tmp_path / "BODY").mkdir()
    (tmp_path / "BODY" / "b.csv").write_bytes(b"time,weight\n\xff\xfe\x00,1\n")
    with pytest.raises(data.ExportError, match="UTF-8"):
        data.load(str(tmp_path))


def test_empty_file_is_an_export_error(tmp_path):
    (tmp_path / "BODY").mkdir()
    (tmp_path / "BODY" / "b.csv").write_bytes(b"")
    with pytest.raises(data.ExportError, match="empty"):
        data.load(str(tmp_path))
