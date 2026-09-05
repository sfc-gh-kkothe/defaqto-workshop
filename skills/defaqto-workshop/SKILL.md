---
name: defaqto-workshop
description: Extend the Defaqto short-term insurance workshop - add a panel to either Streamlit dashboard, add a metric or verified query to the semantic view, or add a dynamic table to the pipeline. Use when working inside this repository.
---

# Extending the Defaqto workshop

Optional. The workshop runs from `notebooks/` without this skill.

## Before changing anything

Read `README.md`, particularly the gotchas. Several are non-obvious and will waste an
afternoon: recreating a dynamic table drops its grants and detaches its policies, container
Streamlit shares one instance across viewers, and `IDENTIFIER()` will not take a concatenated
expression in a `GRANT`.

## Adding a panel to a dashboard

Both apps in `streamlit/` are single-file and follow the same shape: a brand palette, a
registered Altair theme, KPI cards, then panels built with `st.container(border=True)`.

1. Query through the existing `q(sql, role)` helper. **Always pass `MY_ROLE`.** Omitting it
   reintroduces a cross-user cache leak that bypasses row access policies.
2. Read from the gold dynamic tables, never from silver — silver has no policies on it.
3. Put a volume floor on any ratio. A high lift computed over a few dozen quotes is noise
   presented as a finding.
4. Redeploy by adding a version, not with `CREATE OR REPLACE`, which drops every grant.
   See section 5 of `setup/02_deploy_streamlits.sql`.

## Adding to the semantic view

Notebook 03 owns the DDL. It uses `CREATE OR ALTER`, so re-running preserves grants.

- A ratio of two aggregates must be a **derived** metric — no table prefix. Get this wrong and
  you silently average averages.
- Dimension names must be unique across the whole view, not just per table.
- Verified query SQL must be **fully qualified**. It is stored as an opaque string and never
  validated at create time, so a bad reference is accepted silently and only fails when a user
  clicks the question.

## Adding a dynamic table

Follow the existing pattern in notebook 01: `TARGET_LAG = 'DOWNSTREAM'` for silver, an explicit
lag on gold, and `REFRESH_MODE = 'INCREMENTAL'`. Check `refresh_mode_reason` in
`SHOW DYNAMIC TABLES` afterwards — if Snowflake fell back to a full refresh it tells you there,
and nowhere else.
