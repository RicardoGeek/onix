"""Study 10: stop-cascade breakouts.  Buy stop at the highest high of the last N closed M15 bars (+offset), sell stop
at the lowest low, quoted every bar; first touch on the M1 path fills at the level (+slippage, gaps fill at open).
Filter by the 7-EMA ribbon state.  Excursions from the fill (bid/ask path)."""
import sys
import numpy as np
import pandas as pd
from numba import njit
from sw_data import load
import sw_engine as E
import sw_events as V
from sw_study4 import excursions_from_fill_nb


@njit(cache=True)
def breakout_events_nb(bh, bl, atr, bm1s, bm1e, mo, mh, ml, mspr, N, off_atr, slip, ribbon, mode, cooldown):
    """mode 0: any; 1: only with the ribbon stack (long needs bull stack); 2: only when the stack is NOT aligned yet
    (the breakout is the first impulse of a potential fresh wave); 3: against the stack."""
    n = len(bh)
    ev_m1 = np.full(n, -1, np.int64); ev_dir = np.zeros(n, np.int64); ev_px = np.zeros(n); ev_atr = np.zeros(n)
    cnt = 0
    last = -10 ** 9
    for i in range(N + 1, n):
        if i - last < cooldown:
            continue
        p = i - 1
        hh = bh[p - N + 1]
        ll = bl[p - N + 1]
        for q in range(p - N + 1, p + 1):
            if bh[q] > hh:
                hh = bh[q]
            if bl[q] < ll:
                ll = bl[q]
        a = atr[p]
        up = hh + off_atr * a
        dn = ll - off_atr * a
        r = ribbon[p]
        lok = mode == 0 or (mode == 1 and r == 1) or (mode == 2 and r == 0) or (mode == 3 and r == -1)
        sok = mode == 0 or (mode == 1 and r == -1) or (mode == 2 and r == 0) or (mode == 3 and r == 1)
        for j in range(bm1s[i], bm1e[i]):
            if lok and mh[j] + mspr[j] >= up:
                px = max(up, mo[j] + mspr[j]) + slip
                ev_m1[cnt] = j; ev_dir[cnt] = 1; ev_px[cnt] = px; ev_atr[cnt] = a; cnt += 1; last = i
                break
            if sok and ml[j] <= dn:
                px = min(dn, mo[j]) - slip
                ev_m1[cnt] = j; ev_dir[cnt] = -1; ev_px[cnt] = px; ev_atr[cnt] = a; cnt += 1; last = i
                break
    return ev_m1[:cnt], ev_dir[:cnt], ev_px[:cnt], ev_atr[:cnt]


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "duka"
    m1 = load("duka_m1" if src == "duka" else "pep_m1")
    m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
    m1a = E.m1_arrays(m1, src)
    b = E.add_ribbon(E.make_bars(m1a, 15))
    years = pd.to_datetime(m1a["t"], unit="s").year.values
    ribbon = np.where(b["stack_bull"], 1, np.where(b["stack_bear"], -1, 0)).astype(np.int64)
    cost_usd = 0.07 + 0.05 * 0.5
    for N in (16, 48, 96, 192):
        for off in (-0.25, 0.0, 0.25):
            for mode, mn in ((0, "any"), (1, "with-stack"), (2, "unaligned"), (3, "against")):
                em, ed, ep, ea = breakout_events_nb(b["h"], b["l"], b["atr"], b["m1s"], b["m1e"], m1a["o"], m1a["h"],
                                                    m1a["l"], m1a["spr"], N, off, 0.05, ribbon, mode, 4)
                if len(em) < 100:
                    continue
                mfe = excursions_from_fill_nb(em, ed, ep, ea, m1a["h"], m1a["l"], m1a["spr"], V.YS, 1440)
                s, rows = V.table(mfe, cost_usd / ea, f"N={N:3d} off={off:+.2f} {mn:10s}")
                y_, x_ = sorted(rows, key=lambda r: -r[3])[0][:2]
                yi = list(V.YS).index(y_)
                per = []
                for yy in range(2017, 2027):
                    m = years[em] == yy
                    if m.sum() < 5:
                        per.append("  .  "); continue
                    w = mfe[m, yi] >= x_
                    per.append(f"{np.mean((w * x_ - (~w) * y_ - cost_usd / ea[m]) / y_):+.2f}")
                days = (m1a["t"][em[-1]] - m1a["t"][em[0]]) / 86400 * 5 / 7
                print(f"{s[:112]} [{len(em) / days:.2f}/d] yrs: {' '.join(per)}")
