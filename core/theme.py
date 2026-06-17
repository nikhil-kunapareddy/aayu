"""
Design tokens — colors, typography, and Plotly layout defaults.
"""

# Palette — pure-black canvas with the expanded high-contrast accent set
C = dict(
    bg       = "#000000",   # pure black canvas
    surface  = "#0E0E11",   # near-black card
    surface2 = "#17171B",   # elevated surface
    border   = "#232328",   # subtle separator
    purple   = "#A78BFA",   # original purple
    cyan     = "#22D3EE",   # vibrant cyan
    green    = "#4ADE80",   # mint green
    pink     = "#FB7185",   # soft coral
    amber    = "#FACC15",   # original yellow
    red      = "#FB7185",   # alert (reuse coral)
    text     = "#FFFFFF",   # primary text
    sub      = "#8A8A92",   # secondary text
    muted    = "#56565E",   # muted / disabled
    grid     = "#18181B",   # very subtle gridlines
)

# Friendly aliases (same hues, clearer names)
C["lime"]   = C["green"]
C["violet"] = C["purple"]
C["orange"] = C["pink"]   # no orange in palette → fall back to coral

# Shared axis style — minimal, horizontal-only gridlines
AXIS = dict(
    gridcolor=C["grid"],
    showgrid=True,
    zeroline=False,
    tickfont=dict(color=C["sub"], size=10),
    linecolor="rgba(0,0,0,0)",
)


def _rgb(hex_color: str) -> tuple:
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def fade(hex_color: str, top: float = 0.42, bottom: float = 0.0) -> dict:
    """Vertical fill gradient: saturated near the line, transparent at the baseline."""
    r, g, b = _rgb(hex_color)
    return dict(
        type="vertical",
        colorscale=[
            [0.0, f"rgba({r},{g},{b},{bottom})"],
            [1.0, f"rgba({r},{g},{b},{top})"],
        ],
    )


def plot_base(**overrides) -> dict:
    """Return a base Plotly layout dict, optionally merged with overrides."""
    cfg = dict(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor  = "rgba(0,0,0,0)",
        font          = dict(color=C["text"], family="Inter, sans-serif", size=11),
        margin        = dict(l=16, r=30, t=36, b=16),  # right room so edge x-labels (e.g. month-end) don't clip
        hovermode     = "x unified",
        barcornerradius = 5,
        hoverlabel    = dict(
            bgcolor     = C["surface2"],
            font_color  = C["text"],
            bordercolor = C["border"],
        ),
        legend = dict(
            bgcolor="rgba(0,0,0,0)",
            font=dict(color=C["sub"], size=10),
            orientation="h",
            yanchor="bottom", y=1.01,
            xanchor="right",  x=1,
        ),
    )
    cfg.update(overrides)
    return cfg
