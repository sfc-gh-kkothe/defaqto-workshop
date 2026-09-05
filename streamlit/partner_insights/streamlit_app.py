"""
Defaqto — Partner Insights
Snowflake x Defaqto workshop, 8 September 2026.
Author: Ketki Kothe, Solution Engineer, Snowflake.

The premium service Ben wants to sell: "predominantly more about being able to offer it
as a premium service to Providers".

Two sections only: the dashboard, and "talk to your data".

This app contains NO filtering logic. What a partner sees is decided entirely by the row
access policies on the gold dynamic tables — PROVIDER_RAP on GOLD_PROVIDER_DAILY and
GOLD_COHORT_CONVERSION, PCW_RAP on GOLD_FUNNEL_DAILY. One app, two audiences, filtered
by policy rather than by code. That is the point worth making on the day.

Market context is expressed WITHOUT naming a competitor: "you were cheapest on 22% of
quotes", never "Veygo beat you". That is what makes it safe to sell.

CONTAINER runtime, for one reason: Cortex Agents cannot be called from a
warehouse-runtime Streamlit app.

Note on rights: this app uses st.connection("snowflake-callers-rights"), so the row
access policies evaluate against the VIEWER's role, not the app owner's. ZIXTY_USER
therefore sees one insurer while ACCOUNTADMIN sees all seven, from identical code.
Two things this depends on: the viewer's DEFAULT role (not the one picked in
Snowsight), and CALLER grants on every table the app reads.
"""

import json
import re

import altair as alt
import pandas as pd
import streamlit as st

AGENT_NAME = "DEFAQTO_ANALYST"

st.set_page_config(
    page_title="Defaqto — Partner Insights",
    page_icon="D",
    layout="wide",
    initial_sidebar_state="collapsed",
)

session = st.connection("snowflake-callers-rights").session()

# The cache key MUST include this. On container runtime every viewer shares ONE
# app instance, and st.cache_data is global to it - so without the role in the
# key, the first viewer's rows are served to everyone, straight past the row
# access policy. Do NOT rename this to _role: Streamlit excludes underscore-
# prefixed arguments from the hash, which would silently reintroduce the leak.
MY_ROLE = str(session.sql("SELECT CURRENT_ROLE() AS R").collect()[0]["R"])

