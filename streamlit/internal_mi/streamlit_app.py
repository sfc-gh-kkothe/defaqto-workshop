"""
Defaqto — Internal MI
Snowflake x Defaqto workshop, 8 September 2026.
Author: Ketki Kothe, Solution Engineer, Snowflake.

The master data set Ben asked for: the whole funnel, every insurer, every comparison
site — then a Cortex Agent you can ask questions of in plain English.

Two sections only: the dashboard, and "talk to your data". No exceptions panel, no
pipeline health.

This is a CONTAINER runtime app, for one reason: Cortex Agents cannot be called from a
warehouse-runtime Streamlit app. Everything else here would run happily on a warehouse.

Reads three gold dynamic tables in DEFAQTO_DB.TRANSFORMED_<alias>, all of which refresh
themselves:
  GOLD_FUNNEL_DAILY       six funnel stages by day and comparison site
  GOLD_PROVIDER_DAILY     per-insurer daily scorecard
  GOLD_COHORT_CONVERSION  conversion by customer type

Sample data is synthetic. The cohort conversion pattern was generated deliberately —
the company names are real, the pattern is not a finding about any real insurer.
"""

import json
import re

import altair as alt
import pandas as pd
import streamlit as st

AGENT_NAME = "DEFAQTO_ANALYST"

st.set_page_config(
    page_title="Defaqto — Internal MI",
    page_icon="D",
    layout="wide",
    initial_sidebar_state="collapsed",
)

# Container runtimes serve many viewers from one process, so get_active_session() is
# not thread-safe here. st.connection manages the connection properly.
session = st.connection("snowflake").session()

# Owner's rights here, so there is no cross-user leak today. The role is still in
# the cache key so that switching to "snowflake-callers-rights" later cannot
# silently serve one viewer's rows to another.
MY_ROLE = str(session.sql("SELECT CURRENT_ROLE() AS R").collect()[0]["R"])

# ---------------------------------------------------------------------------
# Defaqto brand palette, sourced from defaqto.com CSS custom properties.
# ---------------------------------------------------------------------------
BRAND = "#392388"     # deep purple, primary series
BRAND2 = "#5a2dd0"    # lighter purple, secondary series
ACCENT = "#ff7000"    # orange, "this is the number that matters"
TEAL = "#27adaa"
PINK = "#f843a2"
INK = "#241456"       # headings and data labels
INK_SOFT = "#5b5675"  # body text, axis labels
LINE = "#d6d4e8"      # borders
CANVAS = "#f5f3fd"    # page background
GRID = "#EAE7F6"      # chart gridlines

SERIES = [BRAND, ACCENT, TEAL, PINK, BRAND2, "#2a4eef", "#ffb27a"]

