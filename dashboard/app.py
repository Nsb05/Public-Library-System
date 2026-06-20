"""
dashboard/app.py — Streamlit Dashboard for the Public Library Management System.

Connects to a live MySQL database and visualises 4 key analytical reports:
  1. Checkout Trend       — Rolling 30-day average line chart
  2. Top Books            — Checkout velocity bar chart
  3. Branch Utilisation   — Scatter plot (copies vs checkouts)
  4. Fine Collection      — Stacked bar (collected vs outstanding) by year

Usage:
    streamlit run dashboard/app.py -- --host localhost --user root --password secret
"""

from urllib.parse import quote_plus

from sqlalchemy import create_engine, text
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

# ── page config ───────────────────────────────────────────────────────────────
st.set_page_config(
    page_title="Library Analytics Dashboard",
    page_icon="📚",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── custom CSS ────────────────────────────────────────────────────────────────
st.markdown("""
<style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap');

    html, body, [class*="css"] {
        font-family: 'Inter', sans-serif;
    }

    /* Dark gradient background */
    .main {
        background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
    }

    /* Metric cards */
    [data-testid="metric-container"] {
        background: rgba(255,255,255,0.07);
        border: 1px solid rgba(255,255,255,0.12);
        border-radius: 12px;
        padding: 16px 20px;
        backdrop-filter: blur(10px);
    }

    /* Section headers */
    .section-header {
        font-size: 1.3rem;
        font-weight: 700;
        color: #a78bfa;
        margin-bottom: 4px;
        letter-spacing: 0.02em;
    }

    .section-subtext {
        font-size: 0.85rem;
        color: #94a3b8;
        margin-bottom: 16px;
    }

    /* Sidebar */
    [data-testid="stSidebar"] {
        background: rgba(15, 12, 41, 0.95);
    }
</style>
""", unsafe_allow_html=True)


# ── DB engine (cached) ────────────────────────────────────────────────────
@st.cache_resource
def get_engine(host, port, user, password, database):
    """Create a SQLAlchemy engine with connection-pool health checks."""
    try:
        url = (
            f"mysql+mysqlconnector://{quote_plus(user)}:{quote_plus(password)}"
            f"@{host}:{port}/{database}"
        )
        engine = create_engine(url, pool_pre_ping=True)
        # Validate credentials immediately
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return engine
    except Exception as e:
        st.error(f"❌ Cannot connect to MySQL: {e}")
        st.stop()


@st.cache_data(ttl=300)   # cache query results for 5 minutes
def run_query(_engine, sql: str) -> pd.DataFrame:
    try:
        with _engine.connect() as conn:
            return pd.read_sql(text(sql), conn)
    except Exception:
        # Engine pool exhausted or DB went away — clear cache and prompt reconnect
        get_engine.clear()
        st.warning("⚠️ Lost connection to MySQL. Please reconnect using the sidebar button.")
        st.stop()


# ── sidebar — connection settings ────────────────────────────────────────────
# Read defaults from .streamlit/secrets.toml [mysql] section if present
_s = st.secrets.get("mysql", {}) if hasattr(st, "secrets") else {}

with st.sidebar:
    st.markdown("## ⚙️ Connection")
    host     = st.text_input("Host",     value=_s.get("host",     "localhost"))
    port     = st.number_input("Port",   value=int(_s.get("port", 3306)), step=1)
    user     = st.text_input("User",     value=_s.get("user",     "root"))
    password = st.text_input("Password", type="password", value=_s.get("password", ""))
    database = st.text_input("Database", value=_s.get("database", "public_library"))

    connect_btn = st.button("🔌 Connect", use_container_width=True)

    st.markdown("---")
    st.markdown("## 🔍 Filters")
    top_n = st.slider("Top N books (velocity chart)", 10, 50, 20)
    genre_filter = st.multiselect(
        "Genre filter",
        options=["Fiction","Mystery","Science Fiction","Fantasy","Biography",
                 "History","Self-Help","Romance","Horror","Thriller",
                 "Children","Young Adult"],
        default=[],
    )

if "engine" not in st.session_state or connect_btn:
    st.session_state["engine"] = get_engine(host, int(port), user, password, database)

engine = st.session_state["engine"]


# ── header ────────────────────────────────────────────────────────────────────
st.markdown("""
<div style="text-align:center; padding: 24px 0 8px 0;">
    <h1 style="font-size:2.6rem; font-weight:800;
               background: linear-gradient(90deg, #a78bfa, #60a5fa, #34d399);
               -webkit-background-clip: text; -webkit-text-fill-color: transparent;">
        📚 Library Analytics Dashboard
    </h1>
    <p style="color:#94a3b8; font-size:1rem; margin-top:-8px;">
        Multi-Branch Public Library Management System · MySQL Live Data
    </p>
</div>
""", unsafe_allow_html=True)

st.markdown("---")


# ── KPI summary row ───────────────────────────────────────────────────────────
kpi_sql = """
SELECT
    (SELECT COUNT(*) FROM branches)  AS branches,
    (SELECT COUNT(*) FROM books)     AS books,
    (SELECT COUNT(*) FROM copies)    AS copies,
    (SELECT COUNT(*) FROM patrons)   AS patrons,
    (SELECT COUNT(*) FROM loans)     AS total_loans,
    (SELECT COUNT(*) FROM loans
     WHERE return_date IS NULL)      AS active_loans,
    (SELECT COUNT(*) FROM holds
     WHERE status IN ('waiting','ready')) AS pending_holds,
    (SELECT ROUND(SUM(CASE WHEN paid = FALSE THEN amount ELSE 0 END),2)
     FROM fines)                     AS outstanding_fines
"""
kpi_df = run_query(engine, kpi_sql)
if kpi_df.empty:
    st.info("ℹ️ No KPI data found. Make sure the database is seeded.")
else:
    kpi = kpi_df.iloc[0]
    c1, c2, c3, c4, c5, c6, c7, c8 = st.columns(8)
    c1.metric("🏛 Branches",        f"{kpi['branches']:,}")
    c2.metric("📖 Books",           f"{kpi['books']:,}")
    c3.metric("📦 Copies",          f"{kpi['copies']:,}")
    c4.metric("🧑 Patrons",         f"{kpi['patrons']:,}")
    c5.metric("📋 Total Loans",     f"{kpi['total_loans']:,}")
    c6.metric("🔓 Active Loans",    f"{kpi['active_loans']:,}")
    c7.metric("🔖 Pending Holds",   f"{kpi['pending_holds']:,}")
    c8.metric("💰 Outstanding $",   f"${kpi['outstanding_fines']:,.2f}")

st.markdown("---")


# ══════════════════════════════════════════════════════════════════════════════
# PANEL 1: Rolling 30-Day Checkout Trend
# ══════════════════════════════════════════════════════════════════════════════
st.markdown('<p class="section-header">📈 Checkout Trend (Rolling 30-Day Average)</p>', unsafe_allow_html=True)
st.markdown('<p class="section-subtext">Daily system-wide checkouts smoothed with a 30-day trailing window to reveal seasonal patterns.</p>', unsafe_allow_html=True)

trend_sql = """
WITH daily AS (
    SELECT DATE(checkout_date) AS loan_date, COUNT(*) AS daily_count
    FROM loans
    GROUP BY DATE(checkout_date)
)
SELECT
    loan_date,
    daily_count,
    AVG(daily_count) OVER (
        ORDER BY loan_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS rolling_30d,
    AVG(daily_count) OVER (
        ORDER BY loan_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7d
FROM daily
ORDER BY loan_date
"""
trend_df = run_query(engine, trend_sql)
if trend_df.empty:
    st.info("ℹ️ No loan data found for checkout trend.")
else:
    trend_df["loan_date"] = pd.to_datetime(trend_df["loan_date"])

    fig_trend = go.Figure()
    fig_trend.add_trace(go.Scatter(
        x=trend_df["loan_date"], y=trend_df["daily_count"],
        name="Daily checkouts", mode="lines",
        line=dict(color="rgba(167,139,250,0.25)", width=1),
        fill="tozeroy", fillcolor="rgba(167,139,250,0.05)",
    ))
    fig_trend.add_trace(go.Scatter(
        x=trend_df["loan_date"], y=trend_df["rolling_7d"].round(1),
        name="7-day avg", mode="lines",
        line=dict(color="#60a5fa", width=1.5, dash="dot"),
    ))
    fig_trend.add_trace(go.Scatter(
        x=trend_df["loan_date"], y=trend_df["rolling_30d"].round(1),
        name="30-day avg", mode="lines",
        line=dict(color="#a78bfa", width=2.5),
    ))
    fig_trend.update_layout(
        template="plotly_dark",
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        legend=dict(orientation="h", y=1.08),
        xaxis_title="Date",
        yaxis_title="Checkouts",
        height=350,
        margin=dict(l=0, r=0, t=30, b=0),
    )
    st.plotly_chart(fig_trend, use_container_width=True)

st.markdown("---")


# ══════════════════════════════════════════════════════════════════════════════
# PANEL 2: Checkout Velocity — Top Books
# ══════════════════════════════════════════════════════════════════════════════
st.markdown('<p class="section-header">🏆 Checkout Velocity — Top Books (Last 12 Months)</p>', unsafe_allow_html=True)
st.markdown('<p class="section-subtext">Books ranked by number of checkouts. High-demand titles candidates for additional copy purchases.</p>', unsafe_allow_html=True)

genre_clause = ""
if genre_filter:
    genres_str = ", ".join(f"'{g}'" for g in genre_filter)
    genre_clause = f"AND b.genre IN ({genres_str})"

velocity_sql = f"""
SELECT
    CONCAT(b.title, ' (#', b.id, ')') AS unique_title,
    b.title,
    b.author,
    b.genre,
    COUNT(l.id) AS checkouts,
    DENSE_RANK() OVER (ORDER BY COUNT(l.id) DESC) AS rnk
FROM books b
JOIN copies c ON c.book_id = b.id
JOIN loans  l ON l.copy_id = c.id
WHERE l.checkout_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
{genre_clause}
GROUP BY b.id, b.title, b.author, b.genre
ORDER BY checkouts DESC
LIMIT {top_n}
"""
vel_df = run_query(engine, velocity_sql)
if vel_df.empty:
    st.info("ℹ️ No checkout data found for the selected filters in the last 12 months.")
else:
    fig_vel = px.bar(
        vel_df.sort_values("checkouts"),
        x="checkouts", y="unique_title",
        color="genre",
        orientation="h",
        color_discrete_sequence=px.colors.qualitative.Vivid,
        labels={"checkouts": "Checkouts", "unique_title": "Book Title", "genre": "Genre"},
        hover_data=["title", "author", "genre"],
    )
    fig_vel.update_layout(
        template="plotly_dark",
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        height=max(350, top_n * 22),
        margin=dict(l=0, r=0, t=10, b=0),
        yaxis=dict(tickfont=dict(size=11)),
    )
    st.plotly_chart(fig_vel, use_container_width=True)

st.markdown("---")





# ══════════════════════════════════════════════════════════════════════════════
# PANEL 3: Fine Collection by Year
# ══════════════════════════════════════════════════════════════════════════════
st.markdown('<p class="section-header">💰 Fine Collection — Issued vs. Collected by Year</p>', unsafe_allow_html=True)
st.markdown('<p class="section-subtext">Stacked bars show what was issued; green portion = collected. Line = cumulative outstanding balance.</p>', unsafe_allow_html=True)

fines_sql = """
SELECT
    YEAR(f.created_at)                                       AS fine_year,
    SUM(f.amount)                                            AS total_issued,
    SUM(CASE WHEN f.paid = TRUE  THEN f.amount ELSE 0 END)  AS collected,
    SUM(CASE WHEN f.paid = FALSE THEN f.amount ELSE 0 END)  AS outstanding
FROM fines f
GROUP BY YEAR(f.created_at)
ORDER BY fine_year
"""
fines_df = run_query(engine, fines_sql)
if fines_df.empty:
    st.info("ℹ️ No fines data found.")
else:
    fines_df["fine_year"] = fines_df["fine_year"].astype(str)
    fines_df["running_outstanding"] = fines_df["outstanding"].cumsum()

    fig_fines = go.Figure()
    fig_fines.add_trace(go.Bar(
        name="Collected",
        x=fines_df["fine_year"], y=fines_df["collected"].round(2),
        marker_color="#34d399",
    ))
    fig_fines.add_trace(go.Bar(
        name="Outstanding",
        x=fines_df["fine_year"], y=fines_df["outstanding"].round(2),
        marker_color="#f87171",
    ))
    fig_fines.add_trace(go.Scatter(
        name="Cumulative Outstanding",
        x=fines_df["fine_year"], y=fines_df["running_outstanding"].round(2),
        mode="lines+markers",
        line=dict(color="#fbbf24", width=2),
        yaxis="y2",
    ))
    fig_fines.update_layout(
        barmode="stack",
        template="plotly_dark",
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        height=380,
        legend=dict(orientation="h", y=1.08),
        margin=dict(l=0, r=0, t=30, b=0),
        yaxis=dict(title="Amount ($)"),
        yaxis2=dict(
            title="Cumulative Outstanding ($)",
            overlaying="y",
            side="right",
            showgrid=False,
        ),
    )
    st.plotly_chart(fig_fines, use_container_width=True)

st.markdown("---")
st.markdown(
    "<p style='text-align:center; color:#475569; font-size:0.8rem;'>"
    "Public Library Management System · Built with Streamlit + Plotly · MySQL 8.0"
    "</p>",
    unsafe_allow_html=True,
)
