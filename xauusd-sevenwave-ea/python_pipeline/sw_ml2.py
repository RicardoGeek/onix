"""ML 2: walk-forward AI quality model on HIERARCHY-ALIGNED M15 bars (M15 ribbon + H1/H4/D1 stacks agree).

Label = the real trade outcome under the SevenWave management (simulated independently per candidate, pessimistic
costs): win = net R > 0.  Features = 35 M15 ribbon/context features + multi-timeframe structure features.
Strict yearly walk-forward; the selection threshold for year Y comes from the validation slice of the training
years only (no look-ahead).  Then the selected setups are traded ONE AT A TIME in time order -> per-year stats.
"""
import sys
import time
import numpy as np
import pandas as pd
import lightgbm as lgb
from sklearn.metrics import roc_auc_score
from sw_data import load
import sw_engine as E
import sw_features as SF
import sw_mtf as M

MGMT = dict(tp1_r=0.25, tp1_frac=0.5, be_r=0.05, trail_mode=2, trail_k=3.0, trail_act_r=0.25, tp2_r=0.0, max_bars=96)
SL_ATR = 3.0
HIGHER = ("H1", "H4", "D1")
MTF_FEATS = [f"{tf}_{k}" for tf in HIGHER for k in ("w", "d0", "d6", "age", "bos", "room", "risk", "s0")] + \
            ["m15_realign", "m15_since_realign", "m15_bos"]
ALL_FEATS = SF.FEATURES + MTF_FEATS


