"""Study 28: robustness of the M15 fresh-wave + M15-pool streams.  Neighbouring geometric ribbons (f x r), both data
feeds (Dukascopy 2017-2026, Pepperstone 2023-2026 real spreads), growth management, independent outcomes.
A real edge must survive the whole neighbourhood, not one lucky ribbon."""
import sys
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E
import sw_mtf as M
import sw_sim2 as S2
from sw_study17 import pools_nb, pool_stop_events_nb

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
tfs = M.build_hierarchy(m1a)
MG = (dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=3.0, max_min=1440), 1.5, 2.0)
a1 = tfs["H1"]["atr"]
POOL15 = pools_nb(tfs["M15"]["h"], tfs["M15"]["l"], 3, 3)


def stacks(per):
    st, rib = {}, {}
    for tf in ("M15", "H1", "H4", "D1"):
        T = tfs[tf]
        Em = np.vstack([E.ema_nb(T["c"], float(p)) for p in per])
        sc = np.sign(-np.diff(Em, axis=0)).sum(axis=0)
        st[tf] = np.where(sc >= 6, 1, np.where(sc <= -6, -1, 0)).astype(np.int64)
        rib[tf] = np.where((st[tf] == 1) & (T["c"] > Em[0]), 1, np.where((st[tf] == -1) & (T["c"] < Em[0]), -1, 0))
    return st, rib


def gate(st, T, names):
    o = None
    for h in names:
        k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
        sd = st[h][k]
        o = sd if o is None else np.where(o == sd, sd, 0)
    return o.astype(np.int64)


def run(per):
    st, rib = stacks(per)
    T = tfs["M15"]
    g = gate(st, T, ("H1", "H4", "D1"))
    rb = rib["M15"]
    r = np.zeros(T["n"], np.int64)
    r[1:] = np.where((rb[1:] == 1) & (rb[:-1] != 1) & (g[1:] == 1), 1, np.where((rb[1:] == -1) & (rb[:-1] != -1) & (g[1:] == -1), -1, 0))
    idx = np.flatnonzero(r != 0)
    idx = idx[(idx > 2000) & (idx < T["n"] - 1)]
    j = T["m1e"][idx]
    ok = (m1a["t"][np.minimum(j, len(m1a["t"]) - 1)] - m1a["t"][j - 1]) <= 1800
    idx, j = idx[ok], j[ok]
    d = r[idx]
    px = np.where(d > 0, m1a["o"][j] + m1a["spr"][j] + 0.05, m1a["o"][j] - 0.05)
    out = {}
    for name, (em, dd, pp) in (("wave", (j, d, px)),):
        k = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][em]), 0)
        tr = S2.run_fills(m1a, em, dd, pp, MG[1] * a1[k], MG[2] * a1[k], MG[0], one_at_a_time=False)
        out[name] = tr
    ph, phi, pl, pli = POOL15
    em, dd, pp, _ = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], g, T["m1s"], T["m1e"], m1a["o"], m1a["h"], m1a["l"],
                                       m1a["spr"], 0.15, 12, 96, 0.05, 3.0)
    k = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][em]), 0)
    out["pool15"] = S2.run_fills(m1a, em, dd, pp, MG[1] * a1[k], MG[2] * a1[k], MG[0], one_at_a_time=False)
    return out


print(src)
for f in (3, 5, 8, 10, 15, 20):
    for rr in (1.6, 1.8, 2.0):
        per = tuple(int(round(f * rr ** k)) for k in range(7))
        if len(set(per)) < 7:
            continue
        o = run(per)
        line = f"ribbon {'/'.join(map(str, per)):28s}"
        for nm, tr in o.items():
            yr = tr.groupby("year").r.sum()
            line += (f" | {nm}: n={len(tr):5d} avgR={tr.r.mean():+.3f} +yrs={int((yr > 0).sum())}/{len(yr)} "
                     f"worst={yr.min():+5.0f}")
        print(line)
