# CLAUDE.md

## Overview
**Aayu** — a personal health dashboard, packaged as a **Mac app for Apple
Silicon**. Wearable data exported from the **Zepp** app (Amazfit devices) is
loaded and crunched by a **Python backend** (pandas) and drawn by a **SwiftUI
front end** with **Swift Charts**. The user picks the Zepp export folder in
Settings. Look (from a dashboard mock-up the user supplied): a dark navy
header — greeting, month control, a frosted Sleep Score panel (ring + stage
mix) — over a pale page of white KPI tiles and one chart card at a time
(‹ › on its edges, dots below, ⌘[ ⌘]); no title bar. The
app icon is the user's Aayu logo (lavender crescent "boat" with a violet sail
on an indigo tile), redrawn as clean vectors in `scripts/make_icon.py` from the
artwork in `assets/image copy.png`; the welcome
screen shows the app icon itself (`AayuLogo`).

> History: Dash → Streamlit → FastAPI + Streamlit → pywebview + Plotly → this.
> Any `dash`, `streamlit`, `fastapi`, `plotly`, `pywebview` or `frontend/`
> reference is a straggler and should be removed.

## Running
- `make run` — debug build, backend from source; opens the app and waits.
- `make app` — `dist/Aayu.app` (arm64, ad-hoc signed, frozen backend inside);
  `make dmg` — the release disk image (`dist/Aayu-<version>.dmg`).
  `make install` copies it to `/Applications`.
- Needs `uv` and the Xcode Command Line Tools (Swift 6, macOS SDK). Full
  Xcode is NOT needed: SwiftPM builds the binary, `scripts/bundle.sh` wraps it.
- Everything generated lives in `~/Library/Caches/aayu` (venv, Swift and
  PyInstaller builds, the bundles); only the signed app is copied to `dist/`.
- `make test` — backend pytest + app Swift Testing; `make lint` — ruff + mypy --strict.
- CI: `.github/workflows/ci.yml`. Backend on ubuntu (uv sync --group dev, then ruff, mypy, pytest);
  app on macos-26 with Xcode 26.6 (release build with `-warnings-as-errors`, swift test). Both job
  names are required checks on `main`, so renaming a job means updating branch protection.
- Releases: bump `CFBundleShortVersionString` in `app/Info.plist`, then push tag `v<version>`.
  `release.yml` checks the tag matches, runs `make test` and `make dmg`, and uploads `Aayu.dmg` +
  `Aayu.zip` (the README links `releases/latest/download/Aayu.dmg`). `make dmg` → `dist/Aayu-<version>.dmg`.
