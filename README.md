---
# Front matter for workshop catalogues. Keep accurate.
title: Defaqto Workshop — Short-Term Insurance 360
audience: Data engineers, analysts, technical champions
level: Intermediate
duration: Half day (~4 hours)
features: Dynamic Tables, Semantic Views, Cortex Agent, Row Access Policies, Streamlit on Container Runtime, dbt Projects
summary: Attendees turn seven raw insurance extracts into a governed analytics layer - dynamic tables, a semantic view, a Cortex Agent, and two dashboards - each in their own schema, then prove partner isolation with a row access policy.
---

# Defaqto Workshop — Short-Term Insurance 360

> **One-liner:** By the end, each attendee has built a six-stage quote funnel from seven raw
> extracts using Dynamic Tables, exposed it through a Semantic View and a Cortex Agent, and
> proved with a Row Access Policy that one insurer sees only itself.

> **Data is not included in this repository.** See [Data](#data) below. The lab needs seven
> tables in `DEFAQTO_DB.RAW`; supplying them is a prerequisite, not a step.

## Who it's for

- **Audience:** data engineers and analysts comfortable with SQL. No Snowflake internals assumed.
- **Level:** intermediate.
- **Prerequisites:** a Snowflake login with a **default role and a default warehouse set**, and
  access to Snowsight. Both matter more than they look — a Cortex Agent runs as the caller's
  *default* role, and a user with no roles granted cannot complete module 4.

## What they build

Seven landed extracts describing short-term motor insurance quotes — quotes, insurer rate
responses, click-outs, driver and vehicle detail, and sales — become:

| Layer | Objects | What it gives you |
|---|---|---|
| Silver | 7 dynamic tables | one row per quote, per rate, per quote-and-insurer pair |
| Gold | 3 dynamic tables | daily funnel, insurer scorecard, conversion by customer type |
| Semantic | 1 semantic view + 1 Cortex Agent | ask the funnel questions in English |
| Governed | row access policy + partner role/user | one insurer sees one insurer |
| Apps | 2 Streamlit apps | internal whole-market view, and a partner view |

The point that lands: **a large share of quote journeys end before any insurer is asked for a
price**, and nothing in the source systems makes that visible.

Each attendee works in their **own** `TRANSFORMED_<alias>` schema, so nobody overwrites anyone.

## Modules

| # | Notebook | Outcome | Time |
|---|---|---|---|
| 1 | `notebooks/01_explore_and_build_dynamic_tables.ipynb` | 7 silver + 3 gold dynamic tables | 50 min |
| 2 | `notebooks/02_dbt_project.ipynb` | the same transforms as a dbt project (optional) | 30 min |
| 3 | `notebooks/03_semantic_view_talk_to_your_data.ipynb` | semantic view + Cortex Agent | 45 min |
| 4 | `notebooks/04_row_access_policy.ipynb` | role, user, policy, and the isolation proof | 25 min |

Run them in order. Each begins with an alias cell — **edit it** before running anything else.

## Setup (facilitator)

Run once as `ACCOUNTADMIN`, before the room arrives:

| Script | Purpose |
|---|---|
| `setup/00_admin_setup.sql` | database, `RAW` schema, warehouse, workshop role, cross-region inference, PyPI grant |
| `setup/01_load_raw_data.sql` | load `RAW` from your own seed files (see [Data](#data)) |
| `setup/02_deploy_streamlits.sql` | deploy both dashboards from this repo or a stage |
| `setup/99_teardown.sql` | remove everything the workshop creates, **keep `RAW`** |

Two account-level prerequisites are easy to miss and both fail confusingly:

- `CORTEX_ENABLED_CROSS_REGION` — without it the agent cannot reach a model in regions where
  not every model is resident.
- `SNOWFLAKE.PYPI_REPOSITORY_USER` — without it a container-runtime Streamlit app fails to
  **build**, with an artifact-repository error rather than a permission error.

Attendees open the notebooks via **Projects » Workspaces » Create Workspace » From Git
repository**, pointed at this repo. That flow is Snowsight-only; there is no DDL for it.

## Data

The seed extracts are **not distributed with this repository**. Supply seven tables in
`DEFAQTO_DB.RAW`:

```
STC_QUOTES               one row per quote journey
STC_RATES                one row per insurer response per quote
STC_CLICKS               click-outs to insurer sites
STC_PERSONAL_ATTRIBUTES  driver detail
STC_COVERDETAILS         cover requested
STC_VEHICLES             vehicle detail
SALESDB_SALESEVENTS      policies sold
```

`setup/01_load_raw_data.sql` loads them from a stage and infers the schema, so column layout is
yours to choose. The notebooks join on `QUOTE_ID` throughout.

Any figures quoted in the notebooks describe the dataset they were written against. **Expect
your own numbers to differ**, and treat every insurer-level result as an illustration of the
capability rather than a finding about a real company.

## Gotchas worth knowing before you run it

These each cost real debugging time.

- **`CREATE OR REPLACE DYNAMIC TABLE` silently detaches row access policies and drops both
  normal and CALLER grants.** Re-running module 1 after module 4 leaves the partner app showing
  everything, or nothing, with no error anywhere. Re-run module 4 from `attach_policy` onward.
- **Caller's rights uses the viewer's *default* role**, not the role selected in Snowsight.
- **On container runtime all viewers share one app instance**, and `st.cache_data` is global to
  it. A cache key that omits `CURRENT_ROLE()` will serve the first viewer's rows to everyone,
  bypassing row access policies entirely. Both apps here include the role in the key.
- **`pyproject.toml` is mandatory** on container runtime. Without it the app will not start.
- **`FROM` copies files once.** A later push or upload does not update a deployed app — add a
  version instead of using `CREATE OR REPLACE`, which drops the grants.
- **`ARTIFACT_REPOSITORIES` shows in `SHOW STREAMLITS` but reads as `None` in `DESCRIBE`.**
- **`IDENTIFIER()` accepts a plain session variable but not a concatenated expression** in a
  `GRANT`. Build the full name into a variable first.
- **A row access policy body resolves unqualified names against the policy's own schema**, so
  `FROM PARTNER_ACCESS a` follows each attendee automatically. Do not qualify it, and do not
  use `IDENTIFIER()` inside a policy body.
- **`snow sql -f` cannot run Snowflake Scripting blocks** — it splits input on `;`. Use a
  Snowsight worksheet or `EXECUTE IMMEDIATE FROM @stage/...`.

## Teardown

`setup/99_teardown.sql` drops every `TRANSFORMED_*` schema, the partner roles and users, and the
workspace, then suspends the compute pool and warehouse. It **does not touch `DEFAQTO_DB.RAW`**
and refuses to run unless `RAW` holds all seven tables. Run the dry-run block at the top first.

## Repository layout

```
setup/          facilitator SQL, run once, in order
notebooks/      the four attendee notebooks
dbt_project/    the same transforms as dbt, for module 2
streamlit/      two apps, container runtime, pinned dependencies
skills/         optional Cortex Code Desktop extension
```
