-- =====================================================================
-- India Lake Water Quality Analytics | CPCB NWMP lake data, 2017-2022
-- File     : sql/01_basic.sql
-- Database : data/lakes.db (built by etl/clean_lakes.py)
-- Tables   : dim_station       one row per station
--            fact_lake_quality one row per station-year (min/max per parameter)
--            dq_issues         every fix or rejected value from the ETL
-- =====================================================================
--
-- HOW TO RUN (DB Browser for SQLite)
--   * Select ONE query (from its "-- Qx" heading to its semicolon) and press Ctrl+Enter.
--   * Do not run the whole file at once: DB Browser shows only the last result.
--   * Section 4 and 5 use the view vw_station_year_class. Run the CREATE VIEW block
--     once, then press Ctrl+S (Write Changes) so the view is saved in lakes.db.
--   * Each query has an "Expected" line. If your result differs, something is wrong.
--
-- CONTENTS
--   1. Explore          Q1, Q2, Q3, Q3b   counts by state, water body type, year, years monitored
--   2. Rankings         Q4, Q5            state-wise BOD, top lakes by fecal coliform
--   3. Outliers and     Q5b-Q5f, Q6, Q6b  fecal coliform outliers, repeated values,
--      data quality                       year-over-year spikes, BDL entries
--   4. DO/BOD classes   view, Q7a-Q7f     CPCB class from DO and BOD only
--   5. Full A-C         Q8a-Q8d           adds pH and total coliform, fixed panel, robustness
--
-- METHOD NOTES
--   * Source for class thresholds: CPCB Designated Best Use Water Quality Criteria
--     https://cpcb.nic.in/wqm/Designated_Best_Use_Water_Quality_Criteria.pdf
--     (thresholds checked on 2026-10-12)
--   * Worst-case annual values are used: minimum DO, maximum BOD, pH min and max,
--     maximum total coliform.
--   * Only Classes A, B and C are assessed. D and E need ammonia, conductivity and SAR,
--     which are not available in this data. "Below C" therefore means "does not meet A-C".
--   * NULL and BDL (below detection limit) values are NOT treated as clean water.
--     They give "Insufficient data" unless DO/BOD already fails.
--   * "Panel" = the 321 stations monitored in all 6 years (years_monitored = 6).
-- =====================================================================


-- =====================================================================
-- 1. EXPLORE
-- =====================================================================

-- Q1: Number of monitoring stations per state
-- Expected: 31 rows, KARNATAKA 171 first, TELANGANA 160 second
SELECT state, COUNT(*) AS station_count
FROM dim_station
GROUP BY state
ORDER BY station_count DESC;

-- Q2: Stations by water body type
-- Expected: LAKE 419, TANK 136, POND 121, WETLAND 23 (total 699)
SELECT water_body_type, COUNT(*) AS station_count
FROM dim_station
GROUP BY water_body_type
ORDER BY station_count DESC;

-- Q3: Stations with a record in each year
-- Expected: 2017 373, 2018 429, 2019 529, 2020 566, 2021 619, 2022 639 (total 3,155)
SELECT year, COUNT(DISTINCT stn_code) AS station_count
FROM fact_lake_quality
WHERE year BETWEEN 2017 AND 2022
GROUP BY year
ORDER BY year;

-- Q3b: Stations grouped by number of years monitored
-- Expected: 1 yr 68, 2 yrs 65, 3 yrs 46, 4 yrs 102, 5 yrs 97, 6 yrs 321 (total 699)
SELECT years_monitored, COUNT(*) AS station_count
FROM dim_station
WHERE years_monitored BETWEEN 1 AND 6
GROUP BY years_monitored
ORDER BY years_monitored;


-- =====================================================================
-- 2. RANKINGS
-- =====================================================================

