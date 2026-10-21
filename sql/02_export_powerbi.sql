-- 02_export_powerbi.sql
-- Purpose : One row per station-year (all 3,155 rows) with CPCB class screening,
--           exported to CSV for the Power BI dashboard.
-- Source  : CPCB Designated Best Use Water Quality Criteria
--           https://cpcb.nic.in/wqm/Designated_Best_Use_Water_Quality_Criteria.pdf
-- Method  : Worst-case annual values (min DO, max BOD, pH range, max total coliform).
--           Classes A-C only; D and E are not assessed (no ammonia / SAR in the data).
--           BDL and other NULL values are NOT treated as clean water.
-- Output  : data/export/fact_lake_quality_classified.csv

WITH do_bod AS (
    -- Step 1: class using DO and BOD only
    SELECT
        f.*,
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
),
classified AS (
    -- Step 2: full class = DO + BOD + pH + total coliform
    SELECT
        *,
        CASE
            -- DO/BOD already fails: pH/coliform missing does not matter
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
    FROM do_bod
)
SELECT
    c.*,
    -- 1/0 flags make the DAX measures in Power BI simple and consistent with SQL
    CASE WHEN c.full_class IN ('A', 'B', 'C') THEN 1 ELSE 0 END AS is_full_ac,
    CASE WHEN c.full_class = 'Insufficient data' THEN 1 ELSE 0 END AS is_insufficient,
    -- 1 = station monitored in all 6 years (fixed panel of 321 stations)
    CASE WHEN s.years_monitored = 6 THEN 1 ELSE 0 END AS in_6yr_panel
FROM classified c
JOIN dim_station s
    ON c.stn_code = s.stn_code
ORDER BY c.stn_code, c.year;
