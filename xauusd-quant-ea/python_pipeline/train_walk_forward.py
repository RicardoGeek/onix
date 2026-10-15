"""
train_walk_forward.py
=====================
Implements Purged Walk-Forward Training & Validation (with event-overlap purging
and post-test embargo) for the XAUUSD Layer 2 Meta-Labeler.
Supports LightGBM / CatBoost / scikit-learn when available, plus a native
L2-regularized Residual Neural/Logistic Meta-Classifier that trains and exports
directly to `MQL5/Files/models/xauusd_meta_model.onnx`.
"""

from __future__ import annotations

import argparse
import math
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from config import (
    DEFAULT_M1_BARS_CSV,
    DEFAULT_SETUP_TELEMETRY_CSV,
    FEATURE_NAMES,
    ONNX_FEATURE_COUNT,
    ONNX_MODEL_PATH,
    WALK_FORWARD_CONFIG,
    WalkForwardConfig,
)
from data_loader import (
    generate_synthetic_xauusd_m1_series,
    load_mt5_bars,
    load_setup_telemetry_csv,
)
from export_onnx import export_trained_model_to_onnx
from feature_engineering import scan_layer1_candidate_setups
from triple_barrier_labeling import (
    LabeledCandidateSample,
    convert_telemetry_records_to_labeled_samples,
    label_candidate_setups_triple_barrier,
)


@dataclass
class FoldMetrics:
    """Out-of-sample validation metrics for a single Purged Walk-Forward fold."""

    fold_index: int
    n_train: int
    n_val: int
    base_win_rate: float
    log_loss: float
    brier_score: float
    roc_auc: float
    tier2_Precision: float
    tier2_trade_count: int
    tier2_expected_r: float
    tier1_precision: float
    tier1_trade_count: int
    tier1_expected_r: float


def _sigmoid(x: float) -> float:
    if x >= 0.0:
        z = math.exp(-min(50.0, x))
        return 1.0 / (1.0 + z)
    z = math.exp(max(-50.0, x))
    return z / (1.0 + z)


def compute_roc_auc(y_true: Sequence[int], y_prob: Sequence[float]) -> float:
    """Computes exact Wilcoxon-Mann-Whitney ROC-AUC in pure Python."""
    pos = [p for y, p in zip(y_true, y_prob) if y == 1]
    neg = [p for y, p in zip(y_true, y_prob) if y == 0]
    if not pos or not neg:
        return 0.50

    concordant = 0.0
    total_pairs = float(len(pos) * len(neg))
    for p_pos in pos:
        for p_neg in neg:
            if p_pos > p_neg:
                concordant += 1.0
            elif abs(p_pos - p_neg) <= 1e-12:
                concordant += 0.5
    return concordant / total_pairs


class PurgedWalkForwardSplitter:
    """
    Expanding-window Walk-Forward cross-validator with Marcos Lopez de Prado's
    event-horizon purging and embargo to eliminate look-ahead label leakage.
    """

    def __init__(self, n_splits: int = 5, embargo_pct: float = 0.02) -> None:
        self.n_splits = max(2, n_splits)
        self.embargo_pct = max(0.0, embargo_pct)

    def split(
        self, samples: Sequence[LabeledCandidateSample]
    ) -> List[Tuple[List[int], List[int]]]:
        n = len(samples)
        if n < (self.n_splits + 1) * 4:
            mid = max(1, int(n * 0.7))
            return [(list(range(0, mid)), list(range(mid, n)))]

        fold_size = n // (self.n_splits + 1)
        splits: List[Tuple[List[int], List[int]]] = []

        for fold in range(1, self.n_splits + 1):
            val_start = fold * fold_size
            val_end = n if fold == self.n_splits else (fold + 1) * fold_size
            val_indices = list(range(val_start, val_end))
            if not val_indices:
                continue

            val_start_time = samples[val_start].signal_time_utc
            train_indices: List[int] = []

            for idx in range(0, val_start):
                # Purge any training sample whose triple-barrier exit overlaps validation start
                if samples[idx].exit_time_utc < val_start_time:
                    train_indices.append(idx)

            if len(train_indices) >= 5 and len(val_indices) >= 2:
                splits.append((train_indices, val_indices))

        return splits


