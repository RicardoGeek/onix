"""Study 17: structure-level breakout stops (liquidity pools) aligned with the higher-timeframe trend.

Structure TF S (M15 or H1): last confirmed fractal swing high/low that is still UNBROKEN.  Its age = S-bars since the
pivot.  Each S bar, if the trend filter agrees, quote a buy stop at swing_high - off (sell stop at swing_low + off),
off = frac * ATR_S.  Fill on the M1 path (ask >= L / bid <= L, +slippage, gaps at open).  Excursions in ATR_S."""
import sys
import numpy as np
import pandas as pd
from numba import njit
from sw_data import load
import sw_engine as E
import sw_events as V
import sw_mtf as M
from sw_study4 import excursions_from_fill_nb


@njit(cache=True)
def pools_nb(h, l, L, R):
    """For each bar i: price & pivot index of the most recent confirmed swing high/low that no later bar (up to i)
    has traded through.  Stack of unbroken pivots, nearest first."""
    n = len(h)
    ph = np.full(n, np.nan); phi = np.full(n, -1, np.int64)
    pl = np.full(n, np.nan); pli = np.full(n, -1, np.int64)
    sh_v = np.empty(4096); sh_i = np.empty(4096, np.int64); nsh = 0
    sl_v = np.empty(4096); sl_i = np.empty(4096, np.int64); nsl = 0
    for i in range(n):
        p = i - R
        if p - L >= 0:
            okh = True; okl = True
            for q in range(p - L, p + R + 1):
                if q != p:
                    if h[q] >= h[p]:
                        okh = False
                    if l[q] <= l[p]:
                        okl = False
            if okh and nsh < 4096:
                sh_v[nsh] = h[p]; sh_i[nsh] = p; nsh += 1
            if okl and nsl < 4096:
                sl_v[nsl] = l[p]; sl_i[nsl] = p; nsl += 1
        # remove pivots broken by bar i
        k = 0
        for q in range(nsh):
            if h[i] <= sh_v[q] or sh_i[q] > i - 1:
                sh_v[k] = sh_v[q]; sh_i[k] = sh_i[q]; k += 1
        nsh = k
        k = 0
        for q in range(nsl):
            if l[i] >= sl_v[q] or sl_i[q] > i - 1:
                sl_v[k] = sl_v[q]; sl_i[k] = sl_i[q]; k += 1
        nsl = k
        # nearest unbroken above current close / below current close
        best = 1e18; bi = -1
        for q in range(nsh):
            if sh_v[q] > h[i] and sh_v[q] < best:
                best = sh_v[q]; bi = q
        if bi >= 0:
            ph[i] = sh_v[bi]; phi[i] = sh_i[bi]
        best = -1e18; bi = -1
        for q in range(nsl):
            if sl_v[q] < l[i] and sl_v[q] > best:
                best = sl_v[q]; bi = q
        if bi >= 0:
            pl[i] = sl_v[bi]; pli[i] = sl_i[bi]
    return ph, phi, pl, pli


