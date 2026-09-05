/* ============================================================================
   Defaqto workshop — shared admin setup
   Run ONCE as ACCOUNTADMIN before the room arrives.

   Creates only the objects participants READ but never create. Everything a
   participant builds (their own TRANSFORMED_<alias> schema, dynamic tables,
   semantic view, agent, role, policy, Streamlit) is created by the notebooks,
   so nothing here can be overwritten mid-workshop.

   Idempotent: safe to re-run. Uses IF NOT EXISTS / OR ALTER throughout, and
   never touches DEFAQTO_DB.RAW data.

   Prerequisite: DEFAQTO_DB.RAW already holds the seven landed tables. If this
   is a fresh account, run setup/01_load_raw_data.sql FIRST.

   Author: Ketki Kothe (Snowflake Solution Engineering)
============================================================================ */

USE ROLE ACCOUNTADMIN;

/* -- 1. Account-level features -------------------------------------------- */

-- Cortex Analyst and Agents need inference available. The workshop account is
-- Azure UK South, where not every model is resident, so allow cross-region.
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- Container-runtime Streamlit pins its dependencies from Snowflake's own PyPI
-- mirror. Without this grant the apps fail to build with a repository error,
-- and there is no external access integration to fall back on.
GRANT DATABASE ROLE SNOWFLAKE.PYPI_REPOSITORY_USER TO ROLE ACCOUNTADMIN;

/* -- 2. Database and the read-only landed layer ---------------------------- */

CREATE DATABASE IF NOT EXISTS DEFAQTO_DB
    COMMENT = 'Defaqto short-term insurance workshop. RAW is read-only; each attendee builds their own TRANSFORMED_<alias>.';

CREATE SCHEMA IF NOT EXISTS DEFAQTO_DB.RAW
    COMMENT = 'Landed extracts, read only. Nobody writes here during the workshop.';

CREATE SCHEMA IF NOT EXISTS DEFAQTO_DB.PUBLIC;

-- Dynamic tables read RAW incrementally, which requires change tracking on the
-- source. Enabling it here rather than in notebook 01 means the first attendee
-- to run does not pay the initialisation cost for everyone else.
ALTER TABLE IF EXISTS DEFAQTO_DB.RAW.STC_QUOTES              SET CHANGE_TRACKING = TRUE;
ALTER TABLE IF EXISTS DEFAQTO_DB.RAW.STC_RATES               SET CHANGE_TRACKING = TRUE;
ALTER TABLE IF EXISTS DEFAQTO_DB.RAW.STC_CLICKS              SET CHANGE_TRACKING = TRUE;
ALTER TABLE IF EXISTS DEFAQTO_DB.RAW.STC_PERSONAL_ATTRIBUTES SET CHANGE_TRACKING = TRUE;
ALTER TABLE IF EXISTS DEFAQTO_DB.RAW.STC_COVERDETAILS        SET CHANGE_TRACKING = TRUE;
ALTER TABLE IF EXISTS DEFAQTO_DB.RAW.STC_VEHICLES            SET CHANGE_TRACKING = TRUE;
ALTER TABLE IF EXISTS DEFAQTO_DB.RAW.SALESDB_SALESEVENTS     SET CHANGE_TRACKING = TRUE;

/* -- 3. Shared compute ---------------------------------------------------- */

CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'Shared workshop warehouse. XSMALL is enough - the heaviest table is 1.5m rows.';

-- Streamlit on container runtime needs a compute pool. SYSTEM_COMPUTE_POOL_CPU
-- exists in every account and is shared with Notebook and Workspace sessions,
-- so it is not created here - only resumed on the morning.
-- ALTER COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU RESUME;

/* -- 4. Workshop role ----------------------------------------------------- */
/* On this account every attendee currently defaults to ACCOUNTADMIN, so this
   role is optional today. It is the right shape for any other account, and it
   is what lets you hand the repo to another SE. */

