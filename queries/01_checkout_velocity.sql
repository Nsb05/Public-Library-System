-- =============================================================================
-- Query 01: Checkout Velocity Ranking
-- File: queries/01_checkout_velocity.sql
-- Database: MySQL 8.0+
-- =============================================================================
--
-- BUSINESS QUESTION:
--   Which books are being checked out most frequently in the last 12 months?
--
-- PURPOSE:
--   Rank every book title by its total number of checkouts over the past year
--   using DENSE_RANK() so that titles with identical checkout counts share
--   the same rank with no gaps.
--
-- INTERPRETATION:
--   Books at the top of this ranking are in high demand and should be
--   prioritised for additional copy acquisitions or inter-branch transfers.
--   Books at the bottom may be candidates for deaccessioning or weeding.
--   Library managers can filter by genre to understand genre-level demand.
-- =============================================================================

SELECT
    b.id                                                          AS book_id,
    b.title,
    b.author,
    b.genre,
    b.publication_year,
    COUNT(l.id)                                                   AS checkouts_last_12m,
    DENSE_RANK() OVER (ORDER BY COUNT(l.id) DESC)                 AS checkout_rank,

    -- Bonus: share of total system-wide checkouts in the period
    ROUND(
        100.0 * COUNT(l.id)
        / SUM(COUNT(l.id)) OVER (),
        2
    )                                                             AS pct_of_total_checkouts

FROM books b
JOIN copies c ON c.book_id = b.id
JOIN loans  l ON l.copy_id = c.id
WHERE
    l.checkout_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
GROUP BY
    b.id, b.title, b.author, b.genre, b.publication_year
ORDER BY
    checkout_rank
LIMIT 100;   -- top 100; remove LIMIT for full ranking
