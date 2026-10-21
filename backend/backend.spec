# PyInstaller spec — freezes the backend into a folder holding `aayu-backend`,
# which scripts/bundle.sh copies into Aayu.app/Contents/Resources/backend.
# Run it with `make app`.

a = Analysis(
    ["aayu_backend/__main__.py"],
    pathex=["."],
    excludes=["tkinter"],
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="aayu-backend",
    console=True,           # a stdio helper, not a window app
    target_arch="arm64",
)
coll = COLLECT(exe, a.binaries, a.datas, name="aayu-backend")
