"""Study 12: information-shock momentum.  (a) 08:30 New-York data window: direction of the first N minutes after
08:30 NY vs the rest of the hour.  (b) generic M1 volatility bursts (range >= k x the 60-minute average M1 range,
close in the outer third) followed in the burst direction from the next M1 open.  Pessimistic fills."""
import sys
import numpy as np
import pandas as pd
from numba import njit
from sw_data import load
import sw_engine as E
import sw_events as V

src = sys.argv[1] if len(sys.argv) > 1 else "pep"
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
b = E.add_ribbon(E.make_bars(m1a, 15))
atr15 = np.repeat(b["atr"], b["m1e"] - b["m1s"])
ny = pd.to_datetime(m1a["t"], unit="s").tz_localize("UTC").tz_convert("America/New_York")
nym = (ny.hour * 60 + ny.minute).values
years = ny.year.values
o, h, l, c, spr = m1a["o"], m1a["h"], m1a["l"], m1a["c"], m1a["spr"]
cost_usd = 0.07 + 0.05 + 0.05
print("=== (a) 08:30 NY window: first-N-minute direction, enter at 08:30+N next open, excursions over 120 min ===")
for N in (1, 3, 5, 10):
    for kmin in (0.5, 1.0, 1.5):
        st = np.flatnonzero(nym == 8 * 60 + 30)
        ev_j, ev_d, ev_a = [], [], []
        for j in st:
            e = j + N
            if e >= len(c) or (m1a["t"][e] - m1a["t"][j]) != N * 60:
                continue
            mv = c[e - 1] - o[j]
            if abs(mv) >= kmin * atr15[j]:
                ev_j.append(e); ev_d.append(1 if mv > 0 else -1); ev_a.append(atr15[j])
        if len(ev_j) < 40:
            continue
        ev_j = np.array(ev_j, np.int64); ev_d = np.array(ev_d, np.int64); ev_a = np.array(ev_a)
        mfe, _ = V.excursions_nb(ev_j, ev_d, ev_a, o, h, l, spr, V.YS, 120)
        s, rows = V.table(mfe, cost_usd / ev_a, f"N={N:2d}m |move|>={kmin}ATR")
        y_, x_ = sorted(rows, key=lambda r: -r[3])[0][:2]
        yi = list(V.YS).index(y_)
        per = []
        for yy in range(2017, 2027):
            m = years[ev_j] == yy
            if m.sum() < 3:
                per.append("  .  "); continue
            w = mfe[m, yi] >= x_
            per.append(f"{np.mean((w * x_ - (~w) * y_ - cost_usd / ev_a[m]) / y_):+.2f}")
        print(f"{s[:120]}  yrs: {' '.join(per)}")


@njit(cache=True)
def bursts_nb(o, h, l, c, k, cool):
    n = len(c)
    out_j = np.zeros(n, np.int64); out_d = np.zeros(n, np.int64)
    cnt = 0
    avg = 0.0
    last = -10 ** 9
    for i in range(n - 1):
        r = h[i] - l[i]
        if i >= 60 and avg > 0 and r >= k * avg and i - last >= cool:
            pos = (c[i] - l[i]) / max(r, 1e-9)
            if pos >= 0.67:
                out_j[cnt] = i + 1; out_d[cnt] = 1; cnt += 1; last = i
            elif pos <= 0.33:
                out_j[cnt] = i + 1; out_d[cnt] = -1; cnt += 1; last = i
        avg = avg + (r - avg) / 60.0 if i > 0 else r
    return out_j[:cnt], out_d[:cnt]


print("\n=== (b) generic M1 bursts, follow direction ===")
for k in (4.0, 6.0, 8.0):
    for fade in (False, True):
        j, d = bursts_nb(o, h, l, c, k, 30)
        if fade:
            d = -d
        a = atr15[j]
        mfe, _ = V.excursions_nb(j, d, a, o, h, l, spr, V.YS, 240)
        s, rows = V.table(mfe, cost_usd / a, f"burst k={k} {'FADE' if fade else 'FOLLOW'}")
        y_, x_ = sorted(rows, key=lambda r: -r[3])[0][:2]
        yi = list(V.YS).index(y_)
        per = []
        for yy in range(2017, 2027):
            m = years[j] == yy
            if m.sum() < 3:
                per.append("  .  "); continue
            w = mfe[m, yi] >= x_
            per.append(f"{np.mean((w * x_ - (~w) * y_ - cost_usd / a[m]) / y_):+.2f}")
        days = (m1a["t"][j[-1]] - m1a["t"][j[0]]) / 86400 * 5 / 7
        print(f"{s[:120]} [{len(j) / days:.2f}/d] yrs: {' '.join(per)}")
