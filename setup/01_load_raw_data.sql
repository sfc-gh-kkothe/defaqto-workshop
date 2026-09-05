/* ============================================================================
   Defaqto workshop — load the RAW layer
   OPTIONAL. Only needed on a fresh account, or to rebuild RAW after a mistake.
   If DEFAQTO_DB.RAW already holds seven tables, skip this file.

   Run as ACCOUNTADMIN, after 00_admin_setup.sql.

   The data is synthetic. Company names are real reference values reused from
   Defaqto's own lists; every transactional row is generated. Nothing here is a
   finding about a real insurer.

   ---------------------------------------------------------------------------
   BEFORE RUNNING: the seed files are not in this repository
   ---------------------------------------------------------------------------
   This repository ships the workshop code, not its data. Supply your own seven
   extracts as gzipped CSVs. Any column layout works - INFER_SCHEMA reads it -
   provided every file carries QUOTE_ID, which is what the notebooks join on.

   Upload them with the Snow CLI, then run this script:

       snow sql -q "CREATE STAGE IF NOT EXISTS DEFAQTO_DB.RAW.SEED"
       snow stage copy <path>/STC_Quotes.csv.gz              @DEFAQTO_DB.RAW.SEED
       snow stage copy <path>/STC_Rates.csv.gz               @DEFAQTO_DB.RAW.SEED
       snow stage copy <path>/STC_Clicks.csv.gz              @DEFAQTO_DB.RAW.SEED
       snow stage copy <path>/STC_Personal_Attributes.csv.gz @DEFAQTO_DB.RAW.SEED
       snow stage copy <path>/STC_CoverDetails.csv.gz        @DEFAQTO_DB.RAW.SEED
       snow stage copy <path>/STC_Vehicles.csv.gz            @DEFAQTO_DB.RAW.SEED
       snow stage copy <path>/SalesDB_SaleEvents.csv.gz      @DEFAQTO_DB.RAW.SEED

   Gzip anything the generator wrote uncompressed first - a rates file at this
   grain is easily 150 MB as plain CSV and a fraction of that gzipped.

   Author: Snowflake Solution Engineering
============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA DEFAQTO_DB.RAW;

CREATE STAGE IF NOT EXISTS DEFAQTO_DB.RAW.SEED
    COMMENT = 'Seed extracts for the workshop. Load once, then read only.';

CREATE OR REPLACE FILE FORMAT DEFAQTO_DB.RAW.SEED_CSV
    TYPE                         = CSV
    FIELD_DELIMITER              = ','
    SKIP_HEADER                  = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                      = ('', 'NULL', 'null', '\\N')
    EMPTY_FIELD_AS_NULL          = TRUE
    TRIM_SPACE                   = TRUE
    COMPRESSION                  = GZIP
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
    COMMENT = 'Header row, quoted fields, gzip. Column-count mismatch fails loudly rather than shifting every column silently.';

/* -- Load ------------------------------------------------------------------
   INFER_SCHEMA keeps this file short and means a generator change does not
   also require a DDL change here. The trade-off is that column types are
   inferred, not declared - which is acceptable for a landed layer whose whole
   job is to be a faithful copy of the extract. The silver dynamic tables in
   notebook 01 do the casting.

   MATCH_BY_COLUMN_NAME is not used: these are headerless-by-position extracts
   once SKIP_HEADER consumes the header, so ordinal loading is correct. */

