/* ============================================================================
   Defaqto workshop — teardown

   Removes everything the workshop creates and LEAVES DEFAQTO_DB.RAW UNTOUCHED.
   Run as ACCOUNTADMIN. Safe to re-run.

   What it removes
     - every DEFAQTO_DB.TRANSFORMED_* schema and all its contents:
       dynamic tables, PARTNER_ACCESS, row access policies, the semantic view,
       the Cortex Agent, the Streamlit apps, the APPS stage
     - the Streamlit container services those apps own
     - every PARTNER_* role and the users whose default role is one of them
     - the WORKSHOP workspace
     - suspends the compute pool and the warehouse

   What it deliberately does NOT touch
     - DEFAQTO_DB.RAW and its seven landed tables  <-- the data
     - DEFAQTO_DB itself
     - change tracking on RAW (notebook 01 needs it again next run)
     - @DEFAQTO_DB.PUBLIC.RELOAD_STAGE
     - the dbt project object and DBT_* schemas (see the opt-in block at the end)

   ---------------------------------------------------------------------------
   HOW TO RUN THIS - read before you do
   ---------------------------------------------------------------------------
   This file contains Snowflake Scripting blocks (DECLARE ... BEGIN ... END),
   which contain their own semicolons.

   USE:  Snowsight worksheet - paste the file, Run All.
   USE:  EXECUTE IMMEDIATE FROM @stage/99_teardown.sql;

   DO NOT USE:  snow sql -f 99_teardown.sql
                The CLI splits input on ';' and will cut each block into
                fragments. It fails with "unexpected '<EOF>'" - verified, not
                theoretical. Run the blocks one at a time if you must use it.

   Author: Ketki Kothe (Snowflake Solution Engineering)
============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

/* -- 0. DRY RUN ------------------------------------------------------------ */
/* Run this block ON ITS OWN first. It changes nothing and prints exactly what
   the rest of the file would remove. If the list surprises you, stop. */

DECLARE
    sc CURSOR FOR SELECT SCHEMA_NAME AS n FROM DEFAQTO_DB.INFORMATION_SCHEMA.SCHEMATA
                  WHERE SCHEMA_NAME LIKE 'TRANSFORMED_%';
    schemas ARRAY := ARRAY_CONSTRUCT();
    users   ARRAY := ARRAY_CONSTRUCT();
    roles   ARRAY := ARRAY_CONSTRUCT();
    raw_ct  INT;
BEGIN
    SELECT COUNT(*) INTO raw_ct FROM DEFAQTO_DB.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'RAW' AND TABLE_TYPE = 'BASE TABLE';

    FOR r IN sc DO schemas := ARRAY_APPEND(schemas, r.n); END FOR;

    LET uc CURSOR FOR SELECT "name" AS n FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
                      WHERE "default_role" LIKE 'PARTNER_%';
    SHOW USERS;
    FOR r IN uc DO users := ARRAY_APPEND(users, r.n); END FOR;

    LET rc CURSOR FOR SELECT "name" AS n FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
                      WHERE "name" LIKE 'PARTNER_%';
    SHOW ROLES;
    FOR r IN rc DO roles := ARRAY_APPEND(roles, r.n); END FOR;

    RETURN 'RAW tables kept: '  || raw_ct
        || '  |  schemas to drop: ' || NVL(ARRAY_TO_STRING(schemas, ', '), 'none')
        || '  |  users to drop: '   || NVL(ARRAY_TO_STRING(users,   ', '), 'none')
        || '  |  roles to drop: '   || NVL(ARRAY_TO_STRING(roles,   ', '), 'none');
END;

/* -- Guard: refuse to run if RAW is not intact ----------------------------- */
/* A teardown that runs against a half-built account is how data gets lost.
   This fails loudly rather than proceeding on an account it does not recognise. */

DECLARE
    raw_tables INT;
BEGIN
    SELECT COUNT(*) INTO raw_tables
    FROM   DEFAQTO_DB.INFORMATION_SCHEMA.TABLES
    WHERE  TABLE_SCHEMA = 'RAW' AND TABLE_TYPE = 'BASE TABLE';

    IF (raw_tables <> 7) THEN
        RETURN 'ABORTED: expected 7 tables in DEFAQTO_DB.RAW, found ' ||
               raw_tables || '. Teardown not run.';
    END IF;
    RETURN 'RAW intact (' || raw_tables || ' tables). Safe to proceed.';
END;

/* -- 1. Drop the participant schemas -------------------------------------- */
/* One block handles any number of attendees. DROP SCHEMA CASCADE takes the
   dynamic tables, the semantic view, the agent, the Streamlit apps (and with
   them their container services), the APPS stage, PARTNER_ACCESS and both row
   access policies in one statement each.

   Row access policies are dropped with their schema, so they do not need
   detaching first - every policy and every table it guards live together in
   the same TRANSFORMED_* schema. */

