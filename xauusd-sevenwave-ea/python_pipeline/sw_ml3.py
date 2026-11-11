"""ML 3: walk-forward AI rater for Liquidity-Wave setups (stop orders at aged swing pools, hierarchy-gated).

One row per stop fill from all candidate streams (incl. weaker ones, so the model can learn when they work).
Features are taken from bars CLOSED before the fill minute (no look-ahead).  Label = net R of the SevenWave
management simulated independently.  Strict yearly walk-forward; threshold from the training validation slice.
"""
import sys
import time
import numpy as np
import pandas as pd
import lightgbm as lgb
from sklearn.metrics import roc_auc_score
from sw_data import load
import sw_engine as E
import sw_mtf as M
import sw_sim2 as S2
from sw_study17 import pools_nb, pool_stop_events_nb

MG = dict(tp1_r=0.5, tp1_frac=0.2, be_r=0.05, act_r=1.5, tp2_r=2.0, max_min=2880)
SL_K, TRAIL_K = 2.0, 1.0
STREAMS = {  # name: (structure TF, pivot LR, trend filter, offset ATR, min age, max age)
    "A": ("H1", 3, ("H4", "D1"), 0.15, 12, 48),
    "B": ("H2", 3, ("H4", "D1"), 0.0, 6, 48),
    "C": ("H1", 3, ("H4",), 0.15, 12, 120),
    "E": ("H1", 3, ("H1",), 0.15, 12, 48),
    "F": ("M30", 3, ("H1", "H4"), 0.15, 12, 96),
    "G": ("H1", 3, ("H4", "D1"), 0.15, 3, 12),
}
FEATS = ["stream", "dir", "age", "dist_lvl", "h1_order", "h4_order", "d1_order", "h1_w", "h4_w", "d1_w",
         "h1_d0", "h4_d0", "d1_d0", "h1_age", "h4_age", "d1_age", "h1_bos", "h4_bos", "volreg", "atr_bp", "cost_atr",
         "hsin", "hcos", "dow", "ret_h4", "ret_d1", "er_h1", "pos_d1", "m15_order", "m15_d0"]


def prep(src, start="2017-01-01"):
    m1 = load("duka_m1" if src == "duka" else "pep_m1")
    m1 = m1[m1["t"] >= pd.Timestamp(start).value // 10 ** 9].reset_index(drop=True)
    m1a = E.m1_arrays(m1, src)
    tfs = M.build_hierarchy(m1a)
    tfs["M30"] = M.tf_states(E.make_bars(m1a, 30))
    tfs["H2"] = M.tf_states(E.make_bars(m1a, 120))
    return m1a, tfs


def trend_of(tfs, T, names):
    out = None
    for h in names:
        k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
        sd = tfs[h]["stackd"][k]
        out = sd if out is None else np.where(out == sd, sd, 0)
    return out.astype(np.int64)


def events(m1a, tfs):
    rows = []
    for si, (nm, (S, LR, filt, off, amin, amax)) in enumerate(STREAMS.items()):
        T = tfs[S]
        ph, phi, pl, pli = pools_nb(T["h"], T["l"], LR, LR)
        em, ed, ep, ea = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], trend_of(tfs, T, filt), T["m1s"], T["m1e"],
                                             m1a["o"], m1a["h"], m1a["l"], m1a["spr"], off, amin, amax, 0.05, 3.0)
        # level age at placement bar: bar containing fill -> previous closed structure bar
        bi = np.searchsorted(T["t_close"], m1a["t"][em], side="right") - 1
        piv = np.where(ed > 0, phi[np.maximum(bi, 0)], pli[np.maximum(bi, 0)])
        lvl = np.where(ed > 0, ph[np.maximum(bi, 0)], pl[np.maximum(bi, 0)])
        rows.append(pd.DataFrame({"j": em, "dir": ed, "px": ep, "stream": si, "age": bi - piv, "lvl": lvl,
                                  "S_atr": T["atr"][np.maximum(bi, 0)]}))
    df = pd.concat(rows, ignore_index=True).sort_values(["j", "stream"]).drop_duplicates("j").reset_index(drop=True)
    t = m1a["t"][df.j.values]
    feat = {}
    for tf in ("M15", "H1", "H4", "D1"):
        T = tfs[tf]
        k = np.maximum(M.map_last_closed(T, t), 0)
        a = np.maximum(T["atr"][k], 1e-9)
        d = df["dir"].values
        order = np.sign(-np.diff(T["E"], axis=0)).sum(axis=0)[k]
        key = tf.lower()
        feat[f"{key}_order"] = order * d
        feat[f"{key}_d0"] = (df.px.values - T["E"][0][k]) / a * d
        if tf != "M15":
            feat[f"{key}_w"] = (T["E"][0][k] - T["E"][6][k]) / a * d
            feat[f"{key}_age"] = np.log1p(T["sage"][k])
        if tf in ("H1", "H4"):
            feat[f"{key}_bos"] = T["bos"][k] * d
        if tf == "H1":
            atr_long = pd.Series(T["atr"]).rolling(480, min_periods=100).mean().values
            feat["volreg"] = T["atr"][k] / atr_long[k]
            feat["atr_bp"] = T["atr"][k] / T["c"][k] * 1e4
            feat["cost_atr"] = m1a["spr"][df.j.values] / a
            c = T["c"]
            r4 = np.r_[np.full(4, np.nan), c[4:] - c[:-4]]
            r24 = np.r_[np.full(24, np.nan), c[24:] - c[:-24]]
            feat["ret_h4"] = r4[k] / a * d
            feat["ret_d1"] = r24[k] / a * d
            ch = np.abs(c[24:] - c[:-24]); vol = pd.Series(np.abs(np.diff(c))).rolling(24).sum().values[23:]
            er = np.r_[np.full(24, np.nan), ch / np.maximum(vol, 1e-9)]
            feat["er_h1"] = er[k]
            hi = pd.Series(T["h"]).rolling(24).max().values; lo = pd.Series(T["l"]).rolling(24).min().values
            feat["pos_d1"] = ((c[k] - lo[k]) / np.maximum(hi[k] - lo[k], 1e-9) - 0.5) * d
    hr = (t % 86400) / 3600.0
    feat["hsin"] = np.sin(2 * np.pi * hr / 24); feat["hcos"] = np.cos(2 * np.pi * hr / 24)
    feat["dow"] = pd.to_datetime(t, unit="s").dayofweek.values
    feat["dist_lvl"] = np.abs(df.px.values - df.lvl.values) / np.maximum(df.S_atr.values, 1e-9)
    feat["age"] = np.log1p(df.age.values)
    feat["stream"] = df.stream.values
    feat["dir"] = df.dir.values
    X = np.column_stack([np.asarray(feat[f], np.float64) for f in FEATS]).astype(np.float32)
    k = np.maximum(M.map_last_closed(tfs["H1"], t), 0)
    R = SL_K * tfs["H1"]["atr"][k]
    tr = S2.run_fills(m1a, df.j.values, df.dir.values, df.px.values, R, TRAIL_K * tfs["H1"]["atr"][k], MG,
                      one_at_a_time=False)
    r = np.full(len(df), np.nan)
    r[tr["eidx"].values] = tr["r"].values
    df["r"] = r
    df["R"] = R
    df["trail"] = TRAIL_K * tfs["H1"]["atr"][k]
    df["year"] = pd.to_datetime(t, unit="s").year
    ok = np.isfinite(r)
    return df[ok].reset_index(drop=True), X[ok]


