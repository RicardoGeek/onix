"""Study 2: fresh-flip edge across timeframes / ribbon scales / years (fixed TP-SL grid, pessimistic costs)."""
import sys
import time
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E
import sw_events as V

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
t0 = time.time()
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
cost_usd = (0.30 if src == "duka" else 0.25) + 0.08 + 0.05 + 0.10
years = pd.to_datetime(m1a["t"], unit="s").year.values
for tf in (5, 15, 30, 60, 240):
    b = E.make_bars(m1a, tf)
    for scale in (0.5, 1.0):
        periods = tuple(max(2, int(round(p * scale))) for p in E.DEFAULT_PERIODS)
        E.add_ribbon(b, periods)
        sig = E.fresh_signals_nb(b["bull"], b["bear"], max(8, int(480 / tf)))
        idx = np.flatnonzero(sig != 0)
        idx = idx[(idx > 1500) & (idx < b["n"] - 1)]
        d = sig[idx]
        atr = b["atr"][idx]
        mfe, cens = V.excursions_nb(b["m1e"][idx], d, atr, m1a["o"], m1a["h"], m1a["l"], m1a["spr"], V.YS, 7200)
        cost_atr = cost_usd / atr
        s, rows = V.table(mfe, cost_atr, f"tf={tf:3d} periods={periods}")
        days = (b["t"][idx[-1]] - b["t"][idx[0]]) / 86400 * 5 / 7
        print(f"{s}  [{len(idx) / days:.2f}/day]")
        # per-year EV of a mid config SL2/TP2 and SL1.5/TP0.5
        yrs = years[b["m1e"][idx]]
        line = []
        for y in sorted(set(yrs)):
            m = yrs == y
            yi = list(V.YS).index(2.0)
            w = mfe[m, yi] >= 2.0
            ev = np.nanmean((w * 2.0 - (~w) * 2.0 - cost_atr[m]) / 2.0)
            line.append(f"{y}:{ev:+.2f}")
        print("      SL2/TP2 per year: " + " ".join(line))
print(f"{time.time() - t0:.1f}s")