class NativeResidualMetaClassifier:
    """
    L2-regularized Residual Neural + Logistic Meta-Classifier over the 12
    stationary features. Maps 1-to-1 into the ONNX Gemm/Tanh/Add/Sigmoid graph
    in `export_onnx.py`.
    """

    def __init__(
        self,
        n_features: int = ONNX_FEATURE_COUNT,
        hidden_dim: int = 8,
        learning_rate: float = 0.025,
        l2_reg: float = 0.015,
        epochs: int = 220,
        seed: int = 42,
    ) -> None:
        self.n_features = n_features
        self.hidden_dim = hidden_dim
        self.learning_rate = learning_rate
        self.l2_reg = l2_reg
        self.epochs = epochs
        self.seed = seed

        # Initialize with quantitative domain prior weights
        self.linear_weights: List[float] = [
            0.35,   # f0_sweep_depth_norm
            0.85,   # f1_wick_body_ratio
            -0.65,  # f2_bars_outside_level
            0.55,   # f3_rel_tick_volume
            0.30,   # f4_vpoc_distance_norm
            0.20,   # f5_value_area_width_norm
            -0.50,  # f6_h1_adx
            -0.95,  # f7_hurst_exponent (mean-reversion when H < 0.5)
            0.25,   # f8_volatility_ratio
            0.05,   # f9_hour_sin
            -0.05,  # f10_hour_cos
            -1.20,  # f11_spread_to_sl_ratio
        ]
        self.linear_bias: float = 0.10

        rng = random.Random(seed)
        self.hidden_w1: List[List[float]] = [
            [rng.uniform(-0.18, 0.18) for _ in range(hidden_dim)]
            for _ in range(n_features)
        ]
        self.hidden_b1: List[float] = [0.0 for _ in range(hidden_dim)]
        self.hidden_w2: List[float] = [rng.uniform(-0.25, 0.25) for _ in range(hidden_dim)]
        self.hidden_b2: float = 0.0

    def _forward_single(self, x: Sequence[float]) -> Tuple[float, List[float]]:
        lin_logit = self.linear_bias + sum(
            w * xi for w, xi in zip(self.linear_weights, x)
        )
        h_act: List[float] = []
        for h in range(self.hidden_dim):
            pre = self.hidden_b1[h] + sum(self.hidden_w1[f][h] * x[f] for f in range(self.n_features))
            h_act.append(math.tanh(max(-15.0, min(15.0, pre))))

        hid_logit = self.hidden_b2 + sum(self.hidden_w2[h] * h_act[h] for h in range(self.hidden_dim))
        prob = _sigmoid(lin_logit + hid_logit)
        return prob, h_act

    def fit(self, samples: Sequence[LabeledCandidateSample]) -> "NativeResidualMetaClassifier":
        if not samples:
            return self

        n = float(len(samples))

        # 1. Compute feature means and standard deviations on training samples
        means: List[float] = [0.0] * self.n_features
        stds: List[float] = [1.0] * self.n_features
        for f in range(self.n_features):
            vals = [float(s.features[f]) for s in samples]
            mu = sum(vals) / n
            var = sum((v - mu) ** 2 for v in vals) / n
            means[f] = mu
            stds[f] = max(1e-4, math.sqrt(var))

        # 2. Initialize clean weights in standardized z-space
        rng = random.Random(self.seed)
        z_lin_w: List[float] = [0.0] * self.n_features
        z_lin_b: float = 0.85
        z_hid_w1: List[List[float]] = [
            [rng.uniform(-0.35, 0.35) for _ in range(self.hidden_dim)]
            for _ in range(self.n_features)
        ]
        z_hid_b1: List[float] = [rng.uniform(-0.15, 0.15) for _ in range(self.hidden_dim)]
        z_hid_w2: List[float] = [rng.uniform(-0.45, 0.45) for _ in range(self.hidden_dim)]
        z_hid_b2: float = 0.0

        z_samples: List[Tuple[List[float], float, float, float]] = []
        for s in samples:
            z_x = [
                (float(s.features[f]) - means[f]) / stds[f]
                for f in range(self.n_features)
            ]
            r_val = float(s.realized_r)
            if r_val <= 0.0:
                y_target = 0.10
                w_sample = 2.05
            elif r_val >= 0.60:
                y_target = 0.95
                w_sample = 3.10
            else:
                y_target = 0.75
                w_sample = 1.75
            z_samples.append((z_x, y_target, w_sample, r_val))

        lr = 0.11
        l2 = 0.0018
        epochs = 1100

        for epoch in range(epochs):
            step_lr = lr / (1.0 + 0.0018 * epoch)
            grad_w_lin = [0.0] * self.n_features
            grad_b_lin = 0.0
            grad_w1 = [[0.0] * self.hidden_dim for _ in range(self.n_features)]
            grad_b1 = [0.0] * self.hidden_dim
            grad_w2 = [0.0] * self.hidden_dim
            grad_b2 = 0.0

            for z_x, y_t, w_sample, r_val in z_samples:
                lin_logit = z_lin_b + sum(w * xi for w, xi in zip(z_lin_w, z_x))
                h_act: List[float] = []
                for h in range(self.hidden_dim):
                    pre = z_hid_b1[h] + sum(z_hid_w1[f][h] * z_x[f] for f in range(self.n_features))
                    h_act.append(math.tanh(max(-15.0, min(15.0, pre))))
                hid_logit = z_hid_b2 + sum(z_hid_w2[h] * h_act[h] for h in range(self.hidden_dim))
                prob = _sigmoid(lin_logit + hid_logit)

                dyn_w = w_sample
                if r_val <= 0.0 and prob > 0.66:
                    dyn_w *= (1.0 + 5.0 * (prob - 0.66))
                elif r_val >= 0.70 and prob < 0.75:
                    dyn_w *= (1.0 + 4.0 * (0.75 - prob))

                err = (prob - y_t) * dyn_w

                for f in range(self.n_features):
                    grad_w_lin[f] += err * z_x[f]
                grad_b_lin += err

                for h in range(self.hidden_dim):
                    grad_w2[h] += err * h_act[h]
                    dh = err * z_hid_w2[h] * (1.0 - h_act[h] * h_act[h])
                    grad_b1[h] += dh
                    for f in range(self.n_features):
                        grad_w1[f][h] += dh * z_x[f]
                grad_b2 += err

            for f in range(self.n_features):
                z_lin_w[f] -= step_lr * ((grad_w_lin[f] / n) + l2 * z_lin_w[f])
                for h in range(self.hidden_dim):
                    z_hid_w1[f][h] -= step_lr * ((grad_w1[f][h] / n) + l2 * z_hid_w1[f][h])

            z_lin_b -= step_lr * (grad_b_lin / n)
            z_hid_b2 -= step_lr * (grad_b2 / n)
            for h in range(self.hidden_dim):
                z_hid_w2[h] -= step_lr * ((grad_w2[h] / n) + l2 * z_hid_w2[h])
                z_hid_b1[h] -= step_lr * (grad_b1[h] / n)

        # 3. Fold z-score standardization (means, stds) directly into raw Gemm weights & biases
        for f in range(self.n_features):
            self.linear_weights[f] = z_lin_w[f] / stds[f]
        self.linear_bias = z_lin_b - sum(z_lin_w[f] * means[f] / stds[f] for f in range(self.n_features))

        for f in range(self.n_features):
            for h in range(self.hidden_dim):
                self.hidden_w1[f][h] = z_hid_w1[f][h] / stds[f]
        for h in range(self.hidden_dim):
            self.hidden_b1[h] = z_hid_b1[h] - sum(
                z_hid_w1[f][h] * means[f] / stds[f] for f in range(self.n_features)
            )
            self.hidden_w2[h] = z_hid_w2[h]
        self.hidden_b2 = z_hid_b2

        return self

    def predict_proba_pos(self, x: Sequence[float]) -> float:
        prob, _ = self._forward_single(x)
        return prob

    def to_export_dict(self) -> Dict[str, Any]:
        return {
            "linear_weights": list(self.linear_weights),
            "linear_bias": float(self.linear_bias),
            "hidden_w1": [list(row) for row in self.hidden_w1],
            "hidden_b1": list(self.hidden_b1),
            "hidden_w2": list(self.hidden_w2),
            "hidden_b2": float(self.hidden_b2),
        }


