"""Study 31: can an AI separate 'rainbow-slide' retests from fakes?  Walk-forward meta-labeler on retest events.

Events: M15 ribbon (10/16/26/41/66/105/168) fully stacked + H1 stack agrees; bar tests EMA16 (or deeper) against the trend and
closes back beyond EMA10.  Features (all causal, scale-free): ribbon fan width / slope / evenness on M15, H1, H4; wave age;
retest number inside the wave; retest depth; impulse since wave start; distance to EMA168; volatility regime; cost/ATR;
H4/D1 stack states; 1h/4h/24h momentum; hour of day (UTC).  Label: scalp TP 1R before SL (SL beyond the retest bar).
Train 2017-2022 (Dukascopy), test 2023-2026; then trade the top-scored retests ONE AT A TIME (real-account replay).
"""
import sys
import numpy as np
import pandas as pd
import lightgbm as lgb
from sklearn.metrics import roc_auc_score
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_engine as E
import sw_mtf as M
import sw_sim2 as S2

m1a, tfs = V.m1a, V.tfs
T = tfs["M15"]
n = T["n"]
per = V.RIBBON
EmM = np.vstack([E.ema_nb(T["c"], float(p)) for p in per])
a15 = np.maximum(T["atr"], 1e-9)
scM = np.sign(-np.diff(EmM, axis=0)).sum(axis=0)
stM = np.where(scM >= 6, 1, np.where(scM <= -6, -1, 0))
st_all, _ = V.stacks()

# wave bookkeeping on M15: age of the current stack, retest count inside the wave, extreme since wave start
age = np.zeros(n); rcount = np.zeros(n); wave_ext = np.zeros(n)
a_, rc, ext = 0, 0, 0.0
retest_any = ((stM == 1) & (T["l"] <= EmM[1]) & (T["c"] > EmM[0])) | ((stM == -1) & (T["h"] >= EmM[1]) & (T["c"] < EmM[0]))
for i in range(n):
    if i > 0 and stM[i] != 0 and stM[i] == stM[i - 1]:
        a_ += 1
        ext = max(ext, T["h"][i]) if stM[i] == 1 else min(ext, T["l"][i])
    else:
        a_, rc = (1 if stM[i] != 0 else 0), 0
        ext = T["c"][i]
    age[i] = a_; rcount[i] = rc; wave_ext[i] = ext
    if retest_any[i]:
        rc += 1


def htf(tf):
    U = tfs[tf]
    Em = np.vstack([E.ema_nb(U["c"], float(p)) for p in per])
    k = np.maximum(M.map_last_closed(U, T["t_close"]), 0)
    a = np.maximum(U["atr"][k], 1e-9)
    return Em[:, k], a


EmH1, aH1 = htf("H1")
EmH4, aH4 = htf("H4")
kH1 = np.maximum(M.map_last_closed(tfs["H1"], T["t_close"]), 0)
kH4 = np.maximum(M.map_last_closed(tfs["H4"], T["t_close"]), 0)
kD1 = np.maximum(M.map_last_closed(tfs["D1"], T["t_close"]), 0)
gH1 = st_all["H1"][kH1]
d = np.zeros(n, np.int64)
d[(stM == 1) & (gH1 == 1) & (T["l"] <= EmM[1]) & (T["c"] > EmM[0])] = 1
d[(stM == -1) & (gH1 == -1) & (T["h"] >= EmM[1]) & (T["c"] < EmM[0])] = -1
idx = np.flatnonzero(d != 0)
idx = idx[(idx > 3000) & (idx < n - 1)]
j = T["m1e"][idx]
ok = (m1a["t"][np.minimum(j, len(m1a["t"]) - 1)] - m1a["t"][j - 1]) <= 1800
idx, j = idx[ok], j[ok]
dd = d[idx].astype(float)
px = np.where(dd > 0, m1a["o"][j] + m1a["spr"][j] + 0.05, m1a["o"][j] - 0.05)
a = a15[idx]
stop = np.where(dd > 0, T["l"][idx] - 0.1 * a, T["h"][idx] + 0.1 * a)
R = np.maximum(np.abs(px - stop), 0.5 * a)


def fan(Em, at, i):
    w = (Em[0][i] - Em[6][i]) / at[i]
    gaps = np.diff(Em[:, i]) / at[i]
    even = np.std(gaps) / (np.abs(np.mean(gaps)) + 1e-9)
    return w, even


