"""Study 21: optimise the 7-EMA ribbon periods of the trend gate (H1/H4/D1 stacks) for the Liquidity-Wave streams.

Candidate ribbons: the v1.00 linear set, scaled copies, geometric gradients (fast f, ratio r: f, f*r, ..., f*r^6),
and a relaxed gate (>=5 of 6 EMA pairs ordered instead of all 6).  Structure pools do not depend on the ribbon, so
they are built once.  Every config is traded with the real management, one position at a time, rules only (no AI).
Selection uses 2017-2022 ONLY; 2023-2026 is reported as the unseen check.
"""
import sys
import time
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E
import sw_mtf as M
import sw_sim2 as S2
from sw_study17 import pools_nb, pool_stop_events_nb

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
t0 = time.time()
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
tfs = M.build_hierarchy(m1a)
tfs["M30"] = M.tf_states(E.make_bars(m1a, 30))
tfs["H2"] = M.tf_states(E.make_bars(m1a, 120))
POOLS = {S: pools_nb(tfs[S]["h"], tfs[S]["l"], 3, 3) for S in ("M30", "H1", "H2")}
STREAMS = [("H1", ("H4", "D1"), 0.15, 12, 48), ("H2", ("H4", "D1"), 0.0, 6, 48), ("H1", ("H4",), 0.15, 12, 120),
           ("H1", ("H1",), 0.15, 12, 48), ("M30", ("H1", "H4"), 0.15, 12, 96), ("H1", ("H4", "D1"), 0.15, 3, 12)]
WEIGHT = np.array([1.0, 1.0, 0.5, 0.5, 0.35, 0.35])
MGMT = {"growth": (dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=3.0, max_min=1440), 1.5, 2.0),
        "prop": (dict(tp1_r=0.3, tp1_frac=0.2, be_r=0.05, act_r=1.5, tp2_r=2.0, max_min=2880), 2.0, 1.0)}
years = pd.to_datetime(m1a["t"], unit="s").year.values
print(f"setup {time.time() - t0:.0f}s")


def stack_states(periods, relaxed=False):
    out = {}
    for tf in ("H1", "H4", "D1"):
        T = tfs[tf]
        Em = np.vstack([E.ema_nb(T["c"], float(p)) for p in periods])
        d = np.diff(Em, axis=0)
        if relaxed:
            sc = np.sign(-d).sum(axis=0)
            st = np.where(sc >= 5, 1, np.where(sc <= -5, -1, 0))
        else:
            st = np.where(np.all(d < 0, axis=0), 1, np.where(np.all(d > 0, axis=0), -1, 0))
        out[tf] = st.astype(np.int64)
    return out


def trend(T, stk, names):
    o = None
    for h in names:
        k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
        sd = stk[h][k]
        o = sd if o is None else np.where(o == sd, sd, 0)
    return o.astype(np.int64)


def run_config(periods, relaxed=False):
    stk = stack_states(periods, relaxed)
    ej, ed, ep, eR, est = [], [], [], [], []
    a1 = tfs["H1"]["atr"]
    for si, (S, filt, off, amin, amax) in enumerate(STREAMS):
        T = tfs[S]
        ph, phi, pl, pli = POOLS[S]
        em, d, px, _ = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], trend(T, stk, filt), T["m1s"], T["m1e"],
                                          m1a["o"], m1a["h"], m1a["l"], m1a["spr"], off, amin, amax, 0.05, 3.0)
        k = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][em]), 0)
        ej.append(em); ed.append(d); ep.append(px); eR.append(a1[k]); est.append(np.full(len(em), si))
    ej = np.concatenate(ej); ed = np.concatenate(ed); ep = np.concatenate(ep); eA = np.concatenate(eR)
    est = np.concatenate(est)
    o = np.lexsort((est, ej))
    ej, ed, ep, eA, est = ej[o], ed[o], ep[o], eA[o], est[o]
    keep = np.r_[True, np.diff(ej) > 0]
    ej, ed, ep, eA, est = ej[keep], ed[keep], ep[keep], eA[keep], est[keep]
    res = {}
    for mode, (mg, slk, trk) in MGMT.items():
        tr = S2.run_fills(m1a, ej, ed, ep, slk * eA, trk * eA, mg, meta={"stream": est})
        tr["w"] = WEIGHT[tr.stream.values]
        tr["wr_"] = tr.r * tr.w
        per = tr.groupby("year").wr_.sum()
        res[mode] = dict(n=len(tr), avg=tr.r.mean(), wsum=tr.wr_.sum(), per=per,
                         ins=per[per.index <= 2022].sum(), oos=per[per.index >= 2023].sum(),
                         pos_ins=int((per[per.index <= 2022] > 0).sum()), pos_oos=int((per[per.index >= 2023] > 0).sum()),
                         tpd=len(tr) / ((tr.entry_t.max() - tr.entry_t.min()) / 86400 * 5 / 7))
    return res


cands = {"v1.00 linear 20-200": (20, 40, 60, 80, 100, 150, 200)}
base = np.array([20, 40, 60, 80, 100, 150, 200], float)
for s in (0.5, 0.75, 1.25, 1.5, 2.0, 3.0):
    cands[f"linear x{s}"] = tuple(np.maximum(2, np.round(base * s)).astype(int))
for f in (5, 10, 20, 30):
    for r in (1.3, 1.5, 1.8, 2.0):
        p = tuple(int(round(f * r ** k)) for k in range(7))
        if len(set(p)) == 7 and p[-1] <= 1500:
            cands[f"geom f={f} r={r}"] = p
cands["wide 10-400 even"] = (10, 75, 140, 205, 270, 335, 400)
cands["fib 8-233"] = (8, 13, 21, 34, 55, 89, 233)
rows = []
for name, p in cands.items():
    for relaxed in (False, True):
        r = run_config(p, relaxed)
        g, q = r["growth"], r["prop"]
        rows.append(dict(ribbon=name + (" [5/6]" if relaxed else ""), periods="/".join(map(str, p)), n=g["n"],
                         tpd=round(g["tpd"], 2), g_avgR=round(g["avg"], 3), g_ins=round(g["ins"], 1), g_oos=round(g["oos"], 1),
                         g_pos=f"{g['pos_ins']}/6+{g['pos_oos']}/4", p_ins=round(q["ins"], 1), p_oos=round(q["oos"], 1),
                         p_pos=f"{q['pos_ins']}/6+{q['pos_oos']}/4",
                         years=" ".join(f"{v:+.0f}" for v in g["per"].values)))
        print(f"{time.time() - t0:5.0f}s {rows[-1]['ribbon']:28s} n={g['n']:4d} tpd={g['tpd']:.2f} growth wR ins={g['ins']:+6.1f} "
              f"oos={g['oos']:+6.1f} ({rows[-1]['g_pos']}) | prop ins={q['ins']:+6.1f} oos={q['oos']:+6.1f} ({rows[-1]['p_pos']})")
R = pd.DataFrame(rows)
R.to_csv(rf"C:\Users\faker\Documents\goldie_research\sevenwave\data\ribbon_opt_{src}.csv", index=False)
pd.set_option("display.width", 250)
print("\n=== ranked by IN-SAMPLE (2017-2022) growth weighted R ===")
print(R.sort_values("g_ins", ascending=False).head(15).to_string(index=False))
