"""
Pydantic response models.

These declare the shape of what the API returns: FastAPI uses them to validate
outgoing data and to generate the schema at ``/docs``. The dataset endpoints
return free-form row records, so only the fixed-shape KPI summary is modelled here.
"""

from pydantic import BaseModel


class KPIs(BaseModel):
    """The four headline numbers shown in the dashboard banner."""

    avg_steps: int
    avg_sleep_h: float
    avg_resting_hr: int
    latest_weight: float | None = None