-- Q4: State-wise average of the yearly maximum BOD (mg/L)
-- Only states with at least 10 station-year records.
-- Expected: 27 rows, DELHI 50.27 (18 records), UTTAR PRADESH 33.13 (24),
--           KARNATAKA 28.43 (835)
SELECT d.state,
       ROUND(AVG(f.bod_mg_l_max), 2) AS avg_max_bod,
       COUNT(*) AS records,
       COUNT(DISTINCT f.stn_code) AS stations
FROM fact_lake_quality f
JOIN dim_station d ON f.stn_code = d.stn_code
WHERE f.bod_mg_l_max IS NOT NULL
GROUP BY d.state
HAVING COUNT(*) >= 10
ORDER BY avg_max_bod DESC;

-- Q5: Top 10 stations by maximum fecal coliform (MPN/100ml)
-- One row per station (its highest value across all years).
-- Expected: all 10 are in KARNATAKA, HOSAKEREHALLI LAKE first (8,400,000,000)
SELECT d.station_name, d.state, d.water_body_type,
       MAX(f.fecal_coliform_mpn_max) AS max_fecal_coliform
FROM fact_lake_quality f
JOIN dim_station d ON f.stn_code = d.stn_code
WHERE f.fecal_coliform_mpn_max IS NOT NULL
GROUP BY d.stn_code, d.station_name, d.state, d.water_body_type
ORDER BY max_fecal_coliform DESC
LIMIT 10;


-- =====================================================================
-- 3. OUTLIERS AND DATA QUALITY (fecal / total coliform)
-- =====================================================================

-- Q5b: Sanity check on the top station across years
-- Expected: 4 rows (2019-2022), 2022 fecal max 8,400,000,000 vs 700,000 in 2021
SELECT year,
       fecal_coliform_mpn_min,
       fecal_coliform_mpn_max,
       total_coliform_mpn_max
FROM fact_lake_quality
WHERE stn_code = (SELECT stn_code FROM dim_station
                  WHERE station_name LIKE 'HOSAKEREHALLI%')
ORDER BY year;

-- Q5c: Records per year with fecal coliform above 10 crore (1e8)
-- Expected: 2021 3, 2022 5 (no other years)
SELECT year, COUNT(*) AS high_fecal_coliform_records
FROM fact_lake_quality
WHERE fecal_coliform_mpn_max > 100000000
GROUP BY year
ORDER BY year;

-- Q5d: Which station-years are those?
-- Expected: 8 rows, all KARNATAKA
SELECT d.station_name, d.state, f.year,
       f.fecal_coliform_mpn_min,
       f.fecal_coliform_mpn_max,
       f.total_coliform_mpn_max
FROM fact_lake_quality f
JOIN dim_station d ON f.stn_code = d.stn_code
WHERE f.fecal_coliform_mpn_max > 100000000
ORDER BY f.fecal_coliform_mpn_max DESC;

-- Q5e: Repeated total coliform values among the largest values
-- Expected: 10 rows (for example 2,400,000,000 appears 4 times)
SELECT total_coliform_mpn_max, COUNT(*) AS times_repeated
FROM fact_lake_quality
WHERE total_coliform_mpn_max IS NOT NULL
GROUP BY total_coliform_mpn_max
HAVING COUNT(*) >= 2
ORDER BY total_coliform_mpn_max DESC
LIMIT 10;

-- Q5f: Most frequently repeated total coliform values overall
-- Expected: 540 appears 205 times, 1,600 appears 122 times
-- Reading: values come in fixed steps (likely the MPN lab method), so repeats are normal.
SELECT total_coliform_mpn_max, COUNT(*) AS times_repeated
FROM fact_lake_quality
WHERE total_coliform_mpn_max IS NOT NULL
GROUP BY total_coliform_mpn_max
ORDER BY times_repeated DESC
LIMIT 10;

