"""
train_usdjpy_onnx.py
====================
Trains and exports the 12-feature USDJPY ONNX Meta-Labeler (`usdjpy_meta_model.onnx`)
using exact MetaTrader 5 `POSITION_CLOSED` telemetry across multi-year regimes (2023-2026+)
from `usdjpy_setup_telemetry.csv`.
"""

import os
import sys
import math
import random
import pandas as pd
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_EA_DIR = os.path.dirname(SCRIPT_DIR)
XAU_PIPE_DIR = os.path.join(os.path.dirname(REPO_EA_DIR), "xauusd-quant-ea", "python_pipeline")
sys.path.insert(0, XAU_PIPE_DIR)

from train_walk_forward import NativeResidualMetaClassifier, _sigmoid
from export_onnx import export_trained_model_to_onnx

COMMON_FILES = r"C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
ARTIFACTS_DIR = r"C:\Users\faker\Documents\onix_artifacts"

FEAT_COLS = [
    "f0_sweep_depth_norm",
    "f1_wick_body_ratio",
    "f2_bars_outside_level",
    "f3_rel_tick_volume",
    "f4_vpoc_distance_norm",
    "f5_value_area_width_norm",
    "f6_h1_adx",
    "f7_hurst_exponent",
    "f8_volatility_ratio",
    "f9_hour_sin",
    "f10_hour_cos",
    "f11_spread_to_sl_ratio",
]


