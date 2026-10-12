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
- [ ] Full CPCB A-C screening (adds pH and total coliform)
- [ ] Power BI dashboard

## Findings so far
- 699 stations across 31 states/UTs; Karnataka (171) and Telangana (160) make up about half.
- The monitoring network grew from 373 stations (2017) to 639 (2022). Only 321 stations have data for all 6 years, so year-on-year comparisons use percentages, not raw counts.
- The 10 stations with the highest fecal coliform maxima are all in Karnataka.
- On DO/BOD alone (worst-case annual values), the share of station-years not meeting CPCB Class A-C fell from about 70% (2017) to about 63% (2022) in a fixed panel of 321 stations monitored every year, but looked flat (67-73%) across the whole network. In 2022, stations monitored for fewer than 6 years had a higher share (77%) than the 6-year panel (63%), which may explain why the network-wide share looks flat. The panel is Karnataka-heavy (87 of 321 stations). No causal claim and no formal significance testing.

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
- Class screening so far uses DO and BOD only (not the full CPCB classification); BDL values treated as missing may affect class shares slightly.

## How to run
1. `pip install -r requirements.txt`
2. Download the six yearly CSVs from the Kaggle dataset above, rename them to `2017_lake_data.csv` ... `2022_lake_data.csv`, and place them in `data/raw/`.
3. `python etl/clean_lakes.py` (creates `data/clean/*.csv` and `data/lakes.db`)
4. Open `data/lakes.db` in DB Browser for SQLite and run `sql/01_basic.sql`.