-- Q6: Year-over-year fecal coliform spikes
-- Threshold: more than 100x the previous available year, previous value >= 1000.
-- The minimum baseline avoids huge ratios from tiny denominators.
-- gap_years shows if LAG compared with a non-adjacent year (all rows are 1 here).
-- (An earlier version without the baseline filter was removed. See git history.)
-- Expected: 15 rows, 13 in KARNATAKA, top ratio 12,000 (Hosakerehalli, 2022)
WITH yearly AS (
    SELECT
        stn_code,
        year,
        fecal_coliform_mpn_max,
        LAG(year) OVER (PARTITION BY stn_code ORDER BY year) AS prev_year,
        LAG(fecal_coliform_mpn_max) OVER (
            PARTITION BY stn_code ORDER BY year
        ) AS prev_year_value
    FROM fact_lake_quality
    WHERE fecal_coliform_mpn_max IS NOT NULL
)
SELECT
    d.station_name,
    d.state,
    y.stn_code,
    y.prev_year,
    y.year,
    y.year - y.prev_year AS gap_years,
    y.prev_year_value,
    y.fecal_coliform_mpn_max AS current_year_value,
    ROUND(1.0 * y.fecal_coliform_mpn_max / y.prev_year_value, 2) AS spike_ratio
FROM yearly y
JOIN dim_station d ON y.stn_code = d.stn_code
WHERE y.prev_year_value >= 1000
  AND y.fecal_coliform_mpn_max > y.prev_year_value * 100
ORDER BY spike_ratio DESC;

-- Q6b: Below-detection-limit (BDL) entries by parameter (from the ETL log)
-- Expected: Total Coliform 80, Nitrate 18, BOD 16, DO 12, Fecal Coliform 8, pH 1
SELECT parameter, COUNT(*) AS bdl_records
FROM dq_issues
WHERE issue = 'below_detection_limit'
GROUP BY parameter
ORDER BY bdl_records DESC;


-- =====================================================================
-- 4. DO/BOD CLASS SCREENING
-- =====================================================================

-- ---------------------------------------------------------------------
-- VIEW: vw_station_year_class
-- One row per station-year with both classifications. Defined once here so the
-- long CASE logic is not copied into every query below.
--   do_bod_class : DO and BOD only
--   full_class   : DO, BOD, pH and total coliform
--   in_6yr_panel : 1 if the station was monitored in all 6 years
-- Run this block once, then press Ctrl+S (Write Changes).
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS vw_station_year_class;

CREATE VIEW vw_station_year_class AS
WITH do_bod AS (
    SELECT
        f.stn_code,
        f.year,
        d.station_name,
        d.state,
        d.years_monitored,
        CASE WHEN d.years_monitored = 6 THEN 1 ELSE 0 END AS in_6yr_panel,
        f.do_mg_l_min,
        f.bod_mg_l_max,
        f.ph_min,
        f.ph_max,
        f.total_coliform_mpn_max,
        CASE
            WHEN f.do_mg_l_min IS NULL
              OR f.bod_mg_l_max IS NULL
                THEN 'Insufficient data'

            WHEN f.do_mg_l_min >= 6
             AND f.bod_mg_l_max <= 2
                THEN 'A'

            WHEN f.do_mg_l_min >= 5
             AND f.bod_mg_l_max <= 3
                THEN 'B'

            WHEN f.do_mg_l_min >= 4
             AND f.bod_mg_l_max <= 3
                THEN 'C'

            ELSE 'Below C'
        END AS do_bod_class
    FROM fact_lake_quality f
    JOIN dim_station d ON f.stn_code = d.stn_code
)
SELECT
    *,
    CASE
        -- DO/BOD already fails: missing pH or coliform does not matter
        WHEN do_bod_class = 'Below C'
            THEN 'Below C'

        WHEN do_mg_l_min IS NULL
          OR bod_mg_l_max IS NULL
          OR ph_min IS NULL
          OR ph_max IS NULL
          OR total_coliform_mpn_max IS NULL
            THEN 'Insufficient data'

        WHEN do_mg_l_min >= 6
         AND bod_mg_l_max <= 2
         AND ph_min >= 6.5
         AND ph_max <= 8.5
         AND total_coliform_mpn_max <= 50
            THEN 'A'

        WHEN do_mg_l_min >= 5
         AND bod_mg_l_max <= 3
         AND ph_min >= 6.5
         AND ph_max <= 8.5
         AND total_coliform_mpn_max <= 500
            THEN 'B'

        WHEN do_mg_l_min >= 4
         AND bod_mg_l_max <= 3
         AND ph_min >= 6.0
         AND ph_max <= 9.0
         AND total_coliform_mpn_max <= 5000
            THEN 'C'

        ELSE 'Below C'
    END AS full_class
