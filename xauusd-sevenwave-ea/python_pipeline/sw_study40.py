"""Study 40: a stronger AI rater for the v1.10+ setups.  17 v1.10 features + 14 new causal features, LightGBM,
EXPANDING-WINDOW walk-forward (train <= Y-1, predict year Y, for Y = 2020..2026), so every prediction is out of sample.
Reports OOS AUC and the win rate / avg R of the top-scored setups, base 17 vs extended 31 features.
"""
import sys
import numpy as np
import pandas as pd
import lightgbm as lgb
from sklearn.metrics import roc_auc_score
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "check"]
import sw_v110_ai as A
sys.argv = _argv
V, E, M = A.V, A.E, A.M
m1a, tfs = V.m1a, V.tfs

ev = V.all_events(use=A.USE)
J, D, PX, AT, SI = ev
tr = V.outcomes(ev, "growth")
r = np.full(len(J), np.nan); r[tr.eidx.values] = tr.r.values
X0 = A.features(ev)
t = m1a["t"][J]
yr = pd.to_datetime(t, unit="s").year.values

# ---------------------------------------------------------------- new causal features
c1 = m1a["c"]
a1 = np.maximum(AT, 1e-9)
f = {}
for mins in (15, 60, 240):
    f[f"mom{mins}"] = (c1[J - 1] - c1[np.maximum(J - 1 - mins, 0)]) / a1 * D
f["dow"] = m1a["nydow"][J].astype(float)
Dd = tfs["D1"]
kd = np.maximum(M.map_last_closed(Dd, t), 0)
ad = np.maximum(Dd["atr"][kd], 1e-9)
f["pdh"] = (PX - Dd["h"][kd]) / ad * D
f["pdl"] = (PX - Dd["l"][kd]) / ad * D
hi20 = pd.Series(Dd["h"]).rolling(20).max().values; lo20 = pd.Series(Dd["l"]).rolling(20).min().values
f["pos20"] = ((PX - lo20[kd]) / np.maximum(hi20[kd] - lo20[kd], 1e-9) - 0.5) * D
c5 = Dd["c"]
f["ret5d"] = (c5[kd] - c5[np.maximum(kd - 5, 0)]) / ad * D
f["ret20d"] = (c5[kd] - c5[np.maximum(kd - 20, 0)]) / ad * D
# today's range so far vs the daily ATR (from M1 since the day start)
tday = m1a["tday"].astype(np.int64)
starts = np.r_[0, np.flatnonzero(np.diff(tday) != 0) + 1]
day_of = np.searchsorted(starts, J, side="right") - 1
hmax = pd.Series(m1a["h"]).groupby(tday).cummax().values
lmin = pd.Series(m1a["l"]).groupby(tday).cummin().values
f["dayrng"] = (hmax[J - 1] - lmin[J - 1]) / ad
f["daymove"] = (c1[J - 1] - m1a["o"][starts[day_of]]) / ad * D
for tf in ("H4", "D1"):
    T = tfs[tf]
    e10 = E.ema_nb(T["c"], 10.0)
    k = np.maximum(M.map_last_closed(T, t), 0)
    aa = np.maximum(T["atr"][k], 1e-9)
    f[f"{tf}_slope"] = (e10[k] - e10[np.maximum(k - 3, 0)]) / aa * D
M15 = tfs["M15"]
k15 = np.maximum(M.map_last_closed(M15, t), 0)
f["vol15_h1"] = M15["atr"][k15] / a1
f["spr"] = m1a["spr"][J] / a1
X1 = np.column_stack([X0] + [np.asarray(v, float) for v in f.values()]).astype(np.float32)
names = [f"v110_{i}" for i in range(X0.shape[1])] + list(f.keys())

P = dict(objective="binary", learning_rate=0.03, num_leaves=7, min_data_in_leaf=60, feature_fraction=0.7,
         bagging_fraction=0.8, bagging_freq=1, lambda_l2=20.0, verbose=-1, num_threads=2, seed=5)


def walk(X):
    p = np.full(len(r), np.nan)
    ok = np.isfinite(r)
    for Y in range(2020, 2027):
        trn = ok & (yr < Y); tst = ok & (yr == Y)
        if tst.sum() == 0:
            continue
        idx = np.flatnonzero(trn); cut = int(len(idx) * 0.85)
        mdl = lgb.train(P, lgb.Dataset(X[idx[:cut]], (r[idx[:cut]] > 0).astype(int)), 800,
                        valid_sets=[lgb.Dataset(X[idx[cut:]], (r[idx[cut:]] > 0).astype(int))],
                        callbacks=[lgb.early_stopping(60, verbose=False)])
        p[tst] = mdl.predict(X[tst], num_iteration=mdl.best_iteration)
    return p, mdl


for nm, X in (("v1.10 17 features", X0), ("extended 31 features", X1)):
    p, mdl = walk(X)
    ok = np.isfinite(p) & np.isfinite(r)
    print(f"\n=== {nm}: OOS 2020-2026 AUC {roc_auc_score(r[ok] > 0, p[ok]):.3f}, n={ok.sum()}, base WR {(r[ok] > 0).mean() * 100:.1f}%, "
          f"base avgR {r[ok].mean():+.3f}")
    for q in (0.0, 0.25, 0.5, 0.7, 0.8, 0.9):
        out = []
        for Y in range(2020, 2027):
            s = ok & (yr == Y)
            thr = np.quantile(p[s], q) if s.sum() else 1.0
            k = s & (p >= thr)
            out.append(f"{Y}:{r[k].mean():+.2f}")
        thr_all = np.array([np.quantile(p[ok & (yr == Y)], q) for Y in yr[ok]])
        k = p[ok] >= thr_all
        rr = r[ok][k]
        print(f"  top {int((1 - q) * 100):3d}%: n={k.sum():5d} WR {(rr > 0).mean() * 100:5.1f}% avgR {rr.mean():+.3f} | " + " ".join(out))
    if nm.startswith("extended"):
        imp = pd.Series(mdl.feature_importance("gain"), index=names).sort_values(ascending=False)
        print("  top features (last fold, gain):", ", ".join(f"{k}" for k in imp.index[:12]))
