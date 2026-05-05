-- =============================================================================
-- FILE   : 01_create_tables.sql
-- SCHEMA : TELECOM
-- PURPOSE: Create tables for the telecom dataset and answer all
--          functional requirements.
-- PLACE  : ./init-scripts/01_create_tables.sql   (auto-run by Docker Compose)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: TARIFFS
--   Stores available subscription plans.
--   DATA_LIMIT / MINUTE_LIMIT / SMS_LIMIT = 0 means unlimited for that resource
--   (see "Kurumsal SMS" tariff which has unlimited data/minutes, 10 000 SMS).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE TARIFFS (
    TARIFF_ID    NUMBER(10)     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    NAME         VARCHAR2(100)  NOT NULL,
    MONTHLY_FEE  NUMBER(10, 2)  NOT NULL CHECK (MONTHLY_FEE >= 0),
    DATA_LIMIT   NUMBER(15, 2)  NOT NULL CHECK (DATA_LIMIT   >= 0),  -- MB; 0 = unlimited
    MINUTE_LIMIT NUMBER(10)     NOT NULL CHECK (MINUTE_LIMIT >= 0),  -- 0 = unlimited
    SMS_LIMIT    NUMBER(10)     NOT NULL CHECK (SMS_LIMIT    >= 0)   -- 0 = unlimited
);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: CUSTOMERS
--   One row per subscriber.
--   SIGNUP_DATE stored as DATE for proper chronological comparisons.
--   TARIFF_ID references TARIFFS with cascade restrict (no orphan customers).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE CUSTOMERS (
    CUSTOMER_ID  NUMBER(10)    PRIMARY KEY,
    NAME         VARCHAR2(100) NOT NULL,
    CITY         VARCHAR2(100) NOT NULL,
    SIGNUP_DATE  DATE          NOT NULL,
    TARIFF_ID    NUMBER(10)    NOT NULL,
    CONSTRAINT fk_customer_tariff FOREIGN KEY (TARIFF_ID)
        REFERENCES TARIFFS (TARIFF_ID)
);

CREATE INDEX idx_customers_tariff   ON CUSTOMERS (TARIFF_ID);
CREATE INDEX idx_customers_signup   ON CUSTOMERS (SIGNUP_DATE);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: MONTHLY_STATS
--   Records this month's usage and payment status per customer.
--   CUSTOMER_ID is UNIQUE because each customer has at most one record.
--   PAYMENT_STATUS constrained to known values to prevent dirty data.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE MONTHLY_STATS (
    ID             NUMBER(10)     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    CUSTOMER_ID    NUMBER(10)     NOT NULL UNIQUE,
    DATA_USAGE     NUMBER(15, 2)  NOT NULL CHECK (DATA_USAGE   >= 0),  -- MB
    MINUTE_USAGE   NUMBER(10)     NOT NULL CHECK (MINUTE_USAGE >= 0),
    SMS_USAGE      NUMBER(10)     NOT NULL CHECK (SMS_USAGE    >= 0),
    PAYMENT_STATUS VARCHAR2(10)   NOT NULL
        CHECK (PAYMENT_STATUS IN ('PAID', 'UNPAID', 'LATE')),
    CONSTRAINT fk_stats_customer FOREIGN KEY (CUSTOMER_ID)
        REFERENCES CUSTOMERS (CUSTOMER_ID)
);

CREATE INDEX idx_stats_customer ON MONTHLY_STATS (CUSTOMER_ID);
CREATE INDEX idx_stats_payment  ON MONTHLY_STATS (PAYMENT_STATUS);


-- =============================================================================
-- IMPORT NOTE
-- =============================================================================
-- After the container is running, import the three CSV files via DBeaver:
--   Right-click table → Import Data → CSV
--   Map columns as:  TARIFFS.csv    → TARIFFS    (skip TARIFF_ID column;
--                                                  it is IDENTITY-generated)
--                    CUSTOMERS.csv  → CUSTOMERS  (SIGNUP_DATE format: DD/MM/YYYY)
--                    MONTHLY_STATS.csv→ MONTHLY_STATS (skip ID column)
--
-- Or use SQL*Loader / external tables for large datasets.
-- =============================================================================


