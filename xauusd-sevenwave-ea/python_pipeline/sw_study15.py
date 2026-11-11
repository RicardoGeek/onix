"""Study 15: trade management for the hierarchy setups (one position at a time, full pessimistic simulator).
Setups: M15 ribbon realign with H1+H4+D1 stacked the same way (SevenWave core), optionally + H1 realign setups.
Grid over SL (ATR M15), TP1 (R) + fraction, breakeven, chandelier trail, TP2, time stop.  Per-year table."""
import sys
import itertools
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E
import sw_mtf as M

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
tfs = M.build_hierarchy(m1a)
b = tfs["M15"]
n = b["n"]
higher = ["H1", "H4", "D1"]
hm = {h: np.maximum(M.map_last_closed(tfs[h], b["t_close"]), 0) for h in higher}
rib = b["ribbon"]
realign = np.zeros(n, np.int64)
realign[1:] = np.where((rib[1:] == 1) & (rib[:-1] != 1), 1, np.where((rib[1:] == -1) & (rib[:-1] != -1), -1, 0))
idx = np.flatnonzero(realign != 0)
idx = idx[(idx > 3000) & (idx < n - 1)]
d = realign[idx]
allst = np.all([tfs[h]["stackd"][hm[h][idx]] == d for h in higher], axis=0)
idx, d = idx[allst], d[allst]
print(f"{src}: {len(idx)} hierarchy setups")
rows = []
grid = list(itertools.product((2.0, 3.0, 4.0), (0.25, 0.4, 0.6), (0.5, 0.7), (2, 0), (3.0,), (0.0, 0.75, 1.0), (96,)))
for sl_k, tp1, frac, tmode, tk, tp2, mb in grid:
    p = dict(tp1_r=tp1, tp1_frac=frac, be_r=0.05, trail_mode=tmode, trail_k=tk, trail_act_r=tp1, tp2_r=tp2,
             max_bars=mb, exit_ema=-1)
    tr = E.run(b, m1a, idx, d, sl_k * b["atr"][idx], p)
    st = E.year_stats(tr)
    a = st.iloc[-1]
    yrs = st.iloc[:-1]
    rows.append(dict(sl=sl_k, tp1=tp1, frac=frac, trail=tmode, tp2=tp2, n=a.n, wr=a.wr, avg_r=a.avg_r, sum_r=a.sum_r,
                     pf=a.pf, tpd=a.tpd, pos_yrs=int((yrs.sum_r > 0).sum()), nyrs=len(yrs),
                     worst_yr=yrs.sum_r.min(), green=a.green_m))
R = pd.DataFrame(rows).sort_values("sum_r", ascending=False)
pd.set_option("display.width", 220)
print(R.head(25).to_string(index=False))
print("\nhighest WR with positive sum_r:")
print(R[R.sum_r > 0].sort_values("wr", ascending=False).head(10).to_string(index=False))
R.to_csv(rf"C:\Users\faker\Documents\goldie_research\sevenwave\data\mgmt_grid_{src}.csv", index=False)
