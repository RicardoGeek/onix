"""Study 39: let the whales run.  Only for trades that reached +1.5R (the ones that get the pyramid add), the probe AND the add
use an extended target / time stop: TP 3R (v1.20) vs 5R vs 8R, time stop 24h vs 72h.  Trades that never reach +1.5R keep the
v1.20 management.  Real-lot account replay (study 37 engine), Growth $1k and $10k at 1% and 2% risk, Prop never pyramids.
"""
import numpy as np
import pandas as pd
from sw_study37_lib import (m, J, D, PX, AT, SI, mg, slk, trk, Rv, probe, W, K, ja, has, addpx, S2, acct, total_row)

hidx = np.flatnonzero(has)


def variant(tpx, tmax):
    if tpx == 3.0 and tmax == 1440:
        pr = probe
        mga = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=(3.0 - K) / K, max_min=1440)
    else:
        ext = S2.run_fills(m, J[has], D[has].astype(np.int64), PX[has], Rv[has], trk * AT[has], dict(mg, tp2_r=tpx, max_min=tmax),
                           one_at_a_time=False)
        ext.index = hidx[ext.eidx.values]
        pr = probe.copy()
        common = pr.index.intersection(ext.index)
        pr.loc[common, ["entry_t", "exit_t", "r"]] = ext.loc[common, ["entry_t", "exit_t", "r"]].values
        mga = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=(tpx - K) / K, max_min=tmax)
    ad = S2.run_fills(m, ja[has], D[has].astype(np.int64), addpx[has], K * Rv[has], trk * AT[has], mga, one_at_a_time=False)
    adds = {int(hidx[e]): (int(a0), int(a1), float(r)) for e, a0, a1, r in zip(ad.eidx.values, ad.entry_t.values, ad.exit_t.values, ad.r.values)}
    ev = []
    for e in pr.index.values:
        t = pr.loc[e]
        ev.append((int(t.entry_t), "P", ("v", int(e)), int(t.exit_t), float(t.r), float(Rv[e]), W[int(SI[e])]))
        if int(e) in adds:
            a0, a1, ar = adds[int(e)]
            ev.append((a0, "A", ("v", int(e)), a1, ar, K * float(Rv[e]) + 0.05, W[int(SI[e])] * K))
    ev.sort(key=lambda z: (z[0], z[1]))
    rp = pr.loc[pr.index.intersection(hidx)].r.values
    ra = np.array([v[2] for v in adds.values()])
    return ev, rp.mean(), ra.mean(), len(ra)


WIN = (("2018-01-01", "2024-01-01", "2018-2023"), ("2024-01-01", "2026-11-01", "2024-2026"))
print("| Run | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score | |")
print("|---|---|---|---|---|---|---|---|---|")
for tpx, tmax in ((3.0, 1440), (5.0, 1440), (5.0, 4320), (8.0, 4320), (8.0, 7200)):
    ev, rp, ra, na = variant(tpx, tmax)
    print(f"| -- whale mgmt TP {tpx:.0f}R, time stop {tmax // 60}h: pyramided probes avg {rp:+.3f}R, adds avg {ra:+.3f}R (n={na}) | | | | | | | | |")
    for start, rk in ((1e3, 1.0), (1e4, 1.0), (1e4, 2.0)):
        for (a, b, lab) in WIN:
            T = acct(ev, 0.5, 3, rk, start, 10.0, 30.0, 0.0, a, b)
            print(total_row(T, start, f"GROWTH ${start / 1e3:.0f}k {rk:.0f}% {lab} TP{tpx:.0f}R/{tmax // 60}h"))
