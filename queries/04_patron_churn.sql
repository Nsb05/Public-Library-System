-- =============================================================================
-- Query 04: Patron Retention / Churn Analysis
-- File: queries/04_patron_churn.sql
-- Database: MySQL 8.0+
-- =============================================================================
--
-- BUSINESS QUESTION:
--   Which patrons were active library users in the past year (months 7–18 ago)
--   but have not checked out anything in the most recent 6 months?
--
-- PURPOSE:
--   Cohort-style churn analysis using two CTEs:
--     • active_prior_year  — patrons with ≥1 checkout in the window
--                            [18 months ago … 6 months ago]
--     • active_recent      — patrons with ≥1 checkout in the last 6 months
--   Patrons in the first cohort but NOT the second are "churned" — they
--   were once engaged but have since gone quiet.
--
-- INTERPRETATION:
--   These patrons are the best candidates for a re-engagement campaign
--   (e.g., a personalised email highlighting new arrivals in their favourite
--   genre).  The query also surfaces the patron's home branch so the
--   outreach can be coordinated at the branch level.
-- =============================================================================

WITH active_prior_year AS (
    -- Patrons who checked out at least once in the 7–18 month window
    SELECT DISTINCT patron_id
    FROM loans
    WHERE checkout_date BETWEEN
            DATE_SUB(CURDATE(), INTERVAL 18 MONTH)
        AND DATE_SUB(CURDATE(), INTERVAL  6 MONTH)
),

active_recent AS (
    -- Patrons who checked out at least once in the last 6 months
    SELECT DISTINCT patron_id
    FROM loans
    WHERE checkout_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
),

churned AS (
    -- In prior-year cohort but NOT in recent cohort
    SELECT apy.patron_id
    FROM active_prior_year apy
    LEFT JOIN active_recent ar ON ar.patron_id = apy.patron_id
    WHERE ar.patron_id IS NULL
),

patron_genre_preference AS (
    -- Most checked-out genre per patron (for personalised outreach)
    SELECT
        l.patron_id,
        b.genre,
        COUNT(*) AS genre_count,
        ROW_NUMBER() OVER (
            PARTITION BY l.patron_id
            ORDER BY COUNT(*) DESC
        )        AS rn
    FROM loans    l
    JOIN copies   c ON c.id = l.copy_id
    JOIN books    b ON b.id = c.book_id
    GROUP BY l.patron_id, b.genre
)

SELECT
    p.id                                       AS patron_id,
    p.name,
    p.email,
    p.phone,
    br.name                                    AS home_branch,
    br.city,
    MAX(l.checkout_date)                       AS last_checkout_date,
    DATEDIFF(CURDATE(), MAX(l.checkout_date))  AS days_since_last_checkout,
    COUNT(l.id)                                AS total_historical_loans,
    pgp.genre                                  AS favourite_genre

FROM churned          ch
JOIN patrons          p   ON p.id  = ch.patron_id
JOIN branches         br  ON br.id = p.home_branch_id
JOIN loans            l   ON l.patron_id = p.id
LEFT JOIN patron_genre_preference pgp
                       ON pgp.patron_id = p.id AND pgp.rn = 1
WHERE
    p.is_active = TRUE     -- only send to patrons still holding a library card

GROUP BY
    p.id, p.name, p.email, p.phone,
    br.name, br.city, pgp.genre

ORDER BY
    last_checkout_date ASC;  -- longest-lapsed first
