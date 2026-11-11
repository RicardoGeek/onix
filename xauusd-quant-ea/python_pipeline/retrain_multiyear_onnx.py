"""
retrain_multiyear_onnx.py
=========================
Retrains and exports the 12-feature XAUUSD ONNX Meta-Labeler (`xauusd_meta_model.onnx`)
strictly using the 2024.01.01 - 2026.04.30 training window so that:
  1. 2017.01.01 - 2023.12.31 (7 years of Dukascopy data) is 100% UNSEEN out-of-sample.
  2. 2026.05.01 - 2026.10.31 (last 6 months of 2026) is 100% UNSEEN forward out-of-sample.
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
    model_buf.extend(_encode_string_field(3, "4.40.0"))
    model_buf.extend(_encode_varint_field(5, 1))
    model_buf.extend(_encode_bytes_field(7, bytes(graph_buf)))
    model_buf.extend(_encode_bytes_field(8, opset_msg))
    return bytes(model_buf)


def main() -> None:
    telemetry_path = os.path.join(COMMON_FILES, "xauusd_setup_telemetry.csv")
    if not os.path.exists(telemetry_path):
        raise FileNotFoundError(f"Telemetry file not found: {telemetry_path}")

    full_df = pd.read_csv(telemetry_path)
    sigs_all = full_df[full_df["event_stage"] == "SIGNAL_TRIGGERED"].copy()
    outs_all = full_df[full_df["event_stage"] == "POSITION_CLOSED"].copy()

    mt5_outcomes = (
        outs_all.drop_duplicates(subset=["timestamp_utc"], keep="last")
        .set_index("timestamp_utc")[["realized_r_multiple", "mfe_r"]]
        .to_dict("index")
    )
    print(f"Total POSITION_CLOSED outcomes mapped: {len(mt5_outcomes)}")

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

    # Strictly train on 2024.01.01 - 2026.04.30 (leaving 2017-2023 and 2026 H2 100% UNSEEN)
    train_mask = (cand["sig_utc"] >= "2024-01-01") & (cand["sig_utc"] < "2026-05-01")
    train_df = cand[train_mask].copy().reset_index(drop=True)

    X_raw = train_df[FEAT_COLS].values.astype(np.float64)
    r_vals = train_df["r_opt"].values.astype(np.float64)
    n, n_features = X_raw.shape
    hidden_dim = 16

    means = X_raw.mean(axis=0)
    stds = np.maximum(1e-4, X_raw.std(axis=0))
    Z = (X_raw - means) / stds

    # Regularized L2 logistic + shallow Tanh residual head (prevents in-sample memorization)
    is_p = (X_raw[:, 0] >= 1.35)
    y_bin = np.where(~is_p, 0.01, np.where(r_vals >= 0.25, 0.96, np.where(r_vals > 0.0, 0.85, 0.72))).reshape(-1, 1)
    w_s = np.where(~is_p, 5.00, 2.50).reshape(-1, 1)
    z_lin_w = np.zeros((n_features, 1), dtype=np.float64)
    z_lin_b = 0.0
    rng = np.random.default_rng(42)
    z_hid_w1 = rng.normal(0.0, 0.05, size=(n_features, hidden_dim))
    z_hid_b1 = np.zeros((1, hidden_dim), dtype=np.float64)
    z_hid_w2 = np.zeros((hidden_dim, 1), dtype=np.float64)
    z_hid_b2 = 0.0

    lr, l2, epochs = 0.08, 0.015, 2500
    inv_n = 1.0 / float(max(1, n))

    for _ in range(epochs):
        lin_logit = Z @ z_lin_w + z_lin_b
        pre_hid = np.clip(Z @ z_hid_w1 + z_hid_b1, -10.0, 10.0)
        h_act = np.tanh(pre_hid)
        hid_logit = h_act @ z_hid_w2 + z_hid_b2
        total_logit = np.clip(lin_logit + hid_logit, -25.0, 25.0)
        prob = 1.0 / (1.0 + np.exp(-total_logit))

        err = (prob - y_bin) * w_s
        grad_w_lin = (Z.T @ err) * inv_n + l2 * z_lin_w
        grad_b_lin = float(err.sum() * inv_n)
        grad_w2 = (h_act.T @ err) * inv_n + 2.0 * l2 * z_hid_w2
        grad_b2 = float(err.sum() * inv_n)
        dh = (err @ z_hid_w2.T) * (1.0 - h_act * h_act)
        grad_w1 = (Z.T @ dh) * inv_n + 2.0 * l2 * z_hid_w1
        grad_b1 = dh.sum(axis=0, keepdims=True) * inv_n

        z_lin_w -= lr * grad_w_lin
        z_lin_b -= lr * grad_b_lin
        z_hid_w2 -= 0.25 * lr * grad_w2
        z_hid_b2 -= 0.25 * lr * grad_b2
        z_hid_w1 -= 0.25 * lr * grad_w1
        z_hid_b1 -= 0.25 * lr * grad_b1

    # Unscale weights from Z-space back to raw feature space X
    raw_lin_w = (z_lin_w.reshape(-1) / stds).reshape(n_features, 1)
    raw_lin_b = float(z_lin_b - np.sum(z_lin_w.reshape(-1) * means / stds))
    raw_hid_w1 = z_hid_w1 / stds.reshape(-1, 1)
    raw_hid_b1 = z_hid_b1 - (means.reshape(1, -1) / stds.reshape(1, -1)) @ z_hid_w1

    # Score entire 2017-2026 dataset to verify unseen out-of-sample generalization
    X_all = cand[FEAT_COLS].values.astype(np.float64)
    lin_all = X_all @ raw_lin_w + raw_lin_b
    h_all = np.tanh(np.clip(X_all @ raw_hid_w1 + raw_hid_b1, -15.0, 15.0))
    tot_all = np.clip(lin_all + h_all @ z_hid_w2 + z_hid_b2, -35.0, 35.0)
    cand["prob"] = (1.0 / (1.0 + np.exp(-tot_all))).reshape(-1)

    for label, sub in [
        ("UNSEEN 2017-2023 (OOS)", cand[cand["year"] <= 2023]),
        ("TRAIN 2024-2026H1 (IS)", cand[train_mask]),
        ("UNSEEN 2026H2 (OOS)", cand[cand["sig_utc"] >= "2026-05-01"]),
    ]:
        t2 = sub[sub["prob"] >= 0.58]
        t1 = sub[sub["prob"] >= 0.72]
        w2 = (t2["r_opt"] > 0.0).mean() * 100 if len(t2) else 0.0
        w1 = (t1["r_opt"] > 0.0).mean() * 100 if len(t1) else 0.0
        print(
            f"{label:24s}: T2={len(t2):4d} (WR={w2:5.1f}%, MeanR={t2['r_opt'].mean():+.3f}R, SumR={t2['r_opt'].sum():+7.2f}R) | "
            f"T1={len(t1):4d} (WR={w1:5.1f}%, MeanR={t1['r_opt'].mean():+.3f}R)"
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
