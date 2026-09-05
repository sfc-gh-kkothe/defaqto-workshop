/* ============================================================================
   Deploy the two workshop dashboards
   Run as ACCOUNTADMIN, after 00_admin_setup.sql and after at least one
   attendee has built their gold tables in notebook 01.

   Both apps are CONTAINER runtime for one reason: a Cortex Agent cannot be
   called from a warehouse-runtime Streamlit app. Everything else in them would
   run happily on a warehouse.

   ONE deployment serves every attendee. The apps discover schemas at runtime:

       SHOW SCHEMAS LIKE 'TRANSFORMED_%' IN DATABASE DEFAQTO_DB

   so a viewer sees only the schemas their role has USAGE on. There is no need
   for a per-attendee app, and a per-attendee app would cost one SPCS service
   each on a system compute pool you cannot resize.

   The two apps deliberately differ in whose rights they run with:

     INTERNAL  owner's rights   - an internal analyst sees the whole market
     PARTNER   caller's rights  - the viewer's own role hits the row access
                                  policy, so ZIXTY_USER sees one insurer while
                                  ACCOUNTADMIN sees all seven, from identical
                                  code. This is the point of the app.
============================================================================ */

USE ROLE ACCOUNTADMIN;

/* -- 1. Prerequisites ------------------------------------------------------ */
/* Container runtime installs pinned dependencies from Snowflake's own PyPI
   mirror. Without this grant the app fails to BUILD, with an error about the
   artifact repository rather than anything obviously permission-shaped. */
GRANT DATABASE ROLE SNOWFLAKE.PYPI_REPOSITORY_USER TO ROLE ACCOUNTADMIN;

ALTER COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU RESUME;

CREATE SCHEMA IF NOT EXISTS DEFAQTO_DB.APPS
    COMMENT = 'Workshop dashboards. Kept out of any TRANSFORMED_* schema so a teardown of attendee work does not take the apps with it.';

USE SCHEMA DEFAQTO_DB.APPS;

/* -- 2. Source files ------------------------------------------------------- */
/* Two ways in. Pick one.

   PATH A - from this Git repository. No upload step at all.
            Needs a secret holding a PAT if the repository is private.

   PATH B - from a stage. No secret, but you upload with the Snow CLI first.

   Path B is uncommented because it needs no credential in the account.
   Swap the FROM clauses in section 3 if you use Path A.
*/

---- PATH A ------------------------------------------------------------------
-- CREATE OR REPLACE SECRET GH_PAT
--   TYPE = PASSWORD USERNAME = '<github-user>' PASSWORD = '<personal-access-token>';
--
-- CREATE OR REPLACE API INTEGRATION GITHUB_DEFAQTO
--   API_PROVIDER = git_https_api
--   API_ALLOWED_PREFIXES = ('https://github.com/<owner>')
--   ALLOWED_AUTHENTICATION_SECRETS = (DEFAQTO_DB.APPS.GH_PAT)
--   ENABLED = TRUE;
--
-- CREATE OR REPLACE GIT REPOSITORY WORKSHOP_REPO
--   API_INTEGRATION = GITHUB_DEFAQTO
--   GIT_CREDENTIALS = DEFAQTO_DB.APPS.GH_PAT
--   ORIGIN = 'https://github.com/<owner>/defaqto-workshop.git';
--
-- ALTER GIT REPOSITORY WORKSHOP_REPO FETCH;
--
-- Then the FROM clauses below become:
--   FROM '@DEFAQTO_DB.APPS.WORKSHOP_REPO/branches/main/streamlit/internal_mi/'
--   FROM '@DEFAQTO_DB.APPS.WORKSHOP_REPO/branches/main/streamlit/partner_insights/'

---- PATH B ------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS DEFAQTO_DB.APPS.SRC
    DIRECTORY = (ENABLE = TRUE)
    COMMENT   = 'Streamlit source. Upload with: snow stage copy streamlit/<app>/ @DEFAQTO_DB.APPS.SRC/<app>/ --overwrite';

/* Upload from the repository root before continuing:

     snow stage copy streamlit/internal_mi/streamlit_app.py       @DEFAQTO_DB.APPS.SRC/internal_mi/       --overwrite
     snow stage copy streamlit/internal_mi/pyproject.toml         @DEFAQTO_DB.APPS.SRC/internal_mi/       --overwrite
     snow stage copy streamlit/partner_insights/streamlit_app.py  @DEFAQTO_DB.APPS.SRC/partner_insights/  --overwrite
     snow stage copy streamlit/partner_insights/pyproject.toml    @DEFAQTO_DB.APPS.SRC/partner_insights/  --overwrite

   pyproject.toml is NOT optional on container runtime. Without it the app
   fails to start with "Installing dependencies failed because the
   pyproject.toml file does not exist." */

LIST @DEFAQTO_DB.APPS.SRC;   -- expect 4 files before you go on

