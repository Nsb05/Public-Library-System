-- =============================================================================
-- Query 03: Hold Queue Wait Time
-- File: queries/03_hold_queue_wait_time.sql
-- Database: MySQL 8.0+
-- =============================================================================
--
-- BUSINESS QUESTION:
--   For books with significant hold demand, how long on average does a patron
--   wait from the moment they place a hold until it is fulfilled?
--
-- PURPOSE:
--   Calculate the average wait time (in days) between request_date and
--   fulfilled_date for each book, restricted to books that have accumulated
--   more than 5 fulfilled holds (to filter out noise from rarely-held titles).
--   Also surfaces the number of physical copies available to contextualise
--   whether the wait is driven by insufficient supply.
--
-- INTERPRETATION:
--   A long average wait time combined with few copies is a strong signal that
--   the library should purchase additional copies of that title.
--   A long wait despite many copies may indicate those copies are concentrated
--   at a single branch — inter-branch transfers or a new purchase at a high-
--   demand branch would help.
-- =============================================================================

WITH fulfilled_hold_stats AS (
    -- Aggregate wait time only for fulfilled holds
    SELECT
        h.book_id,
        COUNT(h.id)                                          AS fulfilled_holds,
        AVG(DATEDIFF(h.fulfilled_date, h.request_date))     AS avg_wait_days,
        MIN(DATEDIFF(h.fulfilled_date, h.request_date))     AS min_wait_days,
        MAX(DATEDIFF(h.fulfilled_date, h.request_date))     AS max_wait_days
    FROM holds h
    WHERE
        h.status         = 'fulfilled'
        AND h.fulfilled_date IS NOT NULL
    GROUP BY
        h.book_id
    HAVING
        COUNT(h.id) > 5   -- only books with meaningful hold volume
),
copy_counts AS (
    SELECT book_id, COUNT(*) AS total_copies
    FROM copies
    GROUP BY book_id
),
active_hold_queue AS (
    -- How many patrons are STILL waiting right now
    SELECT book_id, COUNT(*) AS patrons_waiting
    FROM holds
    WHERE status IN ('waiting', 'ready')
    GROUP BY book_id
)

SELECT
    b.id                                       AS book_id,
    b.title,
    b.author,
    b.genre,
    fhs.fulfilled_holds,
    ROUND(fhs.avg_wait_days, 1)                AS avg_wait_days,
    fhs.min_wait_days,
    fhs.max_wait_days,
    cc.total_copies,
    COALESCE(ahq.patrons_waiting, 0)           AS currently_waiting,

    -- Demand-supply pressure score: higher = more urgent
    ROUND(
        COALESCE(ahq.patrons_waiting, 0) / NULLIF(cc.total_copies, 0),
        2
    )                                          AS demand_supply_ratio

FROM fulfilled_hold_stats fhs
JOIN books          b   ON b.id = fhs.book_id
JOIN copy_counts    cc  ON cc.book_id = fhs.book_id
LEFT JOIN active_hold_queue ahq ON ahq.book_id = fhs.book_id

ORDER BY
    avg_wait_days DESC;
