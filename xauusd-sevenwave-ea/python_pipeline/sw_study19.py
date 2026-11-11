"""Study 19: SevenWave 'Liquidity-Wave' strategy = stop orders at aged unbroken swing pools on H1/H2 structure,
only in the direction of the higher-timeframe 7-EMA stack hierarchy.  Multi-stream union, one position at a time,
fill-accurate management grid.  Per-year table + frequency / idle stats."""
import sys
import itertools
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
tfs["M30"] = M.tf_states(E.make_bars(m1a, 30))
tfs["H2"] = M.tf_states(E.make_bars(m1a, 120))


def trend_of(T, names):
    out = None
    for h in names:
        k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
        sd = tfs[h]["stackd"][k]
        out = sd if out is None else np.where(out == sd, sd, 0)
    return out.astype(np.int64)


STREAMS = {
    "S1 H1|H4+D1 a12-48": ("H1", 3, ("H4", "D1"), 0.15, 12, 48),
    "S2 H2|H4+D1 a6-48": ("H2", 3, ("H4", "D1"), 0.0, 6, 48),
    "S3 H1|H4 a12-120": ("H1", 3, ("H4",), 0.15, 12, 120),
    "S4 H1|H4+D1 a3-12": ("H1", 3, ("H4", "D1"), 0.15, 3, 12),
    "S5 M30|H1+H4 a12-96": ("M30", 3, ("H1", "H4"), 0.15, 12, 96),
}
ATR_H1 = tfs["H1"]["atr"]
ev = {}
for name, (S, LR, filt, off, amin, amax) in STREAMS.items():
    T = tfs[S]
    ph, phi, pl, pli = pools_nb(T["h"], T["l"], LR, LR)
    tr = trend_of(T, filt)
    em, ed, ep, ea = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], tr, T["m1s"], T["m1e"], m1a["o"], m1a["h"],
                                         m1a["l"], m1a["spr"], off, amin, amax, 0.05, 3.0)
    # risk unit = H1 ATR at the fill (last closed H1 bar)
    k = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][em]), 0)
    ev[name] = (em, ed, ep, ATR_H1[k])
    print(f"{name}: {len(em)} fills")


def combo(names, sl_k, trail_k, mg, show=True, label=""):
    ej = np.concatenate([ev[n][0] for n in names]); ed = np.concatenate([ev[n][1] for n in names])
    ep = np.concatenate([ev[n][2] for n in names]); ea = np.concatenate([ev[n][3] for n in names])
    st = np.concatenate([np.full(len(ev[n][0]), i) for i, n in enumerate(names)])
    tr = S2.run_fills(m1a, ej, ed, ep, sl_k * ea, trail_k * ea, mg, meta={"stream": st})
    s = E.year_stats(tr)
    if show:
        a = s.iloc[-1]; yrs = s.iloc[:-1]
        print(f"{label:40s} n={a.n:5d} tpd={a.tpd:.2f} wr={a.wr:4.1f} avgR={a.avg_r:+.3f} sumR={a.sum_r:+7.1f} "
              f"pf={a.pf:4.2f} +yrs={int((yrs.sum_r > 0).sum())}/{len(yrs)} idle={a.max_wait_h:5.0f}h green={a.green_m} | "
              + " ".join(f"{v:+5.1f}" for v in yrs.sum_r))
    return tr, s


base = dict(tp1_r=0.5, tp1_frac=0.5, be_r=0.05, act_r=1.0, tp2_r=0.0, max_min=2880)
print("\n=== streams alone (SL 1.5 ATR_H1, trail 1.5 ATR_H1, TP1 0.5R/50%, BE, 48h time stop) ===")
for n in STREAMS:
    combo([n], 1.5, 1.5, base, label=n)
print("\n=== unions ===")
U1 = ["S1 H1|H4+D1 a12-48", "S2 H2|H4+D1 a6-48"]
U2 = U1 + ["S3 H1|H4 a12-120"]
U3 = U2 + ["S4 H1|H4+D1 a3-12"]
U4 = U3 + ["S5 M30|H1+H4 a12-96"]
for nm, U in (("U1 S1+S2", U1), ("U2 +S3", U2), ("U3 +S4", U3), ("U4 +S5", U4)):
    combo(U, 1.5, 1.5, base, label=nm)
print("\n=== management grid on U3 ===")
rows = []
for sl_k, tp1, act, trk, tp2, mm in itertools.product((1.0, 1.5, 2.0), (0.3, 0.5, 0.75), (0.75, 1.25), (1.0, 2.0),
                                                     (0.0, 2.5), (1440, 2880)):
    mg = dict(tp1_r=tp1, tp1_frac=0.5, be_r=0.05, act_r=act, tp2_r=tp2, max_min=mm)
    tr, s = combo(U3, sl_k, trk, mg, show=False)
    a = s.iloc[-1]; yrs = s.iloc[:-1]
    rows.append(dict(sl=sl_k, tp1=tp1, act=act, trail=trk, tp2=tp2, maxmin=mm, n=a.n, tpd=a.tpd, wr=a.wr,
                     avg_r=a.avg_r, sum_r=a.sum_r, pf=a.pf, pos_yrs=int((yrs.sum_r > 0).sum()),
                     worst=yrs.sum_r.min(), green=a.green_m))
G = pd.DataFrame(rows).sort_values("sum_r", ascending=False)
pd.set_option("display.width", 240)
print(G.head(20).to_string(index=False))
print("\nWR >= 75 sorted by sum_r:")
print(G[G.wr >= 75].head(12).to_string(index=False))
G.to_csv(rf"C:\Users\faker\Documents\goldie_research\sevenwave\data\lw_grid_{src}.csv", index=False)
