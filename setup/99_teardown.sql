/* ============================================================================
   Teardown — simple version

   Plain DROP statements, in dependency order, for ONE person's workshop objects.
   Reads top to bottom. No scripting blocks, so this runs anywhere:
   a Snowsight worksheet, or snow sql -f.

   Leaves DEFAQTO_DB.RAW alone. That is the only thing worth keeping.

   Change ONE line - the schema on line 20 - then run the whole file.

   For several attendees at once, use 99b_teardown_all_attendees.sql instead.
============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- >>> THE ONLY LINE TO EDIT <<<
USE SCHEMA DEFAQTO_DB.TRANSFORMED_KKOTHE;

/* Everything below is unqualified on purpose, so it resolves against the schema
   above and there is nothing else to keep in sync. */


/* -- 1. Streamlit apps ---------------------------------------------------- */
/* First, because each container app owns an SPCS service that holds the compute
   pool busy. Both locations are listed: apps deployed by 02_deploy_streamlits.sql
   live in DEFAQTO_DB.APPS, earlier ones lived in the attendee schema. */

DROP STREAMLIT IF EXISTS DEFAQTO_DB.APPS.DEFAQTO_INTERNAL_MI;
DROP STREAMLIT IF EXISTS DEFAQTO_DB.APPS.DEFAQTO_PARTNER_INSIGHTS;
DROP STREAMLIT IF EXISTS DEFAQTO_INTERNAL_MI_SIMPLE;
DROP STREAMLIT IF EXISTS DEFAQTO_PARTNER_INSIGHTS_SIMPLE;


/* -- 2. Agent and semantic view ------------------------------------------- */
/* Agent first: it references the semantic view. */

DROP AGENT         IF EXISTS DEFAQTO_ANALYST;
DROP SEMANTIC VIEW IF EXISTS DEFAQTO_INSIGHTS;


/* -- 3. Row access policies ----------------------------------------------- */
/* Detach before dropping. A policy cannot be dropped while it is attached, and
   DROP ALL is a no-op on a table with none - so this is safe either way. */

ALTER DYNAMIC TABLE IF EXISTS GOLD_PROVIDER_DAILY    DROP ALL ROW ACCESS POLICIES;
ALTER DYNAMIC TABLE IF EXISTS GOLD_COHORT_CONVERSION DROP ALL ROW ACCESS POLICIES;
ALTER DYNAMIC TABLE IF EXISTS GOLD_FUNNEL_DAILY      DROP ALL ROW ACCESS POLICIES;

DROP ROW ACCESS POLICY IF EXISTS PROVIDER_RAP;
DROP ROW ACCESS POLICY IF EXISTS PCW_RAP;


/* -- 4. Gold dynamic tables ----------------------------------------------- */
/* Gold before silver: a dynamic table cannot be dropped while another one reads
   from it. */

DROP DYNAMIC TABLE IF EXISTS GOLD_COHORT_CONVERSION;
DROP DYNAMIC TABLE IF EXISTS GOLD_PROVIDER_DAILY;
DROP DYNAMIC TABLE IF EXISTS GOLD_FUNNEL_DAILY;


/* -- 5. Silver dynamic tables --------------------------------------------- */
/* Reverse dependency order:
       SILVER_PROVIDER  <-  RATES / CLICKS / SALES  <-  QUOTE_PROVIDER  <-  gold
       SILVER_SALES     <-  SILVER_SALESDB_AGGREGATE                            */

DROP DYNAMIC TABLE IF EXISTS SILVER_SALESDB_AGGREGATE;
DROP DYNAMIC TABLE IF EXISTS SILVER_QUOTE_PROVIDER;
DROP DYNAMIC TABLE IF EXISTS SILVER_SALES;
DROP DYNAMIC TABLE IF EXISTS SILVER_CLICKS;
DROP DYNAMIC TABLE IF EXISTS SILVER_RATES;
DROP DYNAMIC TABLE IF EXISTS SILVER_QUOTES;
DROP DYNAMIC TABLE IF EXISTS SILVER_PROVIDER;


