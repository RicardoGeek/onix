"""Study 6: tail mean-reversion ("snap-back to the ribbon").  Event = M15 close where price is stretched from the
ribbon (dist to EMA-fast in ATR >= k) or the last-hour move ret4 >= k ATR; trade = FADE toward the ribbon.
Split by ribbon context: stretch WITH the 7-EMA stack (trend extension) vs AGAINST it (counter-trend spike)."""
import sys
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E
import sw_events as V

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
b = E.add_ribbon(E.make_bars(m1a, 15))
n = b["n"]
c, a, Em = b["c"], b["atr"], b["E"]
years = pd.to_datetime(b["t"], unit="s").year.values
d0 = (c - Em[0]) / a
ret4 = np.r_[np.full(4, np.nan), (c[4:] - c[:-4])] / a
stack = np.where(b["stack_bull"], 1, np.where(b["stack_bear"], -1, 0))
cost_usd = 0.08 + 0.05 + 0.05
nxt = b["m1e"]
okgap = np.r_[(m1a["t"][np.minimum(nxt[:-1], len(m1a["t"]) - 1)] - m1a["t"][nxt[:-1] - 1]) <= 1800, False]
ys = V.YS
for feat, fname in ((d0, "dist20"), (ret4, "ret1h")):
    for k in (1.5, 2.0, 2.5, 3.0, 4.0):
        for ctx in ("with_stack", "against_stack", "any"):
            sgn = np.sign(feat)
            ev = (np.abs(feat) >= k) & okgap
            ev[:1500] = False
            # avoid consecutive duplicates: first bar of each stretch episode
            ev[1:] &= ~((np.abs(feat[:-1]) >= k) & (np.sign(feat[:-1]) == sgn[1:]))
            if ctx == "with_stack":
                ev &= stack == sgn
            elif ctx == "against_stack":
                ev &= stack == -sgn
            idx = np.flatnonzero(ev)
            if len(idx) < 80:
                continue
            dirs = -sgn[idx].astype(np.int64)  # fade
            mfe, _ = V.excursions_nb(b["m1e"][idx], dirs, a[idx], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], ys, 960)
            s, rows = V.table(mfe, cost_usd / a[idx], f"{fname}>={k} {ctx:13s}")
            y_, x_ = sorted(rows, key=lambda r: -r[3])[0][:2]
            yi = list(ys).index(y_)
            per = []
            for yy in range(2017, 2027):
                m = years[idx] == yy
                if m.sum() < 5:
                    per.append("  .  "); continue
                w = mfe[m, yi] >= x_
                per.append(f"{np.mean((w * x_ - (~w) * y_ - cost_usd / a[idx][m]) / y_):+.2f}")
            days = (b["t"][idx[-1]] - b["t"][idx[0]]) / 86400 * 5 / 7
            print(f"{s[:118]} [{len(idx) / days:.2f}/d] yrs: {' '.join(per)}")
