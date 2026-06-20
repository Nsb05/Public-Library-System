-- =============================================================================
-- Query 08: Fine Collection Analysis
-- File: queries/08_fine_collection.sql
-- Database: MySQL 8.0+
-- =============================================================================
--
-- BUSINESS QUESTION:
--   How much in fines has the library system issued vs. actually collected,
--   broken down by branch and year?  What is the running uncollected balance
--   accumulating over time?
--
-- PURPOSE:
--   Aggregate fine data by branch and year, then apply a cumulative SUM()
--   window function to track the running outstanding balance — the total
--   amount owed but unpaid, growing over time.  MySQL does not support
--   FILTER (WHERE ...) syntax, so conditional aggregation with CASE is used.
--
-- INTERPRETATION:
--   A low collection rate (collected ÷ issued) at a branch indicates that
--   fines are being waived too readily or the collection process is broken.
--   The running outstanding total helps finance teams report the accounts-
--   receivable balance.  Branches with a large outstanding balance may
--   benefit from an amnesty programme to encourage returns.
-- =============================================================================

WITH fine_by_branch_year AS (
    SELECT
        br.id                                                     AS branch_id,
        br.name                                                   AS branch_name,
        br.city,
        YEAR(f.created_at)                                        AS fine_year,

        -- Total fines issued
        SUM(f.amount)                                             AS total_issued,

        -- Total fines collected (paid = TRUE)
        SUM(CASE WHEN f.paid = TRUE  THEN f.amount ELSE 0 END)   AS total_collected,

        -- Outstanding (unpaid) balance
        SUM(CASE WHEN f.paid = FALSE THEN f.amount ELSE 0 END)   AS outstanding,

        COUNT(f.id)                                               AS fine_count,
        SUM(CASE WHEN f.paid = TRUE  THEN 1 ELSE 0 END)          AS paid_count,
        SUM(CASE WHEN f.paid = FALSE THEN 1 ELSE 0 END)          AS unpaid_count
    FROM fines    f
    JOIN loans    l  ON l.id  = f.loan_id
    JOIN copies   c  ON c.id  = l.copy_id
    JOIN branches br ON br.id = c.branch_id
    GROUP BY
        br.id, br.name, br.city, YEAR(f.created_at)
)

SELECT
    branch_id,
    branch_name,
    city,
    fine_year,
    fine_count,
    paid_count,
    unpaid_count,
    ROUND(total_issued,    2)  AS total_issued,
    ROUND(total_collected, 2)  AS total_collected,
    ROUND(outstanding,     2)  AS outstanding_balance,

    -- Collection rate as a percentage
    ROUND(
        100.0 * total_collected / NULLIF(total_issued, 0),
        1
    )                          AS collection_rate_pct,

    -- Running total of outstanding balances (cumulative unpaid, system-wide, by year)
    ROUND(
        SUM(outstanding) OVER (
            ORDER BY fine_year
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        2
    )                          AS running_outstanding_total,

    -- Rank branches by outstanding balance within each year
    RANK() OVER (
        PARTITION BY fine_year
        ORDER BY outstanding DESC
    )                          AS outstanding_rank_in_year

FROM fine_by_branch_year
ORDER BY
    fine_year,
    outstanding DESC;
