<img src="assets/icon.png" width="128" alt="Aayu app icon">

# Aayu — Personal Health Dashboard

[![CI](https://github.com/nikhil-kunapareddy/aayu/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nikhil-kunapareddy/aayu/actions/workflows/ci.yml)
[![Release](https://github.com/nikhil-kunapareddy/aayu/actions/workflows/release.yml/badge.svg)](https://github.com/nikhil-kunapareddy/aayu/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/nikhil-kunapareddy/aayu?sort=semver&label=version)](https://github.com/nikhil-kunapareddy/aayu/releases/latest)
[![Last commit](https://img.shields.io/github/last-commit/nikhil-kunapareddy/aayu/main)](https://github.com/nikhil-kunapareddy/aayu/commits/main)
[![Open issues](https://img.shields.io/github/issues/nikhil-kunapareddy/aayu)](https://github.com/nikhil-kunapareddy/aayu/issues)
<br>
![macOS 15+ · Apple Silicon](https://img.shields.io/badge/macOS-15%2B%20%C2%B7%20Apple%20Silicon-000000?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Python 3.12](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)
![Privacy: local only](https://img.shields.io/badge/privacy-local%20only-2ea44f)

A native Mac app (Apple Silicon) for wearable data exported from the **Zepp**
app (Amazfit devices). Point it at your Zepp export folder and it charts your
sleep, workouts, calories and weight.

One window: a greeting and month menu (‹ ›, ⌘← ⌘→, plus **Last 30 days**),
your **sleep score** with the month's sleep-stage mix, tiles for steps, sleep,
resting heart rate and weight (each compared with the month before), and one
large chart at a time — a night-by-night **Sleep Breakdown** (hypnogram),
**Workout Sessions**, **Calories Burned** and **Weight Trend** — with hover
details. Step through the charts with ‹ › on the card, the dots below it,
⌘1–⌘4 or ⌘[ ⌘]. Light, Dark or System appearance; the layout adapts down to a
720 × 600 window; VoiceOver labels throughout.

## Download

**[⬇ Download Aayu for Mac](https://github.com/nikhil-kunapareddy/aayu/releases/latest/download/Aayu.zip)**
(Apple Silicon, macOS 15 or later) · [all releases](https://github.com/nikhil-kunapareddy/aayu/releases)

1. Unzip it and drag **Aayu** into **Applications**.
2. The app isn't notarized by Apple, so macOS blocks the first launch. Open
   **System Settings › Privacy & Security**, find "Aayu was blocked…" and
   click **Open Anyway**. You only need to do this once per version. Or in
   Terminal: `xattr -dr com.apple.quarantine /Applications/Aayu.app`.

Each release lists SHA-256 checksums in `SHA256SUMS.txt`.

## Build from source

Needs [uv](https://docs.astral.sh/uv/) and the Xcode Command Line Tools
(`xcode-select --install`); full Xcode isn't required.

```bash
git clone <repo-url> && cd aayu
make install        # builds Aayu.app and copies it to /Applications
```

Or `make app` to build `dist/Aayu.app` without installing, and `make run` to
run a debug build from source.

## Use

1. Export your data from the Zepp app and unzip it.
2. Open Aayu, click **Choose Zepp Folder…** (⌘O) and pick the unzipped folder
   (the one containing `SLEEP/`, `ACTIVITY/`, `BODY/`, …) — or drop the folder
   onto the window. **Help › Aayu Help** (⌘?) walks through the export.
3. If the folder is in Documents, Desktop or Downloads, macOS asks once whether
   Aayu may access it — click **Allow**.

Settings (⌘,):

| Setting | What it does |
| --- | --- |
| Zepp data folder | Where your export lives. Shows which data types were found. |
| Reload when a new export appears | Picks up a new export automatically. ⌘R reloads by hand. |
| Appearance | System, Light or Dark. |
| Weight units | lbs or kg, for the KPI and the weight chart. |
| Open on | Start on the latest month or the last 30 days. |

## How it's built

A SwiftUI app with Swift Charts in front of a Python (pandas) backend. The app
starts the backend as a hidden helper and they exchange JSON over a private
pipe — no network port, nothing else on your Mac can read the data.

```
app/                        # SwiftUI front end (Swift package, Swift 6)
  Sources/Aayu/main.swift   #   the executable: just launches AayuKit
  Sources/AayuKit/          #   App, Backend (the pipe), Model, Features,
                            #   Charts, DesignSystem, Support (logging)
  Tests/AayuKitTests/       #   Swift Testing, on synthetic data
  Info.plist, PrivacyInfo.xcprivacy
backend/
  aayu_backend/             # Python backend
    data.py                 #   CSV loading, cleaning, KPI values
    series.py               #   the numbers behind each chart
    server.py               #   JSON-lines protocol + folder watcher
  tests/                    #   pytest, on synthetic fixtures (+ a golden snapshot)
  pyproject.toml, uv.lock   #   pinned dependencies
scripts/
  bundle.sh                 #   assembles + signs Aayu.app
  make_icon.py              #   draws the app icon
Makefile                    # run / app / install / test / lint / clean
```

## Development

```bash
make run     # debug build, backend from source; logs in ~/Library/Caches/aayu/build/Aayu-dev.log
make test    # backend pytest + app Swift Testing
make lint    # ruff + mypy --strict
```

CI (GitHub Actions) runs the backend checks on Linux and builds and tests
the app on macOS for every pull request; `main` only accepts pull requests
that pass both. To publish a release, bump `CFBundleShortVersionString` in
`app/Info.plist`, then push a matching tag (`git tag v2.0.1 && git push
origin v2.0.1`); the Release workflow builds, signs (ad hoc), zips and
uploads `Aayu.app`.

Quit Aayu before `make run` — `open` only brings an already-running copy
forward. Rebuilt apps are ad-hoc signed, so macOS may ask for folder access
again after a rebuild. The app logs to unified logging (subsystem
`io.github.nikhil-kunapareddy.aayu`); request payloads are never logged.

## Data Privacy

Everything stays on your Mac: the app reads only the folder you choose and
makes no network requests — no tracking, no data collected (see
`app/PrivacyInfo.xcprivacy`). Tests use made-up data only. `data/` is gitignored, so health data you keep in
the repo is never committed.
