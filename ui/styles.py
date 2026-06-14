"""
Streamlit CSS injection — recreates the iOS-inspired dark theme from core.theme.

Streamlit's base look is set in .streamlit/config.toml; this layers the custom
palette, card styling, banner, and sidebar on top via injected CSS.
"""

import streamlit as st

from core.theme import C


def inject() -> None:
    st.markdown(
        f"""
        <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;800&display=swap');

        /* ── Canvas ─────────────────────────────────────────────── */
        .stApp {{
            background: {C['bg']};
            font-family: 'Inter', ui-sans-serif, system-ui, sans-serif;
            color: {C['text']};
        }}
        .block-container {{
            max-width: 1800px;
            padding-top: 1.5rem;
            padding-bottom: 1.5rem;
        }}
        #MainMenu, footer, header {{ visibility: hidden; }}

        /* ── Cards: ONLY the keyed chart container is a box. ───────
           Streamlit columns are themselves border-wrappers, so a broad
           [data-testid="stVerticalBlockBorderWrapper"] selector would paint
           a second nested card on the column. Scope to the st-key-* class
           that st.container(key=...) emits, and neutralise the column. */
        div[class*="st-key-aayucard-"] {{
            background: {C['surface']};
            border: 1px solid {C['border']} !important;
            border-radius: 16px;
            padding: 12px 16px;
            transition: transform 0.2s ease, box-shadow 0.2s ease;
        }}
        div[class*="st-key-aayucard-"]:hover {{
            transform: translateY(-2px);
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
        }}
        /* the column wrapper around each card must stay invisible */
        div[data-testid="stColumn"] div[data-testid="stVerticalBlockBorderWrapper"]:not([class*="st-key-aayucard-"]) {{
            background: transparent !important;
            border: none !important;
        }}

        /* ── Scrollbar ──────────────────────────────────────────── */
        ::-webkit-scrollbar {{ width: 6px; height: 6px; }}
        ::-webkit-scrollbar-track {{ background: {C['surface']}; }}
        ::-webkit-scrollbar-thumb {{ background: {C['border']}; border-radius: 3px; }}
        ::-webkit-scrollbar-thumb:hover {{ background: {C['muted']}; }}

        /* ── Banner ─────────────────────────────────────────────── */
        div[class*="st-key-aayubanner"] {{
            background: {C['surface']}; border: 1px solid {C['border']};
            border-radius: 18px; padding: 26px 36px; margin-bottom: 24px;
        }}
        .aayu-title {{
            font-size: 80px; font-weight: 800; color: {C['text']};
            letter-spacing: -0.02em; line-height: 1;
        }}
        /* inline month filter — strip the selectbox chrome to a bare 'May | 2026' */
        div[class*="st-key-aayubanner"] div[data-baseweb="select"] > div {{
            background-color: transparent; border: none; box-shadow: none;
        }}
        div[class*="st-key-aayubanner"] div[data-baseweb="select"] * {{
            font-size: 22px; color: {C['sub']}; font-weight: 500;
        }}
        .aayu-stats {{ display: flex; gap: 24px; align-items: flex-start; justify-content: flex-end; flex-wrap: wrap; }}
        .aayu-stat-row {{ display: flex; align-items: baseline; }}
        .aayu-stat-label {{
            font-size: 18px; color: {C['sub']}; font-weight: 500; margin-bottom: -10px;
        }}
        .aayu-stat-value {{
            font-size: 36px; font-weight: 600; color: {C['text']}; letter-spacing: -0.02em;
        }}
        .aayu-stat-unit {{ font-size: 15px; color: {C['sub']}; margin-left: 5px; }}

        .aayu-section-title {{
            font-size: 24px; font-weight: 600; color: {C['text']};
            margin: 4px 0 4px 4px; letter-spacing: -0.01em;
        }}
        .aayu-footer {{
            text-align: center; color: {C['muted']}; font-size: 11px; padding: 16px 0 8px;
        }}

        /* ── Sidebar ────────────────────────────────────────────── */
        section[data-testid="stSidebar"] {{
            background: {C['surface']}; border-right: 1px solid {C['border']};
        }}
        </style>
        """,
        unsafe_allow_html=True,
    )
