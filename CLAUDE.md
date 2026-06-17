# CLAUDE.md

## Overview
**Aayu** — a personal health dashboard. Loads wearable data exported from the
**Zepp** app (Amazfit devices), processes it with pandas, and renders it as a
single-page Streamlit dashboard with Plotly charts. Dark, iOS-inspired theme.

> Migrated from Dash → Streamlit. If you find any `dash`/`dcc`/`html`/`@callback`
> references, they are stragglers and should be removed.

## Running
- Install: `pip install -r requirements.txt`
- Run: `streamlit run streamlit_app.py` (NOT `python streamlit_app.py` — that
  only prints a warning and never serves).
- Expects Zepp CSV exports under `data/` (gitignored — see Data Conventions).

## Architecture — keep this separation
The codebase is split into framework-agnostic logic vs. the Streamlit view.
**Preserve this boundary** when adding features.

- `streamlit_app.py`   # entrypoint; thin view: filter → load → chart → display
- `core/`              # framework-agnostic, NO streamlit imports allowed here
  - `data.py`          # CSV loading + cleaning; exposes module-level DataFrames
                       #   (`sleep`, `activity`, `body`, `sport`, `daily_hr`…)
                       #   and precomputed KPIs (`avg_steps`, `latest_weight`…)
  - `charts.py`        # one function per chart; each RETURNS a `go.Figure`,
                       #   never renders. Imports `from core import data as d`.
  - `theme.py`         # design tokens: `C` (color dict), `AXIS`, `plot_base()`,
                       #   `fade()`. All Plotly styling flows from here.
- `ui/`                # Streamlit-only view primitives
  - `styles.py`        # `inject()` — one big `<style>` block (custom dark theme)
  - `components.py`    # `banner()`, `chart_card()`, `footer()`
- `.streamlit/config.toml`  # base dark theme (background, font, primaryColor)

## Conventions
- New chart → add a `go.Figure`-returning function in `core/charts.py`, style it
  via `plot_base()` + `C`/`AXIS` from `core/theme.py`, then render it in
  `streamlit_app.py` with `ui.chart_card(title, fig)`.
- Never put `import streamlit` in `core/`. Never put data/figure logic in `ui/`
  or `streamlit_app.py`.
- The data loader is wrapped in `@st.cache_data` — keep expensive work cached so
  it isn't re-run on every widget interaction.
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