c = T["c"]
X = np.column_stack([
    (EmM[0][idx] - EmM[6][idx]) / a * dd,                               # M15 fan width
    (EmM[0][idx] - EmM[0][np.maximum(idx - 4, 0)]) / a * dd,            # M15 fast slope 1h
    (EmM[6][idx] - EmM[6][np.maximum(idx - 16, 0)]) / a * dd,           # M15 slow slope 4h
    np.array([np.std(np.diff(EmM[:, i])) / (abs(np.mean(np.diff(EmM[:, i]))) + 1e-9) for i in idx]),  # fan evenness
    (EmH1[0][idx] - EmH1[6][idx]) / aH1[idx] * dd,                      # H1 fan width
    (EmH4[0][idx] - EmH4[6][idx]) / aH4[idx] * dd,                      # H4 fan width
    st_all["H4"][kH4[idx]] * dd, st_all["D1"][kD1[idx]] * dd,           # H4 / D1 stacks
    np.log1p(age[idx]), rcount[idx],                                    # wave age, retest number in wave
    np.where(dd > 0, (EmM[0][idx] - T["l"][idx]), (T["h"][idx] - EmM[0][idx])) / a,   # retest depth
    np.where(dd > 0, wave_ext[idx] - c[idx], c[idx] - wave_ext[idx]) / a,              # pullback from wave extreme
    (c[idx] - EmM[6][idx]) / a * dd,                                    # distance to EMA168
    a / pd.Series(a15).rolling(960, min_periods=100).mean().values[idx],                # vol regime
    a / c[idx] * 1e4, m1a["spr"][j] / a, R / a,                         # atr bp, cost/ATR, stop size
    np.r_[np.full(4, np.nan), c[4:] - c[:-4]][idx] / a * dd,
    np.r_[np.full(16, np.nan), c[16:] - c[:-16]][idx] / a * dd,
    np.r_[np.full(96, np.nan), c[96:] - c[:-96]][idx] / a * dd,
    np.sin(2 * np.pi * ((T["t"][idx] + 900) % 86400) / 86400), np.cos(2 * np.pi * ((T["t"][idx] + 900) % 86400) / 86400),
]).astype(np.float32)
yr = pd.to_datetime(T["t"][idx], unit="s").year.values
for lab_name, mg in (("scalp TP1R", dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=1.0, max_min=240)),
                     ("ride", dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=3.0, max_min=1440))):
    ind = S2.run_fills(m1a, j, dd.astype(np.int64), px, R, (a if lab_name == "ride" else 0 * a), mg, one_at_a_time=False)
    r = np.full(len(idx), np.nan); r[ind.eidx.values] = ind.r.values
    y = (r > 0).astype(int)
    tr = (yr <= 2022) & np.isfinite(r)
    te = (yr >= 2023) & np.isfinite(r)
    ti = np.flatnonzero(tr)
    cut = int(len(ti) * 0.8)
    params = dict(objective="binary", learning_rate=0.03, num_leaves=15, min_data_in_leaf=80, feature_fraction=0.7,
                  bagging_fraction=0.8, bagging_freq=1, lambda_l2=10.0, verbose=-1, num_threads=2, seed=3)
    mdl = lgb.train(params, lgb.Dataset(X[ti[:cut]], y[ti[:cut]]), 800, valid_sets=[lgb.Dataset(X[ti[cut:]], y[ti[cut:]])],
                    callbacks=[lgb.early_stopping(80, verbose=False)])
    p = mdl.predict(X)
    pv = p[ti[cut:]]
    print(f"\n=== {lab_name}: {len(idx)} retests, base WR test {y[te].mean():.3f}, avgR test {np.nanmean(r[te]):+.3f}, "
          f"AUC val {roc_auc_score(y[ti[cut:]], pv):.3f} test {roc_auc_score(y[te], p[te]):.3f}, trees {mdl.best_iteration}")
    for q in (0.0, 0.5, 0.7, 0.8, 0.9):
        thr = np.quantile(pv, q)
        sel = te & (p >= thr)
        seq = S2.run_fills(m1a, j[sel], dd[sel].astype(np.int64), px[sel], R[sel], (a[sel] if lab_name == "ride" else 0 * a[sel]),
                           mg, one_at_a_time=True)
        ys = seq.groupby("year").r.sum()
        print(f"  top {int((1 - q) * 100):3d}% (thr {thr:.3f}): independent avgR {np.nanmean(r[sel]):+.3f} n={sel.sum()} | "
              f"real-account replay n={len(seq)} WR={(seq.r > 0).mean() * 100:.1f}% avgR={seq.r.mean():+.3f} sumR={seq.r.sum():+.1f} "
              f"per-year " + " ".join(f"{k}:{v:+.1f}" for k, v in ys.items()))
