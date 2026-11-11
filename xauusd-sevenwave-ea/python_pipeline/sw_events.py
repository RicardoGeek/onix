"""Event study: for candidate entries, the favourable excursion reached before each adverse-excursion level.

mfe_before_stop[e, y] = best move (in ATR units, net of entry spread) achieved before the adverse move reaches
Y[y] ATR (pessimistic: inside an M1 bar the adverse extreme counts first).  From this one matrix we can read the
win probability and expectancy of ANY fixed take-profit x / stop y pair without re-simulating.
"""
import numpy as np
from numba import njit

YS = np.array([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0])
XS = np.array([0.25, 0.35, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0])


@njit(cache=True)
def excursions_nb(ev_m1, ev_dir, ev_atr, mo, mh, ml, mspr, ys, horizon):
    ne = len(ev_m1)
    ny = len(ys)
    out = np.full((ne, ny), np.nan)
    cens = np.zeros((ne, ny), np.int64)
    nm = len(mo)
    for e in range(ne):
        j = ev_m1[e]
        d = ev_dir[e]
        a = ev_atr[e]
        if j >= nm or not (a > 0):
            continue
        ep = mo[j] + mspr[j] if d == 1 else mo[j]
        mfe = 0.0
        yi = 0
        end = min(nm, j + horizon)
        for k in range(j, end):
            sp = mspr[k]
            if d == 1:
                adv = (ep - ml[k]) / a
                fav = (mh[k] - ep) / a
            else:
                adv = (mh[k] + sp - ep) / a
                fav = (ep - (ml[k] + sp)) / a
            while yi < ny and adv >= ys[yi]:
                out[e, yi] = mfe
                yi += 1
            if yi >= ny:
                break
            if fav > mfe:
                mfe = fav
        while yi < ny:
            out[e, yi] = mfe
            cens[e, yi] = 1
            yi += 1
    return out, cens


def table(mfe, cost_atr, label="", ys=YS, xs=XS, min_ev=-0.02):
    """Win rate and expectancy (in R = stop units) for every TP x / SL y, net of cost (in ATR units per event)."""
    rows = []
    for yi, y in enumerate(ys):
        for x in xs:
            win = mfe[:, yi] >= x
            ev = (win * x - (~win) * y - cost_atr) / y
            rows.append((y, x, win.mean(), np.nanmean(ev)))
    best = sorted(rows, key=lambda r: -r[3])[:6]
    s = f"{label}: n={len(mfe)}  best: " + "  ".join(f"SL{y}/TP{x} wr={w:.2f} ev={e:+.3f}R" for y, x, w, e in best)
    return s, rows
