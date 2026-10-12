# India Lake Water Quality Analytics

End-to-end analytics project on CPCB NWMP lake water quality data (2017-2022).

## Data source
CPCB National Water Quality Monitoring Programme (NWMP), via Kaggle dataset
"NWMP Water Quality Data for Indian Lakes".

## Pipeline
Raw CSV -> Python ETL (cleaning + validation) -> SQLite -> SQL analysis -> Power BI dashboard


## Status
- [x] ETL and data quality checks
- [~] SQL analysis (Q1-Q6 done, CPCB class scoring in progress)
- [ ] Power BI dashboard

## Findings so far
- Dataset covers 699 stations across 31 states/UTs; Karnataka (171) and Telangana (160) make up about half of all stations.
- Monitoring network grew from 373 stations (2017) to 639 (2022). Only 321 stations have data for all 6 years, so year-on-year comparisons use percentages, not raw counts.
- Highest fecal coliform maxima are all from Bengaluru-area lakes in Karnataka.

## Data quality notes
- 40 junk header rows removed during ETL; 135 "BDL" values treated as missing.
- 8 station-year records have fecal coliform above 10^8 MPN/100ml (2021-2022, Karnataka). They are kept but flagged, not verified against the source PDFs.
- Coliform values repeat in fixed steps (e.g. 540, 1,600, 160,000), which looks like a lab-method effect; not independently verified.
- 15 year-over-year spikes (>100x, previous value >= 1,000) found, 13 of them in Karnataka; values not verified against the source.

## Limitations
- Maharashtra has no stations in this dataset.
- Data is annual min/max per station, not a time series.
- No GPS coordinates, so maps are state-level.

“On DO/BOD alone (worst-case annual values), the share of station-years not meeting CPCB Class A-C fell from about 70% (2017) to about 63% (2022) in a fixed panel of 321 stations monitored every year, but looked flat (67-73%) across the whole network. In 2022, stations monitored for fewer than 6 years had a higher share (77%) than the 6-year panel (63%), so network expansion hides the improvement. The panel is Karnataka-heavy (87 of 321 stations). No causal claim and no formal significance testing; classification uses DO and BOD only.”