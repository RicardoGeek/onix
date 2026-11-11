"""Compute MT5 HTML summary stats + AGENTS.md Lesson 16 0-100 Torture Scores for OliverKell runs."""
import os
import re
import numpy as np
import pandas as pd

dir_p = r"C:\Users\faker\Documents\onix_artifacts\reports\oliver_kell"
for nm, dep in [
    ("ok_prop50k_2018_2023", 50000),
    ("ok_prop50k_2024_2026", 50000),
    ("ok_g10k_2018_2023", 10000),
    ("ok_g10k_2024_2026", 10000),
]:
    htm_path = os.path.join(dir_p, nm + ".htm")
    if not os.path.exists(htm_path):
        continue
    htm = open(htm_path, encoding="utf-16", errors="ignore").read()

    def grab(label):
        m = re.search(re.escape(label) + r".*?<b>([^<]+)</b>", htm, re.S)
        return m.group(1).strip() if m else "?"

    print(f"=== {nm} ===")
    print("  MT5 Total Net Profit :", grab("Total Net Profit:"))
    print("  MT5 Profit Factor    :", grab("Profit Factor:"))
    print("  MT5 Balance DD Max   :", grab("Balance Drawdown Maximal:"))
    print("  MT5 Equity DD Max    :", grab("Equity Drawdown Maximal:"))
    print("  MT5 Total Trades     :", grab("Total Trades:"))

    t = pd.read_csv(os.path.join(dir_p, nm + "_trades.csv"))
    t["entry"] = pd.to_datetime(t.entry, format="%Y.%m.%d %H:%M:%S")
    t["exit"] = pd.to_datetime(t.exit, format="%Y.%m.%d %H:%M:%S")
    t = t[t.entry.dt.year > 1971].sort_values("entry").reset_index(drop=True)
    for y, g in list(t.groupby(t.entry.dt.year)) + [("ALL", t)]:
        if y == "ALL":
            y0 = pd.Timestamp(f"{t.entry.dt.year.min()}-01-01")
            y1 = pd.Timestamp("2024-01-01") if "2018_2023" in nm else pd.Timestamp("2026-11-01")
        else:
            y0 = pd.Timestamp(f"{y}-01-01")
            y1 = min(pd.Timestamp(f"{y + 1}-01-01"), pd.Timestamp("2026-11-01"))
        cal_days = max(1.0, (y1 - y0).days)
        tr_days = max(1.0, np.busday_count(y0.date(), y1.date()))
        yrs = cal_days / 365.25
        net = g.net.sum()
        n_tr = len(g)
        is_add = g.stream.str.endswith("+")
        n_pr = int((~is_add).sum())
        n_ad = int(is_add.sum())
        ann_prof = max(0.0, net / yrs)
        ann_tr = n_tr / yrs
        tpd_tr = n_tr / tr_days
        tpd_cal = n_tr / cal_days
        wait_tr_d = tr_days / max(1, n_tr)
        wait_cal_d = cal_days / max(1, n_tr)
        s_prof = 25.0 * ann_prof / (ann_prof + 30000.0)
        s_tr = 25.0 * ann_tr / (ann_tr + 35.0)
        s_freq = 25.0 * tpd_tr / (tpd_tr + 0.15)
        s_wait = 25.0 * 4.0 / (wait_tr_d + 4.0)
        tot_s = s_prof + s_tr + s_freq + s_wait
        print(
            f"  {str(y):4s}: Net={net:+10.2f} | Trades={n_tr:4d} (probes={n_pr:3d}, adds={n_ad:3d}) | "
            f"TPD={tpd_tr:.2f} tr ({tpd_cal:.2f} cal) | Wait={wait_tr_d * 24:.1f}h tr ({wait_cal_d * 24:.1f}h cal) | "
            f"TortureScore={tot_s:.1f}/100"
        )