CREATE OR REPLACE TABLE STC_QUOTES              USING TEMPLATE (SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM TABLE(INFER_SCHEMA(LOCATION => '@SEED/STC_Quotes.csv.gz',              FILE_FORMAT => 'SEED_CSV')));
CREATE OR REPLACE TABLE STC_RATES               USING TEMPLATE (SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM TABLE(INFER_SCHEMA(LOCATION => '@SEED/STC_Rates.csv.gz',               FILE_FORMAT => 'SEED_CSV')));
CREATE OR REPLACE TABLE STC_CLICKS              USING TEMPLATE (SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM TABLE(INFER_SCHEMA(LOCATION => '@SEED/STC_Clicks.csv.gz',              FILE_FORMAT => 'SEED_CSV')));
CREATE OR REPLACE TABLE STC_PERSONAL_ATTRIBUTES USING TEMPLATE (SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM TABLE(INFER_SCHEMA(LOCATION => '@SEED/STC_Personal_Attributes.csv.gz', FILE_FORMAT => 'SEED_CSV')));
CREATE OR REPLACE TABLE STC_COVERDETAILS        USING TEMPLATE (SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM TABLE(INFER_SCHEMA(LOCATION => '@SEED/STC_CoverDetails.csv.gz',        FILE_FORMAT => 'SEED_CSV')));
CREATE OR REPLACE TABLE STC_VEHICLES            USING TEMPLATE (SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM TABLE(INFER_SCHEMA(LOCATION => '@SEED/STC_Vehicles.csv.gz',            FILE_FORMAT => 'SEED_CSV')));
CREATE OR REPLACE TABLE SALESDB_SALESEVENTS     USING TEMPLATE (SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM TABLE(INFER_SCHEMA(LOCATION => '@SEED/SalesDB_SaleEvents.csv.gz',      FILE_FORMAT => 'SEED_CSV')));

COPY INTO STC_QUOTES              FROM '@SEED/STC_Quotes.csv.gz'              FILE_FORMAT = (FORMAT_NAME = 'SEED_CSV');
COPY INTO STC_RATES               FROM '@SEED/STC_Rates.csv.gz'               FILE_FORMAT = (FORMAT_NAME = 'SEED_CSV');
COPY INTO STC_CLICKS              FROM '@SEED/STC_Clicks.csv.gz'              FILE_FORMAT = (FORMAT_NAME = 'SEED_CSV');
COPY INTO STC_PERSONAL_ATTRIBUTES FROM '@SEED/STC_Personal_Attributes.csv.gz' FILE_FORMAT = (FORMAT_NAME = 'SEED_CSV');
COPY INTO STC_COVERDETAILS        FROM '@SEED/STC_CoverDetails.csv.gz'        FILE_FORMAT = (FORMAT_NAME = 'SEED_CSV');
COPY INTO STC_VEHICLES            FROM '@SEED/STC_Vehicles.csv.gz'            FILE_FORMAT = (FORMAT_NAME = 'SEED_CSV');
COPY INTO SALESDB_SALESEVENTS     FROM '@SEED/SalesDB_SaleEvents.csv.gz'      FILE_FORMAT = (FORMAT_NAME = 'SEED_CSV');

/* -- Change tracking for the dynamic tables -------------------------------- */

ALTER TABLE STC_QUOTES              SET CHANGE_TRACKING = TRUE;
ALTER TABLE STC_RATES               SET CHANGE_TRACKING = TRUE;
ALTER TABLE STC_CLICKS              SET CHANGE_TRACKING = TRUE;
ALTER TABLE STC_PERSONAL_ATTRIBUTES SET CHANGE_TRACKING = TRUE;
ALTER TABLE STC_COVERDETAILS        SET CHANGE_TRACKING = TRUE;
ALTER TABLE STC_VEHICLES            SET CHANGE_TRACKING = TRUE;
ALTER TABLE SALESDB_SALESEVENTS     SET CHANGE_TRACKING = TRUE;

/* -- Verify the load ------------------------------------------------------ */
/* Row counts are whatever your extracts contain. What matters is that all seven
   tables exist and none is empty - an empty table here produces a silently
   wrong funnel three notebooks later rather than an error. */

SELECT TABLE_NAME,
       ROW_COUNT,
       IFF(ROW_COUNT > 0, 'ok', 'EMPTY - fix before running the notebooks') AS status
FROM   DEFAQTO_DB.INFORMATION_SCHEMA.TABLES
WHERE  TABLE_SCHEMA = 'RAW'
ORDER  BY status DESC, TABLE_NAME;

/* Expect seven rows. Fewer means a COPY INTO silently matched no files - check
   the stage path and the .gz extension. */
SELECT COUNT(*) AS tables_loaded
FROM   DEFAQTO_DB.INFORMATION_SCHEMA.TABLES
WHERE  TABLE_SCHEMA = 'RAW' AND TABLE_TYPE = 'BASE TABLE';