# Defaqto brand palette, sourced from defaqto.com CSS custom properties.
BRAND = "#392388"
BRAND2 = "#5a2dd0"
ACCENT = "#ff7000"
TEAL = "#27adaa"
PINK = "#f843a2"
INK = "#241456"
INK_SOFT = "#5b5675"
LINE = "#d6d4e8"
GRID = "#EAE7F6"
SERIES = [BRAND, ACCENT, TEAL, PINK, BRAND2, "#2a4eef", "#ffb27a"]

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
      .dq-kpi .k { font-size: 11px; font-weight: 700; text-transform: uppercase;
                   letter-spacing: .8px; color: #5b5675; min-height: 30px; }
      .dq-kpi .v { font-size: 30px; font-weight: 750; letter-spacing: -1px;
                   margin: 6px 0 3px; color: #241456; }
      .dq-kpi .s { font-size: 12.5px; color: #5b5675; }
      .dq-kpi .s strong { color: #392388; }
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
      .stChatMessage { background: #fff; border: 1px solid #d6d4e8; border-radius: 12px; }
    </style>
    """,
    unsafe_allow_html=True,
)


def defaqto_theme():
    return {
        "config": {
            "background": "#ffffff",
            "font": "Inter, system-ui, sans-serif",
            "view": {"stroke": "transparent"},
            "axis": {"gridColor": GRID, "domainColor": LINE, "tickColor": LINE,
                     "labelColor": INK_SOFT, "titleColor": INK_SOFT,
                     "labelFontSize": 11, "titleFontSize": 11, "titleFontWeight": 600},
            "legend": {"labelColor": INK_SOFT, "titleColor": INK_SOFT,
                       "labelFontSize": 11, "titleFontSize": 11},
            "range": {"category": SERIES},
        }
    }


alt.themes.register("defaqto", defaqto_theme)
alt.themes.enable("defaqto")


# Schema is DISCOVERED, not derived: the alias is chosen by the attendee, so user
# a user named FIRST.LAST may own TRANSFORMED_FLAST, not TRANSFORMED_FIRST_LAST.
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
    st.caption(
        "This app has no filtering logic. Everything below is decided by the row "
        "access policies on the gold tables."
    )


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
# Who is this? Detected by WHAT COMES BACK, not by any code decision. A partner role
# sees exactly one insurer; an internal role sees several and gets a picker.
# ---------------------------------------------------------------------------
visible = q(f"""
    SELECT DISTINCT PROVIDER_KEY AS insurer
    FROM {schema}.GOLD_PROVIDER_DAILY
    ORDER BY 1
""", MY_ROLE)
names = visible["INSURER"].dropna().tolist()

if not names:
    st.error(
        "This session returned no insurer rows, so there is nothing to show. Either the "
        "gold tables are empty, or this role is not mapped in PARTNER_ACCESS. Note that "
        "CREATE OR REPLACE DYNAMIC TABLE silently detaches row access policies, so "
        "re-running notebook 01 can empty this app with no error at all."
    )
    st.stop()

is_partner = len(names) == 1
if is_partner:
    who = names[0]
else:
    who = st.selectbox("Viewing as insurer", names,
                       help="Several insurers are visible, so this is an internal "
                            "session. A partner role sees exactly one.")

W = f"WHERE PROVIDER_KEY = '{who}'"

mine = q(f"""
    SELECT SUM(QUOTES_APPEARED_IN)                                AS appeared,
           SUM(QUOTES_PRICED)                                     AS priced,
           SUM(CLICKS)                                            AS clicks,
           SUM(SALES)                                             AS sales,
           ROUND(SUM(GWP), 2)                                     AS gwp,
           ROUND(AVG(AVG_PRICE_RANK), 2)                          AS avg_rank,
           ROUND(100 * DIV0(SUM(TIMES_CHEAPEST), SUM(QUOTES_PRICED)), 1) AS pct_cheapest,
           ROUND(100 * DIV0(SUM(CLICKS), SUM(QUOTES_PRICED)), 1)   AS click_rate,
           ROUND(100 * DIV0(SUM(SALES), SUM(CLICKS)), 1)           AS win_rate,
           MIN(QUOTE_DATE) AS first_day, MAX(QUOTE_DATE) AS last_day
    FROM {schema}.GOLD_PROVIDER_DAILY {W}
""", MY_ROLE).iloc[0]

daily = q(f"""
    SELECT QUOTE_DATE                     AS day,
           SUM(QUOTES_PRICED)             AS priced,
           SUM(CLICKS)                    AS clicks,
           SUM(SALES)                     AS sales,
           ROUND(SUM(GWP), 2)             AS gwp
    FROM {schema}.GOLD_PROVIDER_DAILY {W}
    GROUP BY QUOTE_DATE ORDER BY QUOTE_DATE
""", MY_ROLE)

# ---------------------------------------------------------------------------
st.markdown(
    f"""
    <div class="dq-head">
      <div class="dq-brand">
        <div class="dq-mark">D</div>
        <div>
          <h1>{who}</h1>
          <p>Your short-term car insurance performance on the Defaqto panel</p>
        </div>
      </div>
      <div style="display:flex;align-items:center;gap:16px">
        <span class="dq-tag">{"Partner view" if is_partner else "Internal preview"}</span>
        <div class="dq-asof">Data to <b>{mine['LAST_DAY']:%-d %B %Y}</b><br>
          {mine['FIRST_DAY']:%-d %b} – {mine['LAST_DAY']:%-d %b %Y}</div>
      </div>
    </div>
    """,
    unsafe_allow_html=True,
)

if is_partner:
    st.markdown(
        f'<div class="dq-scope">Row-level security restricts every figure on this page '
        f'to <b>{who}</b>. Competitor-level detail is never available — market context is '
        f'shown as your own share, never as another insurer\'s numbers.</div>',
        unsafe_allow_html=True,
    )
else:
    st.markdown(
        f'<div class="dq-scope"><b>Internal preview.</b> {len(names)} insurers are '
        f'visible to this role, so the row access policies are not restricting this '
        f'session — they exempt ACCOUNTADMIN and SYSADMIN by design. This is not what a '
        f'customer sees. Open this app as a partner role to see the restricted view.</div>',
        unsafe_allow_html=True,
    )

# --- KPIs ------------------------------------------------------------------
sec("Your performance")
c1, c2, c3, c4 = st.columns(4, gap="medium")
kpi(c1, "a", "Quotes you priced", n(mine["PRICED"]),
    f"You appeared in <strong>{n(mine['APPEARED'])}</strong> quotes")
kpi(c2, "b", "Click-out rate", f"{mine['CLICK_RATE']:.1f}%",
    f"<strong>{n(mine['CLICKS'])}</strong> shoppers clicked through to you")
kpi(c3, "c", "Win rate after a click", f"{mine['WIN_RATE']:.1f}%",
    f"<strong>{n(mine['SALES'])}</strong> policies sold")
kpi(c4, "d", "Gross written premium", gbp(mine["GWP"]),
    f"Average price position <strong>{mine['AVG_RANK']:.2f}</strong>")

st.markdown(
    f'<div class="dq-note">You were the cheapest price on the page for '
    f'<b>{mine["PCT_CHEAPEST"]:.1f}%</b> of the quotes you priced, and your average '
    f'position was <b>{mine["AVG_RANK"]:.2f}</b> where 1 is cheapest. Position is the '
    f'strongest single driver of a click-out — rank 1 wins roughly four times as often '
    f'as rank 2.</div>',
    unsafe_allow_html=True,
)

# --- Trend -----------------------------------------------------------------
sec("Your trend")
t1, t2 = st.columns([1, 1], gap="medium")
with t1.container(border=True):
    panel_head("Clicks and sales by day", "Your daily volume")
    tr = daily.melt("DAY", value_vars=["CLICKS", "SALES"],
                    var_name="measure", value_name="count")
    tr["measure"] = tr["measure"].map({"CLICKS": "Click-outs", "SALES": "Policies sold"})
    st.altair_chart(
        alt.Chart(tr).mark_line(strokeWidth=2.4).encode(
            x=alt.X("DAY:T", title=None),
            y=alt.Y("count:Q", title=None),
            color=alt.Color("measure:N", title=None, scale=alt.Scale(range=[ACCENT, BRAND])),
            tooltip=[alt.Tooltip("DAY:T", title="Day"), "measure:N",
                     alt.Tooltip("count:Q", format=",")],
        ).properties(height=250),
        use_container_width=True,
    )
with t2.container(border=True):
    panel_head("Premium by day", "Gross written premium you earned")
    st.altair_chart(
        alt.Chart(daily).mark_area(
            line={"color": BRAND, "strokeWidth": 2}, opacity=.25, color=BRAND2,
        ).encode(
            x=alt.X("DAY:T", title=None),
            y=alt.Y("GWP:Q", title=None, axis=alt.Axis(format="~s")),
            tooltip=[alt.Tooltip("DAY:T", title="Day"),
                     alt.Tooltip("GWP:Q", format=",.0f", title="GWP")],
        ).properties(height=250),
        use_container_width=True,
    )

# --- Your funnel -----------------------------------------------------------
sec("Your funnel")
with st.container(border=True):
    panel_head("From priced quote to policy sold", "Where your volume goes")
    stages = pd.DataFrame({
        "stage": ["Quotes you appeared in", "Quotes you priced",
                  "Shoppers who clicked out", "Policies sold"],
        "count": [int(mine["APPEARED"]), int(mine["PRICED"]),
                  int(mine["CLICKS"]), int(mine["SALES"])],
    })
    st.altair_chart(
        alt.Chart(stages).mark_bar(cornerRadiusEnd=4, height=30).encode(
            y=alt.Y("stage:N", sort=None, title=None),
            x=alt.X("count:Q", title=None, axis=alt.Axis(format="~s")),
            color=alt.Color("stage:N", sort=None, legend=None,
                            scale=alt.Scale(range=[BRAND, BRAND2, TEAL, ACCENT])),
            tooltip=[alt.Tooltip("stage:N", title="Stage"),
                     alt.Tooltip("count:Q", format=",", title="Quotes")],
        ).properties(height=200),
        use_container_width=True,
    )

# --- Cohort ----------------------------------------------------------------
sec("Which customers you convert")
with st.container(border=True):
    panel_head("Your conversion by customer type",
               "The question you cannot answer about yourself today, because the vehicle "
               "record lives in the quote system and the sale lives elsewhere")
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
        SELECT {dim}                                                 AS cohort,
               SUM(QUOTES_PRICED)                                    AS priced,
               SUM(CLICKS)                                           AS clicks,
               SUM(SALES)                                            AS sales,
               ROUND(100 * DIV0(SUM(CLICKS), SUM(QUOTES_PRICED)), 1)  AS click_rate_pct,
               ROUND(AVG(AVG_BEST_PRICE), 2)                         AS avg_your_price
        FROM {schema}.GOLD_COHORT_CONVERSION
        WHERE PROVIDER_KEY = '{who}' AND {dim} <> 'unknown'
        GROUP BY {dim}
        HAVING SUM(QUOTES_PRICED) > 1000
        ORDER BY click_rate_pct DESC
    """, MY_ROLE)
    if cohort.empty:
        st.info(
            "No cohort on this dimension has more than 1,000 priced quotes. A click rate "
            "off a few dozen quotes is noise rather than a finding, so nothing is shown."
        )
    else:
        st.altair_chart(
            alt.Chart(cohort).mark_bar(cornerRadiusEnd=3).encode(
                y=alt.Y("COHORT:N", sort="-x", title=None),
                x=alt.X("CLICK_RATE_PCT:Q", title="Your click rate (%)"),
                color=alt.Color("COHORT:N", legend=None, scale=alt.Scale(range=SERIES)),
                tooltip=["COHORT:N", alt.Tooltip("PRICED:Q", format=",", title="Quotes priced"),
                         alt.Tooltip("CLICKS:Q", format=",", title="Clicks"),
                         alt.Tooltip("CLICK_RATE_PCT:Q", title="Click rate %"),
                         alt.Tooltip("AVG_YOUR_PRICE:Q", format=",.2f", title="Avg your price")],
            ).properties(height=max(200, 42 * len(cohort))),
            use_container_width=True,
        )
        best = cohort.iloc[0]
        worst = cohort.iloc[-1]
        if len(cohort) > 1 and worst["CLICK_RATE_PCT"]:
            ratio = best["CLICK_RATE_PCT"] / worst["CLICK_RATE_PCT"]
            st.markdown(
                f'<div class="dq-note">You convert <b>{best["COHORT"]}</b> at '
                f'<b>{best["CLICK_RATE_PCT"]:.1f}%</b> against <b>{worst["CLICK_RATE_PCT"]:.1f}%</b> '
                f'for <b>{worst["COHORT"]}</b> — <b>{ratio:.2f}×</b> the rate. Cohorts below '
                f'1,000 priced quotes are excluded, because a ratio off a small base is noise.</div>',
                unsafe_allow_html=True,
            )

# ---------------------------------------------------------------------------
# Talk to your data
# ---------------------------------------------------------------------------
sec("Talk to your data")


def run_agent(messages: list) -> dict:
    """Call the Cortex Agent over SQL. Container runtime is required for this."""
    fqn = f"{schema}.{AGENT_NAME}"
    row = session.sql(
        "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?) AS R",
        params=[fqn, json.dumps({"messages": messages})],
    ).collect()[0]
    return json.loads(row["R"])


def rows_from_result_set(result_set: dict) -> list:
    meta = (result_set or {}).get("resultSetMetaData", {}) or {}
    cols = [c.get("name") for c in meta.get("rowType", []) or []]
    data = (result_set or {}).get("data", []) or []
    if not data:
        return []
    return [dict(zip(cols, r)) for r in data] if cols else [{"value": r} for r in data]


def render(content: list) -> None:
    """Render the agent's reply.

    Query output is nested inside tool_result -> content[] -> json -> result_set, not in
    a top-level "table" item. Handling only "text" would show the prose and silently
    drop every number.

    SQL is deliberately NOT shown to partners: they get answers, not query internals.
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


with st.container(border=True):
    panel_head("Ask about your performance",
               "Answers are restricted to your own account. Competitor-level detail is "
               "never available.")
    st.caption("Try: *What is my click-out rate?* · *Which customer types do I convert "
               "best?* · *How often am I the cheapest?*")

    if "history" not in st.session_state:
        st.session_state.history = []

    for turn in st.session_state.history:
        with st.chat_message(turn["role"]):
            if turn["role"] == "user":
                st.markdown(turn["display"])
            else:
                render(turn["content"])

    prompt = st.chat_input("Ask about your funnel, premium or how you compare")
    if prompt:
        with st.chat_message("user"):
            st.markdown(prompt)
        wire = [t["wire"] for t in st.session_state.history]
        wire.append({"role": "user", "content": [{"type": "text", "text": prompt}]})
        st.session_state.history.append(
            {"role": "user", "display": prompt, "wire": wire[-1]})

        with st.chat_message("assistant"):
            with st.spinner("Checking your figures…"):
                try:
                    content = run_agent(wire).get("content", [])
                except Exception as exc:  # surface the real error, never hide it
                    st.error(
                        f"The agent call failed: {exc}\n\n"
                        "Most likely causes: the agent does not exist in this schema, "
                        "your default role lacks SNOWFLAKE.CORTEX_AGENT_USER, or you "
                        "have no default warehouse — an agent runs as your DEFAULT role, "
                        "not the role selected here."
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
    'Built with Snowflake Solution Engineering. Sample data is synthetic — the cohort conversion '
    'pattern was generated deliberately and is not a finding about any real insurer.</div>',
    unsafe_allow_html=True,
)
