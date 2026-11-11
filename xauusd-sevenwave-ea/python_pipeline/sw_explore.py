"""Quick look at the raw 7-EMA fresh-wave signal under several stop/management variants (no ML yet)."""
import sys
import time
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E

pd.set_option("display.width", 220)
pd.set_option("display.max_columns", 30)

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
t0 = time.time()
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
b = E.make_bars(m1a, 15)
E.add_ribbon(b, E.DEFAULT_PERIODS)
print(f"loaded {len(m1):,} M1 -> {b['n']:,} M15 in {time.time() - t0:.1f}s")

for regap in (32, 96):
    sig = E.fresh_signals_nb(b["bull"], b["bear"], regap)
    idx = np.flatnonzero(sig != 0)
    idx = idx[idx > 1000]
    dirs = sig[idx]
    days = (b["t"][-1] - b["t"][1000]) / 86400 * 5 / 7
    print(f"\nregap={regap}: {len(idx)} fresh signals, {len(idx) / days:.2f}/trading day, long share {np.mean(dirs == 1):.2f}")
    atr = b["atr"][idx]
    dist7 = np.abs(b["c"][idx] - b["E"][6][idx])
    for slname, sld in (("1.5atr", 1.5 * atr), ("2.5atr", 2.5 * atr), ("e7+0.5atr", dist7 + 0.5 * atr)):
        for pname, p in (
            ("tp1 .5R/50% +EMA3 trail", dict(tp1_r=0.5, tp1_frac=0.5, be_r=0.05, trail_mode=1, trail_k=3, trail_act_r=0.5)),
            ("tp1 .3R/60% +chand 3", dict(tp1_r=0.3, tp1_frac=0.6, be_r=0.05, trail_mode=2, trail_k=3, trail_act_r=0.3)),
            ("no tp1, exit EMA4 close", dict(tp1_r=0, tp1_frac=0, trail_mode=0, exit_ema=3)),
            ("fixed 1R:1R", dict(tp1_r=0, tp1_frac=0, trail_mode=0, tp2_r=1.0)),
        ):
            tr = E.run(b, m1a, idx, dirs, sld, p)
            st = E.year_stats(tr)
            a = st.iloc[-1]
            print(f"  SL {slname:10s} {pname:26s} n={a.n:5d} wr={a.wr:5.1f} avgR={a.avg_r:+.3f} sumR={a.sum_r:+8.1f} "
                  f"pf={a.pf:5.2f} tpd={a.tpd:.2f} wait={a.wait_h:5.1f}h green={a.green_m}  "
                  f"yrs+={int((st.iloc[:-1].sum_r > 0).sum())}/{len(st) - 1}")
print(f"total {time.time() - t0:.1f}s")