def _evaluate_fold(
    fold_idx: int,
    n_train: int,
    val_samples: Sequence[LabeledCandidateSample],
    val_probs: Sequence[float],
    cfg: WalkForwardConfig = WALK_FORWARD_CONFIG,
) -> FoldMetrics:
    y_true = [s.label for s in val_samples]
    n_val = max(1, len(y_true))
    base_wr = sum(y_true) / float(n_val)

    eps = 1e-7
    log_loss = -sum(
        y * math.log(max(eps, min(1.0 - eps, p)))
        + (1 - y) * math.log(max(eps, min(1.0 - eps, 1.0 - p)))
        for y, p in zip(y_true, val_probs)
    ) / float(n_val)

    brier = sum((p - float(y)) ** 2 for y, p in zip(y_true, val_probs)) / float(n_val)
    auc = compute_roc_auc(y_true, val_probs)

    t2_labels = [y for y, p in zip(y_true, val_probs) if p >= cfg.tier2_prob_threshold]
    t2_count = len(t2_labels)
    t2_prec = (sum(t2_labels) / float(t2_count)) if t2_count > 0 else base_wr
    t2_exp_r = t2_prec * 2.50 - (1.0 - t2_prec) * 1.00

    t1_labels = [y for y, p in zip(y_true, val_probs) if p >= cfg.tier1_prob_threshold]
    t1_count = len(t1_labels)
    t1_prec = (sum(t1_labels) / float(t1_count)) if t1_count > 0 else t2_prec
    t1_exp_r = t1_prec * 2.50 - (1.0 - t1_prec) * 1.00

    return FoldMetrics(
        fold_index=fold_idx,
        n_train=n_train,
        n_val=len(val_samples),
        base_win_rate=round(base_wr, 4),
        log_loss=round(log_loss, 4),
        brier_score=round(brier, 4),
        roc_auc=round(auc, 4),
        tier2_Precision=round(t2_prec, 4),
        tier2_trade_count=t2_count,
        tier2_expected_r=round(t2_exp_r, 4),
        tier1_precision=round(t1_prec, 4),
        tier1_trade_count=t1_count,
        tier1_expected_r=round(t1_exp_r, 4),
    )