# ---------------------------------------------------------------------------
# The frame. Same proportions, radii and type scale as the HTML dashboard:
# 14px panel radius, 4px coloured KPI edge, uppercase 13px section headings.
# ---------------------------------------------------------------------------
st.markdown(
    """
    <style>
      @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&display=swap');
      .stApp { background: #f5f3fd; }
      .block-container { padding-top: 0 !important; padding-bottom: 3rem; max-width: 1360px; }
      #MainMenu, footer, header[data-testid="stHeader"] { visibility: hidden; height: 0; }
      html, body, [class*="css"] { font-family: Inter, -apple-system, system-ui, sans-serif; }

      .dq-head {
        background: linear-gradient(105deg, #1B0F3C 0%, #392388 46%, #4a2ba8 100%);
        color: #fff; padding: 22px 26px 24px; border-bottom: 3px solid #ff7000;
        border-radius: 0 0 14px 14px; margin: 0 0 6px;
        display: flex; align-items: center; justify-content: space-between;
        gap: 20px; flex-wrap: wrap;
      }
      .dq-brand { display: flex; align-items: center; gap: 14px; }
      .dq-mark {
        width: 44px; height: 44px; border-radius: 11px; background: #fff; color: #392388;
        display: grid; place-items: center; font-weight: 800; font-size: 22px;
        letter-spacing: -1px; flex: none;
      }
      .dq-brand h1 { margin: 0; font-size: 21px; font-weight: 700; letter-spacing: -.2px; color: #fff; }
      .dq-brand p { margin: 3px 0 0; font-size: 12.5px; opacity: .82; }
      .dq-tag {
        background: #ff7000; color: #fff; padding: 6px 13px; border-radius: 6px;
        font-size: 11px; font-weight: 800; letter-spacing: 1px; text-transform: uppercase;
      }
      .dq-asof { font-size: 12.5px; opacity: .85; text-align: right; }

      .dq-scope {
        background: #EBE6FA; border: 1px solid #d6d4e8; border-radius: 10px;
        padding: 10px 16px; font-size: 12.5px; color: #5a2dd0; margin: 0 0 18px;
      }
      .dq-scope b { color: #241456; }

      .dq-sec {
        font-size: 13px; font-weight: 800; text-transform: uppercase; letter-spacing: 1.1px;
        color: #5b5675; margin: 30px 0 12px;
      }

      .dq-kpi {
        background: #fff; border: 1px solid #d6d4e8; border-radius: 14px;
        padding: 18px 20px; position: relative; overflow: hidden; height: 100%;
      }
      .dq-kpi::before { content: ""; position: absolute; left: 0; top: 0; bottom: 0; width: 4px; }
      .dq-kpi.a::before { background: #392388; }
      .dq-kpi.b::before { background: #27adaa; }
      .dq-kpi.c::before { background: #f843a2; }
      .dq-kpi.d::before { background: #ff7000; }
      .dq-kpi .k {
        font-size: 11px; font-weight: 700; text-transform: uppercase;
        letter-spacing: .8px; color: #5b5675; min-height: 30px;
      }
      .dq-kpi .v { font-size: 30px; font-weight: 750; letter-spacing: -1px;
                   margin: 6px 0 3px; color: #241456; }
      .dq-kpi .s { font-size: 12.5px; color: #5b5675; }
      .dq-kpi .s strong { color: #392388; }

      /* Panels. st.container(border=True) renders this wrapper; restyle it to match
         the HTML dashboard rather than hand-rolling divs Streamlit would escape. */
      div[data-testid="stVerticalBlockBorderWrapper"] {
        background: #fff; border: 1px solid #d6d4e8 !important;
        border-radius: 14px !important; padding: 4px 6px;
      }
      .dq-panel-h { font-size: 15px; font-weight: 700; color: #241456;
                    letter-spacing: -.1px; margin: 6px 0 0; }
      .dq-panel-s { font-size: 12.5px; color: #5b5675; margin: 4px 0 10px; }

      .dq-note {
        border-left: 4px solid #ff7000; background: #FFF2E8; color: #241456;
        padding: 12px 15px; border-radius: 0 8px 8px 0; font-size: 13.5px; margin: 4px 0 8px;
      }
      .dq-foot { color: #5b5675; font-size: 12px; margin-top: 34px;
                 border-top: 1px solid #d6d4e8; padding-top: 14px; }

      [data-testid="stDataFrame"] { border-radius: 10px; }
      .stChatMessage { background: #fff; border: 1px solid #d6d4e8; border-radius: 12px; }
    </style>
    """,
    unsafe_allow_html=True,
)


# ---------------------------------------------------------------------------
# One Altair theme so every chart matches the HTML dashboard without repeating
# styling at each call site.
# ---------------------------------------------------------------------------
def defaqto_theme():
    return {
        "config": {
            "background": "#ffffff",
            "font": "Inter, system-ui, sans-serif",
            "view": {"stroke": "transparent"},
            "axis": {
                "gridColor": GRID,
                "domainColor": LINE,
                "tickColor": LINE,
                "labelColor": INK_SOFT,
                "titleColor": INK_SOFT,
                "labelFontSize": 11,
                "titleFontSize": 11,
                "titleFontWeight": 600,
            },
            "legend": {"labelColor": INK_SOFT, "titleColor": INK_SOFT,
                       "labelFontSize": 11, "titleFontSize": 11},
            "range": {"category": SERIES},
        }
    }


alt.themes.register("defaqto", defaqto_theme)
alt.themes.enable("defaqto")


