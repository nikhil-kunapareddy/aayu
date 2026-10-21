"""The JSON the helper sends, as TypedDicts.

These mirror app/Sources/Aayu/Payload.swift field for field (the app decodes
snake_case keys with ``.convertFromSnakeCase``). ``X | None`` marks a field
Swift declares optional; every other field must always hold a value — never
null, never NaN. Keys Swift doesn't declare are ignored there, so additions
are backward compatible. Timestamps are naive local ``YYYY-MM-DDTHH:MM:SS``.
"""

from typing import Literal, TypedDict

Units = Literal["lbs", "kg"]
DefaultRange = Literal["month", "last30"]

UNITS: tuple[Units, ...] = ("lbs", "kg")
DEFAULT_RANGES: tuple[DefaultRange, ...] = ("month", "last30")


class DateWindow(TypedDict):
    """The dates shown: first and last day, at midnight."""

    start: str
    end: str


class ScoreParts(TypedDict):
    """The sleep score's parts, each 0–1 (1 = on target)."""

    timing: float
    consistency: float
    stages: float
    duration: float


class SleepScore(ScoreParts):
    """The 0–100 sleep score with its parts (backend-internal; split up in ``KPIs``)."""

    score: int


class KPIs(TypedDict):
    """Header numbers for the window; every field is optional in Swift."""

    sleep_score: int | None
    sleep_score_change: int | None
    sleep_score_parts: ScoreParts | None
    avg_steps: int | None
    avg_steps_change_pct: float | None
    avg_sleep_h: float | None
    avg_sleep_h_change: float | None
    avg_resting_hr: int | None
    avg_resting_hr_change: int | None
    weight: float | None
    weight_change: float | None


class StageShare(TypedDict):
    """A stage's minutes and share (0–1) of all sleep minutes."""

    stage: str
    minutes: int
    share: float


class StageSpan(TypedDict):
    """One stretch of a single stage in the hypnogram."""

    stage: str
    start: str
    end: str


class Hypnogram(TypedDict):
    """One night's stages over time, plus the window's nights for stepping."""

    night: str
    nights: list[str]
    start: str
    end: str
    segments: list[StageSpan]
    totals: list[StageShare]
    asleep: int
    duration: int


class WorkoutWeek(TypedDict):
    """Sessions of one type in the week starting ``week`` (a Monday)."""

    week: str
    type: str
    count: int


class Workouts(TypedDict):
    """Weekly session counts over a two-month axis."""

    start: str
    end: str
    weeks: list[WorkoutWeek]


class CalorieDay(TypedDict):
    """A day's activity calories with the 7-day average."""

    date: str
    calories: float
    avg7: float
    marker: bool


class WeightPoint(TypedDict):
    """One weigh-in, in the dashboard's units."""

    date: str
    value: float
    marker: bool


class Dashboard(TypedDict):
    """Everything the dashboard shows (``series.dashboard``)."""

    selection: str
    options: list[str]
    window: DateWindow
    units: Units
    kpis: KPIs
    stages: list[StageShare]
    hypnogram: Hypnogram | None
    workouts: Workouts
    calories: list[CalorieDay]
    weight: list[WeightPoint] | None


class FolderStatus(TypedDict):
    """A folder's contents, for the Settings status line (``Server.status``).

    ``error_code`` is an addition Swift doesn't decode (yet): the ``Code`` of
    ``error``, or null.
    """

    exists: bool
    found: list[str]
    total: int
    error: str | None
    error_code: str | None
