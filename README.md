# India Lake Water Quality Analytics

End-to-end analytics project on CPCB NWMP lake water quality data (2017-2022).

## Data source
CPCB National Water Quality Monitoring Programme (NWMP), via the Kaggle dataset
["NWMP Water Quality Data for Indian Lakes"](https://www.kaggle.com/datasets/akkshaysr/nwmp-water-quality-data-for-indian-lakes).
Raw data is not included in this repo; see "How to run".

## Pipeline
Raw CSV -> Python ETL (cleaning + validation) -> SQLite -> SQL analysis -> Power BI dashboard

## Status
- [x] ETL and data quality checks
- [x] SQL analysis part 1: counts, rankings, outlier checks, DO/BOD class screening (Q1-Q7)
- [x] SQL analysis: counts, rankings, outlier checks, CPCB A-C class screening (Q1-Q8)
- [ ] Power BI dashboard

## Findings so far
- 699 stations across 31 states/UTs; Karnataka (171) and Telangana (160) make up about half.
- The monitoring network grew from 373 stations (2017) to 639 (2022). Only 321 stations have data for all 6 years, so year-on-year comparisons use percentages, not raw counts.
- The 10 stations with the highest fecal coliform maxima are all in Karnataka.
- Applying the full CPCB Class A-C criteria (DO, BOD, pH, total coliform) in a fixed panel of 321 stations monitored every year, the share of station-years meeting them rose from 22-25% (2017) to 32-35% (2022), with a dip in 2018. The range reflects station-years where pH or coliform is missing. In 2022, 8 of 639 station-years (1.3%) met full Class A criteria, versus 31 (4.9%) on DO/BOD alone. Panel is Karnataka-heavy; no significance testing; causes not analysed.

## Data quality notes
- 40 junk header rows removed during ETL.
- 135 "BDL" (below detection limit) values treated as missing, 80 of them total coliform.
- 8 station-year records have fecal coliform above 10^8 MPN/100ml (2021-2022, Karnataka). They are kept but flagged, not verified against the source PDFs.
- Coliform values repeat in fixed steps (e.g. 540, 1,600, 160,000), which looks like a lab-method effect; not independently verified.
- 15 year-over-year spikes (>100x, previous value >= 1,000) found, 13 of them in Karnataka; values not verified against the source.

## Limitations
- Maharashtra has no stations in this dataset.
- Data is annual min/max per station, not a time series.
- No GPS coordinates, so maps will be state-level.
- Class screening covers Classes A-C only (DO, BOD, pH, total coliform); Classes D and E (ammonia, conductivity, SAR) are not assessed. Worst-case annual values are used (minimum DO, maximum BOD and coliform), and BDL values are treated as missing.

## How to run
1. `pip install -r requirements.txt`
2. Download the six yearly CSVs from the Kaggle dataset above, rename them to `2017_lake_data.csv` ... `2022_lake_data.csv`, and place them in `data/raw/`.
3. `python etl/clean_lakes.py` (creates `data/clean/*.csv` and `data/lakes.db`)
4. Open `data/lakes.db` in DB Browser for SQLite and run `sql/01_basic.sql`.