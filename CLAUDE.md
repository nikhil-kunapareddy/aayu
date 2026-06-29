# CLAUDE.md

## Overview
**Aayu** — a personal health dashboard. Wearable data exported from the **Zepp**
app (Amazfit devices) is loaded + processed with pandas by a **FastAPI backend**
and rendered by a **Streamlit frontend** with Plotly charts. Dark, iOS-inspired
theme.

> Two-app split (backend/ + frontend/). Previously a single Streamlit app, and
> before that Dash. Any `dash`/`dcc`/`html`/`@callback` references are stragglers
> and should be removed.

## Running
Two processes — **start the backend first** (the frontend fetches data from it):
- Install: `pip install -r backend/requirements.txt -r frontend/requirements.txt`
- Backend: `cd backend && uvicorn app.main:app --reload` (API on :8000, `/docs`)
- Frontend: `cd frontend && streamlit run streamlit_app.py` (on :8501; NOT
  `python streamlit_app.py` — that only prints a warning and never serves).
- Backend expects Zepp CSV exports under repo-root `data/` (gitignored — see Data
  Conventions). Frontend finds the API via `AAYU_API_URL` (default
  `http://localhost:8000`).

## Architecture — keep this separation
Two apps with a hard HTTP boundary: **the backend owns data, the frontend owns
presentation.** Data crosses the boundary as JSON; the frontend rebuilds
DataFrames from it. **Preserve this boundary** when adding features.

- `backend/`           # FastAPI — data only, NO plotly/streamlit
  - `app/data.py`      # CSV loading + cleaning; module-level DataFrames
                       #   (`sleep`, `activity`, `body`, `sport`, `daily_hr`…)
                       #   and precomputed KPIs (`avg_steps`, `latest_weight`…)
  - `app/main.py`      # endpoints: `/kpis`, `/datasets/{name}`, `/health`
  - `app/schemas.py`   # Pydantic response models (the `KPIs` shape)
- `frontend/`          # Streamlit — presentation only
  - `streamlit_app.py` # entrypoint; thin view: filter → fetch → chart → display
  - `core/`            # framework-agnostic, NO streamlit imports allowed here
    - `data.py`        # HTTP client: fetches the API and rebuilds the same
                       #   `sleep`/`activity`/… DataFrames + KPI scalars. Keeps
                       #   the identical public surface so charts.py is unchanged.
    - `charts.py`      # one function per chart; each RETURNS a `go.Figure`,
                       #   never renders. Imports `from core import data as d`.
    - `theme.py`       # design tokens: `C` (color dict), `AXIS`, `plot_base()`.
                       #   All Plotly styling flows from here.
  - `ui/`              # Streamlit-only view primitives
    - `styles.py`      # `inject()` — one big `<style>` block (custom dark theme)
    - `components.py`  # `banner_*()`, `chart_card()`, `footer()`
  - `.streamlit/config.toml`  # base dark theme (background, font, primaryColor)

## Conventions
- New data/KPI → compute it in `backend/app/data.py`, expose it from
  `app/main.py` (add to `KPIs`/a dataset endpoint), then surface it in
  `frontend/core/data.py` so the frontend sees the same attribute as before.
- New chart → add a `go.Figure`-returning function in `frontend/core/charts.py`,
  style it via `plot_base()` + `C`/`AXIS` from `core/theme.py`, then render it in
  `streamlit_app.py` with `ui.chart_card(title, fig)`.
- Never put `import streamlit` in `core/`. Never put plotly/figure logic in the
  backend. Never read the CSVs from the frontend — go through the API.
- Frontend `core/data.py` fetches at import time, which runs once per Streamlit
  process (Python caches modules), so it isn't re-run on every widget interaction.
- Colors come from the `C` dict in `theme.py`; do not hardcode hex values.

## Data Conventions
- `data/` holds one subfolder per Zepp metric (`SLEEP/`, `ACTIVITY/`, `BODY/`,
  `SPORT/`, `HEARTRATE_AUTO/`, `SLEEP_MINUTE/`, `USER/`), each containing a
  single `.csv`. `core/data.py` reads the first `.csv` it finds in each folder.
- CSVs are read with `encoding="utf-8-sig"` (Zepp exports carry a BOM).
- `data/` is gitignored — it is real personal health data. Never commit it,
  never paste its contents into code, commits, or PRs.

## Gotchas (recurring mistakes — update as new ones surface)
These are Streamlit-specific traps already hit on this project:

- **Indented HTML in `st.markdown` becomes a code block.** Streamlit runs its
  Markdown parser over HTML even with `unsafe_allow_html=True`. Any line indented
  4+ spaces renders as a `<pre>` code block, shattering the layout. Emit custom
  HTML as a single un-indented string (see `ui/components.py::banner`).
- **Streamlit columns are themselves border-wrappers.** A broad
  `[data-testid="stVerticalBlockBorderWrapper"]` CSS selector paints a card on
  BOTH the column and the inner container → nested double boxes. Scope card CSS
  to the `st-key-*` class from `st.container(border=True, key=...)` instead.
- **`st.plotly_chart` must pass `theme=None`** to keep the figure's own
  `core.theme` styling; the default `theme="streamlit"` overrides our colors.
- **No backslashes inside f-string expressions** (Python 3.11). Build nested
  HTML fragments in a helper/variable, not inline in the f-string.
- **`@st.cache_data` ignores leading-underscore args** when hashing — don't rely
  on them for cache keys.
