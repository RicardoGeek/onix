"""Study 42: whale management round 2 (on top of v1.30) + the whale extension for Prop (no add).
For trades that reached +1.5R ('has'): probe + add use TP / time stop / trail variants.  Prop never adds; its extension only
changes the probe's target / time stop / trail.  Real-lot account replay (study 37 engine), Dukascopy, two fresh windows.
"""
import numpy as np
import pandas as pd
from sw_study37_lib import (m, J, D, PX, AT, SI, mg, slk, trk, Rv, probe, W, K, ja, has, addpx, S2, acct, total_row)

hidx = np.flatnonzero(has)


def variant(tpx, tmax, trail_k, with_adds):
    if tpx == 3.0 and tmax == 1440 and trail_k == trk:
        pr = probe
    else:
        ext = S2.run_fills(m, J[has], D[has].astype(np.int64), PX[has], Rv[has], trail_k * AT[has], dict(mg, tp2_r=tpx, max_min=tmax),
                           one_at_a_time=False)
        ext.index = hidx[ext.eidx.values]
        pr = probe.copy()
        common = pr.index.intersection(ext.index)
        pr.loc[common, ["entry_t", "exit_t", "r"]] = ext.loc[common, ["entry_t", "exit_t", "r"]].values
    adds = {}
    if with_adds:
        mga = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=(tpx - K) / K, max_min=tmax)
        ad = S2.run_fills(m, ja[has], D[has].astype(np.int64), addpx[has], K * Rv[has], trail_k * AT[has], mga, one_at_a_time=False)
        adds = {int(hidx[e]): (int(a0), int(a1), float(r)) for e, a0, a1, r in zip(ad.eidx.values, ad.entry_t.values, ad.exit_t.values, ad.r.values)}
    ev = []
    for e in pr.index.values:
        t = pr.loc[e]
        ev.append((int(t.entry_t), "P", ("v", int(e)), int(t.exit_t), float(t.r), float(Rv[e]), W[int(SI[e])]))
        if int(e) in adds:
            a0, a1, ar = adds[int(e)]
            ev.append((a0, "A", ("v", int(e)), a1, ar, K * float(Rv[e]) + 0.05, W[int(SI[e])] * K))
    ev.sort(key=lambda z: (z[0], z[1]))
    return ev


WIN = (("2018-01-01", "2024-01-01", "2018-2023"), ("2024-01-01", "2026-11-01", "2024-2026"))
print("| Run | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score | |")
print("|---|---|---|---|---|---|---|---|---|")
for lab_v, (tpx, tmax, tk) in (("v1.30 TP5R/72h trail2", (5.0, 4320, 2.0)), ("TP5R/72h trail3", (5.0, 4320, 3.0)),
                               ("TP8R/120h trail3", (8.0, 7200, 3.0)), ("TP5R/72h trail2.5", (5.0, 4320, 2.5))):
    ev = variant(tpx, tmax, tk, True)
    for start in (1e3, 1e4):
        for (a, b, lab) in WIN:
            T = acct(ev, 0.5, 3, 1.0, start, 10.0, 30.0, 0.0, a, b)
            print(total_row(T, start, f"GROWTH ${start / 1e3:.0f}k 1% {lab} {lab_v}"))
for lab_v, (tpx, tmax, tk) in (("v1.30 Prop (no extension)", (3.0, 1440, 2.0)), ("Prop + extension TP5R/72h", (5.0, 4320, 2.0)),
                               ("Prop + extension TP5R/72h trail3", (5.0, 4320, 3.0))):
    ev = variant(tpx, tmax, tk, False)
    for (a, b, lab) in WIN:
        T = acct(ev, 0.15, 2, 0.5, 5e4, 3.0, 6.0, 2.4, a, b)
        print(total_row(T, 5e4, f"PROP $50k {lab} {lab_v}"))
