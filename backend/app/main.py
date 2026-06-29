"""
Aayu API — FastAPI backend.

Run with:  uvicorn app.main:app --reload   (from the backend/ directory)
Docs at:   http://localhost:8000/docs

Owns data: loads + cleans the Zepp CSV exports (app.data) and serves them as
JSON. The frontend never touches the CSVs — it only talks to these endpoints.
"""

import json

from fastapi import FastAPI, HTTPException

from app import data as d
from app.schemas import KPIs

app = FastAPI(title="Aayu API", version="0.1.0")

# The cleaned DataFrames the dashboard charts consume, keyed by URL name.
_DATASETS = {
    "sleep": d.sleep,
    "activity": d.activity,
    "body": d.body,
    "sport": d.sport,
}


def _records(df) -> list[dict]:
    """DataFrame → JSON-safe list of row dicts (ISO dates, NaN → null)."""
    return json.loads(df.to_json(orient="records", date_format="iso"))


@app.get("/health")
def health() -> dict:
    """Liveness check."""
    return {"status": "ok"}


@app.get("/kpis", response_model=KPIs)
def kpis() -> KPIs:
    """The headline numbers shown in the dashboard banner."""
    return KPIs(
        avg_steps=d.avg_steps,
        avg_sleep_h=d.avg_sleep_h,
        avg_resting_hr=d.avg_resting_hr,
        latest_weight=d.latest_weight,
    )


@app.get("/datasets")
def list_datasets() -> list[str]:
    """Names of the available datasets."""
    return list(_DATASETS)


@app.get("/datasets/{name}")
def dataset(name: str) -> list[dict]:
    """A cleaned dataset as a list of row records (one dict per row)."""
    if name not in _DATASETS:
        raise HTTPException(status_code=404, detail=f"unknown dataset: {name!r}")
    return _records(_DATASETS[name])
