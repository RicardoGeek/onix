"""Study 9: resting LIMIT fades at ribbon-stretch extremes.  Every M15 bar, quote a sell limit at
EMA[k] + m*ATR and a buy limit at EMA[k] - m*ATR (values of the last closed bar).  A touch on the M1 path fills
(sell when bid >= L, buy when ask <= L).  One fill per stretch episode.  Excursions from the fill price."""
import sys
import numpy as np
import pandas as pd
from numba import njit
from sw_data import load
import sw_engine as E
import sw_events as V
from sw_study4 import excursions_from_fill_nb


@njit(cache=True)
def stretch_limit_events_nb(Em, atr, bm1s, bm1e, mo, mh, ml, mspr, k_level, mult, cooldown_bars, side_filter, stack_dir):
    n = Em.shape[1]
    ev_m1 = np.full(n * 2, -1, np.int64)
    ev_dir = np.zeros(n * 2, np.int64)
    ev_px = np.zeros(n * 2)
    ev_atr = np.zeros(n * 2)
    cnt = 0
    last_fill_bar = -10 ** 9
    for i in range(1500, n):
        p = i - 1
        if i - last_fill_bar < cooldown_bars:
            continue
        a = atr[p]
        up = Em[k_level, p] + mult * a
        dn = Em[k_level, p] - mult * a
        for j in range(bm1s[i], bm1e[i]):
            # sell limit (fade up-spike)
            sell_ok = side_filter == 0 or (side_filter == 1 and stack_dir[p] < 0) or (side_filter == 2 and stack_dir[p] > 0)
            buy_ok = side_filter == 0 or (side_filter == 1 and stack_dir[p] > 0) or (side_filter == 2 and stack_dir[p] < 0)
            if mh[j] >= up and sell_ok:
                px = max(up, mo[j])
                ev_m1[cnt] = j; ev_dir[cnt] = -1; ev_px[cnt] = px; ev_atr[cnt] = a; cnt += 1
                last_fill_bar = i
                break
            if ml[j] + mspr[j] <= dn and buy_ok:
                px = min(dn, mo[j] + mspr[j])
                ev_m1[cnt] = j; ev_dir[cnt] = 1; ev_px[cnt] = px; ev_atr[cnt] = a; cnt += 1
                last_fill_bar = i
                break
    return ev_m1[:cnt], ev_dir[:cnt], ev_px[:cnt], ev_atr[:cnt]


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "duka"
    m1 = load("duka_m1" if src == "duka" else "pep_m1")
    m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
    m1a = E.m1_arrays(m1, src)
    b = E.add_ribbon(E.make_bars(m1a, 15))
    years = pd.to_datetime(m1a["t"], unit="s").year.values
    stack_dir = np.where(b["stack_bull"], 1, np.where(b["stack_bear"], -1, 0)).astype(np.int64)
    cost_usd = 0.07 + 0.05 * 0.5
    for k in (0, 3, 6):
        for mult in (2.0, 3.0, 4.0, 5.0):
            for sf, sfn in ((0, "both"), (1, "counter-stack"), (2, "with-stack")):
                em, ed, ep, ea = stretch_limit_events_nb(b["E"], b["atr"], b["m1s"], b["m1e"], m1a["o"], m1a["h"], m1a["l"],
                                                         m1a["spr"], k, mult, 8, sf, stack_dir)
                if len(em) < 100:
                    continue
                mfe = excursions_from_fill_nb(em, ed, ep, ea, m1a["h"], m1a["l"], m1a["spr"], V.YS, 960)
                s, rows = V.table(mfe, cost_usd / ea, f"EMA{b['periods'][k]:3d}+-{mult}ATR {sfn:13s}")
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
                print(f"{s[:120]} [{len(em) / days:.2f}/d] yrs: {' '.join(per)}")