-- =============================================================================
--  FUNCTIONAL REQUIREMENTS — SQL QUERIES
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 1.1  List customers subscribed to the 'Kobiye Destek' tariff.
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  We join CUSTOMERS to TARIFFS on TARIFF_ID so we can filter by the
  human-readable tariff name instead of a hard-coded ID, making the query
  portable even if the ID changes between environments.
  The JOIN also lets us SELECT any tariff attributes alongside customer info
  without a second round-trip to the database.
  We order by CUSTOMER_ID for deterministic, easy-to-read results.
*/
SELECT
    c.CUSTOMER_ID,
    c.NAME         AS CUSTOMER_NAME,
    c.CITY,
    c.SIGNUP_DATE,
    t.NAME         AS TARIFF_NAME,
    t.MONTHLY_FEE
FROM CUSTOMERS c
JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
WHERE t.NAME = 'Kobiye Destek'
ORDER BY c.CUSTOMER_ID;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 1.2  Newest customer who subscribed to 'Kobiye Destek'.
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  We reuse the same join pattern as Q1.1 but add an analytic RANK() window
  function that orders customers by SIGNUP_DATE descending within the filtered
  tariff group. Wrapping it in a subquery and keeping only RANK = 1 returns
  exactly the most-recent signup(s); if two customers joined on the same day,
  both are returned rather than arbitrarily dropping one.
  This is safer than a plain MAX sub-select when tie-breaking matters.
*/
SELECT *
FROM (
    SELECT
        c.CUSTOMER_ID,
        c.NAME       AS CUSTOMER_NAME,
        c.CITY,
        c.SIGNUP_DATE,
        RANK() OVER (ORDER BY c.SIGNUP_DATE DESC) AS rk
    FROM CUSTOMERS c
    JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
    WHERE t.NAME = 'Kobiye Destek'
)
WHERE rk = 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 2.1  Tariff distribution among customers.
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  We GROUP BY tariff and count customers to see how popular each plan is.
  Joining to TARIFFS ensures the result shows the plan name, not just an
  opaque ID, making it immediately useful for business reporting.
  RATIO_TO_REPORT is an Oracle analytic function that divides each count by
  the overall total in a single pass, avoiding a self-join or scalar subquery.
*/
SELECT
    t.NAME                                            AS TARIFF_NAME,
    COUNT(c.CUSTOMER_ID)                              AS CUSTOMER_COUNT,
    ROUND(
        RATIO_TO_REPORT(COUNT(c.CUSTOMER_ID)) OVER () * 100,
        2
    )                                                 AS PERCENTAGE
FROM CUSTOMERS c
JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
GROUP BY t.TARIFF_ID, t.NAME
ORDER BY CUSTOMER_COUNT DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 3.1  Earliest customers to sign up.
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  The hint warns that lowest CUSTOMER_ID ≠ earliest signup, so we must sort
  by SIGNUP_DATE. We use RANK() (not ROWNUM or simple MIN) so that all
  customers who signed up on the single earliest date are included — none are
  silently dropped. The outer query filters to rank = 1, returning the true
  founding cohort regardless of how many members it has.
  This pattern is idiomatic Oracle and performs well with the index on
  SIGNUP_DATE created during table setup.
*/
SELECT CUSTOMER_ID, NAME, CITY, SIGNUP_DATE
FROM (
    SELECT
        CUSTOMER_ID,
        NAME,
        CITY,
        SIGNUP_DATE,
        RANK() OVER (ORDER BY SIGNUP_DATE ASC) AS rk
    FROM CUSTOMERS
)
WHERE rk = 1
ORDER BY CUSTOMER_ID;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 3.2  City distribution of the earliest signup cohort.
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  We build on the Q3.1 logic by wrapping it in a CTE (WITH clause) for
  readability and then grouping the result by CITY. Using a CTE avoids
  repeating the RANK window expression and makes the two-step logic
  (first find earliest date, then aggregate by city) explicit and auditable.
  The count per city directly answers the distribution question asked.
