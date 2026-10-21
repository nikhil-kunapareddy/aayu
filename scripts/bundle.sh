#!/bin/bash
# Assemble Aayu.app from the SwiftUI binary, the icon and the Python backend,
# then ad-hoc sign it. `make run` / `make app` call this.
#
#   scripts/bundle.sh <swift-binary> <icon.icns> <out.app> <backend>
#
# <backend> is either PyInstaller's output folder (release: holds the frozen
# `aayu-backend`), or a Python interpreter (development: the bundle gets a copy
# of backend/aayu_backend plus an `aayu-backend` script that runs it). Either
# way the app finds its helper at Contents/Resources/backend/aayu-backend.
#
# The development copy matters: if the helper imported its code straight from
# the repo in ~/Documents, macOS would hold it on a privacy prompt for access
# to the Documents folder.
#
# Put <out.app> outside iCloud-synced folders: iCloud tags new files with
# extended attributes that make codesign fail ("resource fork, Finder
# information, or similar detritus not allowed"). Copy the signed app after.
set -euo pipefail

binary=$1 icon=$2 app=$3 backend=$4
contents="$app/Contents"
helper="$contents/Resources/backend"

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$binary" "$contents/MacOS/Aayu"
cp app/Info.plist "$contents/Info.plist"
cp "$icon" "$contents/Resources/Aayu.icns"

if [ -d "$backend" ]; then
    cp -R "$backend" "$helper"
else
    mkdir -p "$helper"
    cp -R backend/aayu_backend "$helper/"
    rm -rf "$helper/aayu_backend/__pycache__"
    cat > "$helper/aayu-backend" <<EOF
#!/bin/sh
# Development helper (written by scripts/bundle.sh): the backend from source.
export PYTHONPATH="\$(dirname "\$0")" PYTHONDONTWRITEBYTECODE=1
exec "$backend" -m aayu_backend "\$@"
EOF
    chmod +x "$helper/aayu-backend"
fi

codesign --force --deep --sign - "$app"
