-- =============================================================================
-- Query 05: Rolling 30-Day Checkout Trend
-- File: queries/05_rolling_30day_trend.sql
-- Database: MySQL 8.0+
-- =============================================================================
--
-- BUSINESS QUESTION:
--   How does daily checkout volume trend over time across the entire library
--   system, and does it exhibit clear seasonal patterns?
--
-- PURPOSE:
--   Compute a rolling 30-day average of daily checkouts using a window
--   function.  First, aggregate loans to a daily count; then smooth the
--   noisy daily signal with a 30-day trailing average to reveal the
--   underlying seasonal trend.
--
-- INTERPRETATION:
--   Peaks in the rolling average (typically June–August and December–January)
--   indicate periods of high demand — branches should schedule extra staff
--   and accelerate holds processing during these windows.  Sustained drops
--   may warrant investigation (e.g., holiday closures, data gaps).
--   This data feeds directly into the Streamlit "Checkout Trend" panel.
-- =============================================================================

WITH daily_checkouts AS (
    -- Step 1: count checkouts per calendar day
    SELECT
        DATE(checkout_date)   AS loan_date,
        COUNT(*)              AS daily_count
    FROM loans
    GROUP BY
        DATE(checkout_date)
),

rolling AS (
    -- Step 2: apply a 30-day trailing window average
    SELECT
        loan_date,
        daily_count,
        AVG(daily_count) OVER (
            ORDER BY loan_date
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        )                     AS rolling_30d_avg,

        -- Also compute 7-day rolling average for a shorter-term view
        AVG(daily_count) OVER (
            ORDER BY loan_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )                     AS rolling_7d_avg,

        -- Cumulative total checkouts (ever-growing counter)
        SUM(daily_count) OVER (
            ORDER BY loan_date
            ROWS UNBOUNDED PRECEDING
        )                     AS cumulative_total
    FROM daily_checkouts
)

SELECT
    loan_date,
    daily_count,
    ROUND(rolling_7d_avg,  1)  AS rolling_7d_avg,
    ROUND(rolling_30d_avg, 1)  AS rolling_30d_avg,
    cumulative_total,
    DAYNAME(loan_date)         AS day_of_week,
    MONTHNAME(loan_date)       AS month_name,
    YEAR(loan_date)            AS year
FROM rolling
ORDER BY
    loan_date;