DECLARE
    c CURSOR FOR
        SELECT SCHEMA_NAME
        FROM   DEFAQTO_DB.INFORMATION_SCHEMA.SCHEMATA
        WHERE  SCHEMA_NAME LIKE 'TRANSFORMED_%';
    dropped ARRAY := ARRAY_CONSTRUCT();
BEGIN
    FOR r IN c DO
        EXECUTE IMMEDIATE 'DROP SCHEMA IF EXISTS DEFAQTO_DB."' ||
                          r.SCHEMA_NAME || '" CASCADE';
        dropped := ARRAY_APPEND(dropped, r.SCHEMA_NAME);
    END FOR;
    RETURN 'dropped schemas: ' || ARRAY_TO_STRING(dropped, ', ');
END;

/* -- 2. Drop partner users, then partner roles ---------------------------- */
/* Users first: a role cannot be dropped cleanly while it is somebody's default.
   Users are matched on their default role, not on a name pattern - matching
   '%_USER' would be a coin flip on any account with real logins. */

DECLARE
    c CURSOR FOR
        SELECT "name" AS n
        FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE  "default_role" LIKE 'PARTNER_%';
    dropped ARRAY := ARRAY_CONSTRUCT();
BEGIN
    SHOW USERS;
    FOR r IN c DO
        EXECUTE IMMEDIATE 'DROP USER IF EXISTS "' || r.n || '"';
        dropped := ARRAY_APPEND(dropped, r.n);
    END FOR;
    RETURN 'dropped users: ' || NVL(ARRAY_TO_STRING(dropped, ', '), 'none');
END;

DECLARE
    c CURSOR FOR
        SELECT "name" AS n
        FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE  "name" LIKE 'PARTNER_%';
    dropped ARRAY := ARRAY_CONSTRUCT();
BEGIN
    SHOW ROLES;
    FOR r IN c DO
        EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS "' || r.n || '"';
        dropped := ARRAY_APPEND(dropped, r.n);
    END FOR;
    RETURN 'dropped roles: ' || NVL(ARRAY_TO_STRING(dropped, ', '), 'none');
END;

/* -- 3. Drop the workspace ------------------------------------------------ */
/* Only the shared one. Personal DEFAULT$ workspaces in USER$<name>.PUBLIC are
   left alone - they are not workshop artefacts and dropping them would take
   somebody's own files with them. */

DROP WORKSPACE IF EXISTS DEFAQTO_DB.PUBLIC.WORKSHOP;

/* -- 4. Stand the compute down -------------------------------------------- */
/* Check what else is on the pool before suspending it - it is shared with
   Notebook and Workspace sessions, so it is rarely only yours:
       SHOW SERVICES IN COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU; */

ALTER COMPUTE POOL IF EXISTS SYSTEM_COMPUTE_POOL_CPU SUSPEND;
ALTER WAREHOUSE    IF EXISTS COMPUTE_WH              SUSPEND;

/* -- 5. Verify what is left ----------------------------------------------- */

SHOW SCHEMAS IN DATABASE DEFAQTO_DB;
SELECT "name" AS remaining_schema
FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER  BY 1;

SELECT TABLE_NAME, ROW_COUNT
FROM   DEFAQTO_DB.INFORMATION_SCHEMA.TABLES
WHERE  TABLE_SCHEMA = 'RAW'
ORDER  BY TABLE_NAME;

/* ============================================================================
   OPT-IN: dbt objects
   ----------------------------------------------------------------------------
   Left in place by default. Uncomment only for a completely clean re-test.

   DBT_UNSET_* is the sentinel your generate_schema_name macro writes to when a
   run omits --vars '{alias: ...}'. Leaving it is arguably better than removing
   it: it is visible evidence the guard rail fires.

   DROP SCHEMA IF EXISTS DEFAQTO_DB.DBT_<ALIAS>_MARTS   CASCADE;
   DROP SCHEMA IF EXISTS DEFAQTO_DB.DBT_<ALIAS>_STAGING CASCADE;
   DROP SCHEMA IF EXISTS DEFAQTO_DB.DBT_UNSET_MARTS    CASCADE;
   DROP SCHEMA IF EXISTS DEFAQTO_DB.DBT_UNSET_STAGING  CASCADE;
   DROP DBT PROJECT IF EXISTS DEFAQTO_DB.DBT.DEFAQTO_SALESDB_DBT;
   DROP SCHEMA IF EXISTS DEFAQTO_DB.DBT CASCADE;
============================================================================ */

/* ============================================================================
   OPT-IN: account leftovers unrelated to this project
   ----------------------------------------------------------------------------
   DROP DATABASE  IF EXISTS SNOWFLAKE_LEARNING_DB;
   DROP WAREHOUSE IF EXISTS SNOWFLAKE_LEARNING_WH;
   DROP ROLE      IF EXISTS SNOWFLAKE_LEARNING_ROLE;
   REMOVE @DEFAQTO_DB.PUBLIC.RELOAD_STAGE;   -- 5 of 7 files only, not a backup
============================================================================ */
