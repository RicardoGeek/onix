"""v1.10 AI check + export.  Same 17 feature definitions as v1.00 (AiRater.mqh) but computed with the v1.10 ribbon,
stream ids remapped to the v1.10 set (0=A, 1=B, 2=G, 3=P).  Walk-forward: train <= 2022, judge 2023-2026 at the
PORTFOLIO level (taken-trade edge, CAGR), not on independent outcomes.
  python sw_v110_ai.py check | export
"""
import os
import sys
import json
import numpy as np
import pandas as pd
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "duka"]
import sw_v110 as V
import sw_study22 as S22
sys.argv = _argv
import sw_engine as E
import sw_mtf as M
import lightgbm as lgb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
USE = ["A", "B", "G", "P"]
REMAP = {0: 0, 1: 1, 5: 2, 6: 3}            # NAMES index -> v1.10 stream id
WEIGHT = np.array([1, 1, 0, 0, 0, .6, .8, 0], float)


def features(ev, per=V.RIBBON):
    J, D, PX, AT, SI = ev
    tfs, m1a = V.tfs, V.m1a
    t = m1a["t"][J]
    F = {}
    for tf in ("H1", "H4", "D1"):
        T = tfs[tf]
        Em = np.vstack([E.ema_nb(T["c"], float(p)) for p in per])
        order = np.sign(-np.diff(Em, axis=0)).sum(axis=0)
        k = np.maximum(M.map_last_closed(T, t), 0)
        a = np.maximum(T["atr"][k], 1e-9)
        F[f"{tf}_order"] = order[k] * D
        F[f"{tf}_w"] = (Em[0][k] - Em[6][k]) / a * D
        F[f"{tf}_d0"] = (PX - Em[0][k]) / a * D
        if tf == "H1":
            atr_long = pd.Series(T["atr"]).rolling(480, min_periods=100).mean().values
            F["volreg"] = T["atr"][k] / atr_long[k]
            F["cost"] = np.where(np.isin((t // 3600) % 24, (21, 22)), 0.60, 0.30) / a
            c = T["c"]
            r24 = np.r_[np.full(24, np.nan), c[24:] - c[:-24]]
            F["ret_d1"] = r24[k] / a * D
            hi = pd.Series(T["h"]).rolling(24).max().values
            lo = pd.Series(T["l"]).rolling(24).min().values
            F["pos_d1"] = ((c[k] - lo[k]) / np.maximum(hi[k] - lo[k], 1e-9) - 0.5) * D
    # pool age is not carried by the event arrays; use structure-TF bars since the last H1 stack change as proxy -> 0
    hr = ((t - t % 60) % 86400) / 3600.0
    X = np.column_stack([np.vectorize(REMAP.get)(SI), D, np.zeros(len(J)), F["H1_order"], F["H4_order"], F["D1_order"],
                         F["H1_w"], F["H4_w"], F["D1_w"], F["H1_d0"], F["H4_d0"], F["volreg"], F["cost"],
                         np.sin(2 * np.pi * hr / 24), np.cos(2 * np.pi * hr / 24), F["ret_d1"], F["pos_d1"]]).astype(np.float32)
    return X


def train(X, y):
    p = dict(objective="binary", learning_rate=0.03, num_leaves=7, min_data_in_leaf=60, feature_fraction=0.7,
             bagging_fraction=0.8, bagging_freq=1, lambda_l2=20.0, verbose=-1, num_threads=2, seed=5)
    cut = int(len(y) * 0.8)
    m = lgb.train(p, lgb.Dataset(X[:cut], y[:cut]), 600, valid_sets=[lgb.Dataset(X[cut:], y[cut:])],
                  callbacks=[lgb.early_stopping(60, verbose=False)])
    b = lgb.train(p, lgb.Dataset(X[:cut], y[:cut]), max(1, m.best_iteration))
    thr = float(np.quantile(b.predict(X[cut:]), 0.25))
    return b, thr


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "check"
    ev = V.all_events(use=USE)
    tr = V.outcomes(ev, "growth")              # one row per event, eidx = index into ev arrays (sorted by J)
    X = features(ev)
    y_all = np.full(len(ev[0]), np.nan)
    y_all[tr.eidx.values] = tr.r.values
    yr = pd.to_datetime(V.m1a["t"][ev[0]], unit="s").year.values
    ok = np.isfinite(y_all)
    if what == "check":
        src23 = open("sw_study23.py", encoding="utf-8-sig").read().split("rows = []")[0]
        ns = {}
        exec(src23, ns)
        S22.WEIGHT = WEIGHT
        sel = ok & (yr <= 2022)
        b, thr = train(X[sel], (y_all[sel] > 0).astype(int))
        p = b.predict(X)
        print(f"trees={b.num_trees()} thr={thr:.4f} vetoed 2023+: {(p[yr >= 2023] < thr).mean():.1%}")
        base = tr.sort_values("entry_t").reset_index(drop=True)
        keep = tr[p[tr.eidx.values] >= thr].sort_values("entry_t").reset_index(drop=True)
        for nm, T in (("rules", base), ("rules+AI", keep)):
            for K, risk in ((2, 0.5), (3, 1.0)):
                day, taken, _ = ns["portfolio"](T, K, risk, 0.0, start=10000.0, daily=10.0, maxdd=30.0)
                b2 = ns["metrics"](day, taken, 10000.0, 2023, 2026) or {}
                tk = taken[pd.to_datetime(taken.entry_t, unit="s").dt.year >= 2023]
                print(f"{nm:9s} K={K} risk={risk}: 2023-26 taken avgR={tk.r.mean():+.3f} n={len(tk)} CAGR={b2.get('cagr', np.nan):+.1f}% "
                      f"DD={b2.get('dd', np.nan):.1f}% green months={b2.get('gm', np.nan):.0f}%")
    else:
        import onnx
        from onnxmltools import convert_lightgbm
        from onnxmltools.convert.common.data_types import FloatTensorType
        import onnxruntime as ort
        sel = ok & (yr <= 2023)
        b, thr = train(X[sel], (y_all[sel] > 0).astype(int))
        onx = convert_lightgbm(b, initial_types=[("input", FloatTensorType([1, X.shape[1]]))], zipmap=False, target_opset=13)
        path = os.path.join(ROOT, "MQL5", "Files", "models", "sevenwave_rater.onnx")
        onnx.save(onx, path)
        sess = ort.InferenceSession(path)
        rs = np.random.default_rng(1).choice(np.flatnonzero(ok), 200, replace=False)
        diff = np.max(np.abs(b.predict(X[rs]) - np.array([sess.run(None, {"input": X[i:i + 1]})[1][0, 1] for i in rs])))
        print(f"exported {path}: trees={b.num_trees()} thr={thr:.5f} parity={diff:.2e}")
        with open(os.path.join(ROOT, "MQL5", "Include", "SevenWave", "AiModelMeta.mqh"), "w", encoding="utf-8") as fh:
            fh.write("//+------------------------------------------------------------------+\n")
            fh.write("//| AiModelMeta.mqh - generated by python_pipeline/sw_v110_ai.py     |\n")
            fh.write("//+------------------------------------------------------------------+\n")
            fh.write("#ifndef SEVENWAVE_AIMODELMETA_MQH\n#define SEVENWAVE_AIMODELMETA_MQH\n")
            fh.write("#define SW_AI_FEATURES 17\n")
            fh.write(f"#define SW_AI_THRESHOLD {thr:.8f}\n")
            fh.write(f"#define SW_AI_TRAIN_STAMP \"v1.10 Duka 2017-2023, {int(sel.sum())} setups, {b.num_trees()} trees\"\n#endif\n")
        json.dump(dict(threshold=thr, trees=b.num_trees(), n_train=int(sel.sum()), ribbon=list(V.RIBBON), streams=USE),
                  open(os.path.join(ROOT, "python_pipeline", "models", "sevenwave_rater_meta.json"), "w"), indent=2)