/* -- 6. Supporting objects ------------------------------------------------ */

DROP TABLE IF EXISTS PARTNER_ACCESS;
DROP STAGE IF EXISTS APPS;


/* -- 7. Notebooks --------------------------------------------------------- */
/* Notebooks opened from a Workspace are files, not NOTEBOOK objects, so the
   workspace drop in section 9 removes them. Uncomment these only if you also
   created standalone notebooks (Projects > Notebooks). Check first with:
       SHOW NOTEBOOKS IN ACCOUNT;

   DROP NOTEBOOK IF EXISTS DEFAQTO_01_EXPLORE_AND_BUILD_DYNAMIC_TABLES;
   DROP NOTEBOOK IF EXISTS DEFAQTO_02_DBT_PROJECT;
   DROP NOTEBOOK IF EXISTS DEFAQTO_03_SEMANTIC_VIEW_TALK_TO_YOUR_DATA;
   DROP NOTEBOOK IF EXISTS DEFAQTO_04_ROW_ACCESS_POLICY;                      */


/* -- 8. The schema itself ------------------------------------------------- */
/* CASCADE catches anything the sections above missed - a table you added by
   hand, a view, a stage. Everything named so far is listed explicitly anyway,
   so that you can see what the workshop built rather than trusting one line. */

DROP SCHEMA IF EXISTS DEFAQTO_DB.TRANSFORMED_KKOTHE CASCADE;   -- edit to match line 20

-- Apps schema, if you used 02_deploy_streamlits.sql:
DROP SCHEMA IF EXISTS DEFAQTO_DB.APPS CASCADE;


/* -- 9. Workspace --------------------------------------------------------- */
/* This removes the notebooks. Personal DEFAULT$ workspaces in USER$<name>.PUBLIC
   are left alone - they are not workshop objects. */

DROP WORKSPACE IF EXISTS DEFAQTO_DB.PUBLIC.WORKSHOP;


/* -- 10. Partner user and role -------------------------------------------- */
/* User before role: a role cannot be dropped cleanly while it is somebody's
   default. Add a line per insurer you used. */

DROP USER IF EXISTS ZIXTY_USER;
DROP USER IF EXISTS VEYGO_USER;
DROP USER IF EXISTS COVERTIME_USER;

DROP ROLE IF EXISTS PARTNER_ZIXTY;
DROP ROLE IF EXISTS PARTNER_VEYGO;
DROP ROLE IF EXISTS PARTNER_COVERTIME;


/* -- 11. Stand the compute down ------------------------------------------- */
/* Check what else is on the pool first - it is shared with Notebook and
   Workspace sessions, so it is rarely only yours:
       SHOW SERVICES IN COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU;                 */

ALTER COMPUTE POOL IF EXISTS SYSTEM_COMPUTE_POOL_CPU SUSPEND;
ALTER WAREHOUSE    IF EXISTS COMPUTE_WH              SUSPEND;


/* -- 12. Check what is left ----------------------------------------------- */
/* Expect: RAW, PUBLIC, INFORMATION_SCHEMA, and the DBT_* schemas if you kept
   the dbt project. RAW must still hold its seven tables. */

SHOW SCHEMAS IN DATABASE DEFAQTO_DB;

SELECT TABLE_NAME, ROW_COUNT
FROM   DEFAQTO_DB.INFORMATION_SCHEMA.TABLES
WHERE  TABLE_SCHEMA = 'RAW'
ORDER  BY TABLE_NAME;


/* ============================================================================
   NOT removed on purpose
   ----------------------------------------------------------------------------
   DEFAQTO_DB.RAW and its seven tables   the data
   DEFAQTO_DB itself
   Change tracking on RAW                notebook 01 needs it again next time
   COMPUTE_WH                            suspended, not dropped
   DEFAQTO_HOL_ROLE                      created by 00_admin_setup.sql
   The dbt project and DBT_* schemas     see 99b for the opt-in drops
============================================================================ */
