"""Study 20: SevenWave Liquidity-Wave v2 - core hierarchy streams + frequency fallback, small-partial + runner
management grid, daily-coverage stats (share of weekdays with a new trade, max idle)."""
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
tfs["H2"] = M.tf_states(E.make_bars(m1a, 120))
ATR_H1 = tfs["H1"]["atr"]


def trend_of(T, names):
    if names == ("both",):
        return np.full(T["n"], 2, np.int64)
    out = None
    for h in names:
        k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
        sd = tfs[h]["stackd"][k]
        out = sd if out is None else np.where(out == sd, sd, 0)
    return out.astype(np.int64)


def stream_events(S, LR, filt, off, amin, amax):
    T = tfs[S]
    ph, phi, pl, pli = pools_nb(T["h"], T["l"], LR, LR)
    if filt == ("both",):
        parts = []
        for sgn in (1, -1):
            parts.append(pool_stop_events_nb(ph, phi, pl, pli, T["atr"], np.full(T["n"], sgn, np.int64), T["m1s"],
                                             T["m1e"], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], off, amin, amax, 0.05, 3.0))
        em = np.concatenate([p[0] for p in parts]); ed = np.concatenate([p[1] for p in parts])
        ep = np.concatenate([p[2] for p in parts])
    else:
        em, ed, ep, _ = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], trend_of(T, filt), T["m1s"], T["m1e"], m1a["o"],
                                            m1a["h"], m1a["l"], m1a["spr"], off, amin, amax, 0.05, 3.0)
    k = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][em]), 0)
    return em, ed, ep, ATR_H1[k]


STREAMS = {
    "A H1|H4+D1 a12-48": ("H1", 3, ("H4", "D1"), 0.15, 12, 48),
    "B H2|H4+D1 a6-48": ("H2", 3, ("H4", "D1"), 0.0, 6, 48),
    "C H1|H4 a12-120": ("H1", 3, ("H4",), 0.15, 12, 120),
    "D H1|none a12-48": ("H1", 3, ("both",), 0.15, 12, 48),
    "E H1|H1 a12-48": ("H1", 3, ("H1",), 0.15, 12, 48),
}
ev = {n: stream_events(*v) for n, v in STREAMS.items()}
for n, v in ev.items():
    print(f"{n}: {len(v[0])} fills")


def coverage(tr):
    d = pd.to_datetime(tr["entry_t"], unit="s").dt.normalize()
    days = pd.bdate_range(d.min(), d.max())
    return len(set(d)) / len(days)


def combo(names, sl_k, trail_k, mg, label="", show=True):
    ej = np.concatenate([ev[n][0] for n in names]); ed = np.concatenate([ev[n][1] for n in names])
    ep = np.concatenate([ev[n][2] for n in names]); ea = np.concatenate([ev[n][3] for n in names])
    st = np.concatenate([np.full(len(ev[n][0]), i) for i, n in enumerate(names)])
    tr = S2.run_fills(m1a, ej, ed, ep, sl_k * ea, trail_k * ea, mg, meta={"stream": st})
    s = E.year_stats(tr)
    a = s.iloc[-1]; yrs = s.iloc[:-1]
    if show:
        print(f"{label:34s} n={a.n:5d} tpd={a.tpd:.2f} cov={coverage(tr):.2f} wr={a.wr:4.1f} avgR={a.avg_r:+.3f} "
              f"sumR={a.sum_r:+7.1f} pf={a.pf:4.2f} +yrs={int((yrs.sum_r > 0).sum())}/{len(yrs)} idle={a.max_wait_h:5.0f}h "
              f"green={a.green_m} | " + " ".join(f"{v:+5.1f}" for v in yrs.sum_r))
    return tr, s


runner = dict(tp1_r=0.4, tp1_frac=0.3, be_r=0.05, act_r=1.0, tp2_r=2.5, max_min=2880)
print("\n=== streams alone, small-partial runner (SL 1.5 ATR_H1, TP1 0.4R x30%, BE, trail 1.5 ATR after 1R, TP2 2.5R) ===")
for n in STREAMS:
    combo([n], 1.5, 1.5, runner, label=n)
print("\n=== unions ===")
U = {"A+B": ["A H1|H4+D1 a12-48", "B H2|H4+D1 a6-48"],
     "A+B+C": ["A H1|H4+D1 a12-48", "B H2|H4+D1 a6-48", "C H1|H4 a12-120"],
     "A+B+C+D": ["A H1|H4+D1 a12-48", "B H2|H4+D1 a6-48", "C H1|H4 a12-120", "D H1|none a12-48"],
     "A+B+E": ["A H1|H4+D1 a12-48", "B H2|H4+D1 a6-48", "E H1|H1 a12-48"],
     "A+B+C+E": ["A H1|H4+D1 a12-48", "B H2|H4+D1 a6-48", "C H1|H4 a12-120", "E H1|H1 a12-48"]}
for k, v in U.items():
    combo(v, 1.5, 1.5, runner, label=k)
print("\n=== management grid on A+B+C+E ===")
rows = []
for sl_k, tp1, frac, tp2, trk, act in itertools.product((1.25, 1.5, 2.0), (0.3, 0.5), (0.2, 0.33, 0.5), (2.0, 3.0, 0.0),
                                                        (1.0, 1.5), (1.0, 1.5)):
    mg = dict(tp1_r=tp1, tp1_frac=frac, be_r=0.05, act_r=act, tp2_r=tp2, max_min=2880)
    tr, s = combo(U["A+B+C+E"], sl_k, trk, mg, show=False)
    a = s.iloc[-1]; yrs = s.iloc[:-1]
    rows.append(dict(sl=sl_k, tp1=tp1, frac=frac, tp2=tp2, trail=trk, act=act, n=a.n, tpd=a.tpd, wr=a.wr, avg_r=a.avg_r,
                     sum_r=a.sum_r, pf=a.pf, pos_yrs=int((yrs.sum_r > 0).sum()), worst=yrs.sum_r.min(), green=a.green_m))
G = pd.DataFrame(rows).sort_values("sum_r", ascending=False)
pd.set_option("display.width", 240)
print(G.head(15).to_string(index=False))
print("\nWR >= 70 by sum_r:")
print(G[G.wr >= 70].head(10).to_string(index=False))
G.to_csv(rf"C:\Users\faker\Documents\goldie_research\sevenwave\data\lw2_grid_{src}.csv", index=False)