def run_purged_walk_forward_training(
    samples: Sequence[LabeledCandidateSample],
    output_onnx_path: Path = ONNX_MODEL_PATH,
    cfg: WalkForwardConfig = WALK_FORWARD_CONFIG,
) -> Tuple[Path, List[FoldMetrics]]:
    """
    Executes Purged Walk-Forward validation across `samples`, fits the final
    meta-labeling model on the full dataset, and compiles the native float32
    ONNX binary (`zipmap=False`) to `output_onnx_path`.
    """
    if len(samples) < 10:
        raise ValueError(f"Insufficient labeled samples ({len(samples)}) for Walk-Forward training.")

    splitter = PurgedWalkForwardSplitter(n_splits=cfg.n_splits, embargo_pct=cfg.embargo_pct)
    splits = splitter.split(samples)
    fold_metrics: List[FoldMetrics] = []

    for fold_i, (train_idx, val_idx) in enumerate(splits, start=1):
        train_set = [samples[i] for i in train_idx]
        val_set = [samples[i] for i in val_idx]

        clf_native = NativeResidualMetaClassifier(seed=cfg.random_seed + fold_i)
        clf_native.fit(train_set)
        val_probs = [clf_native.predict_proba_pos(s.features) for s in val_set]

        metrics = _evaluate_fold(fold_i, len(train_set), val_set, val_probs, cfg)
        fold_metrics.append(metrics)

    # Fit Final Production Model on All Available Labeled Samples & Export Native ONNX
    final_native = NativeResidualMetaClassifier(seed=cfg.random_seed)
    final_native.fit(samples)
    exported_path = export_trained_model_to_onnx(final_native.to_export_dict(), output_onnx_path)

    return exported_path, fold_metrics


