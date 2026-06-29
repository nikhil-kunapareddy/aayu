# Aayu — Personal Health Dashboard

A health dashboard for wearable data exported from the **Zepp** app (Amazfit
devices), built as two apps: a **FastAPI backend** that loads + serves the data
and a **Streamlit frontend** that charts it with Plotly.

![Aayu dashboard](assets/image.png)

At a glance: a KPI banner (sleep score, steps, sleep, resting HR, weight), a
month filter, and four charts — **Sleep Breakdown**, **Workout Sessions**,
**Calories Burned**, and **Weight Trend**.

## Setup

```bash
git clone <repo-url> && cd aayu
python3 -m venv .venv && source .venv/bin/activate
pip install -r backend/requirements.txt -r frontend/requirements.txt
```

Export your data from the Zepp app and drop the folders into `data/` — one
`.csv` per folder:

```
data/
├── ACTIVITY/        ├── SLEEP/
├── BODY/            ├── SLEEP_MINUTE/
├── HEARTRATE_AUTO/  ├── SPORT/
└── USER/
```

## Run

Two processes, two terminals. **Start the backend first** — the frontend fetches
its data from it.

```bash
# terminal 1 — backend API (http://localhost:8000, docs at /docs)
cd backend && uvicorn app.main:app --reload

# terminal 2 — frontend dashboard (http://localhost:8501)
cd frontend && streamlit run streamlit_app.py
```

(Use `streamlit run`, not `python` — a plain `python streamlit_app.py` won't
serve the app.) Point the frontend at a non-default backend with the
`AAYU_API_URL` env var.

## Project Structure

```
backend/                # FastAPI — owns the data
  app/data.py           #   CSV loading, processing, KPI values
  app/main.py           #   API endpoints (/kpis, /datasets/{name})
  app/schemas.py        #   Pydantic response models
frontend/               # Streamlit — owns the presentation
  streamlit_app.py      #   entry point — the view
  core/data.py          #   HTTP client → rebuilds DataFrames from the API
  core/charts.py        #   Plotly figure builders (one per chart)
  core/theme.py         #   colours + Plotly layout defaults
  ui/                   #   styles.py (CSS), components.py
  .streamlit/           #   base theme config
data/                   # Zepp CSV exports (gitignored — read by the backend)
```

## Data Privacy

`data/` is gitignored and never committed — your health data stays local.
