"""Study 46b: the only study-46 survivor (GVZ implied / realized vol, high = good) at the ACCOUNT level.
Thresholds fixed on 2017-2021 (terciles 1.217 / 1.449).  Variants: skip the bad tercile, or weight risk 0.6x / 1.0x / 1.3x.
Engine and windows as study 44 (real lots, never-breach budget, whale management, Growth pyramid)."""
import numpy as np
from sw_study37_lib import (m, J, D, PX, AT, SI, mg, trk, Rv, probe, W, K, ja, has, addpx, S2, acct, total_row)

Z = np.load(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\study46_feats.npz", allow_pickle=True)
x = Z[f"f{list(Z['names']).index('GVZ implied / realized vol (20d)')}"]
Q1, Q2 = 1.217, 1.449
hidx = np.flatnonzero(has)
ext = S2.run_fills(m, J[has], D[has].astype(np.int64), PX[has], Rv[has], trk * AT[has], dict(mg, tp2_r=5.0, max_min=4320), one_at_a_time=False)
ext.index = hidx[ext.eidx.values]
pr = probe.copy()
cm = pr.index.intersection(ext.index)
pr.loc[cm, ["entry_t", "exit_t", "r"]] = ext.loc[cm, ["entry_t", "exit_t", "r"]].values
mga = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=(5.0 - K) / K, max_min=4320)
ad = S2.run_fills(m, ja[has], D[has].astype(np.int64), addpx[has], K * Rv[has], trk * AT[has], mga, one_at_a_time=False)
ADDS = {int(hidx[e]): (int(a0), int(a1), float(r)) for e, a0, a1, r in zip(ad.eidx.values, ad.entry_t.values, ad.exit_t.values, ad.r.values)}


def events(mult, with_adds):
    ev = []
    for e in pr.index.values:
        f = mult[int(e)]
        if f <= 0:
            continue
        q = pr.loc[e]
        ev.append((int(q.entry_t), "P", ("v", int(e)), int(q.exit_t), float(q.r), float(Rv[e]), W[int(SI[e])] * f))
        if with_adds and int(e) in ADDS:
            a0, a1, ar = ADDS[int(e)]
            ev.append((a0, "A", ("v", int(e)), a1, ar, K * float(Rv[e]) + 0.05, W[int(SI[e])] * K * f))
    ev.sort(key=lambda z: (z[0], z[1]))
    return ev


nan = ~np.isfinite(x)
VAR = {
    "baseline (no GVZ)": np.ones(len(J)),
    "skip bad tercile (IV/RV <= 1.217)": np.where(nan, 1.0, np.where(x <= Q1, 0.0, 1.0)),
    "risk weight 0.6 / 1.0 / 1.3": np.where(nan, 1.0, np.where(x <= Q1, 0.6, np.where(x > Q2, 1.3, 1.0))),
}
WIN = (("2018-01-01", "2024-01-01", "2018-2023"), ("2024-01-01", "2026-11-01", "2024-2026"))
print("| Run | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score | |")
print("|---|---|---|---|---|---|---|---|---|")
for nm, mu in VAR.items():
    evg, evp = events(mu, True), events(mu, False)
    for (a, b, lab) in WIN:
        print(total_row(acct(evg, 0.5, 3, 1.0, 1e4, 10.0, 30.0, 0.0, a, b), 1e4, f"GROWTH $10k {lab} {nm}"))
    for (a, b, lab) in WIN:
        print(total_row(acct(evp, 0.15, 2, 0.5, 5e4, 3.0, 6.0, 2.4, a, b), 5e4, f"PROP $50k {lab} {nm}"))