# ---------------------------------------------------------------------------
# Which schema to read.
#
# DISCOVERED from the account, not hard-coded and not derived from the username. The
# alias is chosen by the attendee in notebook 01, so user FIRST.LAST owns
# TRANSFORMED_FLAST, not TRANSFORMED_FIRST_LAST. Deriving it looks right until it
# silently points at a schema that does not exist.
# ---------------------------------------------------------------------------
@st.cache_data(ttl=600, show_spinner=False)
def alias_schemas(role: str) -> list:
    rows = session.sql(
        "SHOW SCHEMAS LIKE 'TRANSFORMED_%' IN DATABASE DEFAQTO_DB"
    ).collect()
    names = [f"DEFAQTO_DB.{r['name']}" for r in rows]
    if not names:
        return []
    me = str(session.sql("SELECT CURRENT_USER() AS U").collect()[0]["U"])
    surname = me.split("@")[0].split(".")[-1].upper()
    names.sort(key=lambda n: 0 if surname in n.upper() else 1)
    return names


with st.sidebar:
    st.markdown("### Which schema?")
    _found = alias_schemas(MY_ROLE)
    if _found:
        schema = st.selectbox("Alias schema", _found,
                              help="Discovered from the account. Yours is pre-selected.")
    else:
        st.warning("No TRANSFORMED_* schema is visible. Run notebook 01 first.")
        schema = st.text_input("Alias schema", value="DEFAQTO_DB.TRANSFORMED_")
    st.caption(f"Role **{session.get_current_role()}**")


@st.cache_data(ttl=600, show_spinner=False)
def q(sql: str, role: str) -> pd.DataFrame:
    return session.sql(sql).to_pandas()


def n(v) -> str:
    return "—" if v is None else f"{int(v):,}"


def gbp(v) -> str:
    if v is None:
        return "—"
    v = float(v)
    if v >= 1e6:
        return f"£{v / 1e6:.2f}m"
    if v >= 1e3:
        return f"£{v / 1e3:,.0f}k"
    return f"£{v:,.0f}"


def kpi(col, cls, label, value, sub):
    col.markdown(
        f'<div class="dq-kpi {cls}"><div class="k">{label}</div>'
        f'<div class="v">{value}</div><div class="s">{sub}</div></div>',
        unsafe_allow_html=True,
    )


def sec(title):
    st.markdown(f'<div class="dq-sec">{title}</div>', unsafe_allow_html=True)


def panel_head(title, sub):
    st.markdown(f'<div class="dq-panel-h">{title}</div>'
                f'<div class="dq-panel-s">{sub}</div>', unsafe_allow_html=True)


# ---------------------------------------------------------------------------
funnel = q(f"""
    SELECT SUM(QUOTES_STARTED)            AS started,
           SUM(REACHED_RESULTS)           AS reached,
           SUM(RECEIVED_A_RATE)           AS rated,
           SUM(RECEIVED_A_PRICE)          AS priced,
           SUM(CLICKED_OUT)               AS clicked,
           SUM(CONVERTED)                 AS converted,
           SUM(ABANDONED_BEFORE_RESULTS)  AS abandoned,
           MIN(QUOTE_DATE)                AS first_day,
           MAX(QUOTE_DATE)                AS last_day
    FROM {schema}.GOLD_FUNNEL_DAILY
""", MY_ROLE).iloc[0]

providers = q(f"""
    SELECT PROVIDER_KEY                                       AS insurer,
           SUM(QUOTES_APPEARED_IN)                            AS appeared_in,
           SUM(QUOTES_PRICED)                                 AS priced,
           SUM(CLICKS)                                        AS clicks,
           SUM(SALES)                                         AS sales,
           ROUND(SUM(GWP), 2)                                 AS gwp,
           ROUND(SUM(COMMISSION), 2)                          AS commission,
           ROUND(AVG(AVG_PRICE_RANK), 2)                      AS avg_price_rank,
           ROUND(100 * DIV0(SUM(TIMES_CHEAPEST),
                            SUM(QUOTES_PRICED)), 1)           AS pct_cheapest,
           ROUND(100 * DIV0(SUM(CLICKS), SUM(QUOTES_PRICED)), 1) AS click_rate_pct,
           ROUND(100 * DIV0(SUM(SALES), SUM(CLICKS)), 1)      AS win_rate_pct
    FROM {schema}.GOLD_PROVIDER_DAILY
    GROUP BY PROVIDER_KEY
    ORDER BY gwp DESC NULLS LAST
""", MY_ROLE)

