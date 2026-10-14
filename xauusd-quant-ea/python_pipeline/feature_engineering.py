"""
feature_engineering.py
======================
Replicates MQL5 Layer 1 (SessionLevels, VolumeProfile, SweepSignalEngine) and
Layer 2 (FeatureExtractor) in Python with zero training-serving skew.
Computes the exact 12 stationary normalized features in identical order to
`FeatureExtractor.mqh`.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, List, Optional, Sequence, Tuple

from config import (
    FEATURE_BOUNDS,
    FEATURE_NAMES,
    LAYER1_CONFIG,
    ONNX_FEATURE_COUNT,
    Layer1SignalConfig,
)
from data_loader import OhlcvBar, resample_m1_to_timeframe


@dataclass
class VolumeProfileSnapshotPy:
    """Python mirror of MQL5 SVolumeProfileSnapshot."""

    vpoc: float
    vah: float
    val: float
    lvn_prices: List[float]
    total_volume: float
    is_valid: bool = True


@dataclass
class CandidateSetupPy:
    """Python mirror of MQL5 SSweepCandidateSetup + 12 Stationary Features."""

    setup_id: int
    m5_bar_index: int
    signal_time_utc: datetime
    direction: int                   # +1 = SIGNAL_LONG, -1 = SIGNAL_SHORT
    swept_pool_type: str
    swept_level_price: float
    sweep_extreme_price: float
    sweep_depth_usd: float
    rejection_wick_usd: float
    reclaim_candle_range_usd: float
    m1_bars_outside_level: int
    sweep_m5_tick_vol: float
    sma20_m5_tick_vol: float
    entry_limit_price: float
    stop_loss_price: float
    sl_distance_usd: float
    tp1_price: float
    tp2_price: float
    vpoc: float
    vah: float
    val: float
    spread_usd: float
    features: List[float]


def _safe_clamp(val: float, min_val: float, max_val: float, fallback: float) -> float:
    if math.isnan(val) or math.isinf(val):
        return fallback
    return max(min_val, min(max_val, val))


def compute_atr_series(bars: Sequence[OhlcvBar], period: int = 14) -> List[float]:
    """Computes MQL5-identical Simple/Wilder Average True Range (ATR) series."""
    n = len(bars)
    if n == 0:
        return []

    tr: List[float] = [0.0] * n
    for i, b in enumerate(bars):
        if i == 0:
            tr[i] = max(0.01, b.high - b.low)
        else:
            prev_c = bars[i - 1].close
            tr[i] = max(b.high - b.low, abs(b.high - prev_c), abs(b.low - prev_c))

    atr: List[float] = [0.0] * n
    running_sum = 0.0
    for i in range(n):
        running_sum += tr[i]
        if i >= period:
            running_sum -= tr[i - period]
            atr[i] = running_sum / float(period)
        else:
            atr[i] = running_sum / float(i + 1)
    return atr


def compute_adx_series(bars: Sequence[OhlcvBar], period: int = 14) -> List[float]:
    """Computes MQL5-compatible ADX(14) Main Line series in [0, 100]."""
    n = len(bars)
    if n < 2:
        return [25.0] * n

    plus_dm = [0.0] * n
    minus_dm = [0.0] * n
    tr = [0.0] * n

    for i in range(1, n):
        up_move = bars[i].high - bars[i - 1].high
        dn_move = bars[i - 1].low - bars[i].low
        plus_dm[i] = up_move if (up_move > dn_move and up_move > 0.0) else 0.0
        minus_dm[i] = dn_move if (dn_move > up_move and dn_move > 0.0) else 0.0
        tr[i] = max(
            bars[i].high - bars[i].low,
            abs(bars[i].high - bars[i - 1].close),
            abs(bars[i].low - bars[i - 1].close),
        )

    alpha = 2.0 / float(period + 1)
    dx_series = [25.0] * n
    adx_series = [25.0] * n

    sm_tr = max(0.01, tr[1])
    sm_pdm = plus_dm[1]
    sm_mdm = minus_dm[1]

    for i in range(1, n):
        sm_tr = (1.0 - alpha) * sm_tr + alpha * max(0.01, tr[i])
        sm_pdm = (1.0 - alpha) * sm_pdm + alpha * plus_dm[i]
        sm_mdm = (1.0 - alpha) * sm_mdm + alpha * minus_dm[i]

        pdi = 100.0 * (sm_pdm / sm_tr) if sm_tr > 1e-9 else 0.0
        mdi = 100.0 * (sm_mdm / sm_tr) if sm_tr > 1e-9 else 0.0
        denom = pdi + mdi
        dx_series[i] = (100.0 * abs(pdi - mdi) / denom) if denom > 1e-9 else 0.0
        adx_series[i] = (1.0 - alpha) * adx_series[i - 1] + alpha * dx_series[i]

    return adx_series


def compute_rolling_m5_hurst_exponent(
    m5_closes: Sequence[float],
    lags: Tuple[int, ...] = (2, 4, 8, 16, 32),
) -> float:
    """
    Exact bit-for-bit replication of `FeatureExtractor.mqh::ComputeRollingM5HurstExponent()`.
    Computes the 100-bar M5 Hurst Exponent H in [0.05, 0.95] via multi-lag log-price
    standard deviation scaling OLS regression.
    """
    window = len(m5_closes)
    if window < 40:
        return 0.50

    log_prices = [math.log(c) if c > 0.0 else 0.0 for c in m5_closes]
    log_lags: List[float] = []
    log_std_devs: List[float] = []

    for tau in lags:
        count = window - tau
        if count <= 2:
            continue

        diffs = [log_prices[i + tau] - log_prices[i] for i in range(count)]
        mean_diff = sum(diffs) / float(count)
        sum_sq = sum((d - mean_diff) ** 2 for d in diffs)
        std_dev = math.sqrt(sum_sq / float(count))
        if std_dev <= 1e-12:
            continue

        log_lags.append(math.log(float(tau)))
        log_std_devs.append(math.log(std_dev))

    if len(log_lags) < 3:
        return 0.50

    mean_x = sum(log_lags) / len(log_lags)
    mean_y = sum(log_std_devs) / len(log_std_devs)

    cov_xy = sum((x - mean_x) * (y - mean_y) for x, y in zip(log_lags, log_std_devs))
    var_x = sum((x - mean_x) ** 2 for x in log_lags)
    if var_x <= 1e-12:
        return 0.50

    hurst = cov_xy / var_x
    return _safe_clamp(hurst, 0.05, 0.95, 0.50)


def compute_intraday_volume_profile(
    day_m1_bars: Sequence[OhlcvBar],
    bin_size_usd: float = 0.25,
    value_area_pct: float = 0.70,
    lvn_threshold_ratio: float = 0.30,
) -> VolumeProfileSnapshotPy:
    """
    Exact replication of `VolumeProfile.mqh::Update()`.
    Discretizes the day's M1 bars from 00:00 UTC into $0.25 bins and computes
    VPOC, 70% Value Area [VAL, VAH], and external Low Volume Nodes (LVNs).
    """
    if len(day_m1_bars) < 3:
        return VolumeProfileSnapshotPy(2650.0, 2652.0, 2648.0, [], 0.0, is_valid=False)

    session_low = min(b.low for b in day_m1_bars if b.low > 0.0)
    session_high = max(b.high for b in day_m1_bars if b.high > 0.0)
    if session_high <= session_low:
        return VolumeProfileSnapshotPy(session_low, session_low + 1.0, session_low - 1.0, [], 0.0, is_valid=False)

    grid_low = math.floor(session_low / bin_size_usd) * bin_size_usd
    grid_high = math.ceil(session_high / bin_size_usd) * bin_size_usd
    num_bins = max(3, min(4096, int(round((grid_high - grid_low) / bin_size_usd)) + 1))

    bin_volumes = [0.0] * num_bins
    total_volume = 0.0

    for bar in day_m1_bars:
        vol = bar.effective_volume
        if vol <= 0.0:
            continue
        start_bin = int(math.floor((bar.low - grid_low + 1e-9) / bin_size_usd))
        end_bin = int(math.floor((bar.high - grid_low + 1e-9) / bin_size_usd))
        start_bin = max(0, min(num_bins - 1, start_bin))
        end_bin = max(start_bin, min(num_bins - 1, end_bin))

        touched = (end_bin - start_bin) + 1
        vol_per_bin = vol / float(touched)
        for b_idx in range(start_bin, end_bin + 1):
            bin_volumes[b_idx] += vol_per_bin
        total_volume += vol

    if total_volume <= 0.0:
        return VolumeProfileSnapshotPy(session_low, session_high, session_low, [], 0.0, is_valid=False)

    vpoc_idx = max(range(num_bins), key=lambda i: bin_volumes[i])
    vpoc_price = round(grid_low + (vpoc_idx + 0.5) * bin_size_usd, 2)

    target_va_vol = total_volume * value_area_pct
    accum_vol = bin_volumes[vpoc_idx]
    low_idx = vpoc_idx
    high_idx = vpoc_idx

    while accum_vol < target_va_vol and (low_idx > 0 or high_idx < num_bins - 1):
        next_up = bin_volumes[high_idx + 1] if high_idx < (num_bins - 1) else -1.0
        next_dn = bin_volumes[low_idx - 1] if low_idx > 0 else -1.0

        if next_up >= next_dn and high_idx < (num_bins - 1):
            high_idx += 1
            accum_vol += bin_volumes[high_idx]
        elif low_idx > 0:
            low_idx -= 1
            accum_vol += bin_volumes[low_idx]
        elif high_idx < (num_bins - 1):
            high_idx += 1
            accum_vol += bin_volumes[high_idx]
        else:
            break

    val_price = round(grid_low + low_idx * bin_size_usd, 2)
    vah_price = round(grid_low + (high_idx + 1) * bin_size_usd, 2)
    if val_price >= vpoc_price:
        val_price = round(vpoc_price - bin_size_usd, 2)
    if vah_price <= vpoc_price:
        vah_price = round(vpoc_price + bin_size_usd, 2)

    avg_bin_vol = total_volume / float(num_bins)
    lvn_cutoff = lvn_threshold_ratio * avg_bin_vol
    lvn_prices: List[float] = []

    for b_idx in range(1, num_bins - 1):
        if low_idx <= b_idx <= high_idx:
            continue
        v_prev = bin_volumes[b_idx - 1]
        v_curr = bin_volumes[b_idx]
        v_next = bin_volumes[b_idx + 1]
        if v_curr <= v_prev and v_curr <= v_next and (v_curr < v_prev or v_curr < v_next):
            if v_curr <= lvn_cutoff:
                lvn_prices.append(round(grid_low + (b_idx + 0.5) * bin_size_usd, 2))

    return VolumeProfileSnapshotPy(
        vpoc=vpoc_price,
        vah=vah_price,
        val=val_price,
        lvn_prices=lvn_prices,
        total_volume=total_volume,
        is_valid=True,
    )


def compute_stationary_12_features(
    sweep_depth_usd: float,
    rejection_wick_usd: float,
    candle_range_usd: float,
    m1_bars_outside_level: int,
    sweep_m5_tick_vol: float,
    sma20_m5_tick_vol: float,
    entry_price: float,
    session_vpoc: float,
    session_vah: float,
    session_val: float,
    atr_m15: float,
    atr_h1: float,
    atr_h4: float,
    adx_h1: float,
    hurst_m5_100: float,
    signal_time_utc: datetime,
    current_spread_usd: float,
    sl_distance_usd: float,
) -> List[float]:
    """
    Computes the exact 12 stationary normalized features in float32[1, 12] order
    matching `FeatureExtractor.mqh::ExtractFeatures()`.
    """
    atr_m15_safe = max(0.10, atr_m15)
    atr_h1_safe = max(0.20, atr_h1)
    atr_h4_safe = max(0.40, atr_h4)
    sl_safe = max(1.20, sl_distance_usd)

    f0 = _safe_clamp(sweep_depth_usd / atr_m15_safe, *FEATURE_BOUNDS["f0_sweep_depth_norm"])
    f1 = _safe_clamp(
        rejection_wick_usd / max(candle_range_usd, 0.01),
        *FEATURE_BOUNDS["f1_wick_body_ratio"],
    )
    f2 = _safe_clamp(
        float(m1_bars_outside_level) / 15.0,
        *FEATURE_BOUNDS["f2_bars_outside_level"],
    )
    f3 = _safe_clamp(
        sweep_m5_tick_vol / max(sma20_m5_tick_vol, 1.0),
        *FEATURE_BOUNDS["f3_rel_tick_volume"],
    )
    f4 = _safe_clamp(
        abs(entry_price - session_vpoc) / atr_m15_safe,
        *FEATURE_BOUNDS["f4_vpoc_distance_norm"],
    )
    va_width = max(0.25, session_vah - session_val)
    f5 = _safe_clamp(va_width / atr_h1_safe, *FEATURE_BOUNDS["f5_value_area_width_norm"])
    f6 = _safe_clamp(adx_h1 / 100.0, *FEATURE_BOUNDS["f6_h1_adx"])
    f7 = _safe_clamp(hurst_m5_100, *FEATURE_BOUNDS["f7_hurst_exponent"])
    f8 = _safe_clamp(atr_m15_safe / atr_h4_safe, *FEATURE_BOUNDS["f8_volatility_ratio"])

    utc_hour_continuous = float(signal_time_utc.hour) + (float(signal_time_utc.minute) / 60.0)
    angle_rad = 2.0 * math.pi * utc_hour_continuous / 24.0
    f9 = _safe_clamp(math.sin(angle_rad), *FEATURE_BOUNDS["f9_hour_sin"])
    f10 = _safe_clamp(math.cos(angle_rad), *FEATURE_BOUNDS["f10_hour_cos"])
    f11 = _safe_clamp(
        max(0.01, current_spread_usd) / sl_safe,
        *FEATURE_BOUNDS["f11_spread_to_sl_ratio"],
    )

    vector = [f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11]
    assert len(vector) == ONNX_FEATURE_COUNT
    return [float(np_f32) for np_f32 in vector]


def scan_layer1_candidate_setups(
    m1_bars: Sequence[OhlcvBar],
    cfg: Layer1SignalConfig = LAYER1_CONFIG,
) -> Tuple[List[CandidateSetupPy], List[OhlcvBar]]:
    """
    Replicates MQL5 Layer 1 (SessionLevels + VolumeProfile + SweepSignalEngine)
    across a historical M1 bar series to extract candidate setups and their
    exact 12 stationary features.
    """
    m5_bars = resample_m1_to_timeframe(m1_bars, 5)
    m15_bars = resample_m1_to_timeframe(m1_bars, 15)
    h1_bars = resample_m1_to_timeframe(m1_bars, 60)
    h4_bars = resample_m1_to_timeframe(m1_bars, 240)
    d1_bars = resample_m1_to_timeframe(m1_bars, 1440)

    atr_m5 = compute_atr_series(m5_bars, 14)
    atr_m15 = compute_atr_series(m15_bars, 14)
    atr_h1 = compute_atr_series(h1_bars, 14)
    atr_h4 = compute_atr_series(h4_bars, 14)
    adx_h1 = compute_adx_series(h1_bars, 14)

    # Index M1 bars by UTC date for fast intraday Volume Profile & Asian range slices
    m1_by_day: Dict[datetime, List[OhlcvBar]] = {}
    for b in m1_bars:
        day_key = b.timestamp_utc.replace(hour=0, minute=0, second=0, microsecond=0)
        m1_by_day.setdefault(day_key, []).append(b)

    # Pre-indexPDH/PDL by day
    d1_by_day: Dict[datetime, OhlcvBar] = {
        b.timestamp_utc.replace(hour=0, minute=0, second=0, microsecond=0): b for b in d1_bars
    }
    sorted_days = sorted(d1_by_day.keys())

    candidates: List[CandidateSetupPy] = []
    setup_seq = 0
    last_signal_bar_idx = -10

    for idx in range(105, len(m5_bars) - 50):
        if idx - last_signal_bar_idx < 6:
            continue

        bar = m5_bars[idx]
        ts = bar.timestamp_utc
        min_of_day = ts.hour * 60 + ts.minute

        # Check active Killzone (London 07:00-10:30 UTC or NY 12:30-16:00 UTC)
        in_london_kz = cfg.london_kz_start_minutes_utc <= min_of_day <= cfg.london_kz_end_minutes_utc
        in_ny_kz = cfg.ny_kz_start_minutes_utc <= min_of_day <= cfg.ny_kz_end_minutes_utc
        if not (in_london_kz or in_ny_kz):
            continue

        day_key = ts.replace(hour=0, minute=0, second=0, microsecond=0)
        day_m1 = [b for b in m1_by_day.get(day_key, []) if b.timestamp_utc <= ts]
        if len(day_m1) < 60:
            continue

        # Asian range (00:00 - 07:00 UTC)
        asian_m1 = [b for b in day_m1 if b.timestamp_utc.hour < cfg.asian_end_hour_utc]
        if not asian_m1:
            continue
        asian_high = max(b.high for b in asian_m1)
        asian_low = min(b.low for b in asian_m1)

        # Previous Day High / Low
        day_pos = sorted_days.index(day_key) if day_key in sorted_days else -1
        pdh = d1_by_day[sorted_days[day_pos - 1]].high if day_pos > 0 else asian_high + 5.0
        pdl = d1_by_day[sorted_days[day_pos - 1]].low if day_pos > 0 else asian_low - 5.0

        # Resolve current multi-timeframe ATR & ADX values
        m15_idx = min(len(m15_bars) - 1, idx // 3)
        h1_idx = min(len(h1_bars) - 1, idx // 12)
        h4_idx = min(len(h4_bars) - 1, idx // 48)

        cur_atr_m5 = max(0.50, atr_m5[idx])
        cur_atr_m15 = max(1.00, atr_m15[m15_idx])
        cur_atr_h1 = max(2.00, atr_h1[h1_idx])
        cur_atr_h4 = max(4.00, atr_h4[h4_idx])
        cur_adx_h1 = adx_h1[h1_idx]

        # Rolling Intraday M1 Volume Profile up to current bar
        vp = compute_intraday_volume_profile(
            day_m1,
            bin_size_usd=cfg.vp_bin_size_usd,
            value_area_pct=cfg.vp_value_area_pct,
            lvn_threshold_ratio=cfg.vp_lvn_threshold_ratio,
        )
        if not vp.is_valid:
            continue

        # 20-bar M5 Tick Volume SMA
        vol_window = [m5_bars[k].tick_volume for k in range(idx - 20, idx)]
        sma20_vol = max(1.0, sum(vol_window) / len(vol_window))

        # Inspect 3-bar window [idx-2, idx-1, idx] for Sweep + Absorption + Reclaim
        window_bars = m5_bars[idx - 2 : idx + 1]
        win_low = min(b.low for b in window_bars)
        win_high = max(b.high for b in window_bars)
        max_vol = max(b.tick_volume for b in window_bars)

        if max_vol < cfg.min_absorption_rel_vol * sma20_vol:
            continue

        min_pierce = cfg.min_sweep_atr_m15_ratio * cur_atr_m15
        max_pierce = cfg.max_sweep_atr_m15_ratio * cur_atr_m15

        direction = 0
        swept_type = "LIQ_NONE"
        swept_level = 0.0
        extreme_px = 0.0
        sweep_depth = 0.0

        # Check Bullish Sweep of Asian Low, PDL, or VAL
        for p_type, lvl in (("ASIAN_LOW", asian_low), ("PDL", pdl), ("EXTERNAL_LVN_LOW", vp.val)):
            pierce = lvl - win_low
            if min_pierce <= pierce <= max_pierce and bar.close > lvl:
                direction = 1
                swept_type = p_type
                swept_level = lvl
                extreme_px = win_low
                sweep_depth = pierce
                break

        # Check Bearish Sweep of Asian High, PDH, or VAH
        if direction == 0:
            for p_type, lvl in (("ASIAN_HIGH", asian_high), ("PDH", pdh), ("EXTERNAL_LVN_HIGH", vp.vah)):
                pierce = win_high - lvl
                if min_pierce <= pierce <= max_pierce and bar.close < lvl:
                    direction = -1
                    swept_type = p_type
                    swept_level = lvl
                    extreme_px = win_high
                    sweep_depth = pierce
                    break

        if direction == 0:
            continue

        # Compute Structural SL and Sniper Entry Price
        sl_buffer = cfg.sl_fixed_buffer_usd + cfg.sl_atr_m5_multiplier * cur_atr_m5
        if direction == 1:
            structural_sl = round(extreme_px - sl_buffer, 2)
            entry_px = round(max(swept_level, min(bar.close, structural_sl + 2.20)), 2)
            sl_dist = round(entry_px - structural_sl, 2)
        else:
            structural_sl = round(extreme_px + sl_buffer, 2)
            entry_px = round(min(swept_level, max(bar.close, structural_sl - 2.20)), 2)
            sl_dist = round(structural_sl - entry_px, 2)

        if sl_dist < cfg.hard_min_sl_usd or sl_dist > cfg.hard_max_sl_usd:
            continue

        # TP1 @ Session VPOC (if >= 1.5R) else 2.0R; TP2 @ Opposing Liquidity or 3.5R
        if direction == 1:
            vpoc_dist = vp.vpoc - entry_px
            tp1_px = round(vp.vpoc if vpoc_dist >= 1.5 * sl_dist else entry_px + 2.0 * sl_dist, 2)
            tp2_px = round(max(asian_high, entry_px + 3.5 * sl_dist), 2)
            rej_wick = max(0.05, min(bar.open, bar.close) - win_low)
        else:
            vpoc_dist = entry_px - vp.vpoc
            tp1_px = round(vp.vpoc if vpoc_dist >= 1.5 * sl_dist else entry_px - 2.0 * sl_dist, 2)
            tp2_px = round(min(asian_low, entry_px - 3.5 * sl_dist), 2)
            rej_wick = max(0.05, win_high - max(bar.open, bar.close))

        candle_rng = max(0.01, win_high - win_low)
        recent_m1 = day_m1[-15:]
        if direction == 1:
            m1_outside = max(1, sum(1 for b in recent_m1 if b.low < swept_level))
        else:
            m1_outside = max(1, sum(1 for b in recent_m1 if b.high > swept_level))

        hurst_100 = compute_rolling_m5_hurst_exponent(
            [m5_bars[k].close for k in range(idx - 99, idx + 1)],
            lags=cfg.hurst_lags,
        )

        feats = compute_stationary_12_features(
            sweep_depth_usd=sweep_depth,
            rejection_wick_usd=rej_wick,
            candle_range_usd=candle_rng,
            m1_bars_outside_level=m1_outside,
            sweep_m5_tick_vol=max_vol,
            sma20_m5_tick_vol=sma20_vol,
            entry_price=entry_px,
            session_vpoc=vp.vpoc,
            session_vah=vp.vah,
            session_val=vp.val,
            atr_m15=cur_atr_m15,
            atr_h1=cur_atr_h1,
            atr_h4=cur_atr_h4,
            adx_h1=cur_adx_h1,
            hurst_m5_100=hurst_100,
            signal_time_utc=ts,
            current_spread_usd=bar.spread_usd,
            sl_distance_usd=sl_dist,
        )

        setup_seq += 1
        last_signal_bar_idx = idx
        candidates.append(
            CandidateSetupPy(
                setup_id=int(ts.timestamp()) * 100 + (setup_seq % 100),
                m5_bar_index=idx,
                signal_time_utc=ts,
                direction=direction,
                swept_pool_type=swept_type,
                swept_level_price=round(swept_level, 2),
                sweep_extreme_price=round(extreme_px, 2),
                sweep_depth_usd=round(sweep_depth, 3),
                rejection_wick_usd=round(rej_wick, 3),
                reclaim_candle_range_usd=round(candle_rng, 3),
                m1_bars_outside_level=m1_outside,
                sweep_m5_tick_vol=max_vol,
                sma20_m5_tick_vol=round(sma20_vol, 2),
                entry_limit_price=entry_px,
                stop_loss_price=structural_sl,
                sl_distance_usd=sl_dist,
                tp1_price=tp1_px,
                tp2_price=tp2_px,
                vpoc=vp.vpoc,
                vah=vp.vah,
                val=vp.val,
                spread_usd=bar.spread_usd,
                features=feats,
            )
        )

    return candidates, m5_bars
