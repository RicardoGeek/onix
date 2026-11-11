"""Study 50: FAILED-BREAKOUT exits.  A pool breakout that has not followed through is likely a fake; cut it before the
full -1R stop.  Two pre-registered families (sw_sim3), on top of the v1.30-like whale management of study 44:
  NF  no follow-through: nf_min minutes after the fill, best excursion still < nf_r R -> exit at the next open
  BI  back inside: a completed M15 / H1 close more than bi_r R beyond the entry against the trade -> exit at the next open
Grid chosen on 2017-2021 only (setup-level avg R), judged on 2022-2026 and in the account replay (both windows).
"""
import sys
import numpy as np
import pandas as pd
from sw_study37_lib import (m, J, D, PX, AT, SI, mg, trk, Rv, W, K, acct, total_row, first_touch)
import sw_sim3 as S3

Dl = D.astype(np.int64)


def outcomes(extra):
    g = dict(mg, **extra)
    pb = S3.run_fills(m, J, Dl, PX, Rv, trk * AT, g, one_at_a_time=False).set_index("eidx")
    xt = np.zeros(len(J), np.int64); xt[pb.index.values] = pb.exit_t.values
    ja = first_touch(J.astype(np.int64), Dl, PX, Rv, xt, m["t"], m["h"], m["l"], m["spr"], K)
    has = ja >= 0
    hidx = np.flatnonzero(has)
    ex = S3.run_fills(m, J[has], Dl[has], PX[has], Rv[has], trk * AT[has], dict(g, tp2_r=5.0, max_min=4320), one_at_a_time=False)
    ex.index = hidx[ex.eidx.values]
    cm = pb.index.intersection(ex.index)
    pb.loc[cm, ["entry_t", "exit_t", "r"]] = ex.loc[cm, ["entry_t", "exit_t", "r"]].values
    addpx = np.where(D > 0, PX + K * Rv + 0.05, PX - K * Rv - 0.05)
    mga = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=(5.0 - K) / K, max_min=4320)
    ad = S3.run_fills(m, ja[has], Dl[has], addpx[has], K * Rv[has], trk * AT[has], mga, one_at_a_time=False)
    adds = {int(hidx[e]): (int(a0), int(a1), float(r)) for e, a0, a1, r in zip(ad.eidx.values, ad.entry_t.values, ad.exit_t.values, ad.r.values)}
    return pb, adds


def events(pb, adds, with_adds):
    ev = []
    for e in pb.index.values:
        q = pb.loc[e]
        ev.append((int(q.entry_t), "P", ("v", int(e)), int(q.exit_t), float(q.r), float(Rv[e]), W[int(SI[e])]))
        if with_adds and int(e) in adds:
            a0, a1, ar = adds[int(e)]
            ev.append((a0, "A", ("v", int(e)), a1, ar, K * float(Rv[e]) + 0.05, W[int(SI[e])] * K))
    ev.sort(key=lambda z: (z[0], z[1]))
    return ev


GRID = {"baseline": {}}
for nmn in (60, 120, 240, 480):
    for nr in (0.25, 0.5):
        GRID[f"NF {nmn}m < {nr}R"] = dict(nf_min=nmn, nf_r=nr)
for tf, tl in ((900, "M15"), (3600, "H1")):
    for br in (0.0, 0.25, 0.5):
        GRID[f"BI {tl} close < -{br}R"] = dict(bi_tf=tf, bi_r=br)

res = {}
print("| Exit rule | n | WR | avg R 2017-21 | avg R 2022-26 | avg loss R | years better than baseline |")
print("|---|---|---|---|---|---|---|")
base_py = None
for name, extra in GRID.items():
    pb, adds = outcomes(extra)
    res[name] = (pb, adds)
    y = pb.year.values
    py = pb.groupby("year").r.mean()
    if base_py is None:
        base_py = py
    better = int((py.reindex(base_py.index) > base_py).sum()) if name != "baseline" else 0
    print(f"| {name} | {len(pb)} | {(pb.r > 0).mean() * 100:.1f}% | {pb.r[y <= 2021].mean():+.3f} | {pb.r[y >= 2022].mean():+.3f} | "
          f"{pb.r[pb.r <= 0].mean():+.3f} | {better}/{len(base_py)} |")

b = res["baseline"][0]
sel = sorted([k for k in GRID if k != "baseline"], key=lambda k: -res[k][0].r[res[k][0].year <= 2021].mean())[:3]
print(f"\nchosen on 2017-2021: {sel}")
WIN = (("2018-01-01", "2024-01-01", "2018-2023"), ("2024-01-01", "2026-11-01", "2024-2026"))
print("| Run | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score | |")
print("|---|---|---|---|---|---|---|---|---|")
for name in ["baseline"] + sel:
    pb, adds = res[name]
    evg, evp = events(pb, adds, True), events(pb, adds, False)
    for (a, b_, lab) in WIN:
        print(total_row(acct(evg, 0.5, 3, 1.0, 1e4, 10.0, 30.0, 0.0, a, b_), 1e4, f"GROWTH $10k {lab} {name}"))
    for (a, b_, lab) in WIN:
        print(total_row(acct(evp, 0.15, 2, 0.5, 5e4, 3.0, 6.0, 2.4, a, b_), 5e4, f"PROP $50k {lab} {name}"))