sites = q(f"""
    SELECT AFFILIATE_ID                                        AS comparison_site,
           SUM(QUOTES_STARTED)                                 AS journeys,
           SUM(ABANDONED_BEFORE_RESULTS)                       AS lost_before_price,
           ROUND(100 * DIV0(SUM(ABANDONED_BEFORE_RESULTS),
                            SUM(QUOTES_STARTED)), 1)           AS abandon_pct,
           SUM(CLICKED_OUT)                                    AS clicked_out,
           SUM(CONVERTED)                                      AS converted,
           ROUND(100 * DIV0(SUM(CONVERTED),
                            SUM(QUOTES_STARTED)), 2)           AS conversion_pct
    FROM {schema}.GOLD_FUNNEL_DAILY
    GROUP BY AFFILIATE_ID
    ORDER BY journeys DESC
""", MY_ROLE)

daily = q(f"""
    SELECT QUOTE_DATE          AS day,
           SUM(CONVERTED)      AS sales,
           SUM(CLICKED_OUT)    AS clicks
    FROM {schema}.GOLD_FUNNEL_DAILY
    GROUP BY QUOTE_DATE ORDER BY QUOTE_DATE
""", MY_ROLE)

# ---------------------------------------------------------------------------
st.markdown(
    f"""
    <div class="dq-head">
      <div class="dq-brand">
        <div class="dq-mark">D</div>
        <div>
          <h1>Defaqto — Internal MI</h1>
          <p>Short-term car insurance · quote journey, insurer performance, customer type</p>
        </div>
      </div>
      <div style="display:flex;align-items:center;gap:16px">
        <span class="dq-tag">Internal</span>
        <div class="dq-asof">Data to <b>{funnel['LAST_DAY']:%-d %B %Y}</b><br>
          {funnel['FIRST_DAY']:%-d %b} – {funnel['LAST_DAY']:%-d %b %Y}</div>
      </div>
    </div>
    <div class="dq-scope">
      Reading <b>{schema}</b> — three gold dynamic tables that refresh themselves.
      Sample data is synthetic; the company names are real, the conversion patterns are not.
    </div>
    """,
    unsafe_allow_html=True,
)

# --- KPIs ------------------------------------------------------------------
sec("Performance")
c1, c2, c3, c4 = st.columns(4, gap="medium")
conv_pct = 100 * funnel["CONVERTED"] / funnel["STARTED"] if funnel["STARTED"] else 0
aband_pct = 100 * funnel["ABANDONED"] / funnel["STARTED"] if funnel["STARTED"] else 0
kpi(c1, "a", "Quote journeys", n(funnel["STARTED"]),
    f"<strong>{n(funnel['CONVERTED'])}</strong> became a sale")
kpi(c2, "b", "Overall conversion", f"{conv_pct:.1f}%", "Sales as a share of journeys started")
kpi(c3, "c", "Lost before any price", f"{aband_pct:.1f}%",
    f"<strong>{n(funnel['ABANDONED'])}</strong> journeys, before an insurer was asked")
kpi(c4, "d", "Gross written premium", gbp(providers["GWP"].sum()),
    f"<strong>{gbp(providers['COMMISSION'].sum())}</strong> commission")

# --- Funnel and trend ------------------------------------------------------
sec("Funnel and trend")
f1, f2 = st.columns([1, 1], gap="medium")

