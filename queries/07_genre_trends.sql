-- =============================================================================
-- Query 07: Genre Trends Over Time (Year-over-Year)
-- File: queries/07_genre_trends.sql
-- Database: MySQL 8.0+
-- =============================================================================
--
-- BUSINESS QUESTION:
--   Which genres are growing in popularity year over year, and which are
--   in decline?  How does each genre's share of total checkouts shift?
--
-- PURPOSE:
--   Use the LAG() window function to compare each genre's annual checkout
--   count against the previous year, computing both the absolute change
--   and the percentage change.  Also surfaces the genre's share of the
--   total checkout volume for that year so a growing niche genre can be
--   distinguished from a genuinely dominant one.
--
-- INTERPRETATION:
--   Rising genres (positive yoy_pct_change) signal areas where the
--   collection should be expanded — more titles, more copies.  Declining
--   genres may indicate the collection is stale and needs fresh titles or
--   that patron tastes have simply shifted.  This data directly informs the
--   annual collection development budget allocation.
-- =============================================================================

WITH yearly_genre_checkouts AS (
    -- Step 1: aggregate checkouts per genre per calendar year
    SELECT
        b.genre,
        YEAR(l.checkout_date)   AS checkout_year,
        COUNT(l.id)             AS total_checkouts
    FROM loans    l
    JOIN copies   c ON c.id  = l.copy_id
    JOIN books    b ON b.id  = c.book_id
    GROUP BY
        b.genre,
        YEAR(l.checkout_date)
),

yearly_totals AS (
    -- Step 2: total checkouts per year (for market-share calculation)
    SELECT
        YEAR(checkout_date)   AS checkout_year,
        COUNT(*)              AS year_total
    FROM loans
    GROUP BY YEAR(checkout_date)
),

with_lag AS (
    -- Step 3: attach previous-year count via LAG()
    SELECT
        yg.genre,
        yg.checkout_year,
        yg.total_checkouts,
        LAG(yg.total_checkouts) OVER (
            PARTITION BY yg.genre
            ORDER BY yg.checkout_year
        )                       AS prev_year_checkouts,
        yt.year_total
    FROM yearly_genre_checkouts yg
    JOIN yearly_totals          yt ON yt.checkout_year = yg.checkout_year
)

SELECT
    genre,
    checkout_year,
    total_checkouts,
    prev_year_checkouts,

    -- Absolute year-over-year change
    total_checkouts - prev_year_checkouts                          AS yoy_change,

    -- Percentage year-over-year change
    ROUND(
        100.0 * (total_checkouts - prev_year_checkouts)
        / NULLIF(prev_year_checkouts, 0),
        1
    )                                                              AS yoy_pct_change,

    -- This genre's share of all checkouts in the year
    ROUND(100.0 * total_checkouts / year_total, 2)                 AS genre_share_pct,

    -- Simple trend label for dashboard colouring
    CASE
        WHEN total_checkouts > COALESCE(prev_year_checkouts, 0)    THEN 'growing'
        WHEN total_checkouts < prev_year_checkouts                 THEN 'declining'
        WHEN prev_year_checkouts IS NULL                           THEN 'baseline'
        ELSE 'flat'
    END                                                            AS trend

FROM with_lag
ORDER BY
    genre,
    checkout_year;
