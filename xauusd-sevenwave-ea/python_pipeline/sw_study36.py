"""Study 36: edges found in the web research, tested on Dukascopy M1 2017-2026 with hostile costs.
  A1  Caporale & Plastun (2021, Fin. Mkts & Portfolio Mgmt): on ABNORMAL days gold keeps moving in the direction of the
      abnormal move until the close.  Rule: once the day's move from the NY-day open reaches k x (20-day average daily
      range), follow it; exit at the day's last minute (or a stop of s x range).  One trade per day.
  A2  Same paper: the day AFTER an abnormal day gold reverses (contrarian).  Rule: if |yesterday's open-to-close| >= k x range,
      fade it at today's open (+5 min), exit after h hours or at the day's end, stop s x range.
  B   MQL5 CodeBase "CME Gap Tracker for Gold": fade the weekend gap toward Friday's close; target = gap fill, stop s x gap.
  C   MQL5 CodeBase "Gold Breakout EA" (Turtle): H4 close above the 20-bar high (fresh), close > EMA200, stop 2 ATR, target 2R.
      Also gated by the v1.10 H4+D1 7-EMA stacks, and with both directions.
Selection on 2017-2022, unseen 2023-2026; R per trade net of spread, commission, slippage and swap.
"""
import sys
import itertools
import numpy as np
import pandas as pd
from numba import njit
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_mtf as M
import sw_sim2 as S2

m1a, tfs = V.m1a, V.tfs
t, o, h, l, c, spr, tday = m1a["t"], m1a["o"], m1a["h"], m1a["l"], m1a["c"], m1a["spr"], m1a["tday"].astype(np.int64)
COMM, SLS, SLM, SWL = S2.COMM, S2.SLIP_STOP, S2.SLIP_MKT, S2.SWAP_LONG

