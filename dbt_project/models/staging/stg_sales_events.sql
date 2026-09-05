-- Sales events with the sale date derived from DATE_TIME.
--
-- Mike's aggregation groups on CAST(date_time AS DATE), not on the SALE_DATE
-- column, even though the table carries both. That distinction is preserved
-- here deliberately, so this model and his SQL agree by construction.
--
-- Materialised as a VIEW. The Dynamic Table equivalent had to be a table, purely
-- so incremental refresh could track changes against a simple grouping key.
-- dbt rebuilds the mart on each run, so no such workaround is needed and this
-- costs nothing to store.

SELECT
    CAST(date_time AS DATE) AS sale_date,
    quote_id,
    affiliate_id,
    affiliate_name,
    provider_id,
    provider_name,
    producttype_id,
    product_type_name,
    cancellation,
    gwp,
    commission
FROM {{ source('raw', 'SALESDB_SALESEVENTS') }}
