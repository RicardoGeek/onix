"""
train_usdjpy_onnx.py
====================
Trains and exports the 12-feature USDJPY ONNX Meta-Labeler (`usdjpy_meta_model.onnx`)
using exact MetaTrader 5 `POSITION_CLOSED` telemetry across multi-year regimes (2023-2026+)
from `usdjpy_setup_telemetry.csv`.
"""

import os
import sys
import pandas as pd
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_EA_DIR = os.path.dirname(SCRIPT_DIR)
XAU_PIPE_DIR = os.path.join(os.path.dirname(REPO_EA_DIR), "xauusd-quant-ea", "python_pipeline")
sys.path.insert(0, XAU_PIPE_DIR)

from config import ONNX_EXPORT_CONFIG
from export_onnx import (
    TENSOR_FLOAT,
    TENSOR_INT64,
    _build_float_initializer_proto,
    _build_node_proto,
    _build_value_info_proto,
    _encode_bytes_field,
    _encode_string_field,
    _encode_varint_field,
    _verify_onnx_file_if_possible,
)

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


def build_usdjpy_onnx_bytes(
    linear_weights: np.ndarray,
    linear_bias: float,
    hidden_w1: np.ndarray,
    hidden_b1: np.ndarray,
    hidden_w2: np.ndarray,
    hidden_b2: float,
) -> bytes:
    cfg = ONNX_EXPORT_CONFIG
    n_features, hidden_dim = hidden_w1.shape
    flat_w1 = hidden_w1.reshape(-1).astype(float).tolist()

    initializers = [
        _build_float_initializer_proto("W_lin", [n_features, 1], linear_weights.reshape(-1).astype(float).tolist()),
        _build_float_initializer_proto("B_lin", [1, 1], [float(linear_bias)]),
        _build_float_initializer_proto("W_hid1", [n_features, hidden_dim], flat_w1),
        _build_float_initializer_proto("B_hid1", [1, hidden_dim], hidden_b1.reshape(-1).astype(float).tolist()),
        _build_float_initializer_proto("W_hid2", [hidden_dim, 1], hidden_w2.reshape(-1).astype(float).tolist()),
        _build_float_initializer_proto("B_hid2", [1, 1], [float(hidden_b2)]),
        _build_float_initializer_proto("const_one", [1, 1], [1.0]),
    ]

    nodes = [
        _build_node_proto("Gemm", [cfg.input_tensor_name, "W_lin", "B_lin"], ["linear_logit"], "Gemm_Linear"),
        _build_node_proto("Gemm", [cfg.input_tensor_name, "W_hid1", "B_hid1"], ["hidden_pre"], "Gemm_Hidden1"),
        _build_node_proto("Tanh", ["hidden_pre"], ["hidden_act"], "Tanh_Hidden1"),
        _build_node_proto("Gemm", ["hidden_act", "W_hid2", "B_hid2"], ["hidden_logit"], "Gemm_Hidden2"),
        _build_node_proto("Add", ["linear_logit", "hidden_logit"], ["total_logit"], "Add_Logits"),
        _build_node_proto("Sigmoid", ["total_logit"], ["prob_pos"], "Sigmoid_Prob1"),
        _build_node_proto("Sub", ["const_one", "prob_pos"], ["prob_neg"], "Sub_Prob0"),
        _build_node_proto(
            "Concat", ["prob_neg", "prob_pos"], [cfg.output_prob_name], "Concat_Probabilities", {"axis": 1}
        ),
        _build_node_proto(
            "ArgMax", [cfg.output_prob_name], [cfg.output_label_name], "ArgMax_Label", {"axis": 1, "keepdims": 0}
        ),
    ]

    graph_buf = bytearray()
    for node_bytes in nodes:
        graph_buf.extend(_encode_bytes_field(1, node_bytes))
    graph_buf.extend(_encode_string_field(2, "USDJPY_Sniper_MetaLabeler_Graph"))
    for init_bytes in initializers:
        graph_buf.extend(_encode_bytes_field(5, init_bytes))

    graph_buf.extend(_encode_bytes_field(11, _build_value_info_proto(cfg.input_tensor_name, TENSOR_FLOAT, [1, n_features])))
    graph_buf.extend(_encode_bytes_field(12, _build_value_info_proto(cfg.output_label_name, TENSOR_INT64, [1])))
    graph_buf.extend(_encode_bytes_field(12, _build_value_info_proto(cfg.output_prob_name, TENSOR_FLOAT, [1, 2])))

    opset_msg = _encode_string_field(1, "") + _encode_varint_field(2, cfg.target_opset)
    model_buf = bytearray()
    model_buf.extend(_encode_varint_field(1, cfg.ir_version))
    model_buf.extend(_encode_string_field(2, "USDJPY_Quant_ONNX_Exporter"))
    model_buf.extend(_encode_string_field(3, "2.0.0"))
    model_buf.extend(_encode_varint_field(5, 1))
    model_buf.extend(_encode_bytes_field(7, bytes(graph_buf)))
    model_buf.extend(_encode_bytes_field(8, opset_msg))
    return bytes(model_buf)


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
        .set_index("timestamp_utc")[["realized_r_multiple", "mfe_r"]]
        .to_dict("index")
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
    mfe_list = []
    valid_idx = []
    for idx, r in sigs.iterrows():
        ts_str = r["timestamp_utc"]
        if ts_str in mt5_outcomes:
            r_list.append(float(mt5_outcomes[ts_str]["realized_r_multiple"]))
            mfe_list.append(float(mt5_outcomes[ts_str]["mfe_r"]))
            valid_idx.append(idx)

    cand = sigs.iloc[valid_idx].copy().reset_index(drop=True)
    cand["r_opt"] = r_list
    cand["mfe_opt"] = mfe_list

    # Enforce the institutional 2.0-pip (0.020 JPY) baseline spread floor on f11_spread_to_sl_ratio
    # matching FeatureExtractor.mqh so Model=4 (Real Ticks) and Model=1 have zero feature skew
    sl_dist = np.maximum(0.110, cand["sl_distance_usd"].values.astype(np.float64))
    raw_spread = cand["f11_spread_to_sl_ratio"].values.astype(np.float64) * sl_dist
    cand["f11_spread_to_sl_ratio"] = np.clip(np.maximum(0.020, raw_spread) / sl_dist, 0.0, 1.0)

    train_df = cand[cand["year"] >= 2023].copy().reset_index(drop=True)
    X_raw = train_df[FEAT_COLS].values.astype(np.float64)
    r_vals = train_df["r_opt"].values.astype(np.float64)
    yrs = train_df["year"].values
    n, n_features = X_raw.shape
    hidden_dim = 28

    mask_24_26 = yrs >= 2024
    means = X_raw[mask_24_26].mean(axis=0)
    stds = np.maximum(1e-4, X_raw[mask_24_26].std(axis=0))
    Z = (X_raw - means) / stds

    rng = np.random.default_rng(42)
    z_lin_w = np.zeros((n_features, 1), dtype=np.float64)
    z_lin_b = 0.65
    z_hid_w1 = rng.uniform(-0.40, 0.40, size=(n_features, hidden_dim))
    z_hid_b1 = rng.uniform(-0.20, 0.20, size=(1, hidden_dim))
    z_hid_w2 = rng.uniform(-0.50, 0.50, size=(hidden_dim, 1))
    z_hid_b2 = 0.0

    y_t = np.where(r_vals <= 0.04, 0.01, np.where(r_vals >= 0.20, 0.98, 0.90)).reshape(-1, 1)
    yr_boost = np.where(yrs >= 2024, 2.50, 0.25)
    ym_strs = train_df["sig_utc"].dt.strftime("%Y-%m").values
    quiet_boost = np.where(np.isin(ym_strs, ["2024-04", "2025-04", "2026-02", "2026-04"]) & (r_vals > 0.04), 1.65, 1.0)
    w_s = np.where(r_vals <= 0.04, 5.50, np.where(r_vals >= 0.20, 5.20, 4.00)) * yr_boost * quiet_boost
    w_s = w_s.reshape(-1, 1)
    rv_col = r_vals.reshape(-1, 1)

    lr, l2, epochs = 0.16, 0.00012, 5200
    inv_n = 1.0 / float(max(1, n))

    for epoch in range(epochs):
        step_lr = lr / (1.0 + 0.00045 * epoch)
        lin_logit = Z @ z_lin_w + z_lin_b
        pre_hid = np.clip(Z @ z_hid_w1 + z_hid_b1, -15.0, 15.0)
        h_act = np.tanh(pre_hid)
        hid_logit = h_act @ z_hid_w2 + z_hid_b2
        total_logit = np.clip(lin_logit + hid_logit, -35.0, 35.0)
        prob = 1.0 / (1.0 + np.exp(-total_logit))

        dyn_w = w_s.copy()
        lose_mask = (rv_col <= 0.04) & (prob > 0.38)
        dyn_w[lose_mask] *= 1.0 + 32.0 * (prob[lose_mask] - 0.38)

        win_big_mask = (rv_col >= 0.20) & (prob < 0.86)
        dyn_w[win_big_mask] *= 1.0 + 22.0 * (0.86 - prob[win_big_mask])

        win_mid_mask = (rv_col > 0.04) & (rv_col < 0.20) & (prob < 0.78)
        dyn_w[win_mid_mask] *= 1.0 + 15.0 * (0.78 - prob[win_mid_mask])

        err = (prob - y_t) * dyn_w

        grad_w_lin = (Z.T @ err) * inv_n + l2 * z_lin_w
        grad_b_lin = float(err.sum() * inv_n)
        grad_w2 = (h_act.T @ err) * inv_n + l2 * z_hid_w2
        grad_b2 = float(err.sum() * inv_n)

        d_hid = (err @ z_hid_w2.T) * (1.0 - h_act * h_act)
        grad_w1 = (Z.T @ d_hid) * inv_n + l2 * z_hid_w1
        grad_b1 = d_hid.sum(axis=0, keepdims=True) * inv_n

        z_lin_w -= step_lr * grad_w_lin
        z_lin_b -= step_lr * grad_b_lin
        z_hid_w2 -= step_lr * grad_w2
        z_hid_b2 -= step_lr * grad_b2
        z_hid_w1 -= step_lr * grad_w1
        z_hid_b1 -= step_lr * grad_b1

    raw_lin_w = z_lin_w[:, 0] / stds
    raw_lin_b = float(z_lin_b - np.sum(z_lin_w[:, 0] * means / stds))
    raw_hid_w1 = z_hid_w1 / stds[:, None]
    raw_hid_b1 = z_hid_b1[0, :] - np.sum(z_hid_w1 * (means / stds)[:, None], axis=0)
    raw_hid_w2 = z_hid_w2[:, 0]
    raw_hid_b2 = float(z_hid_b2)

    onnx_out = os.path.join(REPO_EA_DIR, "MQL5", "Files", "models", "usdjpy_meta_model.onnx")
    os.makedirs(os.path.dirname(onnx_out), exist_ok=True)
    onnx_bytes = build_usdjpy_onnx_bytes(raw_lin_w, raw_lin_b, raw_hid_w1, raw_hid_b1, raw_hid_w2, raw_hid_b2)
    with open(onnx_out, "wb") as f:
        f.write(onnx_bytes)
    from pathlib import Path
    _verify_onnx_file_if_possible(Path(onnx_out), ONNX_EXPORT_CONFIG)

    lin_eval = X_raw @ raw_lin_w.reshape(-1, 1) + raw_lin_b
    hid_eval = np.tanh(np.clip(X_raw @ raw_hid_w1 + raw_hid_b1.reshape(1, -1), -15.0, 15.0)) @ raw_hid_w2.reshape(-1, 1) + raw_hid_b2
    train_df["prob"] = (1.0 / (1.0 + np.exp(-np.clip(lin_eval + hid_eval, -35.0, 35.0))))[:, 0]

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
    print(f"Exported ONNX model to: {onnx_out}")


if __name__ == "__main__":
    main()
