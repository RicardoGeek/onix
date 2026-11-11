"""Study 4: ribbon-direction + LIMIT pullback entries into the ribbon (buy the dip in a bull stack, sell the rip in
a bear stack).  Limit price = ribbon EMA[k] of the last closed M15 bar (re-quoted every bar), filled on the M1 path
when ask <= L (long) / bid >= L (short).  Excursions measured from the fill on bid/ask, adverse extreme of the fill
minute counted first."""
import sys
import time
import numpy as np
import pandas as pd
from numba import njit
from sw_data import load
import sw_engine as E
import sw_events as V



@njit(cache=True)
def limit_events_nb(stack_bull, stack_bear, bull, bear, Em, atr, bm1s, bm1e, mo, mh, ml, mspr, k_level, off_atr,
                    regap, max_age, first_only):
    """For bars i where the stack (as of bar i-1 close) is aligned and the wave is fresh (age <= max_age bars since
    the fresh flip), quote a limit at Em[k_level, i-1] -/+ off_atr*atr[i-1] during bar i."""
    n = len(stack_bull)
    ev_m1 = np.full(n, -1, np.int64)
    ev_dir = np.zeros(n, np.int64)
    ev_px = np.zeros(n)
    ev_atr = np.zeros(n)
    ev_age = np.zeros(n, np.int64)
    last_bull = -10 ** 9
    last_bear = -10 ** 9
    wave_dir = 0
    wave_start = -1
    used = False
    cnt = 0
    for i in range(1, n):
        p = i - 1
        # wave bookkeeping on bar p close
        if bull[p] and not bull[p - 1] and (last_bear > last_bull or p - last_bull >= regap):
            wave_dir = 1; wave_start = p; used = False
        if bear[p] and not bear[p - 1] and (last_bull > last_bear or p - last_bear >= regap):
            wave_dir = -1; wave_start = p; used = False
        if bull[p]:
            last_bull = p
        if bear[p]:
            last_bear = p
        if wave_dir == 1 and not stack_bull[p]:
            wave_dir = 0
        if wave_dir == -1 and not stack_bear[p]:
            wave_dir = 0
        if wave_dir == 0 or (first_only and used):
            continue
        age = p - wave_start
        if age > max_age:
            continue
        a = atr[p]
        L = Em[k_level, p] - wave_dir * off_atr * a
        for j in range(bm1s[i], bm1e[i]):
            if wave_dir == 1:
                if ml[j] + mspr[j] <= L:
                    px = min(L, mo[j] + mspr[j])  # gap below the limit fills at the open
                    ev_m1[cnt] = j; ev_dir[cnt] = 1; ev_px[cnt] = px; ev_atr[cnt] = a; ev_age[cnt] = age
                    cnt += 1; used = True
                    break
            else:
                if mh[j] >= L:
                    px = max(L, mo[j])
                    ev_m1[cnt] = j; ev_dir[cnt] = -1; ev_px[cnt] = px; ev_atr[cnt] = a; ev_age[cnt] = age
                    cnt += 1; used = True
                    break
    return ev_m1[:cnt], ev_dir[:cnt], ev_px[:cnt], ev_atr[:cnt], ev_age[:cnt]


@njit(cache=True)
def excursions_from_fill_nb(ev_m1, ev_dir, ev_px, ev_atr, mh, ml, mspr, ys, horizon):
    ne = len(ev_m1)
    ny = len(ys)
    out = np.full((ne, ny), np.nan)
    nm = len(mh)
    for e in range(ne):
        j = ev_m1[e]; d = ev_dir[e]; a = ev_atr[e]; ep = ev_px[e]
        mfe = 0.0
        yi = 0
        end = min(nm, j + horizon)
        for k in range(j, end):
            sp = mspr[k]
            if d == 1:
                adv = (ep - ml[k]) / a
                fav = (mh[k] - ep) / a if k > j else 0.0   # fill minute: no favourable credit (unknown order)
            else:
                adv = (mh[k] + sp - ep) / a
                fav = (ep - (ml[k] + sp)) / a if k > j else 0.0
            while yi < ny and adv >= ys[yi]:
                out[e, yi] = mfe
                yi += 1
            if yi >= ny:
                break
            if fav > mfe:
                mfe = fav
        while yi < ny:
            out[e, yi] = mfe
            yi += 1
    return out


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "duka"
    tf = int(sys.argv[2]) if len(sys.argv) > 2 else 15
    t0 = time.time()
    m1 = load("duka_m1" if src == "duka" else "pep_m1")
    m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
    m1a = E.m1_arrays(m1, src)
    b = E.add_ribbon(E.make_bars(m1a, tf))
    years = pd.to_datetime(m1a["t"], unit="s").year.values
    cost_usd = 0.08 + 0.10 * 0.5  # commission + (half the time a stop slips); spread already in bid/ask path
    for first_only in (True, False):
        for max_age in (16, 48, 192):
            for k in (0, 1, 2, 3, 4):
                for off in (0.0, 0.5):
                    em, ed, ep, ea, eg = limit_events_nb(b["stack_bull"], b["stack_bear"], b["bull"], b["bear"], b["E"],
                                                         b["atr"], b["m1s"], b["m1e"], m1a["o"], m1a["h"], m1a["l"],
                                                         m1a["spr"], k, off, 32, max_age, first_only)
                    sel = em > 0
                    em, ed, ep, ea = em[sel], ed[sel], ep[sel], ea[sel]
                    if len(em) < 100:
                        continue
                    mfe = excursions_from_fill_nb(em, ed, ep, ea, m1a["h"], m1a["l"], m1a["spr"], V.YS, 4320)
                    s, rows = V.table(mfe, cost_usd / ea, f"first={int(first_only)} age<={max_age:3d} EMA{b['periods'][k]:3d}-{off}ATR")
                    days = (m1a["t"][em[-1]] - m1a["t"][em[0]]) / 86400 * 5 / 7
                    # per-year EV of best config
                    y, x = rows[np.argmax([r[3] for r in rows])][:2]
                    yi = list(V.YS).index(y)
                    yrs = years[em]
                    per = []
                    for yy in range(2017, 2027):
                        m = yrs == yy
                        if m.sum() == 0:
                            continue
                        w = mfe[m, yi] >= x
                        per.append(f"{np.nanmean((w * x - (~w) * y - cost_usd / ea[m]) / y):+.2f}")
                    print(f"{s[:150]}  [{len(em) / days:.2f}/day]  yrs:{' '.join(per)}")
    print(f"{time.time() - t0:.1f}s")

