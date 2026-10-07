"""
ETL: CPCB NWMP lake water quality (2017-2022) -> clean tables.

Source : Kaggle "NWMP Water Quality Data for Indian Lakes" (extracted from CPCB PDFs)
Input  : data/raw/<year>_lake_data.csv
Output : data/clean/dim_station.csv
         data/clean/fact_lake_quality.csv   (one row per station-year, min/max per parameter)
         data/clean/dq_issues.csv           (every fix / rejected value, for auditing)
         data/lakes.db                      (SQLite with the same three tables)

Problems in the raw data that this script handles:
  * PDF-extraction junk: repeated header rows ("Min"/"Max"), line breaks inside cells
  * placeholders: "-" and "BDL" (below detection limit) in numeric columns
  * merged cells: "28.7 \\n34.1" (min and max squashed into one cell)
  * state names broken by PDF line wraps ("LAKSHADWE EP")
  * same station spelled differently across years, STN code stored as float in 2022
  * duplicate station-year rows
  * physically impossible values (pH outside 0-14, min > max, ...)

Run:  python clean_lakes.py
"""
import re
import sqlite3
from collections import Counter
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "raw"
CLEAN_DIR = ROOT / "data" / "clean"
DB_PATH = ROOT / "data" / "lakes.db"

# raw label -> (clean column prefix, plausible lower bound, plausible upper bound)
PARAMS = {
    "Temperature": ("temp_c", 0, 50),
    "Dissolved Oxygen": ("do_mg_l", 0, 25),
    "pH": ("ph", 0, 14),
    "Conductivity": ("conductivity_us_cm", 0, 300_000),
    "BOD": ("bod_mg_l", 0, 500),
    "Nitrate N + Nitrite N": ("nitrate_nitrite_mg_l", 0, 200),
    # sewage-fed lakes can legitimately reach 1e7-1e9 MPN/100ml: keep, but flag (see WARN_ABOVE)
    "Fecal Coliform": ("fecal_coliform_mpn", 0, 1e11),
    "Total Coliform": ("total_coliform_mpn", 0, 1e11),
}
WARN_ABOVE = {"Fecal Coliform": 1e7, "Total Coliform": 1e7}

NUM = re.compile(r"\d+(?:\.\d+)?")
issues = []  # filled while cleaning


def log_issue(year, stn, parameter, issue, detail=""):
    issues.append(dict(year=year, stn_code=stn, parameter=parameter, issue=issue, detail=detail))


def tokens(cell):
    return [float(t) for t in NUM.findall(str(cell))] if pd.notna(cell) else []


def squash(text):
    """Collapse line breaks / repeated spaces, tidy punctuation spacing."""
    if pd.isna(text):
        return np.nan
    text = re.sub(r"\s+", " ", str(text)).strip()
    return re.sub(r"\s+,", ",", text)


def parse_pair(raw_min, raw_max, year, stn, label, lo_ok, hi_ok):
    """Turn one raw (min, max) cell pair into two clean floats."""
    ta, tb = tokens(raw_min), tokens(raw_max)
    lo = hi = np.nan

    if len(ta) == 2 and len(tb) == 0:  # min & max squashed into the min cell
        lo, hi = ta
        log_issue(year, stn, label, "merged_cell_split", f"{raw_min!r}")
    else:
        if len(ta) == 1:
            lo = ta[0]
        elif len(ta) > 1:
            log_issue(year, stn, label, "malformed_min_dropped", f"{raw_min!r}")
        if len(tb) == 1:
            hi = tb[0]
        elif len(tb) > 1:
            log_issue(year, stn, label, "malformed_max_dropped", f"{raw_max!r}")

    for raw in (raw_min, raw_max):
        if isinstance(raw, str) and raw.strip().upper() == "BDL":
            log_issue(year, stn, label, "below_detection_limit")

    if pd.notna(lo) and pd.notna(hi) and lo > hi:
        lo, hi = hi, lo
        log_issue(year, stn, label, "min_gt_max_swapped")

    def in_range(v):
        return pd.isna(v) or lo_ok <= v <= hi_ok

    if not in_range(lo):
        log_issue(year, stn, label, "out_of_range_min_dropped", str(lo))
        lo = np.nan
    if not in_range(hi):
        log_issue(year, stn, label, "out_of_range_max_dropped", str(hi))
        hi = np.nan
    warn = WARN_ABOVE.get(label)
    if warn and pd.notna(hi) and hi > warn:
        log_issue(year, stn, label, "extreme_value_kept", str(hi))
    return lo, hi


def load_year(path):
    year = int(re.search(r"(\d{4})_lake_data", path.name).group(1))
    df = pd.read_csv(path, dtype=str)
    df["year"] = year
    return df