with f1.container(border=True):
    panel_head("Where the journeys go", "Whole book, six stages")
    stages = pd.DataFrame({
        "stage": ["Journeys started", "Reached results", "An insurer responded",
                  "Got a usable price", "Clicked out", "Became a sale"],
        "count": [int(funnel[k]) for k in
                  ("STARTED", "REACHED", "RATED", "PRICED", "CLICKED", "CONVERTED")],
    })
    st.altair_chart(
        alt.Chart(stages).mark_bar(cornerRadiusEnd=4, height=26).encode(
            y=alt.Y("stage:N", sort=None, title=None),
            x=alt.X("count:Q", title=None, axis=alt.Axis(format="~s")),
            color=alt.Color("stage:N", sort=None, legend=None,
                            scale=alt.Scale(range=[BRAND, BRAND2, TEAL, TEAL, PINK, ACCENT])),
            tooltip=[alt.Tooltip("stage:N", title="Stage"),
                     alt.Tooltip("count:Q", format=",", title="Journeys")],
        ).properties(height=250),
        use_container_width=True,
    )
    st.markdown(
        f'<div class="dq-note">The biggest single leak is the first one: '
        f'<b>{aband_pct:.1f}%</b> of journeys end before any insurer is asked for a price. '
        f'Between "an insurer responded" and "got a usable price" you lose another '
        f'<b>{n(funnel["RATED"] - funnel["PRICED"])}</b> — those are declines, which still '
        f'carry a price of zero.</div>',
        unsafe_allow_html=True,
    )

with f2.container(border=True):
    panel_head("Clicks and sales by day", "Daily volume across the whole window")
    trend = daily.melt("DAY", var_name="measure", value_name="count")
    trend["measure"] = trend["measure"].map({"CLICKS": "Click-outs", "SALES": "Sales"})
    st.altair_chart(
        alt.Chart(trend).mark_line(strokeWidth=2.4, point=False).encode(
            x=alt.X("DAY:T", title=None),
            y=alt.Y("count:Q", title=None),
            color=alt.Color("measure:N", title=None,
                            scale=alt.Scale(range=[ACCENT, BRAND])),
            tooltip=[alt.Tooltip("DAY:T", title="Day"), "measure:N",
                     alt.Tooltip("count:Q", format=",")],
        ).properties(height=250),
        use_container_width=True,
    )

# --- Provider league -------------------------------------------------------
sec("Insurer league")
with st.container(border=True):
    panel_head("Every insurer, ranked by premium",
               "Click rate is clicks over quotes priced; win rate is sales over clicks")
    league = providers.rename(columns={
        "INSURER": "Insurer", "PRICED": "Quotes priced", "CLICKS": "Click-outs",
        "SALES": "Sales", "GWP": "GWP", "COMMISSION": "Commission",
        "AVG_PRICE_RANK": "Avg price rank", "PCT_CHEAPEST": "% cheapest",
        "CLICK_RATE_PCT": "Click rate %", "WIN_RATE_PCT": "Win rate %",
    })[["Insurer", "Quotes priced", "Click-outs", "Sales", "GWP", "Commission",
        "Avg price rank", "% cheapest", "Click rate %", "Win rate %"]]
    st.dataframe(
        league, use_container_width=True, hide_index=True,
        column_config={
            "GWP": st.column_config.NumberColumn(format="£%,.0f"),
            "Commission": st.column_config.NumberColumn(format="£%,.0f"),
        },
    )

l1, l2 = st.columns([1, 1], gap="medium")
with l1.container(border=True):
    panel_head("Click rate by insurer", "How often a priced quote turns into a click-out")
    st.altair_chart(
        alt.Chart(providers).mark_bar(cornerRadiusEnd=3, color=BRAND).encode(
            y=alt.Y("INSURER:N", sort="-x", title=None),
            x=alt.X("CLICK_RATE_PCT:Q", title="Click rate (%)"),
            tooltip=["INSURER:N", alt.Tooltip("CLICK_RATE_PCT:Q", title="Click rate %")],
        ).properties(height=260),
        use_container_width=True,
    )
