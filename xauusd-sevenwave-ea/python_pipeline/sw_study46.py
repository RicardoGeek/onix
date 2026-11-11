"""Study 46: OUTSIDE data as setup filters (information that is not in any price bar on MT5).

Sources (parsed by sw_outside.py with conservative availability times, no look-ahead):
  CFTC COT (weekly, gold futures): managed-money / hedger / small-spec positioning, open interest
  Geopolitical Risk daily index (Caldara-Iacoviello), US daily Economic Policy Uncertainty (Baker-Bloom-Davis)
  CBOE GVZ (gold implied vol) and VIX, US Treasury 10Y real yield (TIPS)
Outcomes: v1.10+ setups (streams A/B/G/P) with v1.30-like whale management (TP 5R / 72h after +1.5R), Dukascopy 2017-2026.

Every hypothesis is PRE-REGISTERED with its "good" side (column `good`) before looking at the result:
a feature only counts if the good tercile beats the bad tercile in both halves (2017-2021 and 2022-2026) and in most years.
"""
import sys
import numpy as np
import pandas as pd
from sw_study37_lib import (m, J, D, PX, AT, SI, mg, trk, Rv, probe, W, K, ja, has, addpx, S2, acct, total_row)
import sw_v110 as V

O = np.load(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\outside_clean.npz")
NEWS_LAG = int(sys.argv[1]) if len(sys.argv) > 1 else 1      # extra publication lag (days) for the daily news indices

# ---------------------------------------------------------------- outcomes with whale management (as study 44)
hidx = np.flatnonzero(has)
ext = S2.run_fills(m, J[has], D[has].astype(np.int64), PX[has], Rv[has], trk * AT[has], dict(mg, tp2_r=5.0, max_min=4320), one_at_a_time=False)
ext.index = hidx[ext.eidx.values]
pr = probe.copy()
cm = pr.index.intersection(ext.index)
pr.loc[cm, ["entry_t", "exit_t", "r"]] = ext.loc[cm, ["entry_t", "exit_t", "r"]].values
r = np.full(len(J), np.nan); r[pr.index.values] = pr.r.values
t = m["t"][J].astype(np.int64)                                   # decision time (UTC): the setup bar
yr = pd.to_datetime(t, unit="s").year.values
d = D.astype(float)
ok = np.isfinite(r)


def last_idx(avail, ts):
    return np.searchsorted(avail, ts, side="right") - 1


def trail_pct(v, n):
    """percentile of v[i] inside v[i-n+1..i] (only past and current values)"""
    s = pd.Series(v)
    return s.rolling(n, min_periods=max(20, n // 3)).apply(lambda x: (x <= x[-1]).mean(), raw=True).values


F = {}
# ---------------------------------------------------------------- COT (weekly)
oi = O["cot_oi"]
mm = (O["cot_mm_l"] - O["cot_mm_s"]) / oi
hg = (O["cot_pm_l"] + O["cot_sw_l"] - O["cot_pm_s"] - O["cot_sw_s"]) / oi
nr = (O["cot_nr_l"] - O["cot_nr_s"]) / oi
mm_idx, hg_idx, nr_idx = trail_pct(mm, 156), trail_pct(hg, 156), trail_pct(nr, 156)
mm_chg4 = mm - np.r_[np.full(4, np.nan), mm[:-4]]
oi_chg4 = oi / np.r_[np.full(4, np.nan), oi[:-4]] - 1
k = last_idx(O["cot_avail"], t)
v = k >= 0
kk = np.maximum(k, 0)
age = np.where(v, (t - O["cot_rd"][kk]) / 86400.0, np.nan)
print(f"COT age at decision: median {np.nanmedian(age):.1f} d, max {np.nanmax(age):.0f} d")
dirp = lambda x: np.where(d > 0, x, 1 - x)                       # percentile in the trade direction
F["COT managed-money crowding (trade dir)"] = (np.where(v, dirp(mm_idx[kk]), np.nan), "low")
F["COT managed-money 4w flow agrees"] = (np.where(v, d * mm_chg4[kk], np.nan), "high")
F["COT hedgers positioned with trade"] = (np.where(v, dirp(hg_idx[kk]), np.nan), "high")
F["COT small-spec crowding (trade dir)"] = (np.where(v, dirp(nr_idx[kk]), np.nan), "low")
F["COT open interest 4w change"] = (np.where(v, oi_chg4[kk], np.nan), "high")


# ---------------------------------------------------------------- daily series helpers
def daily(name, val, lag_days=0.0):
    av = O[f"{name}_avail"] + int(lag_days * 86400)
    k = last_idx(av, t)
    return np.maximum(k, 0), k >= 0


def ratio_ma(val, a, b):
    s = pd.Series(val)
    return (s.rolling(a).mean() / s.rolling(b).mean()).values


# GPR / EPU (calendar-day series; NEWS_LAG extra days of publication lag)
for nm, val, lab in (("gpr", O["gpr_gprd"], "Geopolitical risk"), ("epu", O["epu_val"], "Policy uncertainty")):
    k, v = daily(nm, val, NEWS_LAG)
    rat = ratio_ma(val, 7, 90)
    pct = trail_pct(pd.Series(val).rolling(7).mean().values, 365)
    F[f"{lab} 7d/90d rising (x trade dir)"] = (np.where(v, d * (rat[k] - 1), np.nan), "high")
    F[f"{lab} level pct (x trade dir)"] = (np.where(v, d * (pct[k] - 0.5), np.nan), "high")

# GVZ / VIX
gk, gv = daily("gvz", O["gvz_val"])
gvz = O["gvz_val"]
gpct = trail_pct(gvz, 252)
gch5 = gvz - np.r_[np.full(5, np.nan), gvz[:-5]]
F["GVZ gold implied vol pct (1y)"] = (np.where(gv, gpct[gk], np.nan), "high")
F["GVZ 5d change (vol expanding)"] = (np.where(gv, gch5[gk], np.nan), "high")
D1 = V.tfs["D1"]
kd = np.searchsorted(D1["t_close"], t, side="right") - 1
lr = np.r_[np.nan, np.diff(np.log(D1["c"]))]
rv20 = pd.Series(lr).rolling(20).std().values * np.sqrt(252) * 100
F["GVZ implied / realized vol (20d)"] = (np.where(gv & (kd > 25), gvz[gk] / rv20[np.maximum(kd, 0)], np.nan), "high")
vk, vv = daily("vix", O["vix_val"])
vix = O["vix_val"]
vch5 = vix - np.r_[np.full(5, np.nan), vix[:-5]]
F["VIX 5d change (x trade dir)"] = (np.where(vv, d * vch5[vk], np.nan), "high")
F["VIX level pct (1y)"] = (np.where(vv, trail_pct(vix, 252)[vk], np.nan), "high")

# real yields
rk, rvv = daily("ry", O["ry_val"])
ry = O["ry_val"]
for n in (5, 20):
    ch = ry - np.r_[np.full(n, np.nan), ry[:-n]]
    F[f"Real yield {n}d change against trade"] = (np.where(rvv, -d * ch[rk], np.nan), "high")

# ---------------------------------------------------------------- evaluation
print(f"\n{ok.sum()} setups with fills, base WR {(r[ok] > 0).mean() * 100:.1f}% avgR {r[ok].mean():+.3f} (news lag {NEWS_LAG}d)")
print("| Feature (good side) | n | bad tercile R | mid R | good tercile R | good-bad 2017-21 | good-bad 2022-26 | years good>bad |")
print("|---|---|---|---|---|---|---|---|")
rows = []
for name, (x, good) in F.items():
    mk = ok & np.isfinite(x)
    if mk.sum() < 300:
        print(f"| {name} | {mk.sum()} | too few | | | | | |"); continue
    # tercile edges from 2017-2021 only (walk-forward: the thresholds never see 2022+)
    tr = mk & (yr <= 2021)
    q1, q2 = np.nanquantile(x[tr], [1 / 3, 2 / 3])
    lo, hi = mk & (x <= q1), mk & (x > q2)
    mid = mk & ~lo & ~hi
    gd, bd = (hi, lo) if good == "high" else (lo, hi)
    e1 = r[gd & (yr <= 2021)].mean() - r[bd & (yr <= 2021)].mean()
    e2 = r[gd & (yr >= 2022)].mean() - r[bd & (yr >= 2022)].mean()
    yrs = sorted(set(yr[mk]))
    wins = sum(1 for y in yrs if (gd & (yr == y)).sum() >= 10 and (bd & (yr == y)).sum() >= 10
               and r[gd & (yr == y)].mean() > r[bd & (yr == y)].mean())
    rows.append((name, e1, e2, wins, len(yrs), q1, q2, good))
    print(f"| {name} ({good}) | {mk.sum()} | {r[bd].mean():+.3f} | {r[mid].mean():+.3f} | {r[gd].mean():+.3f} | {e1:+.3f} | {e2:+.3f} | {wins}/{len(yrs)} |")

print("\nrobust = good beats bad in BOTH halves and in >= 7 of the years:")
for (name, e1, e2, wins, ny, q1, q2, good) in rows:
    if e1 > 0 and e2 > 0 and wins >= 7:
        print(f"  {name}: +{e1:.3f} / +{e2:.3f} R, {wins}/{ny} years; thresholds {q1:.4g} / {q2:.4g} ({good})")
np.savez(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\study46_feats.npz",
         **{f"f{i}": F[k][0] for i, k in enumerate(F)}, names=np.array(list(F)), goods=np.array([F[k][1] for k in F]), r=r, t=t, d=d)
