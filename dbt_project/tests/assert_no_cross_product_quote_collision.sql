{{ config(severity = 'warn') }}

-- THIS TEST IS EXPECTED TO WARN. That is the point of it.
--
-- QUOTE_ID is minted per product database, so a Gap quote and a short-term car
-- quote can carry the same number while referring to completely different
-- things. Joining sales to STC_QUOTES on quote_id alone therefore produces
-- matches that are pure coincidence.
--
-- On the current data this finds roughly 10,000 rows carrying about GBP 1.6m of
-- premium - enough to overstate short-term car GWP by more than half if anyone
-- builds that join without filtering on PRODUCTTYPE_ID.
--
-- severity = 'warn' rather than 'error' deliberately. The condition is a fact
-- about the source data, not a defect this project introduced, so it should be
-- surfaced on every run without failing the build. This is precisely the class
-- of problem a Dynamic Table cannot tell you about: dynamic tables compute, they
-- do not assert.

SELECT
    s.producttype_id,
    s.product_type_name,
    COUNT(*)      AS colliding_rows,
    SUM(s.gwp)    AS gwp_wrongly_attributable_to_short_term_car
FROM {{ ref('stg_sales_events') }} s
JOIN {{ source('raw', 'STC_QUOTES') }} q
  ON q.quote_id = s.quote_id
WHERE s.producttype_id <> 11
GROUP BY 1, 2
ORDER BY colliding_rows DESC
