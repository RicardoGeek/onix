"""Study 51: the two most-cited gold calendar anomalies, on Dukascopy 2017-2026.
(a) Session drift ("gold rises in Asia, falls in New York"): mean return per session per year, and whether a session-only
    long would beat holding through (costs 0.02% per round trip).  Sessions in UTC: Asia 22:00-07:00, London 07:00-12:30,
    New York 12:30-21:00.
(b) Baur (2013, "The autumn effect of gold"): September and November returns vs other months, per year;
    and our v1.30 long setups in Sep/Nov vs other months.
"""
import sys
import numpy as np
import pandas as pd
_argv = list(sys.argv); sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv

m1 = V.m1a
t = pd.to_datetime(m1["t"], unit="s")
px = pd.Series(m1["c"], index=t)
px = px[(px.index >= "2017-01-01") & (px.index < "2026-10-01")]
h = px.resample("1h").last().dropna()
lr = np.log(h).diff().dropna()
hr = lr.index.hour + lr.index.minute / 60.0
# return of the hour ENDING at index time: the hour started one hour before
start = (lr.index - pd.Timedelta(hours=1))
sh = start.hour + start.minute / 60.0
sess = np.where((sh >= 22) | (sh < 7), "Asia", np.where(sh < 12.5, "London", np.where(sh < 21, "New York", "other")))
df = pd.DataFrame({"r": lr.values * 100, "sess": sess, "y": lr.index.year})
tab = df[df.sess != "other"].groupby(["y", "sess"]).r.sum().unstack()
print("(a) summed log return (%) per session and year")
print("| Year | Asia | London | New York |")
print("|---|---|---|---|")
for y, row in tab.iterrows():
    print(f"| {y} | {row['Asia']:+.1f}% | {row['London']:+.1f}% | {row['New York']:+.1f}% |")
days = df.groupby(["y", "sess"]).size().unstack()["Asia"] / 9  # ~9 Asia hours per day -> trading days
for s in ("Asia", "London", "New York"):
    pos = int((tab[s] > 0).sum())
    net = tab[s] - 0.02 * 252           # one round trip per trading day at 0.02%
    print(f"  {s:9s} positive {pos}/{len(tab)} years, mean {tab[s].mean():+.1f}%/yr; session-only long after costs {net.mean():+.1f}%/yr "
          f"(positive {int((net > 0).sum())}/{len(tab)})")

# (b) autumn effect
mo = px.resample("ME").last()
mret = np.log(mo).diff().dropna() * 100
mm = mret.index.month
au = np.isin(mm, (9, 11))
print("\n(b) Baur autumn effect: mean monthly return")
print(f"  Sep+Nov {mret[au].mean():+.2f}% (n={au.sum()}), other months {mret[~au].mean():+.2f}%; "
      f"Sep {mret[mm == 9].mean():+.2f}%, Nov {mret[mm == 11].mean():+.2f}%")
yy = mret.index.year
wins = sum(1 for y in sorted(set(yy)) if (au & (yy == y)).sum() > 0 and mret[au & (yy == y)].mean() > mret[~au & (yy == y)].mean())
print(f"  Sep/Nov beat the other months in {wins}/{len(set(yy))} years")
Z = np.load(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\study46_feats.npz", allow_pickle=True)
r, ts, d = Z["r"], pd.to_datetime(Z["t"], unit="s"), Z["d"]
ok = np.isfinite(r) & (d > 0)
aut = np.isin(ts.month, (9, 11))
print(f"  v1.30 LONG setups: Sep/Nov n={(ok & aut).sum()} avgR {r[ok & aut].mean():+.3f} | other months n={(ok & ~aut).sum()} avgR {r[ok & ~aut].mean():+.3f}")

# ---------------------------------------------------------------- (c) robustness: MID prices, start away from the reopen
mid = pd.Series(m1["c"] + 0.5 * m1["spr"], index=t)
mid = mid[(mid.index >= "2017-01-01") & (mid.index < "2026-10-01")]
hm = mid.resample("1h").last().dropna()
lrm = np.log(hm).diff().dropna() * 100
st = (lrm.index - pd.Timedelta(hours=1)).hour
print("\n(c) MID-price session returns (%/yr) with later Asia starts")
for a0 in (22, 23, 0, 1):
    asia = (st >= a0) | (st < 7) if a0 >= 12 else ((st >= a0) & (st < 7))
    g = pd.Series(lrm.values[asia], index=lrm.index[asia]).groupby(lrm.index[asia].year).sum()
    nyx = (st >= 13) & (st < 21)
    gn = pd.Series(lrm.values[nyx], index=lrm.index[nyx]).groupby(lrm.index[nyx].year).sum()
    print(f"  Asia from {a0:02d}:00 to 07:00 UTC: mean {g.mean():+.1f}%/yr, positive {int((g > 0).sum())}/{len(g)}; after 0.02%/day "
          f"{(g - 0.02 * 252).mean():+.1f}%/yr ({int((g - 5.04 > 0).sum())}/{len(g)}) | NY 13-21 mean {gn.mean():+.1f}%/yr")
# setups by session of the decision time
hh = ts.hour
sn = np.where((hh >= 22) | (hh < 7), "Asia", np.where(hh < 13, "London", np.where(hh < 21, "New York", "break")))
print("\n| Setups | Asia | London | New York |")
print("|---|---|---|---|")
for lab, dd in (("long", 1), ("short", -1)):
    cells = []
    for s in ("Asia", "London", "New York"):
        k = np.isfinite(r) & (d == dd) & (sn == s)
        cells.append(f"n={k.sum()} {r[k].mean():+.3f}R")
    print(f"| {lab} | " + " | ".join(cells) + " |")