with l2.container(border=True):
    panel_head("Price position against click rate",
               "Rank 1 is cheapest. Position is the strongest driver of a click.")
    st.altair_chart(
        alt.Chart(providers).mark_circle(size=200, color=ACCENT, opacity=.85).encode(
            x=alt.X("AVG_PRICE_RANK:Q", title="Average price rank"),
            y=alt.Y("CLICK_RATE_PCT:Q", title="Click rate (%)"),
            tooltip=["INSURER:N", alt.Tooltip("AVG_PRICE_RANK:Q", title="Avg rank"),
                     alt.Tooltip("CLICK_RATE_PCT:Q", title="Click rate %")],
        ).properties(height=260),
        use_container_width=True,
    )

# --- Comparison sites ------------------------------------------------------
sec("Comparison websites")
with st.container(border=True):
    panel_head("Traffic and conversion by comparison site",
               "Abandonment is the share lost before any insurer was asked")
    st.dataframe(
        sites.rename(columns={
            "COMPARISON_SITE": "Comparison site", "JOURNEYS": "Journeys",
            "LOST_BEFORE_PRICE": "Lost before price", "ABANDON_PCT": "Abandoned %",
            "CLICKED_OUT": "Click-outs", "CONVERTED": "Sales",
            "CONVERSION_PCT": "Conversion %"}),
        use_container_width=True, hide_index=True,
    )

# --- Cohort ----------------------------------------------------------------
sec("Conversion by customer type")
with st.container(border=True):
    panel_head("Which customers each insurer converts",
               'The cohort question: do some insurers convert people with newer cars '
               'much better than people with cars over seven years old." This is the '
               'join Defaqto cannot make today.')
    dim = st.radio(
        "Compare by",
        ["VEHICLE_AGE_BAND", "DRIVER_AGE_BAND", "COVER_LENGTH_BAND", "COVER_REASON"],
        format_func=lambda s: {"VEHICLE_AGE_BAND": "Vehicle age",
                               "DRIVER_AGE_BAND": "Driver age",
                               "COVER_LENGTH_BAND": "Cover length",
                               "COVER_REASON": "Reason for cover"}[s],
        horizontal=True,
    )
    cohort = q(f"""
        SELECT PROVIDER_KEY                                        AS insurer,
               {dim}                                               AS cohort,
               SUM(QUOTES_PRICED)                                  AS priced,
               SUM(CLICKS)                                         AS clicks,
               ROUND(100 * DIV0(SUM(CLICKS), SUM(QUOTES_PRICED)), 1) AS click_rate_pct
        FROM {schema}.GOLD_COHORT_CONVERSION
        WHERE {dim} <> 'unknown'
        GROUP BY PROVIDER_KEY, {dim}
        HAVING SUM(QUOTES_PRICED) > 1000
        ORDER BY insurer, cohort
    """, MY_ROLE)
    if cohort.empty:
        st.info("No cohort has more than 1,000 priced quotes for this dimension.")
    else:
        st.altair_chart(
            alt.Chart(cohort).mark_bar(cornerRadiusEnd=2).encode(
                y=alt.Y("INSURER:N", title=None, sort="-x"),
                x=alt.X("CLICK_RATE_PCT:Q", title="Click rate (%)"),
                yOffset=alt.YOffset("COHORT:N"),
                color=alt.Color("COHORT:N", title=None,
                                scale=alt.Scale(range=SERIES)),
                tooltip=["INSURER:N", "COHORT:N",
                         alt.Tooltip("PRICED:Q", format=",", title="Quotes priced"),
                         alt.Tooltip("CLICK_RATE_PCT:Q", title="Click rate %")],
            ).properties(height=max(260, 46 * cohort["INSURER"].nunique())),
            use_container_width=True,
        )
        st.markdown(
            '<div class="dq-note">Cohorts below 1,000 priced quotes are excluded — a '
            'ratio off a few dozen quotes is noise, not a finding.</div>',
            unsafe_allow_html=True,
        )

# ---------------------------------------------------------------------------
# Talk to your data
# ---------------------------------------------------------------------------
sec("Talk to your data")


def run_agent(messages: list) -> dict:
    """Call the Cortex Agent over SQL.

    This is why the app needs a container runtime: Cortex Agents cannot be called
    from a warehouse-runtime Streamlit app.
    """
    fqn = f"{schema}.{AGENT_NAME}"
    row = session.sql(
        "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?) AS R",
        params=[fqn, json.dumps({"messages": messages})],
    ).collect()[0]
    return json.loads(row["R"])


