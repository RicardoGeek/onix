"""
config.py
=========
Centralized configuration, institutional constants, feature schema definitions,
Triple-Barrier labeling parameters, Purged Walk-Forward CV settings, and ONNX
runtime tensor contracts for the XAUUSD Hybrid Quantitative Sniper EA.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Tuple


# ---------------------------------------------------------------------------
# Workspace & Artifact Directory Paths
# ---------------------------------------------------------------------------
PIPELINE_DIR: Path = Path(__file__).resolve().parent
PROJECT_ROOT: Path = PIPELINE_DIR.parent
MQL5_DIR: Path = PROJECT_ROOT / "MQL5"
MQL5_FILES_DIR: Path = MQL5_DIR / "Files"
ONNX_MODELS_DIR: Path = MQL5_FILES_DIR / "models"
ONNX_MODEL_PATH: Path = ONNX_MODELS_DIR / "xauusd_meta_model.onnx"

DEFAULT_SETUP_TELEMETRY_CSV: Path = MQL5_FILES_DIR / "xauusd_setup_telemetry.csv"
DEFAULT_M1_BARS_CSV: Path = MQL5_FILES_DIR / "XAUUSD_M1.csv"
DEFAULT_M5_BARS_CSV: Path = MQL5_FILES_DIR / "XAUUSD_M5.csv"


# ---------------------------------------------------------------------------
# Exact 12-Feature Stationary Input Schema (Zero Training-Serving Skew)
# ---------------------------------------------------------------------------
ONNX_FEATURE_COUNT: int = 12

FEATURE_NAMES: Tuple[str, ...] = (
    "f0_sweep_depth_norm",       # [0] (Sweep_Extreme_Distance_Beyond_Level) / ATR_M15(14)
    "f1_wick_body_ratio",        # [1] Rejection_Wick_Size / MathMax(Candle_Range, 0.01)
    "f2_bars_outside_level",     # [2] M1 bars spent beyond swept level before reclaim / 15.0
    "f3_rel_tick_volume",        # [3] Sweep_M5_TickVol / SMA(M5_TickVol, 20)
    "f4_vpoc_distance_norm",     # [4] MathAbs(Entry_Price - Session_VPOC) / ATR_M15(14)
    "f5_value_area_width_norm",  # [5] (Session_VAH - Session_VAL) / ATR_H1(14)
    "f6_h1_adx",                 # [6] ADX(H1, 14) / 100.0
    "f7_hurst_exponent",         # [7] Rolling 100-bar M5 Hurst Exponent H in [0, 1]
    "f8_volatility_ratio",       # [8] ATR_M15(14) / ATR_H4(14)
    "f9_hour_sin",               # [9] MathSin(2.0 * M_PI * Current_UTC_Hour / 24.0)
    "f10_hour_cos",              # [10] MathCos(2.0 * M_PI * Current_UTC_Hour / 24.0)
    "f11_spread_to_sl_ratio",    # [11] (Current_Spread_In_Dollars) / Stop_Loss_Distance_In_Dollars
)

FEATURE_BOUNDS: Dict[str, Tuple[float, float, float]] = {
    # feature_name: (min_clamp, max_clamp, default_fallback)
    "f0_sweep_depth_norm":      (0.00, 5.00, 0.30),
    "f1_wick_body_ratio":       (0.00, 1.00, 0.50),
    "f2_bars_outside_level":    (0.00, 3.00, 0.20),
    "f3_rel_tick_volume":       (0.10, 10.0, 1.50),
    "f4_vpoc_distance_norm":    (0.00, 10.0, 1.00),
    "f5_value_area_width_norm": (0.05, 10.0, 1.00),
    "f6_h1_adx":                (0.00, 1.00, 0.25),
    "f7_hurst_exponent":        (0.05, 0.95, 0.50),
    "f8_volatility_ratio":      (0.05, 3.00, 0.25),
    "f9_hour_sin":              (-1.0, 1.00, 0.00),
    "f10_hour_cos":             (-1.0, 1.00, 1.00),
    "f11_spread_to_sl_ratio":   (0.00, 1.00, 0.10),
}


# ---------------------------------------------------------------------------
# Layer 1 Structural & Volume Profile Parameters (Identical to MQL5)
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Layer1SignalConfig:
    symbol: str = "XAUUSD"
    vp_bin_size_usd: float = 0.25
    vp_value_area_pct: float = 0.70
    vp_lvn_threshold_ratio: float = 0.30
    asian_start_hour_utc: int = 0
    asian_end_hour_utc: int = 7
    london_kz_start_minutes_utc: int = 7 * 60        # 07:00 UTC
    london_kz_end_minutes_utc: int = 10 * 60 + 30    # 10:30 UTC
    ny_kz_start_minutes_utc: int = 12 * 60 + 30      # 12:30 UTC
    ny_kz_end_minutes_utc: int = 16 * 60             # 16:00 UTC
    rollover_start_minutes_utc: int = 20 * 60 + 55   # 20:55 UTC
    rollover_end_minutes_utc: int = 22 * 60 + 10     # 22:10 UTC
    min_sweep_atr_m15_ratio: float = 0.15
    max_sweep_atr_m15_ratio: float = 0.65
    equal_level_atr_m15_ratio: float = 0.15
    min_absorption_rel_vol: float = 1.50
    max_reclaim_m5_bars: int = 3
    limit_expiry_m5_bars: int = 3
    sl_fixed_buffer_usd: float = 0.15
    sl_atr_m5_multiplier: float = 0.20
    hard_min_sl_usd: float = 1.20
    hard_max_sl_usd: float = 4.00
    ideal_min_sl_usd: float = 1.50
    ideal_max_sl_usd: float = 3.50
    asian_exhaustion_adr_mult: float = 1.50
    atr_compression_percentile: float = 5.0
    hurst_window_m5_bars: int = 100
    hurst_lags: Tuple[int, ...] = (2, 4, 8, 16, 32)


# ---------------------------------------------------------------------------
# Triple-Barrier Meta-Labeling Parameters (Section 5)
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class TripleBarrierConfig:
    upper_profit_target_r: float = 2.50       # +2.5R profit-taking horizontal barrier
    lower_stop_loss_r: float = 1.00           # -1.0R stop-loss horizontal barrier
    vertical_barrier_hours: float = 4.0       # 4-hour vertical time expiration barrier
    vertical_barrier_m5_bars: int = 48        # 48 M5 bars = 4 hours
    vertical_barrier_m1_bars: int = 240       # 240 M1 bars = 4 hours
    limit_fill_expiry_m5_bars: int = 3        # Pending limit order expires after 3 M5 bars
    runaway_cancel_r: float = 1.50            # Cancel unfilled limit if price reaches +1.5R
    round_turn_commission_per_lot: float = 7.0
    contract_size_oz: float = 100.0


# ---------------------------------------------------------------------------
# Purged Walk-Forward Training & Model Hyperparameters
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class WalkForwardConfig:
    n_splits: int = 5
    purge_window_bars: int = 48               # 4-hour purge window to prevent label leakage
    embargo_pct: float = 0.02                 # 2% embargo after validation fold
    min_train_samples: int = 60
    tier2_prob_threshold: float = 0.58        # Minimum meta-label probability to execute Tier-2
    tier1_prob_threshold: float = 0.72        # High-conviction probability threshold for Tier-1
    random_seed: int = 42
    lgbm_params: Dict[str, object] = field(
        default_factory=lambda: {
            "objective": "binary",
            "metric": "binary_logloss",
            "boosting_type": "gbdt",
            "n_estimators": 150,
            "learning_rate": 0.03,
            "num_leaves": 15,
            "max_depth": 4,
            "min_child_samples": 20,
            "subsample": 0.80,
            "colsample_bytree": 0.80,
            "reg_alpha": 0.50,
            "reg_lambda": 1.50,
            "random_state": 42,
            "n_jobs": 1,
            "verbose": -1,
        }
    )


# ---------------------------------------------------------------------------
# MQL5 Native ONNX Export Contract (Section 5.2)
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class OnnxExportConfig:
    input_tensor_name: str = "input_features"
    output_label_name: str = "label"
    output_prob_name: str = "probabilities"
    n_features: int = ONNX_FEATURE_COUNT
    target_opset: int = 15
    ir_version: int = 8
    zipmap: bool = False                      # MUST be False for MQL5 OnnxRun compatibility


# Default Singleton Configurations
LAYER1_CONFIG = Layer1SignalConfig()
TRIPLE_BARRIER_CONFIG = TripleBarrierConfig()
WALK_FORWARD_CONFIG = WalkForwardConfig()
ONNX_EXPORT_CONFIG = OnnxExportConfig()
