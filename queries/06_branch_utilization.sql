-- =============================================================================
-- Query 06: Branch Utilization
-- File: queries/06_branch_utilization.sql
-- Database: MySQL 8.0+
-- =============================================================================
--
-- BUSINESS QUESTION:
--   Which branches are under-stocked (too few copies relative to demand)
--   and which are over-stocked (many copies sitting idle)?
--
-- PURPOSE:
--   Compare the number of physical copies held at each branch against the
--   number of checkouts originating from that branch in the last 12 months.
--   The ratio (checkouts per copy) is the utilisation metric.
--   A CASE expression classifies branches as understocked / balanced / overstocked.
--
-- INTERPRETATION:
--   Understocked branches experience high turnover — patrons may face long
--   waits or unavailable titles.  A targeted transfer of copies from
--   overstocked branches, or a new acquisition budget allocation, is
--   warranted.  Balanced branches require no immediate action.
--   Combining this view with Query 03 (hold wait times) gives a complete
--   supply-demand picture.
-- =============================================================================

WITH branch_copy_counts AS (
    SELECT
        branch_id,
        COUNT(*) AS total_copies
    FROM copies
    GROUP BY branch_id
),

branch_checkout_counts AS (
    SELECT
        c.branch_id,
        COUNT(l.id)  AS checkouts_12m
    FROM copies c
    JOIN loans  l ON l.copy_id = c.id
    WHERE
        l.checkout_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
    GROUP BY
        c.branch_id
),

branch_active_loans AS (
    SELECT
        c.branch_id,
        COUNT(l.id) AS currently_out
    FROM copies c
    JOIN loans  l ON l.copy_id = c.id
    WHERE l.return_date IS NULL
    GROUP BY c.branch_id
),

branch_pending_holds AS (
    -- Holds on books that have at least one copy at this branch
    SELECT
        c.branch_id,
        COUNT(DISTINCT h.id) AS pending_holds
    FROM copies c
    JOIN holds  h ON h.book_id = c.book_id
    WHERE h.status IN ('waiting', 'ready')
    GROUP BY c.branch_id
)

SELECT
    br.id                                                             AS branch_id,
    br.name                                                           AS branch_name,
    br.city,
    bcc.total_copies,
    COALESCE(bco.checkouts_12m, 0)                                    AS checkouts_last_12m,
    COALESCE(bal.currently_out, 0)                                    AS copies_currently_out,
    COALESCE(bph.pending_holds, 0)                                    AS pending_holds,

    -- Utilisation ratio: checkouts per available copy over 12 months
    ROUND(
        COALESCE(bco.checkouts_12m, 0) / NULLIF(bcc.total_copies, 0),
        2
    )                                                                 AS checkouts_per_copy,

    -- Availability rate: how often a copy is on the shelf
    ROUND(
        100.0 * (bcc.total_copies - COALESCE(bal.currently_out, 0))
        / NULLIF(bcc.total_copies, 0),
        1
    )                                                                 AS availability_pct,

    CASE
        WHEN COALESCE(bco.checkouts_12m, 0) / NULLIF(bcc.total_copies, 0) >= 4.0
            THEN 'understocked'
        WHEN COALESCE(bco.checkouts_12m, 0) / NULLIF(bcc.total_copies, 0) < 1.0
            THEN 'overstocked'
        ELSE 'balanced'
    END                                                               AS utilisation_status

FROM branches            br
JOIN branch_copy_counts  bcc ON bcc.branch_id = br.id
LEFT JOIN branch_checkout_counts bco ON bco.branch_id = br.id
LEFT JOIN branch_active_loans    bal ON bal.branch_id = br.id
LEFT JOIN branch_pending_holds   bph ON bph.branch_id = br.id

ORDER BY
    checkouts_per_copy DESC;   -- most utilised first