# ---------------------------------------------------------------- trading-day table (NY 17:00 sessions)
starts = np.r_[0, np.flatnonzero(np.diff(tday) != 0) + 1]
ends = np.r_[starts[1:], len(t)]                      # exclusive
nd = len(starts)
dO = o[starts]; dC = c[ends - 1]
dH = np.maximum.reduceat(h, starts); dL = np.minimum.reduceat(l, starts)
rng20 = pd.Series(dH - dL).rolling(20, min_periods=20).mean().shift(1).values     # known before the day starts
dyear = pd.to_datetime(t[starts], unit="s").year.values
ny_min = ((t - 4 * 3600 - (t // 86400) * 86400) // 60) % 1440                    # rough minute-of-day (not used for logic)


@njit(cache=True)
def a1_nb(starts, ends, dO, rng, k, s, skip_min, last_entry_min, o, h, l, c, spr, comm, sls, slm):
    nd = len(starts)
    R = np.full(nd, np.nan); D = np.zeros(nd, np.int64)
    for di in range(nd):
        A = rng[di]
        if not (A > 0):
            continue
        a, b = starts[di], ends[di]
        if b - a < 600:
            continue
        for q in range(a + skip_min, min(b - 2, a + last_entry_min)):
            mv = (c[q] - dO[di]) / A
            if abs(mv) >= k:
                d = 1 if mv > 0 else -1
                j = q + 1
                ep = o[j] + spr[j] + slm if d > 0 else o[j] - slm
                stop = ep - d * s * A
                xp = np.nan
                for z in range(j, b):
                    if d > 0 and l[z] <= stop:
                        xp = min(o[z], stop) - sls; break
                    if d < 0 and h[z] + spr[z] >= stop:
                        xp = max(o[z] + spr[z], stop) + sls; break
                if np.isnan(xp):
                    xp = (c[b - 1] - slm) if d > 0 else (c[b - 1] + spr[b - 1] + slm)
                R[di] = (d * (xp - ep) - comm) / (s * A)
                D[di] = d
                break
    return R, D


@njit(cache=True)
def a2_nb(starts, ends, dO, dC, rng, k, s, hold_min, o, h, l, c, spr, comm, sls, slm, swl):
    nd = len(starts)
    R = np.full(nd, np.nan)
    for di in range(1, nd):
        A = rng[di]
        if not (A > 0):
            continue
        prev = (dC[di - 1] - dO[di - 1]) / A
        if abs(prev) < k:
            continue
        d = -1 if prev > 0 else 1
        a, b = starts[di], ends[di]
        j = a + 5
        if j >= b - 2:
            continue
        ep = o[j] + spr[j] + slm if d > 0 else o[j] - slm
        stop = ep - d * s * A
        last = min(b, j + hold_min)
        xp = np.nan
        for z in range(j, last):
            if d > 0 and l[z] <= stop:
                xp = min(o[z], stop) - sls; break
            if d < 0 and h[z] + spr[z] >= stop:
                xp = max(o[z] + spr[z], stop) + sls; break
        if np.isnan(xp):
            z = last - 1
            xp = (c[z] - slm) if d > 0 else (c[z] + spr[z] + slm)
        R[di] = (d * (xp - ep) - comm) / (s * A)
    return R


@njit(cache=True)
def gap_nb(starts, ends, dO, dC, rng, newweek, g, s, hold_min, o, h, l, c, spr, comm, sls, slm):
    nd = len(starts)
    R = np.full(nd, np.nan)
    for di in range(1, nd):
        if not newweek[di]:
            continue
        A = rng[di]
        if not (A > 0):
            continue
        gap = dO[di] - dC[di - 1]
        if abs(gap) < g * A:
            continue
        d = -1 if gap > 0 else 1
        a, b = starts[di], ends[di]
        j = a + 5
        ep = o[j] + spr[j] + slm if d > 0 else o[j] - slm
        tgt = dC[di - 1]
        if d * (tgt - ep) <= 0:
            continue                      # already filled during the first 5 minutes
        risk = s * abs(gap)
        stop = ep - d * risk
        xp = np.nan
        last = min(len(o) - 1, j + hold_min)
        for z in range(j, last):
            if d > 0 and l[z] <= stop:
                xp = min(o[z], stop) - sls; break
            if d < 0 and h[z] + spr[z] >= stop:
                xp = max(o[z] + spr[z], stop) + sls; break
            if d > 0 and h[z] >= tgt:
                xp = tgt; break
            if d < 0 and l[z] + spr[z] <= tgt:
                xp = tgt; break
        if np.isnan(xp):
            z = last
            xp = (c[z] - slm) if d > 0 else (c[z] + spr[z] + slm)
        R[di] = (d * (xp - ep) - comm) / risk
    return R


def summarize(name, R, yrs, n_days):
    m = np.isfinite(R)
    r, y = R[m], yrs[m]
    if len(r) < 40:
        return None
    py = pd.Series(r).groupby(y).mean()
    return dict(test=name, n=int(m.sum()), per_day=round(m.sum() / n_days, 3), wr=round((r > 0).mean() * 100, 1),
                avgR_17_22=round(r[y <= 2022].mean(), 3), avgR_23_26=round(r[y >= 2023].mean(), 3),
                yrs_pos=f"{int((py > 0).sum())}/{len(py)}")


rows = []
n_days = nd
for k, s, skip, lastm in itertools.product((0.4, 0.6, 0.8, 1.0, 1.3), (0.25, 0.5, 1.0), (60, 480), (720, 1320)):
    R, D = a1_nb(starts, ends, dO, rng20, k, s, skip, lastm, o, h, l, c, spr, COMM, SLS, SLM)
    x = summarize(f"A1 abnormal-day momentum k={k} stop={s} start+{skip}m last-entry+{lastm}m", R, dyear, n_days)
    if x: rows.append(x)
for k, s, hold in itertools.product((0.8, 1.0, 1.3, 1.6), (0.3, 0.5, 1.0), (120, 360, 1380)):
    R = a2_nb(starts, ends, dO, dC, rng20, k, s, hold, o, h, l, c, spr, COMM, SLS, SLM, SWL)
    x = summarize(f"A2 next-day contrarian k={k} stop={s} hold={hold}m", R, dyear, n_days)
    if x: rows.append(x)
dow = pd.to_datetime(t[starts] - 5 * 3600, unit="s").dayofweek.values
newweek = np.r_[False, (np.diff(t[starts]) > 1.5 * 86400)]
for g, s, hold in itertools.product((0.05, 0.1, 0.2, 0.3), (1.0, 2.0, 3.0), (240, 1380)):
    R = gap_nb(starts, ends, dO, dC, rng20, newweek, g, s, hold, o, h, l, c, spr, COMM, SLS, SLM)
    x = summarize(f"B weekend-gap fade g={g} stop={s}xgap hold={hold}m", R, dyear, n_days)
    if x: rows.append(x)

# ---------------------------------------------------------------- C: Turtle H4 Donchian breakout
H4 = tfs["H4"]
hh20 = pd.Series(H4["h"]).rolling(20).max().shift(1).values
ll20 = pd.Series(H4["l"]).rolling(20).min().shift(1).values
ema200 = pd.Series(H4["c"]).ewm(span=200, adjust=False).mean().values
upbrk = (H4["c"] > hh20) & ~(np.r_[False, H4["c"][:-1] > hh20[:-1]])
dnbrk = (H4["c"] < ll20) & ~(np.r_[False, H4["c"][:-1] < ll20[:-1]])
st, _ = V.stacks()
kd = np.maximum(M.map_last_closed(tfs["D1"], H4["t_close"]), 0)
g2 = np.where(st["H4"] == st["D1"][kd], st["H4"], 0)
yrs4 = pd.to_datetime(H4["t"], unit="s").year.values
for gname, L, S in (("EMA200 long-only", upbrk & (H4["c"] > ema200), np.zeros(H4["n"], bool)),
                    ("EMA200 both", upbrk & (H4["c"] > ema200), dnbrk & (H4["c"] < ema200)),
                    ("H4+D1 stacks both", upbrk & (g2 == 1), dnbrk & (g2 == -1)),
                    ("H4+D1 stacks long-only", upbrk & (g2 == 1), np.zeros(H4["n"], bool))):
    for slk, tp in itertools.product((1.5, 2.0, 3.0), (1.5, 2.0, 3.0)):
        idx = np.flatnonzero(L | S); idx = idx[(idx > 300) & (idx < H4["n"] - 1)]
        d = np.where(L[idx], 1, -1).astype(np.int64)
        j = H4["m1e"][idx]
        ok = (t[np.minimum(j, len(t) - 1)] - t[j - 1]) <= 1800
        idx, d, j = idx[ok], d[ok], j[ok]
        px = np.where(d > 0, o[j] + spr[j] + 0.05, o[j] - 0.05)
        a = H4["atr"][idx]
        mg = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=tp, max_min=60 * 24 * 20)
        tr = S2.run_fills(m1a, j, d, px, slk * a, 0 * a, mg, one_at_a_time=False)
        R = np.full(len(idx), np.nan); R[tr.eidx.values] = tr.r.values
        x = summarize(f"C Turtle H4 20-bar {gname} SL{slk}ATR TP{tp}R", R, yrs4[idx], n_days)
        if x: rows.append(x)

Rdf = pd.DataFrame(rows)
Rdf.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\study36_web_ideas.csv", index=False)
pd.set_option("display.width", 250); pd.set_option("display.max_rows", 300); pd.set_option("display.max_colwidth", 80)
for fam in ("A1", "A2", "B ", "C "):
    sub = Rdf[Rdf.test.str.startswith(fam)].sort_values("avgR_17_22", ascending=False)
    print(f"\n=== {fam.strip()}: top 8 by 2017-2022 avg R (of {len(sub)}) ===")
    print(sub.head(8).to_string(index=False))