/* -- 3. Create the apps --------------------------------------------------- */
/* FROM copies the files ONCE, at create time. A later upload or git push does
   NOT update a deployed app - see section 5 for how to update one. */

CREATE STREAMLIT IF NOT EXISTS DEFAQTO_DB.APPS.DEFAQTO_INTERNAL_MI
    FROM '@DEFAQTO_DB.APPS.SRC/internal_mi/'
    MAIN_FILE             = 'streamlit_app.py'
    QUERY_WAREHOUSE       = COMPUTE_WH
    RUNTIME_NAME          = 'SYSTEM$ST_CONTAINER_RUNTIME_PY3_11'
    COMPUTE_POOL          = SYSTEM_COMPUTE_POOL_CPU
    ARTIFACT_REPOSITORIES = (snowflake.snowpark.pypi_shared_repository)
    TITLE                 = 'Defaqto Internal MI'
    COMMENT               = 'Whole-market view. Owner rights: an internal analyst sees every insurer.';

CREATE STREAMLIT IF NOT EXISTS DEFAQTO_DB.APPS.DEFAQTO_PARTNER_INSIGHTS
    FROM '@DEFAQTO_DB.APPS.SRC/partner_insights/'
    MAIN_FILE             = 'streamlit_app.py'
    QUERY_WAREHOUSE       = COMPUTE_WH
    RUNTIME_NAME          = 'SYSTEM$ST_CONTAINER_RUNTIME_PY3_11'
    COMPUTE_POOL          = SYSTEM_COMPUTE_POOL_CPU
    ARTIFACT_REPOSITORIES = (snowflake.snowpark.pypi_shared_repository)
    TITLE                 = 'Defaqto Partner Insights'
    COMMENT               = 'Partner view. Caller rights: the row access policy decides what exists. No filtering logic in the app.';

/* An app is NOT live until a live version exists. Skip this and it works for
   the owner and nobody else. */
ALTER STREAMLIT DEFAQTO_DB.APPS.DEFAQTO_INTERNAL_MI      ADD LIVE VERSION FROM LAST;
ALTER STREAMLIT DEFAQTO_DB.APPS.DEFAQTO_PARTNER_INSIGHTS ADD LIVE VERSION FROM LAST;

/* -- 4. Grants ------------------------------------------------------------ */
/* Container-runtime apps need THREE grants per viewer role, not one: the
   Streamlit, the service behind it, and the service's STREAMLIT_VIEWER role.
   Service names are generated, so they are read back rather than hard-coded. */

GRANT USAGE ON STREAMLIT DEFAQTO_DB.APPS.DEFAQTO_INTERNAL_MI      TO ROLE DEFAQTO_HOL_ROLE;
GRANT USAGE ON STREAMLIT DEFAQTO_DB.APPS.DEFAQTO_PARTNER_INSIGHTS TO ROLE DEFAQTO_HOL_ROLE;

/* For each partner role created in notebook 04, run these three, substituting
   the role name and the service name from the query below:

     SHOW SERVICES IN COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU;

     GRANT USAGE ON STREAMLIT    DEFAQTO_DB.APPS.DEFAQTO_PARTNER_INSIGHTS TO ROLE PARTNER_<X>;
     GRANT USAGE ON SERVICE      DEFAQTO_DB.APPS.<service_name>           TO ROLE PARTNER_<X>;
     GRANT USAGE ON SERVICE ROLE DEFAQTO_DB.APPS.<service_name>.STREAMLIT_VIEWER TO ROLE PARTNER_<X>;

   The partner app also needs CALLER grants on each attendee's tables. Those are
   granted by the attendee, in notebook 04, because they own the tables. */

/* -- 5. Updating a deployed app ------------------------------------------- */
/* Do NOT use CREATE OR REPLACE. It drops the live version AND every grant
   above, including the caller grants, and the app then fails for everyone but
   the owner. Add a version instead - grants survive:

     -- after re-uploading to the stage, or after ALTER GIT REPOSITORY ... FETCH
     ALTER STREAMLIT DEFAQTO_DB.APPS.DEFAQTO_PARTNER_INSIGHTS
       ADD VERSION FROM '@DEFAQTO_DB.APPS.SRC/partner_insights/';
     ALTER STREAMLIT DEFAQTO_DB.APPS.DEFAQTO_PARTNER_INSIGHTS
       ADD LIVE VERSION FROM LAST;

   For a git-sourced app, ALTER STREAMLIT ... PULL does the same in one step.

   All viewers share one container instance, so the new code takes effect when
   that instance restarts. If you still see the old behaviour, suspend and
   resume the compute pool to force a fresh instance. */

/* -- 6. Verify ------------------------------------------------------------ */
/* ARTIFACT_REPOSITORIES appears in SHOW but is reported as None by DESCRIBE.
   Check it here or you will conclude it was never attached. */
SHOW STREAMLITS IN SCHEMA DEFAQTO_DB.APPS;
SHOW SERVICES   IN COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU;
