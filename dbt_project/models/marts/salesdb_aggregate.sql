-- The daily sales rollup. Replaces the pre-aggregated SalesDB_Aggregate file.
--
-- Aggregation logic supplied by the Defaqto data lead, unchanged apart from
-- reading the staging model rather than the raw table.
--
-- A note on DISTINCT_QUOTES: it is not additive. SUM(distinct_quotes) across
-- rows does not give the number of distinct quotes, because a single quote can
-- appear under more than one grouping key - a sale and a later cancellation, or
-- a repeat purchase. Anyone who sums it in a BI tool gets a plausible wrong
-- answer. See tests/assert_distinct_quotes_within_row_count.sql.

SELECT
    sale_date,
    affiliate_id,
    affiliate_name,
    provider_id,
    provider_name,
    producttype_id AS product_type_id,
    product_type_name,
    cancellation,
    COUNT(*)                 AS row_count,
    COUNT(DISTINCT quote_id) AS distinct_quotes,
    SUM(gwp)                 AS total_gwp,
    SUM(commission)          AS total_commission
FROM {{ ref('stg_sales_events') }}
GROUP BY
    sale_date,
    affiliate_id,
    affiliate_name,
    provider_id,
    provider_name,
    producttype_id,
    product_type_name,
    cancellation
