"""
triple_barrier_labeling.py
==========================
Implements Marcos Lopez de Prado's Triple-Barrier Meta-Labeling method tailored
for the XAUUSD Sniper EA:
  - Upper Horizontal Barrier : +2.5R profit target from sniper limit entry
  - Lower Horizontal Barrier : -1.0R structural stop loss
  - Vertical Time Barrier    : 4-hour expiration window (48 M5 bars / 240 M1 bars)
  - Binary Meta-Label        : 1 if +2.5R is reached before SL or 4h expiry, else 0
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional, Sequence

from config import TRIPLE_BARRIER_CONFIG, TripleBarrierConfig
from data_loader import OhlcvBar, SetupTelemetryRecord
from feature_engineering import CandidateSetupPy


@dataclass
class LabeledCandidateSample:
    """Complete meta-labeled training sample with 12 stationary features and barrier outcome."""

    setup_id: int
    signal_time_utc: datetime
    exit_time_utc: datetime
    direction: int
    entry_price: float
    stop_loss_price: float
    upper_barrier_2_5r_price: float
    sl_distance_usd: float
    features: List[float]
    label: int                       # 1 = reached +2.5R before SL/Time, 0 = SL or Time expiry
    realized_r: float
    mfe_r: float
    mae_r: float
    holding_m5_bars: int
    exit_reason: str                 # "UPPER_2_5R", "LOWER_SL", "VERTICAL_TIME"
    sample_weight: float = 1.0


def label_candidate_setups_triple_barrier(
    candidates: Sequence[CandidateSetupPy],
    m5_bars: Sequence[OhlcvBar],
    cfg: TripleBarrierConfig = TRIPLE_BARRIER_CONFIG,
    require_limit_fill: bool = True,
) -> List[LabeledCandidateSample]:
    """
    Applies the 3-barrier labeling procedure to each Layer 1 candidate setup
    using subsequent M5 price bars.
    """
    labeled_samples: List[LabeledCandidateSample] = []
    n_bars = len(m5_bars)

    for setup in candidates:
        sig_idx = setup.m5_bar_index
        if sig_idx + 2 >= n_bars:
            continue

        entry_px = setup.entry_limit_price
        sl_px = setup.stop_loss_price
        sl_dist = max(1.20, setup.sl_distance_usd)
        direction = setup.direction

        if direction == 1:
            upper_px = round(entry_px + cfg.upper_profit_target_r * sl_dist, 2)
            runaway_px = entry_px + cfg.runaway_cancel_r * sl_dist
        else:
            upper_px = round(entry_px - cfg.upper_profit_target_r * sl_dist, 2)
            runaway_px = entry_px - cfg.runaway_cancel_r * sl_dist

        # Step 1: Pending Limit Order Fill Evaluation (within 3 M5 bars)
        fill_bar_idx: Optional[int] = None
        if not require_limit_fill:
            fill_bar_idx = sig_idx + 1
        else:
            max_fill_idx = min(n_bars - 1, sig_idx + cfg.limit_fill_expiry_m5_bars)
            for b_idx in range(sig_idx + 1, max_fill_idx + 1):
                bar = m5_bars[b_idx]
                if direction == 1:
                    if bar.low <= entry_px:
                        fill_bar_idx = b_idx
                        break
                    if bar.high >= runaway_px:
                        break  # Runaway +1.5R before limit fill -> order cancelled
                else:
                    if bar.high >= entry_px:
                        fill_bar_idx = b_idx
                        break
                    if bar.low <= runaway_px:
                        break

        if fill_bar_idx is None:
            continue

        # Step 2: Evaluate Horizontal (+2.5R / -1.0R SL) & Vertical (4-Hour = 48 M5 bars) Barriers
        end_barrier_idx = min(n_bars - 1, fill_bar_idx + cfg.vertical_barrier_m5_bars)
        label = 0
        exit_reason = "VERTICAL_TIME"
        exit_bar_idx = end_barrier_idx
        realized_r = 0.0
        mfe_r = 0.0
        mae_r = 0.0

        for b_idx in range(fill_bar_idx, end_barrier_idx + 1):
            bar = m5_bars[b_idx]
            half_spread = 0.5 * bar.spread_usd

            if direction == 1:
                fav_exc = (bar.high - entry_px) / sl_dist
                adv_exc = max(0.0, (entry_px - bar.low) / sl_dist)
                mfe_r = max(mfe_r, fav_exc)
                mae_r = max(mae_r, adv_exc)

                hit_sl = (bar.low - half_spread) <= sl_px
                hit_tp = (bar.high - half_spread) >= upper_px
            else:
                fav_exc = (entry_px - bar.low) / sl_dist
                adv_exc = max(0.0, (bar.high - entry_px) / sl_dist)
                mfe_r = max(mfe_r, fav_exc)
                mae_r = max(mae_r, adv_exc)

                hit_sl = (bar.high + half_spread) >= sl_px
                hit_tp = (bar.low + half_spread) <= upper_px

            # Conservative resolution: if both SL and TP touched on same bar, count as SL loss
            if hit_sl:
                label = 0
                exit_reason = "LOWER_SL"
                exit_bar_idx = b_idx
                realized_r = -1.0
                break

            if hit_tp:
                label = 1
                exit_reason = "UPPER_2_5R"
                exit_bar_idx = b_idx
                realized_r = cfg.upper_profit_target_r
                break

        if exit_reason == "VERTICAL_TIME":
            last_close = m5_bars[exit_bar_idx].close
            if direction == 1:
                realized_r = (last_close - entry_px) / sl_dist
            else:
                realized_r = (entry_px - last_close) / sl_dist
            label = 1 if realized_r >= cfg.upper_profit_target_r else 0

        holding_bars = max(1, exit_bar_idx - fill_bar_idx + 1)
        labeled_samples.append(
            LabeledCandidateSample(
                setup_id=setup.setup_id,
                signal_time_utc=setup.signal_time_utc,
                exit_time_utc=m5_bars[exit_bar_idx].timestamp_utc,
                direction=direction,
                entry_price=entry_px,
                stop_loss_price=sl_px,
                upper_barrier_2_5r_price=upper_px,
                sl_distance_usd=sl_dist,
                features=list(setup.features),
                label=label,
                realized_r=round(realized_r, 4),
                mfe_r=round(mfe_r, 4),
                mae_r=round(mae_r, 4),
                holding_m5_bars=holding_bars,
                exit_reason=exit_reason,
                sample_weight=1.0,
            )
        )

    return compute_concurrency_uniqueness_weights(labeled_samples)


def convert_telemetry_records_to_labeled_samples(
    records: Sequence[SetupTelemetryRecord],
    cfg: TripleBarrierConfig = TRIPLE_BARRIER_CONFIG,
) -> List[LabeledCandidateSample]:
    """
    Converts SetupTelemetryRecord rows exported by MT5 Strategy Tester into
    LabeledCandidateSample objects for Purged Walk-Forward training.
    """
    samples: List[LabeledCandidateSample] = []
    for rec in records:
        if rec.label_2_5r in (0, 1):
            lbl = rec.label_2_5r
        else:
            lbl = 1 if (rec.mfe_r >= cfg.upper_profit_target_r or rec.realized_r_multiple >= 2.25) else 0

        upper_px = (
            rec.entry_limit_price + cfg.upper_profit_target_r * rec.sl_distance_usd
            if rec.direction == 1
            else rec.entry_limit_price - cfg.upper_profit_target_r * rec.sl_distance_usd
        )
        samples.append(
            LabeledCandidateSample(
                setup_id=rec.setup_id,
                signal_time_utc=rec.timestamp_utc,
                exit_time_utc=rec.timestamp_utc,
                direction=rec.direction,
                entry_price=rec.entry_limit_price,
                stop_loss_price=rec.stop_loss_price,
                upper_barrier_2_5r_price=round(upper_px, 2),
                sl_distance_usd=rec.sl_distance_usd,
                features=list(rec.features),
                label=lbl,
                realized_r=rec.realized_r_multiple,
                mfe_r=rec.mfe_r,
                mae_r=rec.mae_r,
                holding_m5_bars=12,
                exit_reason="UPPER_2_5R" if lbl == 1 else "LOWER_SL_OR_TIME",
                sample_weight=1.0,
            )
        )
    return compute_concurrency_uniqueness_weights(samples)


def compute_concurrency_uniqueness_weights(
    samples: List[LabeledCandidateSample],
) -> List[LabeledCandidateSample]:
    """
    Assigns uniqueness-adjusted sample weights based on event overlap between
    [signal_time_utc, exit_time_utc] and outcome magnitude.
    """
    n = len(samples)
    if n == 0:
        return samples

    raw_weights: List[float] = []
    for i, s_i in enumerate(samples):
        overlap_count = 1
        for j, s_j in enumerate(samples):
            if i == j:
                continue
            if s_j.signal_time_utc <= s_i.exit_time_utc and s_j.exit_time_utc >= s_i.signal_time_utc:
                overlap_count += 1
        uniqueness = 1.0 / float(overlap_count)
        magnitude_boost = 1.0 + 0.10 * min(3.0, abs(s_i.realized_r))
        raw_weights.append(uniqueness * magnitude_boost)

    mean_w = sum(raw_weights) / float(n)
    if mean_w > 0.0:
        for s, w in zip(samples, raw_weights):
            s.sample_weight = round(w / mean_w, 4)

    return samples
