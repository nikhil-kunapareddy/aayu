# Aayu — `make run` starts the app from source, `make app` builds dist/Aayu.app.
#
# Everything generated (venv, Swift/PyInstaller builds, the bundles) lives
# outside the repo: thousands of small files don't belong in a synced folder,
# and codesign fails on files iCloud has tagged. Only the finished, signed app
# is copied into dist/.

CACHE  ?= $(HOME)/Library/Caches/aayu
VENV   := $(CACHE)/venv
PYTHON := $(VENV)/bin/python
BUILD  := $(CACHE)/build
SWIFT  := swift build --package-path app --scratch-path $(BUILD)/swift
ICON   := $(BUILD)/Aayu.icns

.PHONY: run app install clean

# Debug SwiftUI build; the backend runs from (a copy of) its source with the
# venv. Launched with `open` like a normal app; waits until you quit, with the
# app's and backend's output in $(BUILD)/Aayu-dev.log.
run: $(VENV)/.installed $(ICON)
	$(SWIFT)
	scripts/bundle.sh $(BUILD)/swift/debug/Aayu $(ICON) $(BUILD)/Aayu-dev.app $(PYTHON)
	open -W --stdout $(BUILD)/Aayu-dev.log --stderr $(BUILD)/Aayu-dev.log $(BUILD)/Aayu-dev.app

# Release SwiftUI build + the backend frozen with PyInstaller, in one bundle.
app: $(VENV)/.installed $(ICON)
	$(SWIFT) -c release
	cd backend && $(PYTHON) -m PyInstaller --noconfirm --clean \
		--distpath $(BUILD)/backend --workpath $(BUILD)/pyinstaller backend.spec
	scripts/bundle.sh $(BUILD)/swift/release/Aayu $(ICON) $(BUILD)/Aayu.app $(BUILD)/backend/aayu-backend
	rm -rf dist/Aayu.app && mkdir -p dist && ditto $(BUILD)/Aayu.app dist/Aayu.app
	@echo "Built dist/Aayu.app — drag it to /Applications, or: make install"

install: app
	rm -rf /Applications/Aayu.app
	ditto $(BUILD)/Aayu.app /Applications/Aayu.app

$(ICON): scripts/make_icon.py $(VENV)/.installed
	$(PYTHON) scripts/make_icon.py $@

$(VENV)/.installed: backend/requirements.txt
	uv venv --allow-existing --python 3.12 $(VENV)
	VIRTUAL_ENV=$(VENV) uv pip install -r backend/requirements.txt
	touch $@

clean:
	rm -rf build dist $(BUILD)
