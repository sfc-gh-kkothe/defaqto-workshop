-- INVARIANT: distinct quotes can never exceed row count within a group.
--
-- This should always pass. It is here as the counterpart to the collision test:
-- it proves the aggregate is internally consistent, so when someone sums
-- DISTINCT_QUOTES across rows and gets a number larger than the true distinct
-- count, the aggregate is not at fault - the summing is.
--
-- A dbt test returns the OFFENDING rows. Zero rows returned means PASS.

SELECT
    sale_date,
    affiliate_id,
    provider_id,
    product_type_id,
    cancellation,
    row_count,
    distinct_quotes
FROM {{ ref('salesdb_aggregate') }}
WHERE distinct_quotes > row_count