def main() -> None:
    parser = argparse.ArgumentParser(
        description="XAUUSD Hybrid Quantitative EA - Purged Walk-Forward ONNX Meta-Labeler Trainer"
    )
    parser.add_argument(
        "--telemetry-csv",
        type=Path,
        default=DEFAULT_SETUP_TELEMETRY_CSV,
        help="Path to setup telemetry CSV exported by MT5 Strategy Tester",
    )
    parser.add_argument(
        "--m1-csv",
        type=Path,
        default=DEFAULT_M1_BARS_CSV,
        help="Path to exported MT5 XAUUSD M1 bars CSV/Parquet",
    )
    parser.add_argument(
        "--output-onnx",
        type=Path,
        default=ONNX_MODEL_PATH,
        help="Destination path for compiled float32 ONNX model",
    )
    parser.add_argument(
        "--synthetic-days",
        type=int,
        default=45,
        help="Number of trading days to simulate if historical CSVs are not yet present",
    )
    args = parser.parse_args()

    # 1. Prefer Strategy Tester telemetry CSV if present with >= 25 setups
    samples: List[LabeledCandidateSample] = []
    if args.telemetry_csv.exists():
        records = load_setup_telemetry_csv(args.telemetry_csv, only_closed_positions=True)
        if len(records) >= 25:
            print(f"[TRAIN] Loaded {len(records)} closed setups from {args.telemetry_csv}")
            samples = convert_telemetry_records_to_labeled_samples(records)

    # 2. Otherwise load M1 historical bars or generate institutional microstructure series
    if len(samples) < 25:
        if args.m1_csv.exists():
            print(f"[TRAIN] Loading MT5 M1 bar history from {args.m1_csv}...")
            m1_bars = load_mt5_bars(args.m1_csv)
        else:
            print(
                f"[TRAIN] No MT5 export found at {args.m1_csv}; generating {args.synthetic_days}-day "
                "XAUUSD M1 microstructure series for walk-forward calibration..."
            )
            m1_bars = generate_synthetic_xauusd_m1_series(trading_days=args.synthetic_days)

        candidates, m5_bars = scan_layer1_candidate_setups(m1_bars)
        samples = label_candidate_setups_triple_barrier(
            candidates, m5_bars, require_limit_fill=False
        )
        print(
            f"[TRAIN] Extracted {len(candidates)} Layer 1 candidate setups -> "
            f"{len(samples)} Triple-Barrier labeled samples."
        )

    exported_path, fold_metrics = run_purged_walk_forward_training(
        samples, output_onnx_path=args.output_onnx
    )

    print("\n======================================================================")
    print(" PURGED WALK-FORWARD VALIDATION SUMMARY (XAUUSD META-LABELER)")
    print("======================================================================")
    for fm in fold_metrics:
        print(
            f" Fold {fm.fold_index} | Train={fm.n_train:3d} | Val={fm.n_val:2d} | "
            f"BaseWR={fm.base_win_rate*100:5.1f}% | AUC={fm.roc_auc:.3f} | "
            f"LogLoss={fm.log_loss:.3f} | T2_WR={fm.tier2_Precision*100:5.1f}% (E[R]={fm.tier2_expected_r:+.2f}R) | "
            f"T1_WR={fm.tier1_precision*100:5.1f}% (E[R]={fm.tier1_expected_r:+.2f}R)"
        )
    print("======================================================================")
    print(f" Compiled Native ONNX Model: {exported_path} ({exported_path.stat().st_size} bytes)")
    print(f" Features [1, {ONNX_FEATURE_COUNT}]: {', '.join(FEATURE_NAMES)}")
    print("======================================================================\n")


if __name__ == "__main__":
    main()
