"""
Data access (frontend) — the HTTP boundary to the backend.

Replaces the old CSV-loading module: instead of reading data/ directly, it
fetches the cleaned datasets + KPIs from the FastAPI backend and rebuilds the
same module-level DataFrames and KPI scalars the rest of the app expects. Because
the public surface is identical (`sleep`, `activity`, `body`, `sport`,
`avg_steps`, `latest_weight`, …), core.charts and the view layer are unchanged.

Framework-agnostic — no streamlit imports here (see CLAUDE.md). The module body
runs once per process: Python caches imported modules, so the fetch happens a
single time even though Streamlit re-executes the page script on every
interaction.
"""

import os

import pandas as pd
import requests

# Base URL of the backend. Override with AAYU_API_URL when the API runs
# elsewhere (e.g. another host/port, or a container).
API = os.environ.get("AAYU_API_URL", "http://localhost:8000").rstrip("/")


def _get(path: str):
    try:
        r = requests.get(f"{API}{path}", timeout=15)
        r.raise_for_status()
    except requests.RequestException as e:
        raise RuntimeError(
            f"Could not reach the Aayu API at {API}{path}. "
            f"Is the backend running? (uvicorn app.main:app --reload)\n  {e}"
        ) from e
    return r.json()


def _frame(name: str, date_cols=("date",)) -> pd.DataFrame:
    """Fetch a dataset and restore its datetime columns (lost in JSON transit)."""
    df = pd.DataFrame(_get(f"/datasets/{name}"))
    for c in date_cols:
        if c in df.columns:
            df[c] = pd.to_datetime(df[c])
    return df


# ── Datasets ─────────────────────────────────────────────────────────────────
sleep    = _frame("sleep")
activity = _frame("activity")
body     = _frame("body")
sport    = _frame("sport")

# ── KPIs ─────────────────────────────────────────────────────────────────────
_kpis = _get("/kpis")

avg_steps      = _kpis["avg_steps"]
avg_sleep_h    = _kpis["avg_sleep_h"]
avg_resting_hr = _kpis["avg_resting_hr"]
latest_weight  = _kpis["latest_weight"]