- Logs from `make run`: `~/Library/Caches/aayu/build/Aayu-dev.log` (helper stderr is
  echoed there); the app logs to unified logging: `/usr/bin/log stream --level debug
  --predicate 'subsystem == "io.github.nikhil-kunapareddy.aayu"'` (zsh's `log` is a builtin).

## Architecture — keep this separation
**The backend owns data, the app owns presentation.** They talk only over a
private pipe: the app starts the backend as a helper process and they exchange
JSON lines on its stdin/stdout. No network port.

- `backend/aayu_backend/` — Python. NO UI code.
  - `data.py`    # CSV loading + cleaning → immutable `Data` (frames + KPIs)
  - `series.py`  # the numbers behind each chart + `dashboard()` payload
  - `server.py`  # the JSON-lines protocol (`Server.METHODS`), folder watcher
  - `__main__.py`
  - `backend.spec` (PyInstaller), `pyproject.toml` + `uv.lock` (pinned deps), `tests/` (pytest, synthetic data)
- `app/` — SwiftUI (SwiftPM, Swift 6 language mode, macOS 15+). Library
  `AayuKit` holds everything; executable `Aayu` is just `main.swift`.
  - `App/`          # AayuApp (scenes), AppCommands (menus)
  - `Backend/`      # actor Backend (spawns the helper, ids, replay), BackendClient
                    # protocol + typed request structs, AppError, PayloadDecoder
  - `Model/`        # Payload (Decodable mirrors), DashboardModel (@Observable), Preferences (`Pref` + enums)
  - `Features/`     # Dashboard/{Header,Page}, Onboarding (FolderPrompt, folder chooser), Settings
  - `Charts/`       # one Swift Charts view per chart, ChartSupport, HoverCard
  - `DesignSystem/` # Palette, Metrics, Modifiers, Components, Appearance, Format — the one place to restyle
  - `Support/Log.swift` # os.Logger channels (app, backend, protocol, model, helper)
  - `Tests/AayuKitTests/` # Swift Testing (fake BackendClient, synthetic JSON fixture)
  - `Info.plist`, `PrivacyInfo.xcprivacy`
- `scripts/bundle.sh` — assembles + signs the .app; `scripts/make_icon.py`.

### Protocol (backend/aayu_backend/server.py ↔ app/Sources/AayuKit/Backend/Backend.swift)
Request `{"id", "method", "params"}` → reply `{"id", "result"}` or
`{"id", "error"}`; pushed `{"event": "reloaded"}` after auto-reload.
Methods: `open(folder)`, `reload()`, `status(folder)`,
`dashboard(selection, units, default_range, night)`, `watch(enabled)`.
Keys are snake_case (Swift decodes with `.convertFromSnakeCase`); timestamps
are naive local `YYYY-MM-DDTHH:MM:SS`, parsed in the Mac's timezone.

## Conventions
- New data/KPI → compute in `data.py`/`series.py`, add to the `dashboard()`
  payload, mirror it in `Payload.swift`, render it in the views.
- New chart → a series function in `series.py`, a `Decodable` in
  `Payload.swift`, a Swift Charts view in `Charts/`, a `ChartPage` case
  and its `ChartCard` in `ChartPager.card(_:)`.
- Colours, type sizes, radii and spacing come only from `DesignSystem/` (`Theme.`):
  `Palette` (WCAG AA-checked by `ContrastTests`), `Typography` (`Theme.title3`,
  `Theme.metric`, `Theme.micro`… — no literal `.font(.system(size:))`), `Metrics`,
  `.card()` for white cards, `.frosted(_:)` on the dark header. Buttons use
  `FrostedButtonStyle` (header) / `CardButtonStyle` / `DotButtonStyle` so every
  control has hover, pressed, disabled and focus states. The icon has its own
  palette, sampled from the logo, in `scripts/make_icon.py`.
- Layout adapts to width via `measuringLayoutClass()` (regular ≥ 1100 pt,
  compact ≥ 860, narrow below: tiles 2 × 2). Minimum window 720 × 600; the
  header and page share one ScrollView, so a short window scrolls instead of
  squeezing the chart below `Theme.chartMinHeight`.
- Errors: backend error `code`s map to `AppError` (title, message, recovery);
  raw text only behind "Details". A failure while a dashboard is up shows a
  `StatusBanner` and keeps the dashboard; the full-screen prompt is only for
  "no dashboard yet". Every user-facing string is localizable (no sentence
  concatenation; plurals via `^[\(n) item](inflect: true)`).
- Shortcuts (AppCommands): ⌘O folder, ⌘R reload, ⌘←/⌘→ month, ⌘T latest
  month, ⌥⌘←/⌥⌘→ night, ⌘1–⌘4 / ⌘[ ⌘] charts, ⌘? help. Respect Reduce Motion.
- Settings → Appearance (System / Light / Dark, default Light). Page colours
  take a light and a dark value (`rgb(light, dark)` in `Palette.swift`); the
  header is dark in both, so colours on it stay fixed. `Theme.apply` sets
  `NSApp.appearance`; don't add `.preferredColorScheme`, which overrides it
  per window. Use `Theme.card`/`Theme.ink`, not `.white`/`.black`, on the page.
- The window has no title bar (`.hiddenTitleBar`); the header drags the window
  (`HeaderBackground` uses `WindowDragGesture`). Keep header content below
  the traffic lights (top padding).
- KPI tiles are for the selected window, with the change vs the window before
  (previous month / previous 30 days); weight's change is across the window.
  The sleep score covers the 14 nights up to the window's last night.
- Don't show claims the data can't back (e.g. "top 10% for your age"); the
  score message comes from the score's own parts (`ScoreText`).
- Settings are `@AppStorage` keys listed in `Pref`; they apply immediately (no
  Save button). The model reads them from `UserDefaults` when it calls the backend.
- `series.py` was ported from the old Plotly chart code and verified to give
  identical numbers; keep that maths unchanged unless a change is intended.

## Data Conventions
- The export folder holds one subfolder per Zepp metric (`SLEEP/`,
  `ACTIVITY/`, `BODY/`, `SPORT/`, `HEARTRATE_AUTO/`, …), each with a `.csv`.
  `data.csv_path()` reads the **newest** CSV per folder (by mtime).
- CSVs are read with `encoding="utf-8-sig"` (Zepp exports carry a BOM).
- A missing metric yields an empty frame; KPIs become `None`, shown as "—".
- `SLEEP_MINUTE` (one row per minute: date, time, DEEP/LIGHT/REM/WAKE) is in
  the watch's local time, while `SLEEP` start/stop are UTC — `series._local`
  converts the latter (via `TZ`) to match before slicing a night.
- A Sleep Breakdown night spans bedtime → wake time **and** every run of stage
  minutes overlapping it, followed through gaps ≤ `series.NIGHT_GAP` (30 min).
  The watch often scores stages past SLEEP's recorded times; clipping to those
  times cut the chart off on most nights.
- Sleep times are shown in `series.TZ` (`America/New_York`, hardcoded).
- The repo's `data/` is gitignored — it is real personal health data. Never
  commit it, never paste its contents into code, commits, or PRs, and never
  commit screenshots of the dashboard with real data.

## Gotchas (recurring mistakes — update as new ones surface)
- **Don't read pipes with `FileHandle.bytes`.** It parks a Swift-concurrency
  thread per pipe and froze the test suite; `Backend/PipeLines.swift` reads
  with `readabilityHandler` instead.
- **The backend's stdout is the protocol.** Never `print()` there; log to
  stderr. Non-JSON-safe values (NaN, numpy scalars) must be converted.
- **macOS privacy prompts block the helper.** Reading a folder in ~/Documents
  (or Desktop/Downloads) triggers "Aayu would like to access…"; the helper's
  `open()` blocks until the user answers. Ad-hoc signatures change on every
  build, so rebuilt apps may ask again. This is also why dev builds copy the
  backend source into the bundle instead of importing it from the repo.
- **Quit Aayu before `make run`.** `open` on an app that's already running only
  brings the old copy forward, so the new build never starts. `dist/Aayu.app`
  (what Finder/Spotlight open) only changes with `make app`.
- **Launch the app with `open`, not by exec'ing the binary** — a bare exec
  from a background shell may never activate or show a window.
- **Stale saved window state hid the window.** After a force quit, AppKit
  "restored" nothing and SwiftUI skipped opening the dashboard; `AayuApp.init`
  registers `ApplePersistenceIgnoreState` to prevent it.
- **The repo lives in iCloud-synced `~/Documents`.** iCloud offloads files to
  "dataless" placeholders (git can hang reading them — `find . -flags
  +dataless`) and tags new files so `codesign` fails ("detritus not
  allowed"). Build and sign outside the repo, then copy.
- **Launched from a background shell, the window may stay off screen** (macOS
  cooperative activation, Stage Manager). It exists; `osascript -e 'tell
  application id "io.github.nikhil-kunapareddy.aayu" to activate'` brings it up.
- **Checking visuals without screen recording:** host the views in an NSWindow
  and `cacheDisplay` it, or `ImageRenderer` for pure-SwiftUI pieces.
  `cacheDisplay` shows faint edge lines on translucent capsules that the real
  window doesn't have.
- **Swift Charts draws marks outside the x domain** (over the axis labels);
  filter or widen the domain (see `WorkoutsChart.visible(_:)`).
