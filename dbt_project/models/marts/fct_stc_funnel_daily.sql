-- The short-term car funnel by day.
--
-- Four stages: a journey starts, a provider returns a usable price, the shopper
-- clicks out to that provider, and a sale comes back. Only about half of
-- journeys ever receive a price at all, which is invisible if you look only at
-- the sales data.
--
-- ONE THING TO NOTE IN THE SALES CTE BELOW: the filter producttype_id = 11 is
-- not optional. QUOTE_ID is minted per product database, so without it, Gap,
-- Bicycle and Home Emergency sales match short-term car quote IDs by
-- coincidence - roughly 10,000 rows carrying about GBP 1.6m of premium that
-- does not belong to this product. See
-- tests/assert_no_cross_product_quote_collision.sql.

WITH quotes AS (
    SELECT
        CAST(created AS DATE)    AS quote_date,
        COUNT(*)                 AS quotes_started,
        COUNT(DISTINCT quote_id) AS distinct_quotes
    FROM {{ source('raw', 'STC_QUOTES') }}
    GROUP BY 1
),

priced AS (
    -- STATUS = 1 means the provider returned a price. STATUS = 3 is a decline,
    -- and declines carry PRICE = 0, so both conditions are needed.
    SELECT
        CAST(q.created AS DATE)    AS quote_date,
        COUNT(DISTINCT r.quote_id) AS quotes_priced
    FROM {{ source('raw', 'STC_RATES') }} r
    JOIN {{ source('raw', 'STC_QUOTES') }} q
      ON q.quote_id = r.quote_id
    WHERE r.status = 1
      AND r.price > 0
    GROUP BY 1
),

clicked AS (
    SELECT
        CAST(q.created AS DATE)    AS quote_date,
        COUNT(DISTINCT c.quote_id) AS quotes_clicked
    FROM {{ source('raw', 'STC_CLICKS') }} c
    JOIN {{ source('raw', 'STC_QUOTES') }} q
      ON q.quote_id = c.quote_id
    GROUP BY 1
),

sold AS (
    SELECT
        CAST(q.created AS DATE)    AS quote_date,
        COUNT(DISTINCT s.quote_id) AS quotes_sold,
        SUM(s.gwp)                 AS gwp,
        SUM(s.commission)          AS commission
    FROM {{ ref('stg_sales_events') }} s
    JOIN {{ source('raw', 'STC_QUOTES') }} q
      ON q.quote_id = s.quote_id
    WHERE s.producttype_id = 11        -- REQUIRED. See the note at the top.
      AND s.cancellation = 0
    GROUP BY 1
)

SELECT
    q.quote_date,
    q.quotes_started,
    COALESCE(p.quotes_priced,  0) AS quotes_priced,
    COALESCE(c.quotes_clicked, 0) AS quotes_clicked,
    COALESCE(s.quotes_sold,    0) AS quotes_sold,
    COALESCE(s.gwp,        0)     AS gwp,
    COALESCE(s.commission, 0)     AS commission,
    ROUND(COALESCE(p.quotes_priced,  0) / NULLIF(q.quotes_started, 0), 4) AS price_rate,
    ROUND(COALESCE(c.quotes_clicked, 0) / NULLIF(p.quotes_priced,  0), 4) AS clickout_rate,
    ROUND(COALESCE(s.quotes_sold,    0) / NULLIF(c.quotes_clicked, 0), 4) AS conversion_rate
FROM quotes q
LEFT JOIN priced  p ON p.quote_date = q.quote_date
LEFT JOIN clicked c ON c.quote_date = q.quote_date
LEFT JOIN sold    s ON s.quote_date = q.quote_date
