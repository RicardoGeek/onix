"""Study 27: new cadence streams under the geometric ribbon (5/9/16/29/52/94/170), rules only, independent outcomes.

  H4pool    : H4 (NY-anchored) structure pools, D1 gate
  M15pool   : M15 structure pools, H1+H4+D1 gate
  M15wave   : M15 ribbon fresh realign (market entry at the M15 close) with H1+H4+D1 stacked the same way
  H1pool2   : core H1 pools (H4+D1) but a wider age window (48-240) = older, bigger pools
Per stream: n, trades/day, WR, avgR under the growth management, per-year sumR (selection 2017-2022 | unseen 2023+).
"""
import numpy as np
import pandas as pd
import sw_study22 as S22
import sw_engine as E
import sw_mtf as M
import sw_sim2 as S2
from sw_study17 import pools_nb, pool_stop_events_nb

PER = (5, 9, 16, 29, 52, 94, 170)
m1a, tfs = S22.m1a, S22.tfs
tfs["M15"] = M.tf_states(E.make_bars(m1a, 15))
stk = S22.stacks(PER, 6)
for tf in ("M15", "H4"):
    Em = np.vstack([E.ema_nb(tfs[tf]["c"], float(p)) for p in PER])
    sc = np.sign(-np.diff(Em, axis=0)).sum(axis=0)
    stk[tf] = np.where(sc >= 6, 1, np.where(sc <= -6, -1, 0)).astype(np.int64)
    tfs[tf]["ribbon_g"] = np.where((stk[tf] == 1) & (tfs[tf]["c"] > Em[0]), 1,
                                   np.where((stk[tf] == -1) & (tfs[tf]["c"] < Em[0]), -1, 0))
mg, slk, trk = S22.MGMT["growth"]
a1 = tfs["H1"]["atr"]


def gate(T, names):
    o = None
    for h in names:
        k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
        sd = stk[h][k]
        o = sd if o is None else np.where(o == sd, sd, 0)
    return o.astype(np.int64)


def pool_stream(S, names, off, amin, amax):
    T = tfs[S]
    ph, phi, pl, pli = pools_nb(T["h"], T["l"], 3, 3)
    em, d, px, _ = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], gate(T, names), T["m1s"], T["m1e"], m1a["o"], m1a["h"],
                                      m1a["l"], m1a["spr"], off, amin, amax, 0.05, 3.0)
    return em, d, px


def wave_stream():
    T = tfs["M15"]
    rib = T["ribbon_g"]
    g = gate(T, ("H1", "H4", "D1"))
    r = np.zeros(T["n"], np.int64)
    r[1:] = np.where((rib[1:] == 1) & (rib[:-1] != 1) & (g[1:] == 1), 1,
                     np.where((rib[1:] == -1) & (rib[:-1] != -1) & (g[1:] == -1), -1, 0))
    idx = np.flatnonzero(r != 0)
    idx = idx[(idx > 2000) & (idx < T["n"] - 1)]
    j = T["m1e"][idx]
    ok = (m1a["t"][np.minimum(j, len(m1a["t"]) - 1)] - m1a["t"][j - 1]) <= 1800
    idx, j = idx[ok], j[ok]
    d = r[idx]
    px = np.where(d > 0, m1a["o"][j] + m1a["spr"][j] + 0.05, m1a["o"][j] - 0.05)
    return j, d, px


def evaluate(name, em, d, px):
    k = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][em]), 0)
    tr = S2.run_fills(m1a, em, d, px, slk * a1[k], trk * a1[k], mg, one_at_a_time=False)
    per = tr.groupby("year").r.sum()
    days = (tr.entry_t.max() - tr.entry_t.min()) / 86400 * 5 / 7
    print(f"{name:10s} n={len(tr):5d} tpd={len(tr) / days:.2f} wr={(tr.r > 0).mean() * 100:4.1f} avgR={tr.r.mean():+.3f} "
          f"ins={per[per.index <= 2022].sum():+6.1f} ({int((per[per.index <= 2022] > 0).sum())}/6) "
          f"oos={per[per.index >= 2023].sum():+6.1f} ({int((per[per.index >= 2023] > 0).sum())}/4) | "
          + " ".join(f"{v:+.0f}" for v in per.values))
    return tr


print("reference core streams (g5x1.8 gate):")
evaluate("A H1|H4D1", *pool_stream("H1", ("H4", "D1"), 0.15, 12, 48))
evaluate("B H2|H4D1", *pool_stream("H2", ("H4", "D1"), 0.0, 6, 48))
print("candidates:")
for amin, amax in ((3, 12), (6, 30), (12, 60)):
    evaluate(f"H4pool{amin}-{amax}", *pool_stream("H4", ("D1",), 0.15, amin, amax))
for amin, amax in ((12, 48), (12, 96), (48, 192)):
    evaluate(f"M15p{amin}-{amax}", *pool_stream("M15", ("H1", "H4", "D1"), 0.15, amin, amax))
evaluate("M15wave", *wave_stream())
evaluate("H1pool2", *pool_stream("H1", ("H4", "D1"), 0.15, 48, 240))
evaluate("H2pool2", *pool_stream("H2", ("H4", "D1"), 0.0, 48, 240))
