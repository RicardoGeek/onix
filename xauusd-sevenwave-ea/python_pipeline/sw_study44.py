"""Study 44: news filter at the ACCOUNT level.  Skip new first positions (probes) on key US release days (NFP, CPI, FOMC, GDP,
Retail Sales, PCE) or near high-impact releases.  Engine: study 37/39 real-lot replay with v1.30-like whale management
(TP 5R / 72h for trades that reached +1.5R, pyramid in Growth).  Dukascopy 2018-2026, two fresh windows.
"""
import numpy as np
import pandas as pd
import sw_data as SD
from sw_study37_lib import (m, J, D, PX, AT, SI, mg, trk, Rv, probe, W, K, ja, has, addpx, S2, acct, total_row)

cal = pd.read_csv(r"C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\Common\Files\sw_calendar_us.csv")
cal["t"] = cal.time_srv.values.astype(np.int64)   # calendar times are UTC
hi = cal[cal.importance == 3]
key = hi[hi.event.str.contains("Nonfarm Payrolls|^CPI|Core CPI|Fed Interest Rate Decision|FOMC Statement|GDP q/q|Retail Sales m/m|PCE", regex=True)]
ht = np.sort(hi.t.unique()); kt = np.sort(key.t.unique())
kdays = set((kt // 86400).tolist())
hidx = np.flatnonzero(has)


def near(ts, ev, before_h, after_h):
    k = np.searchsorted(ev, ts - after_h * 3600, side="left")
    return (k < len(ev)) & (ev[np.minimum(k, len(ev) - 1)] <= ts + before_h * 3600)


tJ = m["t"][J]
FILTERS = {
    "no filter": np.zeros(len(J), bool),
    "skip key-release days": np.array([(x // 86400) in kdays for x in tJ]),
    "skip +-3h of any high release": near(tJ, ht, 3, 3),
    "skip -2h..+2h of key releases": near(tJ, kt, 2, 2),
}
FILTERS["key days + 3h of any high"] = FILTERS["skip key-release days"] | FILTERS["skip +-3h of any high release"]

ext = S2.run_fills(m, J[has], D[has].astype(np.int64), PX[has], Rv[has], trk * AT[has], dict(mg, tp2_r=5.0, max_min=4320), one_at_a_time=False)
ext.index = hidx[ext.eidx.values]
pr_whale = probe.copy()
common = pr_whale.index.intersection(ext.index)
pr_whale.loc[common, ["entry_t", "exit_t", "r"]] = ext.loc[common, ["entry_t", "exit_t", "r"]].values
mga = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=(5.0 - K) / K, max_min=4320)
ad = S2.run_fills(m, ja[has], D[has].astype(np.int64), addpx[has], K * Rv[has], trk * AT[has], mga, one_at_a_time=False)
ADDS = {int(hidx[e]): (int(a0), int(a1), float(r)) for e, a0, a1, r in zip(ad.eidx.values, ad.entry_t.values, ad.exit_t.values, ad.r.values)}


def events(pr, skip, with_adds):
    ev = []
    for e in pr.index.values:
        if skip[int(e)]:
            continue
        t = pr.loc[e]
        ev.append((int(t.entry_t), "P", ("v", int(e)), int(t.exit_t), float(t.r), float(Rv[e]), W[int(SI[e])]))
        if with_adds and int(e) in ADDS:
            a0, a1, ar = ADDS[int(e)]
            ev.append((a0, "A", ("v", int(e)), a1, ar, K * float(Rv[e]) + 0.05, W[int(SI[e])] * K))
    ev.sort(key=lambda z: (z[0], z[1]))
    return ev


WIN = (("2018-01-01", "2024-01-01", "2018-2023"), ("2024-01-01", "2026-11-01", "2024-2026"))
print("| Run | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score | |")
print("|---|---|---|---|---|---|---|---|---|")
for fn, skip in FILTERS.items():
    print(f"| -- {fn}: skips {skip.sum()} of {len(skip)} setups | | | | | | | | |")
    evg = events(pr_whale, skip, True)
    evp = events(pr_whale, skip, False)
    for (a, b, lab) in WIN:
        print(total_row(acct(evg, 0.5, 3, 1.0, 1e4, 10.0, 30.0, 0.0, a, b), 1e4, f"GROWTH $10k 1% {lab} {fn}"))
    for (a, b, lab) in WIN:
        print(total_row(acct(evp, 0.15, 2, 0.5, 5e4, 3.0, 6.0, 2.4, a, b), 5e4, f"PROP $50k {lab} {fn}"))