*/
WITH earliest AS (
    SELECT CITY
    FROM (
        SELECT
            CITY,
            RANK() OVER (ORDER BY SIGNUP_DATE ASC) AS rk
        FROM CUSTOMERS
    )
    WHERE rk = 1
)
SELECT
    CITY,
    COUNT(*) AS CUSTOMER_COUNT
FROM earliest
GROUP BY CITY
ORDER BY CUSTOMER_COUNT DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 4.1  Customer IDs with missing monthly records.
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  We use a LEFT JOIN from CUSTOMERS to MONTHLY_STATS and filter for rows
  where no matching MONTHLY_STATS record exists (ms.CUSTOMER_ID IS NULL).
  This is the standard anti-join pattern; it finds every customer who should
  have a record (all 10 000 of them) but does not. Alternatives like NOT IN
  can behave unexpectedly if NULLs are present in the subquery, so LEFT JOIN
  is the safer and typically faster Oracle approach.
*/
SELECT c.CUSTOMER_ID
FROM CUSTOMERS c
LEFT JOIN MONTHLY_STATS ms ON c.CUSTOMER_ID = ms.CUSTOMER_ID
WHERE ms.CUSTOMER_ID IS NULL
ORDER BY c.CUSTOMER_ID;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 4.2  City distribution of customers with missing monthly records.
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  We extend Q4.1 by grouping the anti-join result set by the customer's CITY.
  Because city is in the CUSTOMERS table (not MONTHLY_STATS), we already have
  access to it through the LEFT JOIN without an extra join. Grouping and
  counting reveals which cities are most affected by the insertion error,
  which is useful for investigating whether the bug is geographically
  correlated (e.g., a regional batch job that failed).
*/
SELECT
    c.CITY,
    COUNT(*) AS MISSING_COUNT
FROM CUSTOMERS c
LEFT JOIN MONTHLY_STATS ms ON c.CUSTOMER_ID = ms.CUSTOMER_ID
WHERE ms.CUSTOMER_ID IS NULL
GROUP BY c.CITY
ORDER BY MISSING_COUNT DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 5.1  Customers who have used at least 75% of their data limit.
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  The TARIFFS table stores each plan's DATA_LIMIT. We compute utilisation as
  (ms.DATA_USAGE / t.DATA_LIMIT) * 100 and filter for >= 75. We must guard
  against plans where DATA_LIMIT = 0 (unlimited), because dividing by zero
  raises ORA-01476 at runtime; the NULLIF wrapper turns zero into NULL, which
  Oracle then skips in comparisons, correctly excluding unlimited-data plans.
  The result is ordered by utilisation descending so the most over-used
  accounts appear first — useful for proactive customer contact.
*/
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    t.NAME                                                      AS TARIFF_NAME,
    t.DATA_LIMIT                                                AS DATA_LIMIT_MB,
    ms.DATA_USAGE                                               AS DATA_USED_MB,
    ROUND(ms.DATA_USAGE / NULLIF(t.DATA_LIMIT, 0) * 100, 2)    AS DATA_USAGE_PCT
FROM CUSTOMERS c
JOIN TARIFFS t         ON c.TARIFF_ID    = t.TARIFF_ID
JOIN MONTHLY_STATS ms  ON c.CUSTOMER_ID  = ms.CUSTOMER_ID
WHERE t.DATA_LIMIT > 0   -- exclude unlimited-data tariffs
  AND ms.DATA_USAGE / t.DATA_LIMIT >= 0.75
ORDER BY DATA_USAGE_PCT DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 5.2  Customers who have exhausted ALL package limits
--         (data, minutes, AND SMS).
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  A customer has "exhausted" a resource when their usage equals or exceeds
  the plan limit. Because some tariffs set a limit to 0 (meaning unlimited),
  we must only check a dimension when the limit is actually > 0; a plan with
  an unlimited dimension cannot be "exhausted" on that dimension. We express
  this with three CASE expressions inside the WHERE clause, each of which
  is TRUE either when the limit is 0 (unlimited — dimension not checked) or
  when usage >= limit (actually exhausted). All three conditions must hold
  simultaneously (AND), so only full-package exhaustion qualifies.
