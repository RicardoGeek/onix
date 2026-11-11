"""Parse the outside data files into one clean numeric file, with a conservative AVAILABLE time (UTC) for every value.

Run in isolated mode on the downloaded files:  python -I sw_outside.py <raw_dir> <out.npz>

raw_dir/cftc/cot_gold_disagg.csv      CFTC Disaggregated Futures Only, COMEX gold (088691), weekly (positions as of Tuesday)
raw_dir/gpr/data_gpr_daily_recent.dta Caldara & Iacoviello daily Geopolitical Risk index (newspaper article counts)
raw_dir/epu/All_Daily_Policy_Data.csv Baker, Bloom & Davis US daily Economic Policy Uncertainty (newspapers)
raw_dir/cboe/GVZ_History.csv          CBOE Gold ETF Volatility Index (30-day implied vol of GLD options), daily close
raw_dir/cboe/VIX_History.csv          CBOE VIX, daily close
raw_dir/treasury/real_yield_YYYY.csv  US Treasury daily par real yield curve (TIPS), 10Y column

Availability (no look-ahead):
- COT: released Friday 15:30 ET for Tuesday positions, Monday after a holiday.  Used from the following MONDAY 21:00 UTC
  (report date + 6d 21h).  Shutdown backlogs: report dates 2018-12-24..2019-03-05 only from 2019-03-11 21:00 UTC, and
  2025-09-30..2025-12-23 only from 2025-12-30 21:00 UTC (CFTC cleared the 2025 backlog by 2025-12-29).
- Daily news indices (GPR, EPU): the value for day d counts articles published on day d, so it is known after day d.
  Stored with avail = d + 1 day 00:00 UTC (the study adds a realistic publication lag on top).
- GVZ / VIX close on day d (16:15 ET): avail = d + 22:00 UTC.
- Treasury real yields for day d (published in the US evening): avail = d + 1 day 06:00 UTC.
"""
import sys
import numpy as np
import pandas as pd

raw, out = sys.argv[1], sys.argv[2]
D = 86400
res = {}


def day_epoch(s, fmt=None):
    return (pd.to_datetime(s, format=fmt).values.astype("datetime64[s]").astype(np.int64) // D) * D


# ---------------------------------------------------------------- CFTC COT
c = pd.read_csv(rf"{raw}\cftc\cot_gold_disagg.csv")
c = c[c.cftc_contract_market_code.astype(str).str.zfill(6) == "088691"].copy()
c["rd"] = day_epoch(c.report_date_as_yyyy_mm_dd.str[:10])
c = c.sort_values("rd").drop_duplicates("rd")
avail = c.rd.values + 6 * D + 21 * 3600
d2e = lambda s: pd.Timestamp(s).value // 10**9
for a, b, rel in (("2018-12-24", "2019-03-05", "2019-03-11 21:00"), ("2025-09-30", "2025-12-23", "2025-12-30 21:00")):
    mk = (c.rd.values >= d2e(a)) & (c.rd.values <= d2e(b))
    avail[mk] = np.maximum(avail[mk], d2e(rel))
res["cot_rd"] = c.rd.values
res["cot_avail"] = avail
cols = dict(oi="open_interest_all", mm_l="m_money_positions_long_all", mm_s="m_money_positions_short_all",
            pm_l="prod_merc_positions_long", pm_s="prod_merc_positions_short", sw_l="swap_positions_long_all",
            sw_s="swap__positions_short_all", or_l="other_rept_positions_long", or_s="other_rept_positions_short",
            nr_l="nonrept_positions_long_all", nr_s="nonrept_positions_short_all")
for k, col in cols.items():
    res[f"cot_{k}"] = pd.to_numeric(c[col], errors="coerce").values.astype(float)
print(f"COT: {len(c)} weekly reports {pd.Timestamp(c.rd.min(), unit='s').date()} .. {pd.Timestamp(c.rd.max(), unit='s').date()}")

# ---------------------------------------------------------------- GPR daily
g = pd.read_stata(rf"{raw}\gpr\data_gpr_daily_recent.dta")
g = g.dropna(subset=["GPRD"]).sort_values("date")
res["gpr_day"] = day_epoch(g.date.values)
res["gpr_avail"] = res["gpr_day"] + D
for k in ("GPRD", "GPRD_ACT", "GPRD_THREAT"):
    res[f"gpr_{k.lower()}"] = g[k].values.astype(float)
print(f"GPR: {len(g)} days {g.date.min().date()} .. {g.date.max().date()}")

# ---------------------------------------------------------------- EPU daily
e = pd.read_csv(rf"{raw}\epu\All_Daily_Policy_Data.csv")
e["d"] = pd.to_datetime(dict(year=e.year, month=e.month, day=e.day))
e = e.dropna(subset=["daily_policy_index"]).sort_values("d")
res["epu_day"] = day_epoch(e.d.values)
res["epu_avail"] = res["epu_day"] + D
res["epu_val"] = e.daily_policy_index.values.astype(float)
print(f"EPU: {len(e)} days {e.d.min().date()} .. {e.d.max().date()}")

# ---------------------------------------------------------------- CBOE GVZ / VIX
for name, f, col in (("gvz", "GVZ_History.csv", "GVZ"), ("vix", "VIX_History.csv", "CLOSE")):
    v = pd.read_csv(rf"{raw}\cboe\{f}")
    v["d"] = pd.to_datetime(v.DATE, format="%m/%d/%Y")
    v = v.dropna(subset=[col]).sort_values("d").drop_duplicates("d")
    v = v[pd.to_numeric(v[col], errors="coerce") > 0]
    res[f"{name}_day"] = day_epoch(v.d.values)
    res[f"{name}_avail"] = res[f"{name}_day"] + 22 * 3600
    res[f"{name}_val"] = pd.to_numeric(v[col]).values.astype(float)
    print(f"{name.upper()}: {len(v)} days {v.d.min().date()} .. {v.d.max().date()}")

# ---------------------------------------------------------------- Treasury real yields (10Y)
fr = []
for y in range(2016, 2027):
    t = pd.read_csv(rf"{raw}\treasury\real_yield_{y}.csv")
    fr.append(t[["Date", "10 YR"]])
t = pd.concat(fr)
t["d"] = pd.to_datetime(t.Date, format="%m/%d/%Y")
t["v"] = pd.to_numeric(t["10 YR"], errors="coerce")
t = t.dropna(subset=["v"]).sort_values("d").drop_duplicates("d")
res["ry_day"] = day_epoch(t.d.values)
res["ry_avail"] = res["ry_day"] + D + 6 * 3600
res["ry_val"] = t.v.values.astype(float)
print(f"Real yield 10Y: {len(t)} days {t.d.min().date()} .. {t.d.max().date()}")

np.savez(out, **res)
print(f"saved {out}: {len(res)} arrays")