FROM do_bod;

-- Quick check of the view
-- Expected: 3,155 rows, 321 stations with in_6yr_panel = 1
SELECT COUNT(*) AS rows_in_view,
       COUNT(DISTINCT CASE WHEN in_6yr_panel = 1 THEN stn_code END) AS panel_stations
FROM vw_station_year_class;

-- Q7a: DO/BOD class for every station-year
-- Expected: 3,155 rows
SELECT stn_code, year, do_mg_l_min, bod_mg_l_max, do_bod_class
FROM vw_station_year_class
ORDER BY stn_code, year;

-- Q7b: Share of each DO/BOD class per year, all stations
-- Percentages per year add up to 100. Station counts changed over time (see Q3),
-- so compare percentages, not counts.
-- Expected 2017: A 29, B 70, C 18, Below C 248, Insufficient 8 (373 total)
SELECT year, do_bod_class,
       COUNT(*) AS stations,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY year), 1) AS pct
FROM vw_station_year_class
GROUP BY year, do_bod_class
ORDER BY year, do_bod_class;

-- Q7c: Same as Q7b, only for the fixed panel (321 stations monitored all 6 years)
-- Expected 2017: A 19, B 55, C 15, Below C 226, Insufficient 6 (321 total)
-- Expected 2022: Below C 203 (63.2%)
SELECT year, do_bod_class,
       COUNT(*) AS stations,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY year), 1) AS pct
FROM vw_station_year_class
WHERE in_6yr_panel = 1
GROUP BY year, do_bod_class
ORDER BY year, do_bod_class;