@njit(cache=True)
def pool_stop_events_nb(ph, phi, pl, pli, atr, trend, bm1s, bm1e, mo, mh, ml, mspr, off, min_age, max_age, slip,
                        max_dist_atr):
    n = len(ph)
    ev_m1 = np.full(n, -1, np.int64); ev_dir = np.zeros(n, np.int64); ev_px = np.zeros(n); ev_atr = np.zeros(n)
    cnt = 0
    used_h = -1; used_l = -1
    for i in range(1, n):
        p = i - 1
        a = atr[p]
        lv_h = ph[p]; lv_l = pl[p]
        okh = trend[p] == 1 and not np.isnan(lv_h) and phi[p] != used_h and (p - phi[p]) >= min_age and (p - phi[p]) <= max_age
        okl = trend[p] == -1 and not np.isnan(lv_l) and pli[p] != used_l and (p - pli[p]) >= min_age and (p - pli[p]) <= max_age
        if okh:
            Lh = lv_h - off * a
            if (Lh - mo[bm1s[i]]) > max_dist_atr * a:
                okh = False
        if okl:
            Ll = lv_l + off * a
            if (mo[bm1s[i]] - Ll) > max_dist_atr * a:
                okl = False
        if not (okh or okl):
            continue
        for j in range(bm1s[i], bm1e[i]):
            if okh and mh[j] + mspr[j] >= lv_h - off * a:
                px = max(lv_h - off * a, mo[j] + mspr[j]) + slip
                ev_m1[cnt] = j; ev_dir[cnt] = 1; ev_px[cnt] = px; ev_atr[cnt] = a; cnt += 1; used_h = phi[p]
                break
            if okl and ml[j] <= lv_l + off * a:
                px = min(lv_l + off * a, mo[j]) - slip
                ev_m1[cnt] = j; ev_dir[cnt] = -1; ev_px[cnt] = px; ev_atr[cnt] = a; cnt += 1; used_l = pli[p]
                break
    return ev_m1[:cnt], ev_dir[:cnt], ev_px[:cnt], ev_atr[:cnt]


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "duka"
    m1 = load("duka_m1" if src == "duka" else "pep_m1")
    m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
    m1a = E.m1_arrays(m1, src)
    tfs = M.build_hierarchy(m1a)
    years = pd.to_datetime(m1a["t"], unit="s").year.values
    cost_usd = 0.07 + 0.05 * 0.5
    for S, tr_tfs in (("M15", ("H1", "H4")), ("H1", ("H4",)), ("H1", ("H4", "D1"))):
        T = tfs[S]
        ph, phi, pl, pli = pools_nb(T["h"], T["l"], 3, 3)
        trend = np.ones(T["n"], np.int64) * 9
        tr_all = None
        for h in tr_tfs:
            k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
            sd = tfs[h]["stackd"][k]
            tr_all = sd if tr_all is None else np.where(tr_all == sd, sd, 0)
        trend_none = np.where(np.isnan(ph), 0, 1)  # placeholder
        for tmode, trend_arr in (("trend", tr_all.astype(np.int64)), ("any", None)):
            for off in (0.0, 0.15, 0.3):
                for amin, amax in ((3, 12), (12, 48), (48, 400)):
                    if trend_arr is None:
                        # no trend filter: quote both sides -> run twice with +1/-1
                        evs = []
                        for sgn in (1, -1):
                            ta = np.full(T["n"], sgn, np.int64)
                            evs.append(pool_stop_events_nb(ph, phi, pl, pli, T["atr"], ta, T["m1s"], T["m1e"], m1a["o"],
                                                           m1a["h"], m1a["l"], m1a["spr"], off, amin, amax, 0.05, 3.0))
                        em = np.concatenate([e[0] for e in evs]); ed = np.concatenate([e[1] for e in evs])
                        ep = np.concatenate([e[2] for e in evs]); ea = np.concatenate([e[3] for e in evs])
                    else:
                        em, ed, ep, ea = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], trend_arr, T["m1s"], T["m1e"],
                                                             m1a["o"], m1a["h"], m1a["l"], m1a["spr"], off, amin, amax,
                                                             0.05, 3.0)
                    if len(em) < 80:
                        continue
                    o = np.argsort(em); em, ed, ep, ea = em[o], ed[o], ep[o], ea[o]
                    mfe = excursions_from_fill_nb(em, ed, ep, ea, m1a["h"], m1a["l"], m1a["spr"], V.YS, 2880)
                    lab = f"{S} pools {'+'.join(tr_tfs) if tmode == 'trend' else 'no-filter'} off={off} age {amin}-{amax}"
                    s, rows = V.table(mfe, cost_usd / ea, lab)
                    y_, x_ = sorted(rows, key=lambda r: -r[3])[0][:2]
                    yi = list(V.YS).index(y_)
                    per = []
                    for yy in range(2017, 2027):
                        m = years[em] == yy
                        if m.sum() < 4:
                            per.append("  .  "); continue
                        w = mfe[m, yi] >= x_
                        per.append(f"{np.mean((w * x_ - (~w) * y_ - cost_usd / ea[m]) / y_):+.2f}")
                    days = (m1a["t"][em[-1]] - m1a["t"][em[0]]) / 86400 * 5 / 7
                    npos = sum(1 for q in per if q.strip() != "." and float(q) > 0)
                    print(f"{s[:118]} [{len(em) / days:.2f}/d] +y={npos} | {' '.join(per)}")
