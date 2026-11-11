"""Study 47: two more ways to use the outside data.
(a) Walk-forward LightGBM on all 16 outside features of study 46 (+ trade direction): can a model rank the v1.30 setups?
    Train on years < Y, test on year Y (2019..2026).  Report AUC (r > 0) and the R of the top half vs the bottom half.
(b) Outside data as its OWN weekly signal on gold (not a filter): pre-registered classic rules, long/short gold for one week
    (Monday 00:00 UTC open to the next Monday), costs 0.04% per round trip.  Weekly gold returns from the Dukascopy M1 data.
"""
import numpy as np
import pandas as pd
import lightgbm as lgb
from sklearn.metrics import roc_auc_score

Z = np.load(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\study46_feats.npz", allow_pickle=True)
names = list(Z["names"]); r, t, d = Z["r"], Z["t"], Z["d"]
X = np.column_stack([Z[f"f{i}"] for i in range(len(names))] + [d])
yr = pd.to_datetime(t, unit="s").year.values
ok = np.isfinite(r)
print("(a) walk-forward LightGBM on the outside features")
print("| Test year | n | AUC (r>0) | top-half R | bottom-half R |")
print("|---|---|---|---|---|")
allp, allr = [], []
for Y in range(2019, 2027):
    tr, te = ok & (yr < Y), ok & (yr == Y)
    if te.sum() < 50:
        continue
    mdl = lgb.LGBMClassifier(n_estimators=150, learning_rate=0.03, num_leaves=7, min_child_samples=40, subsample=0.8,
                             subsample_freq=1, colsample_bytree=0.8, verbose=-1)
    mdl.fit(X[tr], (r[tr] > 0).astype(int))
    p = mdl.predict_proba(X[te])[:, 1]
    med = np.median(p)
    print(f"| {Y} | {te.sum()} | {roc_auc_score(r[te] > 0, p):.3f} | {r[te][p > med].mean():+.3f} | {r[te][p <= med].mean():+.3f} |")
    allp.append(p - med); allr.append(r[te])
allp, allr = np.concatenate(allp), np.concatenate(allr)
print(f"| all | {len(allr)} | {roc_auc_score(allr > 0, allp):.3f} | {allr[allp > 0].mean():+.3f} | {allr[allp <= 0].mean():+.3f} |")

# ---------------------------------------------------------------- (b) standalone weekly signals
import sys
_argv = list(sys.argv); sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
O = np.load(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\outside_clean.npz")
m1 = V.m1a
mt, mo = m1["t"].astype(np.int64), m1["o"]
mon = pd.date_range("2017-01-02", "2026-09-21", freq="W-MON")
ts = mon.values.astype("datetime64[s]").astype(np.int64)
j0 = np.searchsorted(mt, ts)
okw = j0[1:] < len(mt)
p0 = mo[np.minimum(j0, len(mt) - 1)]
wret = (p0[1:] / p0[:-1] - 1) * 100                              # week k: Monday k -> Monday k+1, in %
ts0 = ts[:-1]
wy = pd.to_datetime(ts0, unit="s").year.values


def trail_pct(v, n):
    return pd.Series(v).rolling(n, min_periods=n // 3).apply(lambda x: (x <= x[-1]).mean(), raw=True).values


def at(name, arr, lag=0):
    k = np.searchsorted(O[f"{name}_avail"] + lag * 86400, ts0, side="right") - 1
    return np.where(k >= 0, arr[np.maximum(k, 0)], np.nan)


oi = O["cot_oi"]
mm = (O["cot_mm_l"] - O["cot_mm_s"]) / oi
hg = (O["cot_pm_l"] + O["cot_sw_l"] - O["cot_pm_s"] - O["cot_sw_s"]) / oi
mmi, hgi = at("cot", trail_pct(mm, 156)), at("cot", trail_pct(hg, 156))
gpr = O["gpr_gprd"]; gr = pd.Series(gpr).rolling(7).mean() / pd.Series(gpr).rolling(90).mean()
gratio = at("gpr", gr.values, 1)
ry = O["ry_val"]; ry20 = at("ry", ry - np.r_[np.full(20, np.nan), ry[:-20]])
gvz = O["gvz_val"]; gch = at("gvz", gvz - np.r_[np.full(5, np.nan), gvz[:-5]])
past4 = np.r_[np.full(4, np.nan), (p0[4:-1] / p0[:-5] - 1) * 100]   # gold's own 4-week return (known at Monday)
RULES = {
    "COT hedgers idx >0.8 long / <0.2 short (Williams)": np.where(hgi > 0.8, 1, np.where(hgi < 0.2, -1, 0)),
    "COT managed money idx <0.1 long / >0.9 short (contrarian)": np.where(mmi < 0.1, 1, np.where(mmi > 0.9, -1, 0)),
    "Geopolitical risk 7d/90d > 1.25 long": np.where(gratio > 1.25, 1, 0),
    "Real yield 20d change < -0.15 long / > +0.15 short": np.where(ry20 < -0.15, 1, np.where(ry20 > 0.15, -1, 0)),
    "GVZ 5d jump > +3 long (vol spikes up with gold)": np.where(gch > 3, 1, 0),
    "benchmark: always long": np.ones(len(ts0), int),
    "benchmark: gold 4-week momentum": np.where(past4 > 0, 1, -1),
}
print("\n(b) standalone weekly rules on gold (Monday to Monday, 0.04% cost per trade)")
print("| Rule | weeks in market | avg % per trade | hit rate | t-stat | years positive | 2017-21 | 2022-26 |")
print("|---|---|---|---|---|---|---|---|")
for name, sig in RULES.items():
    s = np.nan_to_num(sig).astype(int)
    mk = okw & (s != 0) & np.isfinite(wret)
    pnl = s[mk] * wret[mk] - 0.04
    py = pd.Series(pnl).groupby(wy[mk]).sum()
    tst = pnl.mean() / (pnl.std(ddof=1) / np.sqrt(len(pnl))) if len(pnl) > 2 else np.nan
    e1 = pnl[wy[mk] <= 2021].mean(); e2 = pnl[wy[mk] >= 2022].mean()
    print(f"| {name} | {mk.sum()} | {pnl.mean():+.3f}% | {(pnl > 0).mean() * 100:.0f}% | {tst:+.2f} | {int((py > 0).sum())}/{len(py)} | {e1:+.3f}% | {e2:+.3f}% |")
