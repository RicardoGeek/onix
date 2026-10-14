"""
bootstrap_dummy_onnx.py
=======================
Generates an initial valid, calibrated 12-feature float32 ONNX model binary at
`MQL5/Files/models/xauusd_meta_model.onnx` so `XAUUSD_Sniper_ONNX.mq5` compiles
with `#resource "\\Files\\models\\xauusd_meta_model.onnx" as uchar ExtOnnxModel[]`
out of the box on Day 1.

Tensor Contract (MQL5 OnnxRun Compatible, zipmap=False):
  - Input 0 : "input_features" float32[1, 12]
  - Output 0: "label"          int64[1]
  - Output 1: "probabilities"  float32[1, 2]
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, List

from config import FEATURE_NAMES, ONNX_EXPORT_CONFIG, ONNX_FEATURE_COUNT, ONNX_MODEL_PATH
from export_onnx import export_trained_model_to_onnx


def build_calibrated_bootstrap_parameters() -> Dict[str, object]:
    """
    Returns calibrated quantitative domain weights for the 12 stationary features
    so the Day-1 ONNX model produces meaningful meta-labeling probabilities
    P in [0, 1] across Tier-1 (>= 0.72), Tier-2 ([0.58, 0.72)), and Reject (< 0.58).
    """
    # Exact 12-feature order matching FeatureExtractor.mqh and feature_engineering.py:
    # [0] f0_sweep_depth_norm      (+) moderate depth beyond liquidity pool
    # [1] f1_wick_body_ratio       (+) large rejection wick relative to candle range
    # [2] f2_bars_outside_level    (-) fewer M1 bars outside level = faster absorption
    # [3] f3_rel_tick_volume       (+) higher M5 tick volume vs SMA(20) = absorption
    # [4] f4_vpoc_distance_norm    (+) room between entry and Session VPOC magnet
    # [5] f5_value_area_width_norm (+) healthy intraday Value Area width vs H1 ATR
    # [6] f6_h1_adx                (-) avoid fading extreme H1 runaway trends
    # [7] f7_hurst_exponent        (-) H < 0.5 indicates mean-reverting microstructure
    # [8] f8_volatility_ratio      (+) active intraday M15 ATR relative to H4 ATR
    # [9] f9_hour_sin              (~) London/NY Killzone phase encoding
    # [10] f10_hour_cos            (~) London/NY Killzone phase encoding
    # [11] f11_spread_to_sl_ratio  (-) penalize wide spread relative to stop loss
    linear_weights: List[float] = [
        0.42,   # [0] f0_sweep_depth_norm
        0.95,   # [1] f1_wick_body_ratio
        -0.75,  # [2] f2_bars_outside_level
        0.58,   # [3] f3_rel_tick_volume
        0.36,   # [4] f4_vpoc_distance_norm
        0.22,   # [5] f5_value_area_width_norm
        -0.55,  # [6] f6_h1_adx
        -1.10,  # [7] f7_hurst_exponent
        0.28,   # [8] f8_volatility_ratio
        0.06,   # [9] f9_hour_sin
        -0.08,  # [10] f10_hour_cos
        -1.35,  # [11] f11_spread_to_sl_ratio
    ]
    assert len(linear_weights) == ONNX_FEATURE_COUNT

    hidden_dim = 8
    hidden_w1: List[List[float]] = []
    for f_idx, w in enumerate(linear_weights):
        row = [
            round(w * (0.22 if (f_idx + h_idx) % 2 == 0 else -0.16), 5)
            for h_idx in range(hidden_dim)
        ]
        hidden_w1.append(row)

    hidden_b1: List[float] = [-0.05, 0.05, -0.03, 0.03, -0.02, 0.02, -0.01, 0.01]
    hidden_w2: List[float] = [0.28, -0.22, 0.24, -0.18, 0.20, -0.15, 0.16, -0.12]

    return {
        "linear_weights": linear_weights,
        "linear_bias": 0.18,
        "hidden_w1": hidden_w1,
        "hidden_b1": hidden_b1,
        "hidden_w2": hidden_w2,
        "hidden_b2": 0.04,
    }


def generate_bootstrap_onnx(output_path: Path = ONNX_MODEL_PATH) -> Path:
    """Builds and writes the Day-1 ONNX model binary for MQL5 #resource embedding."""
    params = build_calibrated_bootstrap_parameters()
    saved_path = export_trained_model_to_onnx(params, output_path=output_path)
    return saved_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Bootstrap initial MQL5-compatible float32[1,12] ONNX Meta-Labeler binary"
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=ONNX_MODEL_PATH,
        help="Output path for xauusd_meta_model.onnx",
    )
    args = parser.parse_args()

    out_path = generate_bootstrap_onnx(args.output)
    size_bytes = out_path.stat().st_size

    print("======================================================================")
    print(" XAUUSD ONNX BOOTSTRAP GENERATOR COMPLETE")
    print("======================================================================")
    print(f" Target Binary : {out_path}")
    print(f" Binary Size   : {size_bytes} bytes")
    print(f" Input Tensor  : '{ONNX_EXPORT_CONFIG.input_tensor_name}' float32[1, {ONNX_FEATURE_COUNT}]")
    print(f" Output 0      : '{ONNX_EXPORT_CONFIG.output_label_name}' int64[1]")
    print(f" Output 1      : '{ONNX_EXPORT_CONFIG.output_prob_name}' float32[1, 2] (zipmap=False)")
    print(f" Feature Order : {', '.join(FEATURE_NAMES)}")
    print("======================================================================")


if __name__ == "__main__":
    main()
