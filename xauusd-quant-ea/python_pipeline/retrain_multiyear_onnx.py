"""
retrain_multiyear_onnx.py
=========================
Retrains and exports the 12-feature XAUUSD ONNX Meta-Labeler (`xauusd_meta_model.onnx`)
using exact MetaTrader 5 `POSITION_CLOSED` telemetry across multi-year regimes (2024-2026+)
with M1 OHLC fallback for unexecuted candidate setups.
"""

import os
import sys
import math
import random
import pandas as pd
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_EA_DIR = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, SCRIPT_DIR)

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
        os.path.join(ARTIFACTS_DIR, "telemetry", "all_2023_2026_setup_telemetry.csv"),
        os.path.join(ARTIFACTS_DIR, "telemetry", "pass1_setup_telemetry.csv"),
        os.path.join(ARTIFACTS_DIR, "telemetry", "pass2a_v2_setup_telemetry.csv"),
        os.path.join(COMMON_FILES, "all_2023_2026_setup_telemetry.csv"),
        os.path.join(COMMON_FILES, "pass2a_v2_setup_telemetry.csv"),
        os.path.join(COMMON_FILES, "xauusd_setup_telemetry.csv"),
    ]

    raw_dfs = []
    for p in telemetry_candidates:
        if os.path.exists(p):
            raw_dfs.append(pd.read_csv(p))

    if not raw_dfs:
        raise FileNotFoundError("No setup telemetry CSV files found in Common\\Files or Documents\\onix_artifacts.")

    full_df = pd.concat(raw_dfs, ignore_index=True)
    sigs_all = full_df[full_df["event_stage"] == "SIGNAL_TRIGGERED"].copy()
    outs_all = full_df[full_df["event_stage"] == "POSITION_CLOSED"].copy()

    mt5_outcomes = (
        outs_all.drop_duplicates(subset=["timestamp_utc"], keep="last")
        .set_index("timestamp_utc")["realized_r_multiple"]
        .to_dict()
    )
    print(f"Exact MT5 POSITION_CLOSED outcomes mapped: {len(mt5_outcomes)}")

    sigs = (
        sigs_all.drop_duplicates(subset=["timestamp_utc"], keep="last")
        .sort_values("timestamp_utc")
        .reset_index(drop=True)
    )
    sigs["sig_utc"] = pd.to_datetime(sigs["timestamp_utc"])
    sigs["year"] = sigs["sig_utc"].dt.year
    sigs["sig_hour"] = sigs["sig_utc"].dt.hour
    sigs["sig_min"] = sigs["sig_utc"].dt.hour * 60 + sigs["sig_utc"].dt.minute

    in_lon = (sigs["sig_min"] >= 390) & (sigs["sig_min"] <= 655)
    in_ny = (sigs["sig_min"] >= 720) & (sigs["sig_min"] <= 955)
    mask_time = in_lon | in_ny

    is_frac = sigs["swept_pool_type"].isin(["M15_SWING_LOW", "M15_SWING_HIGH"])
    mask_frac = ~(
        (is_frac & sigs["sig_hour"].isin([6, 7, 8, 9]) & (sigs["f1_wick_body_ratio"] < 0.55))
        | (is_frac & (sigs["sig_min"] >= 14 * 60 + 20) & (sigs["sig_min"] < 15 * 60))
    )
    mask_pool = ~(
        ((sigs["direction"] == -1) & (sigs["swept_pool_type"] != "EQUAL_HIGHS"))
        | ((sigs["direction"] == 1) & (sigs["swept_pool_type"] == "EXTERNAL_LVN_LOW"))
    )

    cand = sigs[mask_time & mask_frac & mask_pool].copy().reset_index(drop=True)

    m1_path = os.path.join(COMMON_FILES, "of_pep_XAUUSD_20230101.csv")
    has_m1 = os.path.exists(m1_path)
    if has_m1:
        m1 = pd.read_csv(m1_path, usecols=["t", "o", "h", "l", "c"])
        m1_t, m1_o, m1_h, m1_l, m1_c = (
            m1["t"].values,
            m1["o"].values,
            m1["h"].values,
            m1["l"].values,
            m1["c"].values,
        )

    def extract_m1_ticks(srv_ts: int, d: int, limit_px: float, risk: float):
        if not has_m1:
            return None, None
        i0 = np.searchsorted(m1_t, srv_ts)
        if i0 == 0 or i0 >= len(m1_t):
            return None, None
        bar_open = m1_o[i0]
        ep = None
        start_k = i0
        if d == 1:
            ask = bar_open + 0.18
            if abs(ask - limit_px) <= 0.85:
                ep = ask
            else:
                for k in range(i0, min(len(m1_t), i0 + 15)):
                    if m1_l[k] + 0.18 <= limit_px:
                        ep = limit_px
                        start_k = k
                        break
                    if (m1_h[k] - limit_px) / risk >= 1.50:
                        return None, None
        else:
            bid = bar_open
            if abs(limit_px - bid) <= 0.85:
                ep = bid
            else:
                for k in range(i0, min(len(m1_t), i0 + 15)):
                    if m1_h[k] >= limit_px:
                        ep = limit_px
                        start_k = k
                        break
                    if (limit_px - m1_l[k]) / risk >= 1.50:
                        return None, None
        if ep is None:
            return None, None

        i1 = min(len(m1_t), start_k + 245)
        fav_r_seq = []
        for k in range(start_k, i1):
            if m1_t[k] - m1_t[start_k] > 4 * 3600:
                break
            o, h, l, c = m1_o[k], m1_h[k], m1_l[k], m1_c[k]
            pts = [o, l, h, c] if c >= o else [o, h, l, c]
            for px in pts:
                fav_r = ((px - ep) / risk) if d == 1 else ((ep - (px + 0.15)) / risk)
                fav_r_seq.append(fav_r)
        return ep, np.array(fav_r_seq, dtype=np.float64)

    def sim_seq(seq):
        tp1_t, tp1_p, tp1_s = 0.62, 0.35, -0.30
        be_t, be_s = 0.95, 0.10
        r0_t, r0_s = 1.32, 0.38
        r1_t, r1_s = 1.65, 0.78
        r2_t, r2_s = 2.25, 1.40
        r3_t, r3_s = 2.80, 2.05
        tp2_t = 3.50
        cur_sl = -1.00
        tp1_done = False
        for fav_r in seq:
            if fav_r <= cur_sl:
                return (tp1_p * tp1_t + (1.0 - tp1_p) * cur_sl - 0.02) if tp1_done else (cur_sl - 0.02)
            if fav_r >= tp2_t:
                return (tp1_p * tp1_t + (1.0 - tp1_p) * tp2_t - 0.02) if tp1_done else (tp2_t - 0.02)
            if not tp1_done and fav_r >= tp1_t:
                tp1_done = True
                cur_sl = max(cur_sl, tp1_s)
            if tp1_done:
                if fav_r >= be_t:
                    cur_sl = max(cur_sl, be_s)
                if fav_r >= r0_t:
                    cur_sl = max(cur_sl, r0_s)
                if fav_r >= r1_t:
                    cur_sl = max(cur_sl, r1_s)
                if fav_r >= r2_t:
                    cur_sl = max(cur_sl, r2_s)
                if fav_r >= r3_t:
                    cur_sl = max(cur_sl, r3_s)
        fav_r = seq[-1]
        return (tp1_p * tp1_t + (1.0 - tp1_p) * fav_r - 0.02) if tp1_done else (fav_r - 0.02)

    r_list = []
    valid_idx = []
    for idx, r in cand.iterrows():
        ts_str = r["timestamp_utc"]
        if ts_str in mt5_outcomes:
            r_list.append(float(mt5_outcomes[ts_str]))
            valid_idx.append(idx)
        else:
            utc_ts = int(pd.to_datetime(ts_str).timestamp())
            _, seq = extract_m1_ticks(
                utc_ts + 7200,
                int(r["direction"]),
                float(r["entry_limit_price"]),
                float(r["sl_distance_usd"]),
            )
            if seq is not None and len(seq) > 0:
                r_list.append(sim_seq(seq))
                valid_idx.append(idx)

    cand = cand.iloc[valid_idx].copy().reset_index(drop=True)
    cand["r_opt"] = r_list

    train_df = cand[cand["year"] >= 2024].copy().reset_index(drop=True)
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
        yr_boost = 1.35 if yrs[i] == 2024 else 1.0
        if rv <= 0.0:
            y_t, w_s = 0.05, 2.45 * yr_boost
        elif rv >= 0.45:
            y_t, w_s = 0.96, 3.65 * yr_boost
        else:
            y_t, w_s = 0.76, 2.10 * yr_boost
        z_samples.append((Z[i].tolist(), y_t, w_s, rv))

    lr, l2, epochs = 0.11, 0.0010, 1600
    for epoch in range(epochs):
        step_lr = lr / (1.0 + 0.0012 * epoch)
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
            if rv <= 0.0 and prob > 0.54:
                dyn_w *= 1.0 + 9.0 * (prob - 0.54)
            elif rv >= 0.45 and prob < 0.76:
                dyn_w *= 1.0 + 6.0 * (0.76 - prob)

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

        inv_n = 1.0 / float(n)
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
        ("2024", train_df[train_df["year"] == 2024]),
        ("2025-2026", train_df[train_df["year"] >= 2025]),
        ("ALL 2024-2026", train_df),
    ]:
        t2 = sub[sub["prob"] >= 0.58]
        t1 = sub[sub["prob"] >= 0.72]
        w2 = (t2["r_opt"] > 0).mean() * 100 if len(t2) else 0.0
        w1 = (t1["r_opt"] > 0).mean() * 100 if len(t1) else 0.0
        print(
            f"{label:15s}: T2={len(t2):3d} (WR={w2:5.1f}%, SumR={t2['r_opt'].sum():+6.2f}R) | "
            f"T1={len(t1):3d} (WR={w1:5.1f}%, SumR={t1['r_opt'].sum():+6.2f}R)"
        )

    onnx_out = os.path.join(REPO_EA_DIR, "MQL5", "Files", "models", "xauusd_meta_model.onnx")
    export_trained_model_to_onnx(clf.to_export_dict(), onnx_out)
    print(f"Exported ONNX model to: {onnx_out}")


if __name__ == "__main__":
    main()