def rows_from_result_set(result_set: dict) -> list:
    """Turn an agent result_set into records for st.dataframe."""
    meta = (result_set or {}).get("resultSetMetaData", {}) or {}
    cols = [c.get("name") for c in meta.get("rowType", []) or []]
    data = (result_set or {}).get("data", []) or []
    if not data:
        return []
    return [dict(zip(cols, r)) for r in data] if cols else [{"value": r} for r in data]


def render(content: list) -> None:
    """Render the agent's reply.

    DATA_AGENT_RUN does not return a top-level "table" item. Query output is nested
    inside tool_result -> content[] -> json -> result_set, alongside the SQL and a
    verified_query_used flag. Handling only "text" shows the prose and silently drops
    every number.
    """
    for item in content or []:
        kind = item.get("type")
        if kind == "text":
            body = item.get("text")
            body = body.get("text") if isinstance(body, dict) else body
            body = re.sub(r"</?answer>", "", body or "").strip()
            if body:
                st.markdown(body)
        elif kind == "chart":
            spec = (item.get("chart") or {}).get("chart_spec")
            if spec:
                try:
                    st.vega_lite_chart(json.loads(spec), use_container_width=True)
                except (ValueError, TypeError):
                    pass
        elif kind == "tool_result":
            for inner in (item.get("tool_result") or {}).get("content") or []:
                payload = inner.get("json") or {}
                recs = rows_from_result_set(payload.get("result_set"))
                if recs:
                    st.dataframe(recs, use_container_width=True, hide_index=True)
                if payload.get("verified_query_used"):
                    st.caption("Answered using a verified query")
                if payload.get("sql"):
                    with st.expander("SQL the agent ran"):
                        st.code(payload["sql"], language="sql")


with st.container(border=True):
    panel_head("Ask a question in plain English",
               f"Powered by the {AGENT_NAME} agent over the DEFAQTO_INSIGHTS semantic "
               "view. Expand the SQL on any answer to audit it.")

    st.caption("Try: *Where do we lose customers?* · *Which insurers convert best?* · "
               "*Do insurers convert newer cars better than older cars?* · "
               "*How many people arrived on the site?* (it should refuse — there is no "
               "arrivals data)")

    if "history" not in st.session_state:
        st.session_state.history = []

    for turn in st.session_state.history:
        with st.chat_message(turn["role"]):
            if turn["role"] == "user":
                st.markdown(turn["display"])
            else:
                render(turn["content"])

    prompt = st.chat_input("Ask about the funnel, an insurer, or a customer type")
    if prompt:
        with st.chat_message("user"):
            st.markdown(prompt)
        wire = [t["wire"] for t in st.session_state.history]
        wire.append({"role": "user", "content": [{"type": "text", "text": prompt}]})
        st.session_state.history.append(
            {"role": "user", "display": prompt, "wire": wire[-1]})

        with st.chat_message("assistant"):
            with st.spinner("Asking the agent…"):
                try:
                    content = run_agent(wire).get("content", [])
                except Exception as exc:  # surface the real error, never hide it
                    st.error(
                        f"The agent call failed: {exc}\n\n"
                        "Most likely causes: the agent does not exist in this schema, "
                        "your default role lacks SNOWFLAKE.CORTEX_AGENT_USER, or you "
                        "have no default warehouse — an agent runs as your DEFAULT "
                        "role, not the role selected here."
                    )
                    content = []
            if content:
                render(content)
                st.session_state.history.append(
                    {"role": "assistant", "content": content,
                     "wire": {"role": "assistant", "content": content}})
            else:
                st.session_state.history.pop()

st.markdown(
    '<div class="dq-foot">Defaqto × Snowflake workshop · 8 September 2026 · '
    'Built with Snowflake Solution Engineering. Aggregation logic supplied by the Defaqto data lead. '
    'Sample data is synthetic — the cohort conversion pattern was generated deliberately '
    'and is not a finding about any real insurer.</div>',
    unsafe_allow_html=True,
)
