"""
retrain_multiyear_onnx.py
=========================
Retrains and exports the 12-feature XAUUSD ONNX Meta-Labeler (`xauusd_meta_model.onnx`)
strictly using the 99%-100% Real-Tick MetaTrader 5 `POSITION_CLOSED` telemetry
(`2024` Dukascopy Real Ticks + `2025-2026` Pepperstone Live Real Ticks).
"""

import os
import sys
import pandas as pd
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_EA_DIR = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, SCRIPT_DIR)

from pathlib import Path
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


def build_xauusd_onnx_bytes(
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
    graph_buf.extend(_encode_string_field(2, "XAUUSD_Sniper_MetaLabeler_Graph"))
    for init_bytes in initializers:
        graph_buf.extend(_encode_bytes_field(5, init_bytes))

    graph_buf.extend(_encode_bytes_field(11, _build_value_info_proto(cfg.input_tensor_name, TENSOR_FLOAT, [1, n_features])))
    graph_buf.extend(_encode_bytes_field(12, _build_value_info_proto(cfg.output_label_name, TENSOR_INT64, [1])))
    graph_buf.extend(_encode_bytes_field(12, _build_value_info_proto(cfg.output_prob_name, TENSOR_FLOAT, [1, 2])))

    opset_msg = _encode_string_field(1, "") + _encode_varint_field(2, cfg.target_opset)
    model_buf = bytearray()
    model_buf.extend(_encode_varint_field(1, cfg.ir_version))
    model_buf.extend(_encode_string_field(2, "XAUUSD_Quant_ONNX_Exporter"))
    model_buf.extend(_encode_string_field(3, "4.22.0"))
    model_buf.extend(_encode_varint_field(5, 1))
    model_buf.extend(_encode_bytes_field(7, bytes(graph_buf)))
    model_buf.extend(_encode_bytes_field(8, opset_msg))
    return bytes(model_buf)


def main() -> None:
    telemetry_candidates = [
        os.path.join(COMMON_FILES, "xauusd_setup_telemetry.csv"),
    ]

    raw_dfs = []
    for p in telemetry_candidates:
        if os.path.exists(p):
            raw_dfs.append(pd.read_csv(p))

    if not raw_dfs:
        raise FileNotFoundError("No XAUUSD setup telemetry CSV files found in Common\\Files or Documents\\onix_artifacts.")

    full_df = pd.concat(raw_dfs, ignore_index=True)
    sigs_all = full_df[full_df["event_stage"] == "SIGNAL_TRIGGERED"].copy()
    outs_all = full_df[full_df["event_stage"] == "POSITION_CLOSED"].copy()

    mt5_outcomes = (
        outs_all.drop_duplicates(subset=["timestamp_utc"], keep="last")
        .set_index("timestamp_utc")[["realized_r_multiple", "mfe_r"]]
        .to_dict("index")
    )
    print(f"Exact MT5 XAUUSD Real-Tick POSITION_CLOSED outcomes mapped: {len(mt5_outcomes)}")

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

    train_df = cand[cand["year"] >= 2024].copy().reset_index(drop=True)
    X_raw = train_df[FEAT_COLS].values.astype(np.float64)
    r_vals = train_df["r_opt"].values.astype(np.float64)
    yrs = train_df["year"].values
    n, n_features = X_raw.shape
    hidden_dim = 44

    means = X_raw.mean(axis=0)
    stds = np.maximum(1e-4, X_raw.std(axis=0))
    Z = (X_raw - means) / stds

    rng = np.random.default_rng(42)
    z_lin_w = np.zeros((n_features, 1), dtype=np.float64)
    z_lin_b = 0.65
    z_hid_w1 = rng.uniform(-0.40, 0.40, size=(n_features, hidden_dim))
    z_hid_b1 = rng.uniform(-0.20, 0.20, size=(1, hidden_dim))
    z_hid_w2 = rng.uniform(-0.50, 0.50, size=(hidden_dim, 1))
    z_hid_b2 = 0.0

    y_t = np.where(r_vals < -0.03, 0.01, np.where(r_vals >= 0.25, 0.98, 0.70)).reshape(-1, 1)
    yr_boost = np.where(yrs == 2024, 1.35, 1.00)
    w_s = np.where(r_vals < -0.03, 6.50, np.where(r_vals >= 0.25, 5.40, 3.80)) * yr_boost
    w_s = w_s.reshape(-1, 1)
    rv_col = r_vals.reshape(-1, 1)

    lr, l2, epochs = 0.16, 0.00007, 7500
    inv_n = 1.0 / float(max(1, n))

    for epoch in range(epochs):
        step_lr = lr / (1.0 + 0.00035 * epoch)
        lin_logit = Z @ z_lin_w + z_lin_b
        pre_hid = np.clip(Z @ z_hid_w1 + z_hid_b1, -15.0, 15.0)
        h_act = np.tanh(pre_hid)
        hid_logit = h_act @ z_hid_w2 + z_hid_b2
        total_logit = np.clip(lin_logit + hid_logit, -35.0, 35.0)
        prob = 1.0 / (1.0 + np.exp(-total_logit))

        dyn_w = w_s.copy()
        lose_mask = (rv_col < -0.03) & (prob > 0.35)
        dyn_w[lose_mask] *= 1.0 + 46.0 * (prob[lose_mask] - 0.35)

        win_big_mask = (rv_col >= 0.25) & (prob < 0.88)
        dyn_w[win_big_mask] *= 1.0 + 26.0 * (0.88 - prob[win_big_mask])

        win_mid_mask = (rv_col >= -0.03) & (rv_col < 0.25) & (prob < 0.64)
        dyn_w[win_mid_mask] *= 1.0 + 20.0 * (0.64 - prob[win_mid_mask])

        err = (prob - y_t) * dyn_w

        grad_w_lin = (Z.T @ err) * inv_n + l2 * z_lin_w
        grad_b_lin = float(err.sum() * inv_n)
        grad_w2 = (h_act.T @ err) * inv_n + l2 * z_hid_w2
        grad_b2 = float(err.sum() * inv_n)

        dh = (err @ z_hid_w2.T) * (1.0 - h_act * h_act)
        grad_w1 = (Z.T @ dh) * inv_n + l2 * z_hid_w1
        grad_b1 = dh.sum(axis=0, keepdims=True) * inv_n

        z_lin_w -= step_lr * grad_w_lin
        z_lin_b -= step_lr * grad_b_lin
        z_hid_w2 -= step_lr * grad_w2
        z_hid_b2 -= step_lr * grad_b2
        z_hid_w1 -= step_lr * grad_w1
        z_hid_b1 -= step_lr * grad_b1

    # Unscale weights from Z-space back to raw feature space X
    raw_lin_w = (z_lin_w.reshape(-1) / stds).reshape(n_features, 1)
    raw_lin_b = float(z_lin_b - np.sum(z_lin_w.reshape(-1) * means / stds))
    raw_hid_w1 = z_hid_w1 / stds.reshape(-1, 1)
    raw_hid_b1 = z_hid_b1 - (means.reshape(1, -1) / stds.reshape(1, -1)) @ z_hid_w1

    lin_logit = X_raw @ raw_lin_w + raw_lin_b
    h_act = np.tanh(np.clip(X_raw @ raw_hid_w1 + raw_hid_b1, -15.0, 15.0))
    total_logit = np.clip(lin_logit + h_act @ z_hid_w2 + z_hid_b2, -35.0, 35.0)
    train_df["prob"] = (1.0 / (1.0 + np.exp(-total_logit))).reshape(-1)

    for label, sub in [
        ("2024", train_df[train_df["year"] == 2024]),
        ("2025-2026", train_df[train_df["year"] >= 2025]),
        ("ALL 2024-2026", train_df),
    ]:
        t2 = sub[sub["prob"] >= 0.58]
        t1 = sub[sub["prob"] >= 0.72]
        w2 = (t2["r_opt"] > 0.04).mean() * 100 if len(t2) else 0.0
        w1 = (t1["r_opt"] > 0.04).mean() * 100 if len(t1) else 0.0
        print(
            f"{label:15s}: T2={len(t2):3d} (WR={w2:5.1f}%, SumR={t2['r_opt'].sum():+6.2f}R) | "
            f"T1={len(t1):3d} (WR={w1:5.1f}%, SumR={t1['r_opt'].sum():+6.2f}R)"
        )

    onnx_bytes = build_xauusd_onnx_bytes(
        linear_weights=raw_lin_w,
        linear_bias=raw_lin_b,
        hidden_w1=raw_hid_w1,
        hidden_b1=raw_hid_b1,
        hidden_w2=z_hid_w2,
        hidden_b2=z_hid_b2,
    )

    out_onnx = Path(REPO_EA_DIR) / "MQL5" / "Files" / "models" / "xauusd_meta_model.onnx"
    out_onnx.parent.mkdir(parents=True, exist_ok=True)
    out_onnx.write_bytes(onnx_bytes)
    _verify_onnx_file_if_possible(out_onnx, ONNX_EXPORT_CONFIG)
    print(f"Exported ONNX model to: {out_onnx} ({len(onnx_bytes)} bytes)")


if __name__ == "__main__":
    main()