*/
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    t.NAME          AS TARIFF_NAME,
    ms.DATA_USAGE,
    t.DATA_LIMIT,
    ms.MINUTE_USAGE,
    t.MINUTE_LIMIT,
    ms.SMS_USAGE,
    t.SMS_LIMIT
FROM CUSTOMERS c
JOIN TARIFFS t        ON c.TARIFF_ID   = t.TARIFF_ID
JOIN MONTHLY_STATS ms ON c.CUSTOMER_ID = ms.CUSTOMER_ID
WHERE
    -- Data: only check if the tariff has a finite data limit
    (t.DATA_LIMIT   = 0 OR ms.DATA_USAGE   >= t.DATA_LIMIT)
    AND
    -- Minutes: only check if the tariff has a finite minute limit
    (t.MINUTE_LIMIT = 0 OR ms.MINUTE_USAGE >= t.MINUTE_LIMIT)
    AND
    -- SMS: only check if the tariff has a finite SMS limit
    (t.SMS_LIMIT    = 0 OR ms.SMS_USAGE    >= t.SMS_LIMIT)
ORDER BY c.CUSTOMER_ID;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 6.1  Customers with unpaid fees.
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  We filter MONTHLY_STATS for PAYMENT_STATUS = 'UNPAID' and join back to
  CUSTOMERS and TARIFFS to show the outstanding amount (MONTHLY_FEE) and
  contact details. Including the tariff's MONTHLY_FEE gives the finance team
  everything needed to issue payment reminders in a single result set.
  We deliberately exclude 'LATE' here because the query asks specifically
  for unpaid; a separate query (or a UNION) would be needed if 'LATE' should
  also count as outstanding.
*/
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    t.NAME         AS TARIFF_NAME,
    t.MONTHLY_FEE  AS AMOUNT_DUE,
    ms.PAYMENT_STATUS
FROM CUSTOMERS c
JOIN TARIFFS t        ON c.TARIFF_ID   = t.TARIFF_ID
JOIN MONTHLY_STATS ms ON c.CUSTOMER_ID = ms.CUSTOMER_ID
WHERE ms.PAYMENT_STATUS = 'UNPAID'
ORDER BY c.CUSTOMER_ID;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q 6.2  Distribution of all payment statuses across tariffs.
-- ─────────────────────────────────────────────────────────────────────────────
/*
  APPROACH:
  We pivot the data by grouping on both TARIFF name and PAYMENT_STATUS.
  Using a conditional COUNT (SUM(CASE WHEN ...)) instead of separate queries
  produces a compact cross-tabulation in a single pass, making it easy to
  compare PAID vs. UNPAID vs. LATE side-by-side for every tariff.
  The TOTAL column provides a quick sanity check: summing all statuses per
  tariff should equal the number of customers on that plan who have records.
*/
SELECT
    t.NAME                                                          AS TARIFF_NAME,
    SUM(CASE WHEN ms.PAYMENT_STATUS = 'PAID'   THEN 1 ELSE 0 END)  AS PAID,
    SUM(CASE WHEN ms.PAYMENT_STATUS = 'UNPAID' THEN 1 ELSE 0 END)  AS UNPAID,
    SUM(CASE WHEN ms.PAYMENT_STATUS = 'LATE'   THEN 1 ELSE 0 END)  AS LATE,
    COUNT(*)                                                        AS TOTAL
FROM MONTHLY_STATS ms
JOIN CUSTOMERS c ON ms.CUSTOMER_ID = c.CUSTOMER_ID
JOIN TARIFFS t   ON c.TARIFF_ID    = t.TARIFF_ID
GROUP BY t.TARIFF_ID, t.NAME
ORDER BY TOTAL DESC;