CREATE ROLE IF NOT EXISTS DEFAQTO_HOL_ROLE
    COMMENT = 'Workshop participant role. Reads RAW, creates its own TRANSFORMED_<alias>.';

GRANT USAGE   ON DATABASE DEFAQTO_DB                TO ROLE DEFAQTO_HOL_ROLE;
GRANT USAGE   ON SCHEMA   DEFAQTO_DB.RAW            TO ROLE DEFAQTO_HOL_ROLE;
GRANT SELECT  ON ALL    TABLES IN SCHEMA DEFAQTO_DB.RAW TO ROLE DEFAQTO_HOL_ROLE;
GRANT SELECT  ON FUTURE TABLES IN SCHEMA DEFAQTO_DB.RAW TO ROLE DEFAQTO_HOL_ROLE;

-- Each attendee creates their own schema, so they need CREATE SCHEMA on the db.
GRANT CREATE SCHEMA ON DATABASE DEFAQTO_DB TO ROLE DEFAQTO_HOL_ROLE;

GRANT USAGE, OPERATE ON WAREHOUSE COMPUTE_WH TO ROLE DEFAQTO_HOL_ROLE;
GRANT USAGE ON COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU TO ROLE DEFAQTO_HOL_ROLE;

-- Cortex Analyst / Agent usage, and the PyPI mirror for container Streamlit.
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER            TO ROLE DEFAQTO_HOL_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER      TO ROLE DEFAQTO_HOL_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.PYPI_REPOSITORY_USER   TO ROLE DEFAQTO_HOL_ROLE;

GRANT ROLE DEFAQTO_HOL_ROLE TO ROLE SYSADMIN;

/* -- 5. Per-attendee provisioning ----------------------------------------- */
/* Notebook 04 has each attendee create a role and a user, so nothing is
   pre-created here. What DOES need to be true before Tuesday is that every
   attendee has a default role and a default warehouse - an agent runs as the
   caller's DEFAULT role, and a user with no roles cannot create one.

   Verify, do not assume:
       SHOW USERS;
   then for anyone missing a default:
       ALTER USER <name> SET DEFAULT_ROLE = ACCOUNTADMIN,
                             DEFAULT_WAREHOUSE = COMPUTE_WH;
   Grant the role too - DEFAULT_ROLE is only a preference, not a grant:
       GRANT ROLE DEFAQTO_HOL_ROLE TO USER <name>;
*/

/* -- 6. Workspace from Git ------------------------------------------------ */
/* Attendees open the notebooks via Projects > Workspaces > Create Workspace >
   From Git repository. That is a Snowsight-only flow - there is no CREATE
   WORKSPACE ... FROM GIT DDL - so it cannot be scripted here.

   If you would rather pre-load the notebooks instead, create the workspace and
   upload them:
       CREATE WORKSPACE IF NOT EXISTS DEFAQTO_DB.PUBLIC.WORKSHOP;
       -- then: cortex ws upload ... && ALTER WORKSPACE ... COMMIT;
   Uploads land in `live` and are invisible to others until committed.
*/

/* -- 7. Verify ------------------------------------------------------------ */

-- There is no SYSTEM$GET_PARAMETER_VALUE function, so read the parameter with
-- SHOW rather than a scalar call.
SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;

-- The seven landed tables and their row counts. These are what every figure in
-- the lineage diagram and both dashboards is derived from.
SELECT TABLE_NAME, ROW_COUNT
FROM   DEFAQTO_DB.INFORMATION_SCHEMA.TABLES
WHERE  TABLE_SCHEMA = 'RAW'
ORDER  BY TABLE_NAME;

-- CHANGE_TRACKING is not a column on INFORMATION_SCHEMA.TABLES - it is only
-- reported by SHOW. Confirm all seven read ON:
SHOW TABLES IN SCHEMA DEFAQTO_DB.RAW;

SHOW GRANTS TO ROLE DEFAQTO_HOL_ROLE;