def build_dataset(src, start="2017-01-01"):
    m1 = load("duka_m1" if src == "duka" else "pep_m1")
    m1 = m1[m1["t"] >= pd.Timestamp(start).value // 10 ** 9].reset_index(drop=True)
    m1a = E.m1_arrays(m1, src)
    tfs = M.build_hierarchy(m1a)
    b = tfs["M15"]
    F = SF.build(b, tfs["H1"], m1a, SF.tick_volume_bars(m1, b))
    n = b["n"]
    hm = {h: np.maximum(M.map_last_closed(tfs[h], b["t_close"]), 0) for h in HIGHER}
    d_all = b["ribbon"].copy()
    for h in HIGHER:
        d_all = np.where(tfs[h]["stackd"][hm[h]] == d_all, d_all, 0)
    idx = np.flatnonzero(d_all != 0)
    idx = idx[(idx > 3000) & (idx < n - 2)]
    nxt = b["m1e"][idx]
    ok = (m1a["t"][np.minimum(nxt, len(m1a["t"]) - 1)] - m1a["t"][nxt - 1]) <= 1800
    idx = idx[ok]
    d = d_all[idx]
    X0 = SF.candidate_matrix(F, idx, d)
    c = b["c"][idx]
    extra = np.zeros((len(idx), len(MTF_FEATS)), np.float32)
    col = 0
    for h in HIGHER:
        T = tfs[h]
        k = hm[h][idx]
        a = np.maximum(T["atr"][k], 1e-9)
        extra[:, col + 0] = (T["E"][0][k] - T["E"][6][k]) / a * d
        extra[:, col + 1] = (c - T["E"][0][k]) / a * d
        extra[:, col + 2] = (c - T["E"][6][k]) / a * d
        extra[:, col + 3] = np.log1p(T["sage"][k])
        extra[:, col + 4] = T["bos"][k] * d
        room = np.where(d > 0, T["swh"][k] - c, c - T["swl"][k]) / a
        risk = np.where(d > 0, c - T["swl"][k], T["swh"][k] - c) / a
        extra[:, col + 5] = np.nan_to_num(room, nan=0.0)
        extra[:, col + 6] = np.nan_to_num(risk, nan=0.0)
        km3 = np.maximum(k - 3, 0)
        extra[:, col + 7] = (T["E"][0][k] - T["E"][0][km3]) / a * d
        col += 8
    rib = b["ribbon"]
    realign = np.zeros(n, np.int64)
    realign[1:] = (rib[1:] != 0) & (rib[1:] != rib[:-1])
    since = np.zeros(n)
    cnt = 10 ** 6
    for i in range(n):
        cnt = 0 if realign[i] else cnt + 1
        since[i] = cnt
    extra[:, col + 0] = realign[idx]
    extra[:, col + 1] = np.log1p(np.minimum(since[idx], 5000))
    extra[:, col + 2] = b["bos"][idx] * d
    X = np.hstack([X0, extra])
    tr = E.run(b, m1a, idx, d, SL_ATR * b["atr"][idx], MGMT, one_at_a_time=False)
    # align labels to idx order (run keeps signal order; all taken when one_at_a_time=False, except data-end)
    r = np.full(len(idx), np.nan)
    r[tr["sidx"].values] = tr["r"].values
    keep = np.isfinite(r)
    year = pd.to_datetime(b["t"][idx], unit="s").year.values
    return dict(b=b, m1a=m1a, idx=idx[keep], d=d[keep], X=X[keep], r=r[keep], year=year[keep])


def walk_forward(ds, test_years, params=None, label="win", min_train_year=None):
    params = params or dict(objective="binary", learning_rate=0.03, num_leaves=15, min_data_in_leaf=300,
                            feature_fraction=0.6, bagging_fraction=0.7, bagging_freq=1, lambda_l2=10.0,
                            verbose=-1, num_threads=2, seed=11)
    X, r, year = ds["X"], ds["r"], ds["year"]
    y = (r > 0).astype(np.int32)
    p_oos = np.full(len(y), np.nan)
    thr = {}
    for Y in test_years:
        tr = year < Y if min_train_year is None else (year < Y) & (year >= min_train_year)
        te = year == Y
        if te.sum() == 0 or tr.sum() < 2000:
            continue
        ti = np.flatnonzero(tr)
        cut = ti[int(len(ti) * 0.8)]
        fit = ti[ti < cut - 100]
        val = ti[ti > cut]
        m = lgb.train(params, lgb.Dataset(X[fit], y[fit]), 800, valid_sets=[lgb.Dataset(X[val], y[val])],
                      callbacks=[lgb.early_stopping(80, verbose=False)])
        p_oos[te] = m.predict(X[te], num_iteration=m.best_iteration)
        pv = m.predict(X[val], num_iteration=m.best_iteration)
        thr[Y] = {q: float(np.quantile(pv, q)) for q in (0.0, 0.5, 0.7, 0.8, 0.9, 0.95)}
        auc = roc_auc_score(y[te], p_oos[te]) if len(set(y[te])) > 1 else np.nan
        print(f"  {Y}: train={fit.sum() if fit.dtype == bool else len(fit):6d} test={te.sum():6d} iters={m.best_iteration:3d} "
              f"AUC={auc:.3f} base WR={y[te].mean():.3f} avgR={r[te].mean():+.3f}")
    return p_oos, thr


def trade_selected(ds, p_oos, thr, q):
    sel = np.zeros(len(p_oos), bool)
    for Y, tq in thr.items():
        sel |= (ds["year"] == Y) & (p_oos >= tq[q])
    idx = ds["idx"][sel]
    d = ds["d"][sel]
    b = ds["b"]
    tr = E.run(b, ds["m1a"], idx, d, SL_ATR * b["atr"][idx], MGMT, one_at_a_time=True)
    return tr


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "duka"
    t0 = time.time()
    ds = build_dataset(src)
    print(f"{src}: {len(ds['r']):,} hierarchy candidates, base WR {(ds['r'] > 0).mean():.3f}, avgR {ds['r'].mean():+.3f} "
          f"({time.time() - t0:.0f}s)")
    yrs = sorted(set(ds["year"]))
    test_years = [y for y in yrs if y >= (2020 if src == "duka" else 2025)]
    p, thr = walk_forward(ds, test_years)
    pd.set_option("display.width", 220)
    for q in (0.0, 0.5, 0.7, 0.8, 0.9):
        tr = trade_selected(ds, p, thr, q)
        st = E.year_stats(tr)
        print(f"\n--- OOS traded, threshold = validation quantile {q} ---")
        print(st.to_string(index=False))
    np.savez_compressed(rf"C:\Users\faker\Documents\goldie_research\sevenwave\data\ml2_{src}.npz", p=p, r=ds["r"],
                        year=ds["year"], idx=ds["idx"], d=ds["d"])
    print(f"{time.time() - t0:.0f}s")
