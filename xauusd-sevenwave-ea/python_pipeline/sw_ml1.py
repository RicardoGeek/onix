"""ML 1: walk-forward meta-labeler on every aligned-ribbon M15 bar.

Candidate = M15 close where the 7-EMA stack is fully ordered (direction = stack).  Label = +X ATR before -Y ATR
(pessimistic M1 path, entry next M1 open at ask/bid).  Strict yearly walk-forward: the model that scores year Y
only ever saw years < Y.  Prints OOS AUC and the hit-rate / expectancy of the top-scored candidates per year.
"""
import sys
import time
import numpy as np
import pandas as pd
import lightgbm as lgb
from sklearn.metrics import roc_auc_score
from sw_data import load
import sw_engine as E
import sw_events as V
import sw_features as SF

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
LX, LY = 1.0, 1.0  # label: +1.0 ATR before -1.0 ATR
t0 = time.time()
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
b = E.add_ribbon(E.make_bars(m1a, 15))
h1 = E.add_ribbon(E.make_bars(m1a, 60))
F = SF.build(b, h1, m1a, SF.tick_volume_bars(m1, b))
n = b["n"]
dirs_all = np.where(b["stack_bull"], 1, np.where(b["stack_bear"], -1, 0))
idx = np.flatnonzero(dirs_all != 0)
idx = idx[(idx > 1200) & (idx < n - 2)]
# skip candidates whose next price is after a long gap (weekend/daily break)
nxt = b["m1e"][idx]
ok = (m1a["t"][np.minimum(nxt, len(m1a["t"]) - 1)] - m1a["t"][nxt - 1]) <= 1800
idx = idx[ok]
dirs = dirs_all[idx]
X = SF.candidate_matrix(F, idx, dirs)
ys = np.array([0.5, 0.75, 1.0, 1.5, 2.0])
mfe, cens = V.excursions_nb(b["m1e"][idx], dirs, b["atr"][idx], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], ys, 96 * 15)
ylab = (mfe[:, list(ys).index(LY)] >= LX).astype(np.int32)
year = pd.to_datetime(b["t"][idx], unit="s").year.values
cost_atr = (0.08 + 0.05 + 0.10 * 0.5 + 0.0) / b["atr"][idx]  # spread is inside the path
print(f"candidates {len(idx):,}  base rate {ylab.mean():.3f}  ({time.time() - t0:.0f}s)")

params = dict(objective="binary", learning_rate=0.03, num_leaves=15, min_data_in_leaf=400, feature_fraction=0.7,
              bagging_fraction=0.7, bagging_freq=1, lambda_l2=10.0, verbose=-1, num_threads=2, seed=7)
oos_p = np.full(len(idx), np.nan)
imp = np.zeros(len(SF.FEATURES))
for Y in range(2019, 2027):
    tr = year < Y
    te = year == Y
    if te.sum() == 0:
        continue
    tr_idx = np.flatnonzero(tr)
    cut = tr_idx[int(len(tr_idx) * 0.85)]
    fit = tr_idx[tr_idx < cut - 200]
    val = tr_idx[tr_idx > cut]
    dtr = lgb.Dataset(X[fit], ylab[fit])
    dva = lgb.Dataset(X[val], ylab[val])
    m = lgb.train(params, dtr, 600, valid_sets=[dva], callbacks=[lgb.early_stopping(60, verbose=False)])
    p = m.predict(X[te], num_iteration=m.best_iteration)
    oos_p[te] = p
    imp += m.feature_importance("gain")
    auc = roc_auc_score(ylab[te], p)
    line = f"{Y}: n={te.sum():6d} iters={m.best_iteration:3d} AUC={auc:.3f} base={ylab[te].mean():.3f}"
    for q in (0.9, 0.95, 0.98):
        thr = np.quantile(p, q)
        s = p >= thr
        line += f" | top{int(round((1 - q) * 100))}% hit={ylab[te][s].mean():.3f}"
    print(line)
# OOS expectancy table for top-scored candidates (all OOS years pooled), for several TP/SL pairs
ok = np.isfinite(oos_p)
print("\nOOS pooled 2019-2026:")
for q in (0.0, 0.8, 0.9, 0.95, 0.98):
    s = ok & (oos_p >= np.quantile(oos_p[ok], q))
    out = []
    for yv in (1.0, 1.5, 2.0):
        yi = list(ys).index(yv)
        for xv in (0.5, 1.0, 1.5):
            w = mfe[s, yi] >= xv
            ev = np.mean((w * xv - (~w) * yv - cost_atr[s]) / yv)
            out.append(f"SL{yv}/TP{xv}:{w.mean():.2f}/{ev:+.3f}")
    print(f" q>={q:.2f} n={s.sum():6d} " + "  ".join(out))
print("\nfeature gain:", sorted(zip(SF.FEATURES, (imp / imp.sum()).round(3)), key=lambda z: -z[1])[:15])
np.savez_compressed(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\ml1_oos.npz", idx=idx, dirs=dirs,
                    p=oos_p, y=ylab, year=year, mfe=mfe)
print(f"{time.time() - t0:.0f}s")