def main() -> None:
    telemetry_candidates = [
        os.path.join(ARTIFACTS_DIR, "telemetry", "usdjpy_pass1_setup_telemetry.csv"),
        os.path.join(COMMON_FILES, "usdjpy_setup_telemetry.csv"),
    ]

    raw_dfs = []
    for p in telemetry_candidates:
        if os.path.exists(p):
            raw_dfs.append(pd.read_csv(p))

    if not raw_dfs:
        raise FileNotFoundError("No USDJPY setup telemetry CSV files found in Common\\Files or Documents\\onix_artifacts.")

    full_df = pd.concat(raw_dfs, ignore_index=True)
    sigs_all = full_df[full_df["event_stage"] == "SIGNAL_TRIGGERED"].copy()
    outs_all = full_df[full_df["event_stage"] == "POSITION_CLOSED"].copy()

    mt5_outcomes = (
        outs_all.drop_duplicates(subset=["timestamp_utc"], keep="last")
        .set_index("timestamp_utc")["realized_r_multiple"]
        .to_dict()
    )
    print(f"Exact MT5 USDJPY POSITION_CLOSED outcomes mapped: {len(mt5_outcomes)}")

    sigs = (
        sigs_all.drop_duplicates(subset=["timestamp_utc"], keep="last")
        .sort_values("timestamp_utc")
        .reset_index(drop=True)
    )
    sigs["sig_utc"] = pd.to_datetime(sigs["timestamp_utc"])
    sigs["year"] = sigs["sig_utc"].dt.year

    r_list = []
    valid_idx = []
    for idx, r in sigs.iterrows():
        ts_str = r["timestamp_utc"]
        if ts_str in mt5_outcomes:
            r_list.append(float(mt5_outcomes[ts_str]))
            valid_idx.append(idx)

    cand = sigs.iloc[valid_idx].copy().reset_index(drop=True)
    cand["r_opt"] = r_list

    train_df = cand[cand["year"] >= 2023].copy().reset_index(drop=True)
    X_raw = train_df[FEAT_COLS].values.astype(np.float64)
    r_vals = train_df["r_opt"].values.astype(np.float64)
    yrs = train_df["year"].values
    n, n_features = X_raw.shape
    hidden_dim = 8

    means = X_raw.mean(axis=0)
    stds = np.maximum(1e-4, X_raw.std(axis=0))
    Z = (X_raw - means) / stds

    rng = random.Random(42)
    z_lin_w = [0.0] * n_features
    z_lin_b = 0.85
    z_hid_w1 = [[rng.uniform(-0.35, 0.35) for _ in range(hidden_dim)] for _ in range(n_features)]
    z_hid_b1 = [rng.uniform(-0.15, 0.15) for _ in range(hidden_dim)]
    z_hid_w2 = [rng.uniform(-0.45, 0.45) for _ in range(hidden_dim)]
    z_hid_b2 = 0.0

    z_samples = []
    for i in range(n):
        rv = float(r_vals[i])
        yr_boost = 1.65 if yrs[i] >= 2024 else 0.85
        if rv <= 0.0:
            y_t, w_s = 0.04, 2.95 * yr_boost
        elif rv >= 0.45:
            y_t, w_s = 0.96, 3.85 * yr_boost
        else:
            y_t, w_s = 0.76, 2.15 * yr_boost
        z_samples.append((Z[i].tolist(), y_t, w_s, rv))

    lr, l2, epochs = 0.11, 0.0008, 1800
    for epoch in range(epochs):
        step_lr = lr / (1.0 + 0.0011 * epoch)
        grad_w_lin = [0.0] * n_features
        grad_b_lin = 0.0
        grad_w1 = [[0.0] * hidden_dim for _ in range(n_features)]
        grad_b1 = [0.0] * hidden_dim
        grad_w2 = [0.0] * hidden_dim
        grad_b2 = 0.0

        for z_x, y_t, w_s, rv in z_samples:
            lin_logit = z_lin_b + sum(w * xi for w, xi in zip(z_lin_w, z_x))
            h_act = [
                math.tanh(max(-15.0, min(15.0, z_hid_b1[h] + sum(z_hid_w1[f][h] * z_x[f] for f in range(n_features)))))
                for h in range(hidden_dim)
            ]
            hid_logit = z_hid_b2 + sum(w2 * ha for w2, ha in zip(z_hid_w2, h_act))
            prob = _sigmoid(lin_logit + hid_logit)

            dyn_w = w_s
            if rv <= 0.0 and prob > 0.52:
                dyn_w *= 1.0 + 11.0 * (prob - 0.52)
            elif rv >= 0.45 and prob < 0.76:
                dyn_w *= 1.0 + 6.5 * (0.76 - prob)

            err = (prob - y_t) * dyn_w
            grad_b_lin += err
            grad_b2 += err
            for f in range(n_features):
                grad_w_lin[f] += err * z_x[f]
            for h in range(hidden_dim):
                grad_w2[h] += err * h_act[h]
                d_tanh = (1.0 - h_act[h] * h_act[h]) * z_hid_w2[h] * err
                grad_b1[h] += d_tanh
                for f in range(n_features):
                    grad_w1[f][h] += d_tanh * z_x[f]

        inv_n = 1.0 / float(max(1, n))
        z_lin_b -= step_lr * (grad_b_lin * inv_n)
        z_hid_b2 -= step_lr * (grad_b2 * inv_n)
        for f in range(n_features):
            z_lin_w[f] -= step_lr * (grad_w_lin[f] * inv_n + l2 * z_lin_w[f])
        for h in range(hidden_dim):
            z_hid_w2[h] -= step_lr * (grad_w2[h] * inv_n + l2 * z_hid_w2[h])
            z_hid_b1[h] -= step_lr * (grad_b1[h] * inv_n)
            for f in range(n_features):
                z_hid_w1[f][h] -= step_lr * (grad_w1[f][h] * inv_n + l2 * z_hid_w1[f][h])

    clf = NativeResidualMetaClassifier(seed=42)
    for f in range(n_features):
        clf.linear_weights[f] = z_lin_w[f] / stds[f]
    clf.linear_bias = z_lin_b - sum(z_lin_w[f] * means[f] / stds[f] for f in range(n_features))
    for h in range(hidden_dim):
        for f in range(n_features):
            clf.hidden_w1[f][h] = z_hid_w1[f][h] / stds[f]
        clf.hidden_b1[h] = z_hid_b1[h] - sum(z_hid_w1[f][h] * means[f] / stds[f] for f in range(n_features))
        clf.hidden_w2[h] = z_hid_w2[h]
    clf.hidden_b2 = z_hid_b2

    train_df["prob"] = [clf.predict_proba_pos(row) for row in train_df[FEAT_COLS].values]
    for label, sub in [
        ("2023", train_df[train_df["year"] == 2023]),
        ("2024", train_df[train_df["year"] == 2024]),
        ("2025-2026", train_df[train_df["year"] >= 2025]),
        ("ALL 2023-2026", train_df),
    ]:
        t2 = sub[sub["prob"] >= 0.56]
        t1 = sub[sub["prob"] >= 0.70]
        w2 = (t2["r_opt"] > 0).mean() * 100 if len(t2) else 0.0
        w1 = (t1["r_opt"] > 0).mean() * 100 if len(t1) else 0.0
        print(
            f"{label:15s}: T2={len(t2):3d} (WR={w2:5.1f}%, SumR={t2['r_opt'].sum():+6.2f}R) | "
            f"T1={len(t1):3d} (WR={w1:5.1f}%, SumR={t1['r_opt'].sum():+6.2f}R)"
        )

    onnx_out = os.path.join(REPO_EA_DIR, "MQL5", "Files", "models", "usdjpy_meta_model.onnx")
    os.makedirs(os.path.dirname(onnx_out), exist_ok=True)
    export_trained_model_to_onnx(clf.to_export_dict(), onnx_out)
    print(f"Exported ONNX model to: {onnx_out}")


if __name__ == "__main__":
    main()