-- Q7d: 2022 share not meeting DO/BOD A-C, panel vs stations monitored fewer years
-- Records with Insufficient data are excluded.
-- Expected: Under-6-year 315 records, 243 not A-C, 77.1%
--           6-year       320 records, 203 not A-C, 63.4%
SELECT
    CASE WHEN in_6yr_panel = 1 THEN '6-year stations'
         ELSE 'Under-6-year stations' END AS panel_group,
    COUNT(*) AS total_records,
    SUM(CASE WHEN do_bod_class = 'Below C' THEN 1 ELSE 0 END) AS non_ac_records,
    ROUND(100.0 * SUM(CASE WHEN do_bod_class = 'Below C' THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS non_ac_pct
FROM vw_station_year_class
WHERE year = 2022
  AND do_bod_class <> 'Insufficient data'
GROUP BY panel_group
ORDER BY non_ac_pct DESC;

-- Q7e: Top 3 states by number of panel stations
-- Expected: KARNATAKA 87, TELANGANA 33, ASSAM 28
SELECT state, COUNT(DISTINCT stn_code) AS station_count
FROM dim_station
WHERE years_monitored = 6
GROUP BY state
ORDER BY station_count DESC, state
LIMIT 3;

-- Q7f: Stations added after 2017, by state (top 5)
SELECT state,
       COUNT(*) AS total_stations,
       SUM(CASE WHEN first_year > 2017 THEN 1 ELSE 0 END) AS added_after_2017
FROM dim_station
GROUP BY state
ORDER BY added_after_2017 DESC
LIMIT 5;


-- =====================================================================
-- 5. FULL CPCB A-C SCREENING (DO, BOD, pH and total coliform)
-- =====================================================================

-- Q8a: Year-wise effect of adding pH and total coliform, all stations
--   do_bod_ac_records            pass A-C on DO/BOD alone
--   full_ac_records              pass A-C on all four parameters
--   downgraded_records           pass on DO/BOD but fail on pH or coliform
--   insufficient_after_screening pass on DO/BOD but pH or coliform is missing
-- Check: do_bod_ac_records = full_ac_records + downgraded + insufficient
-- Expected 2022: 639 / 189 / 168 / 9 / 12
SELECT
    year,
    COUNT(DISTINCT stn_code) AS station_count,
    COUNT(*) AS total_records,
    SUM(CASE WHEN do_bod_class IN ('A', 'B', 'C') THEN 1 ELSE 0 END) AS do_bod_ac_records,
    SUM(CASE WHEN full_class IN ('A', 'B', 'C') THEN 1 ELSE 0 END) AS full_ac_records,
    SUM(CASE WHEN do_bod_class IN ('A', 'B', 'C')
              AND full_class = 'Below C' THEN 1 ELSE 0 END) AS downgraded_records,
    SUM(CASE WHEN do_bod_class IN ('A', 'B', 'C')
              AND full_class = 'Insufficient data' THEN 1 ELSE 0 END) AS insufficient_after_screening
FROM vw_station_year_class
GROUP BY year
ORDER BY year;

-- Q8b: 2022 transition from DO/BOD class to full class
-- Shows where coliform and pH move records (for example A -> B or A -> C).
-- Expected: DO/BOD A (31 records) -> A 8, B 6, C 10, Below C 2, Insufficient 5
SELECT do_bod_class, full_class, COUNT(*) AS records
FROM vw_station_year_class
WHERE year = 2022
GROUP BY do_bod_class, full_class
ORDER BY do_bod_class, full_class;

-- Q8c: Full A-C share in the fixed panel (321 stations monitored all 6 years)
-- Lower bound: only confirmed A/B/C records
-- Upper bound: A/B/C plus Insufficient data records
-- Expected: 2017 22.1-25.2, 2018 16.8-20.6, 2019 20.2-25.5,
--           2020 28.0-29.9, 2021 29.6-32.1, 2022 32.4-34.9
SELECT
    year,
    COUNT(*) AS total_records,
    SUM(CASE WHEN full_class IN ('A', 'B', 'C') THEN 1 ELSE 0 END) AS full_ac_records,
    ROUND(100.0 * SUM(CASE WHEN full_class IN ('A', 'B', 'C') THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS full_ac_pct_lower,
    ROUND(100.0 * SUM(CASE WHEN full_class IN ('A', 'B', 'C', 'Insufficient data')
                           THEN 1 ELSE 0 END) / COUNT(*), 1) AS full_ac_pct_upper
FROM vw_station_year_class
WHERE in_6yr_panel = 1
GROUP BY year
ORDER BY year;

-- Q8d: Robustness check, same as Q8c but without Karnataka (234 panel stations)
-- Tests whether the Karnataka-heavy panel drives the trend.
-- Expected: 234 records per year, 2017 28.2-31.2 rising to 2022 41.0-44.4
SELECT
    year,
    COUNT(*) AS total_records,
    SUM(CASE WHEN full_class IN ('A', 'B', 'C') THEN 1 ELSE 0 END) AS full_ac_records,
    ROUND(100.0 * SUM(CASE WHEN full_class IN ('A', 'B', 'C') THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS full_ac_pct_lower,
    ROUND(100.0 * SUM(CASE WHEN full_class IN ('A', 'B', 'C', 'Insufficient data')
                           THEN 1 ELSE 0 END) / COUNT(*), 1) AS full_ac_pct_upper
FROM vw_station_year_class
WHERE in_6yr_panel = 1
  AND UPPER(TRIM(state)) <> 'KARNATAKA'
GROUP BY year
ORDER BY year;