def walk(df, X, test_years, seed=5):
    y = (df.r.values > 0).astype(int)
    params = dict(objective="binary", learning_rate=0.03, num_leaves=7, min_data_in_leaf=60, feature_fraction=0.7,
                  bagging_fraction=0.8, bagging_freq=1, lambda_l2=20.0, verbose=-1, num_threads=2, seed=seed)
    p = np.full(len(y), np.nan)
    thr = {}
    for Y in test_years:
        tr = np.flatnonzero(df.year.values < Y)
        te = df.year.values == Y
        if te.sum() == 0 or len(tr) < 400:
            continue
        cut = int(len(tr) * 0.8)
        fit, val = tr[:cut], tr[cut:]
        m = lgb.train(params, lgb.Dataset(X[fit], y[fit]), 600, valid_sets=[lgb.Dataset(X[val], y[val])],
                      callbacks=[lgb.early_stopping(60, verbose=False)])
        p[te] = m.predict(X[te], num_iteration=m.best_iteration)
        pv = m.predict(X[val], num_iteration=m.best_iteration)
        thr[Y] = {q: float(np.quantile(pv, q)) for q in (0.0, 0.25, 0.4, 0.5, 0.6)}
        auc = roc_auc_score(y[te], p[te]) if len(set(y[te])) > 1 else np.nan
        print(f"  {Y}: fit={len(fit)} test={te.sum()} it={m.best_iteration} AUC={auc:.3f} base WR={y[te].mean():.3f}")
    return p, thr


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "duka"
    t0 = time.time()
    m1a, tfs = prep(src)
    df, X = events(m1a, tfs)
    print(f"{len(df)} setup fills; per stream: {df.stream.value_counts().sort_index().to_dict()}  ({time.time() - t0:.0f}s)")
    print("independent outcome by stream (avgR):", df.groupby("stream").r.mean().round(3).to_dict())
    p, thr = walk(df, X, list(range(2019, 2027)))
    core = df.stream.isin([0, 1, 2, 3]).values
    for mode in ("core-rule", "all+ml", "core+ml"):
        for q in ((0.0,) if mode == "core-rule" else (0.25, 0.4, 0.5, 0.6)):
            sel = np.isfinite(p)
            if mode == "core-rule":
                sel &= core
            else:
                if mode == "core+ml":
                    sel &= core
                ok = np.zeros(len(df), bool)
                for Y, tq in thr.items():
                    ok |= (df.year.values == Y) & (p >= tq[q])
                sel &= ok
            d = df[sel]
            tr = S2.run_fills(m1a, d.j.values, d.dir.values, d.px.values, d.R.values, d.trail.values, MG)
            s = E.year_stats(tr)
            a = s.iloc[-1]; yrs = s.iloc[:-1]
            print(f"{mode:9s} q={q:.2f} n={a.n:4d} tpd={a.tpd:.2f} wr={a.wr:4.1f} avgR={a.avg_r:+.3f} sumR={a.sum_r:+6.1f} "
                  f"pf={a.pf:4.2f} +yrs={int((yrs.sum_r > 0).sum())}/{len(yrs)} green={a.green_m} | "
                  + " ".join(f"{v:+5.1f}" for v in yrs.sum_r))
    df["p"] = p
    df.to_pickle(rf"C:\Users\faker\Documents\goldie_research\sevenwave\data\ml3_{src}.pkl")
    print(f"{time.time() - t0:.0f}s")
