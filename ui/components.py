"""
Streamlit view primitives — the Streamlit equivalents of the old Dash
banner/card/section helpers in app/layout.py.

NOTE: Streamlit runs its Markdown parser over HTML even when
unsafe_allow_html=True. Lines indented 4+ spaces become Markdown code blocks,
which breaks the markup — so all HTML emitted here is kept un-indented and is
joined without leading whitespace.
"""

import streamlit as st


def banner_title(title: str) -> None:
    """The big banner title (e.g. 'Aayu')."""
    st.markdown(f'<div class="aayu-title">{title}</div>', unsafe_allow_html=True)


def banner_stats(stats: list[tuple]) -> None:
    """A right-aligned row of label/value/unit KPI stats.

    stats: list of (label, value, unit) tuples.
    """
    def _cell(label, value, unit):
        unit_html = f'<span class="aayu-stat-unit">{unit}</span>' if unit else ""
        return (
            f'<div class="aayu-stat">'
            f'<div class="aayu-stat-label">{label}</div>'
            f'<div class="aayu-stat-row">'
            f'<span class="aayu-stat-value">{value}</span>{unit_html}'
            f'</div></div>'
        )

    cells = "".join(_cell(label, value, unit) for label, value, unit in stats)
    st.markdown(f'<div class="aayu-stats">{cells}</div>', unsafe_allow_html=True)


def chart_card(title: str, fig, height: int = 280) -> None:
    """A bordered surface card holding a section title and a Plotly figure.

    The container is given a `key` so its DOM node gets a `st-key-aayucard-*`
    class — styles.py scopes the card border to that class only, so the
    surrounding column wrapper (also a border-wrapper) stays un-boxed.
    """
    slug = "".join(c if c.isalnum() else "-" for c in title.lower())
    with st.container(border=True, key=f"aayucard-{slug}"):
        st.markdown(f'<div class="aayu-section-title">{title}</div>', unsafe_allow_html=True)
        fig.update_layout(height=height)
        st.plotly_chart(
            fig,
            use_container_width=True,
            config={"displayModeBar": False},
            theme=None,  # use the figure's own (core.theme) styling, not Streamlit's
        )


def footer(text: str) -> None:
    st.markdown(f'<div class="aayu-footer">{text}</div>', unsafe_allow_html=True)
