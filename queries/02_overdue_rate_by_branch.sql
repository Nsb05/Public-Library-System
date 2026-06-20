-- =============================================================================
-- Query 02: Overdue Rate by Branch
-- File: queries/02_overdue_rate_by_branch.sql
-- Database: MySQL 8.0+
-- =============================================================================
--
-- BUSINESS QUESTION:
--   Which branches have the highest proportion of loans that were (or are)
--   returned late, and which branches have the best patron compliance?
--
-- PURPOSE:
--   Compute the overdue rate (%) per branch, defined as the fraction of loans
--   where either:
--     (a) the book was returned after the due date, OR
--     (b) the book has NOT been returned and the due date has already passed.
--   Results are ranked worst-to-best (highest overdue rate first).
--
-- INTERPRETATION:
--   A persistently high overdue rate at a specific branch may signal a need
--   for stronger reminder notifications, staff training, or revised loan
--   period policies.  Branches with very low rates may have best practices
--   that can be adopted system-wide.
-- =============================================================================

SELECT
    br.id                                                             AS branch_id,
    br.name                                                           AS branch_name,
    br.city,
    COUNT(l.id)                                                       AS total_loans,

    -- Count loans that are/were overdue
    SUM(
        CASE
            WHEN l.return_date IS NOT NULL AND l.return_date > l.due_date  THEN 1
            WHEN l.return_date IS NULL     AND l.due_date < CURDATE()      THEN 1
            ELSE 0
        END
    )                                                                 AS overdue_count,

    -- Count still-open (unreturned) overdue loans
    SUM(
        CASE
            WHEN l.return_date IS NULL AND l.due_date < CURDATE() THEN 1
            ELSE 0
        END
    )                                                                 AS currently_overdue,

    -- Overdue rate as a percentage
    ROUND(
        100.0 * SUM(
            CASE
                WHEN l.return_date IS NOT NULL AND l.return_date > l.due_date THEN 1
                WHEN l.return_date IS NULL     AND l.due_date < CURDATE()     THEN 1
                ELSE 0
            END
        ) / COUNT(l.id),
        2
    )                                                                 AS overdue_rate_pct,

    -- Average days overdue (among overdue loans only)
    ROUND(
        AVG(
            CASE
                WHEN l.return_date IS NOT NULL AND l.return_date > l.due_date
                    THEN DATEDIFF(l.return_date, l.due_date)
                WHEN l.return_date IS NULL AND l.due_date < CURDATE()
                    THEN DATEDIFF(CURDATE(), l.due_date)
            END
        ),
        1
    )                                                                 AS avg_days_overdue

FROM branches br
JOIN copies   c  ON c.branch_id = br.id
JOIN loans    l  ON l.copy_id   = c.id
GROUP BY
    br.id, br.name, br.city
ORDER BY
    overdue_rate_pct DESC;    -- worst branch first