def canonical_states(series):
    """Fix PDF line-wrap damage: 'LAKSHADWE EP' -> 'LAKSHADWEEP' (most common spelling wins)."""
    cleaned = series.map(lambda s: squash(s).upper() if pd.notna(s) else np.nan)
    key = cleaned.map(lambda s: re.sub(r"\s+", "", s) if pd.notna(s) else np.nan)
    best = {}
    for k, group in cleaned.groupby(key):
        best[k] = Counter(group).most_common(1)[0][0]
    return key.map(best)


def main():
    raw = pd.concat([load_year(p) for p in sorted(RAW_DIR.glob("*_lake_data.csv"))],
                    ignore_index=True)
    n_raw = len(raw)

    # --- station code: keep numeric ones, drop header-repeat / junk rows -----------------
    raw["stn_code"] = raw["STN Code"].map(lambda x: int(tokens(x)[0]) if tokens(x) else np.nan)
    junk = raw["stn_code"].isna()
    for _, r in raw[junk].iterrows():
        log_issue(r["year"], None, "-", "junk_row_dropped", str(r["STN Code"])[:30])
    raw = raw[~junk].copy()
    raw["stn_code"] = raw["stn_code"].astype(int)

    # --- text fields ---------------------------------------------------------------------
    raw["station_name"] = raw["Name of Monitoring Location"].map(squash)
    raw["state"] = canonical_states(raw["State Name"])
    raw["water_body_type"] = raw["Type Water Body"].map(lambda s: squash(s).upper() if pd.notna(s) else np.nan)

    # --- numeric parameters --------------------------------------------------------------
    records = []
    for _, r in raw.iterrows():
        rec = dict(stn_code=r["stn_code"], year=r["year"])
        for label, (col, lo_ok, hi_ok) in PARAMS.items():
            lo, hi = parse_pair(r[f"Min {label}"], r[f"Max {label}"],
                                r["year"], r["stn_code"], label, lo_ok, hi_ok)
            rec[f"{col}_min"], rec[f"{col}_max"] = lo, hi
        records.append(rec)
    fact = pd.DataFrame(records)

    value_cols = [c for c in fact.columns if c.endswith(("_min", "_max"))]
    fact["completeness_pct"] = (fact[value_cols].notna().mean(axis=1) * 100).round(1)

    # --- duplicates: same station + year -> keep the most complete row -------------------
    fact["_order"] = np.arange(len(fact))
    fact = fact.sort_values(["stn_code", "year", "completeness_pct", "_order"],
                            ascending=[True, True, False, True])
    dup_mask = fact.duplicated(["stn_code", "year"], keep="first")
    for _, r in fact[dup_mask].iterrows():
        log_issue(r["year"], r["stn_code"], "-", "duplicate_station_year_dropped")
    fact = fact[~dup_mask].drop(columns="_order").sort_values(["stn_code", "year"]).reset_index(drop=True)

    # --- station dimension: latest name, most common state/type --------------------------
    raw_sorted = raw.sort_values("year")
    dim = (raw_sorted.groupby("stn_code")
           .agg(station_name=("station_name", "last"),
                state=("state", lambda s: Counter(s.dropna()).most_common(1)[0][0] if s.notna().any() else np.nan),
                water_body_type=("water_body_type", lambda s: Counter(s.dropna()).most_common(1)[0][0] if s.notna().any() else np.nan),
                first_year=("year", "min"), last_year=("year", "max"),
                years_monitored=("year", "nunique"))
           .reset_index())

    dq = pd.DataFrame(issues)

    # --- write outputs -------------------------------------------------------------------
    CLEAN_DIR.mkdir(parents=True, exist_ok=True)
    dim.to_csv(CLEAN_DIR / "dim_station.csv", index=False)
    fact.to_csv(CLEAN_DIR / "fact_lake_quality.csv", index=False)
    dq.to_csv(CLEAN_DIR / "dq_issues.csv", index=False)

    with sqlite3.connect(DB_PATH) as con:
        dim.to_sql("dim_station", con, if_exists="replace", index=False)
        fact.to_sql("fact_lake_quality", con, if_exists="replace", index=False)
        dq.to_sql("dq_issues", con, if_exists="replace", index=False)

    # --- summary -------------------------------------------------------------------------
    print(f"raw rows           : {n_raw:,}")
    print(f"clean fact rows    : {len(fact):,}")
    print(f"stations           : {len(dim):,}")
    print(f"states             : {dim['state'].nunique()}")
    print(f"avg completeness   : {fact['completeness_pct'].mean():.1f}%")
    print("\nData quality issues handled:")
    print(dq["issue"].value_counts().to_string())


if __name__ == "__main__":
    main()
