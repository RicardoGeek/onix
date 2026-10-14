"""
data_loader.py
==============
Loads exported MetaTrader 5 M1 / M5 bar & tick-volume datasets (CSV or Parquet)
and Strategy Tester setup telemetry logs (`xauusd_setup_telemetry.csv`).
Also provides a deterministic XAUUSD intraday M1/M5 market microstructure
generator so the pipeline can be validated and trained before live MT5 exports.
"""

from __future__ import annotations

import csv
import math
import random
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple, Union

from config import (
    DEFAULT_M1_BARS_CSV,
    DEFAULT_M5_BARS_CSV,
    DEFAULT_SETUP_TELEMETRY_CSV,
    FEATURE_NAMES,
)


@dataclass
class OhlcvBar:
    """Normalized OHLCV + Spread bar representation for XAUUSD."""

    timestamp_utc: datetime
    open: float
    high: float
    low: float
    close: float
    tick_volume: float
    real_volume: float = 0.0
    spread_usd: float = 0.20

    @property
    def effective_volume(self) -> float:
        return self.real_volume if self.real_volume > 0.0 else max(1.0, self.tick_volume)


@dataclass
class SetupTelemetryRecord:
    """Parsed setup telemetry record exported by Logger.mqh::WriteSetupTelemetryCSV."""

    setup_id: int
    timestamp_utc: datetime
    symbol: str
    direction: int
    swept_pool_type: str
    swept_level_price: float
    sweep_extreme_price: float
    entry_limit_price: float
    stop_loss_price: float
    sl_distance_usd: float
    tp1_price: float
    tp2_price: float
    vpoc: float
    vah: float
    val: float
    features: List[float]
    onnx_prob: float
    risk_tier: int
    event_stage: str
    realized_pnl_usd: float
    realized_r_multiple: float
    mfe_r: float
    mae_r: float
    label_2_5r: int


def _parse_mt5_datetime(raw_date: str, raw_time: str = "") -> datetime:
    """Parse MetaTrader 5 timestamp formats ('YYYY.MM.DD HH:MM:SS' or ISO-8601) into UTC."""
    combined = f"{raw_date.strip()} {raw_time.strip()}".strip()
    for fmt in (
        "%Y.%m.%d %H:%M:%S",
        "%Y.%m.%d %H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%dT%H:%M:%S",
        "%Y.%m.%d",
        "%Y-%m-%d",
    ):
        try:
            dt = datetime.strptime(combined, fmt)
            return dt.replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    raise ValueError(f"Unrecognized MT5 timestamp format: '{combined}'")


def load_mt5_bars(
    file_path: Union[str, Path],
    broker_gmt_offset_hours: int = 0,
    point_size: float = 0.01,
) -> List[OhlcvBar]:
    """
    Loads MT5 exported bar data from CSV or Parquet.
    Supports both standard MT5 tab/comma exports (<DATE>, <TIME>, <OPEN>, ...)
    and normalized OHLCV tables.
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"MT5 bar file not found: {path}")

    # Support Parquet if pandas/pyarrow is available in the environment
    if path.suffix.lower() in (".parquet", ".pq"):
        try:
            import pandas as pd  # type: ignore

            df = pd.read_parquet(path)
            bars: List[OhlcvBar] = []
            offset_delta = timedelta(hours=broker_gmt_offset_hours)
            for row in df.to_dict(orient="records"):
                ts_raw = row.get("timestamp_utc") or row.get("time") or row.get("datetime")
                if isinstance(ts_raw, datetime):
                    ts = ts_raw if ts_raw.tzinfo else ts_raw.replace(tzinfo=timezone.utc)
                else:
                    ts = _parse_mt5_datetime(str(ts_raw)) - offset_delta

                spread_raw = float(row.get("spread_usd", row.get("spread", 20.0)))
                spread_usd = spread_raw * point_size if spread_raw > 2.0 else spread_raw
                bars.append(
                    OhlcvBar(
                        timestamp_utc=ts,
                        open=float(row["open"]),
                        high=float(row["high"]),
                        low=float(row["low"]),
                        close=float(row["close"]),
                        tick_volume=float(row.get("tick_volume", row.get("tickvol", 100.0))),
                        real_volume=float(row.get("real_volume", row.get("vol", 0.0))),
                        spread_usd=max(0.05, spread_usd),
                    )
                )
            bars.sort(key=lambda b: b.timestamp_utc)
            return bars
        except ImportError as exc:
            raise RuntimeError("Reading Parquet requires pandas and pyarrow.") from exc

    # Standard CSV / TSV parsing (works with zero external dependencies)
    bars = []
    offset_delta = timedelta(hours=broker_gmt_offset_hours)

    with path.open("r", encoding="utf-8-sig", newline="") as f:
        sample = f.read(4096)
        f.seek(0)
        delimiter = "\t" if "\t" in sample and sample.count("\t") >= sample.count(",") else ","
        reader = csv.DictReader(f, delimiter=delimiter)

        for raw_row in reader:
            row = {k.strip("<> ").lower(): (v.strip() if v else "") for k, v in raw_row.items() if k}
            if not row:
                continue

            if "date" in row and "time" in row:
                ts = _parse_mt5_datetime(row["date"], row["time"]) - offset_delta
            elif "timestamp_utc" in row:
                ts = _parse_mt5_datetime(row["timestamp_utc"])
            elif "datetime" in row or "time" in row:
                ts = _parse_mt5_datetime(row.get("datetime") or row.get("time", "")) - offset_delta
            else:
                continue

            open_px = float(row.get("open", 0.0))
            high_px = float(row.get("high", 0.0))
            low_px = float(row.get("low", 0.0))
            close_px = float(row.get("close", 0.0))
            tick_vol = float(row.get("tickvol") or row.get("tick_volume") or row.get("volume") or 1.0)
            real_vol = float(row.get("vol") or row.get("real_volume") or 0.0)
            spread_val = float(row.get("spread_usd") or row.get("spread") or 20.0)
            spread_usd = spread_val * point_size if spread_val > 2.0 else spread_val

            if high_px <= 0.0 or low_px <= 0.0:
                continue

            bars.append(
                OhlcvBar(
                    timestamp_utc=ts,
                    open=open_px,
                    high=high_px,
                    low=low_px,
                    close=close_px,
                    tick_volume=max(1.0, tick_vol),
                    real_volume=max(0.0, real_vol),
                    spread_usd=max(0.05, spread_usd),
                )
            )

    bars.sort(key=lambda b: b.timestamp_utc)
    return bars


def load_setup_telemetry_csv(
    csv_path: Union[str, Path] = DEFAULT_SETUP_TELEMETRY_CSV,
    only_closed_positions: bool = False,
) -> List[SetupTelemetryRecord]:
    """
    Loads historical candidate setups and their 12 stationary features logged by
    MQL5 Logger.mqh::WriteSetupTelemetryCSV.
    """
    path = Path(csv_path)
    if not path.exists():
        return []

    records: List[SetupTelemetryRecord] = []
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stage = row.get("event_stage", "SIGNAL_TRIGGERED").strip()
            if only_closed_positions and stage != "POSITION_CLOSED":
                continue

            feats = [float(row[name]) for name in FEATURE_NAMES]
            records.append(
                SetupTelemetryRecord(
                    setup_id=int(row["setup_id"]),
                    timestamp_utc=_parse_mt5_datetime(row["timestamp_utc"]),
                    symbol=row.get("symbol", "XAUUSD"),
                    direction=int(row["direction"]),
                    swept_pool_type=row.get("swept_pool_type", "LIQ_NONE"),
                    swept_level_price=float(row["swept_level_price"]),
                    sweep_extreme_price=float(row["sweep_extreme_price"]),
                    entry_limit_price=float(row["entry_limit_price"]),
                    stop_loss_price=float(row["stop_loss_price"]),
                    sl_distance_usd=float(row["sl_distance_usd"]),
                    tp1_price=float(row["tp1_price"]),
                    tp2_price=float(row["tp2_price"]),
                    vpoc=float(row["vpoc"]),
                    vah=float(row["vah"]),
                    val=float(row["val"]),
                    features=feats,
                    onnx_prob=float(row.get("onnx_prob", 0.5)),
                    risk_tier=int(row.get("risk_tier", 0)),
                    event_stage=stage,
                    realized_pnl_usd=float(row.get("realized_pnl_usd", 0.0)),
                    realized_r_multiple=float(row.get("realized_r_multiple", 0.0)),
                    mfe_r=float(row.get("mfe_r", 0.0)),
                    mae_r=float(row.get("mae_r", 0.0)),
                    label_2_5r=int(row.get("label_2_5r", -1)),
                )
            )

    records.sort(key=lambda r: r.timestamp_utc)
    return records


def resample_m1_to_timeframe(m1_bars: Sequence[OhlcvBar], timeframe_minutes: int) -> List[OhlcvBar]:
    """Deterministically aggregates M1 bars into M5, M15, H1, H4, or D1 bars."""
    if not m1_bars:
        return []

    aggregated: List[OhlcvBar] = []
    bucket_seconds = timeframe_minutes * 60

    current_bucket_ts: Optional[datetime] = None
    b_open = b_high = b_low = b_close = 0.0
    b_tvol = b_rvol = b_spread_sum = 0.0
    b_count = 0

    for bar in m1_bars:
        epoch = int(bar.timestamp_utc.timestamp())
        aligned_epoch = (epoch // bucket_seconds) * bucket_seconds
        bucket_ts = datetime.fromtimestamp(aligned_epoch, tz=timezone.utc)

        if current_bucket_ts is None:
            current_bucket_ts = bucket_ts
            b_open = bar.open
            b_high = bar.high
            b_low = bar.low
            b_close = bar.close
            b_tvol = bar.tick_volume
            b_rvol = bar.real_volume
            b_spread_sum = bar.spread_usd
            b_count = 1
        elif bucket_ts == current_bucket_ts:
            if bar.high > b_high:
                b_high = bar.high
            if bar.low < b_low:
                b_low = bar.low
            b_close = bar.close
            b_tvol += bar.tick_volume
            b_rvol += bar.real_volume
            b_spread_sum += bar.spread_usd
            b_count += 1
        else:
            aggregated.append(
                OhlcvBar(
                    timestamp_utc=current_bucket_ts,
                    open=round(b_open, 2),
                    high=round(b_high, 2),
                    low=round(b_low, 2),
                    close=round(b_close, 2),
                    tick_volume=b_tvol,
                    real_volume=b_rvol,
                    spread_usd=round(b_spread_sum / max(1, b_count), 3),
                )
            )
            current_bucket_ts = bucket_ts
            b_open = bar.open
            b_high = bar.high
            b_low = bar.low
            b_close = bar.close
            b_tvol = bar.tick_volume
            b_rvol = bar.real_volume
            b_spread_sum = bar.spread_usd
            b_count = 1

    if current_bucket_ts is not None and b_count > 0:
        aggregated.append(
            OhlcvBar(
                timestamp_utc=current_bucket_ts,
                open=round(b_open, 2),
                high=round(b_high, 2),
                low=round(b_low, 2),
                close=round(b_close, 2),
                tick_volume=b_tvol,
                real_volume=b_rvol,
                spread_usd=round(b_spread_sum / max(1, b_count), 3),
            )
        )

    return aggregated


def generate_synthetic_xauusd_m1_series(
    trading_days: int = 35,
    start_price: float = 2650.00,
    seed: int = 42,
) -> List[OhlcvBar]:
    """
    Generates a realistic XAUUSD M1 bar series exhibiting Asian range accumulation
    (00:00-07:00 UTC) and London/NY Killzone liquidity sweeps followed by mean-reversion
    reclaims or trend continuation. Used for verification & initial walk-forward testing
    when live MT5 CSV exports are not yet present.
    """
    rng = random.Random(seed)
    m1_bars: List[OhlcvBar] = []
    current_dt = datetime(2026, 1, 5, 0, 0, 0, tzinfo=timezone.utc)
    price = start_price

    for day in range(trading_days):
        day_start = current_dt + timedelta(days=day)
        if day_start.weekday() >= 5:
            continue  # Skip weekends

        asian_center = price + rng.uniform(-4.0, 4.0)
        asian_half_range = rng.uniform(3.5, 6.5)
        asian_high = asian_center + asian_half_range
        asian_low = asian_center - asian_half_range

        # Choose London & NY sweep regimes for this day
        london_bull_sweep = rng.random() < 0.52
        london_reverts = rng.random() < 0.65
        ny_bull_sweep = rng.random() < 0.48
        ny_reverts = rng.random() < 0.62

        for minute_of_day in range(1440):
            ts = day_start + timedelta(minutes=minute_of_day)
            hour_utc = minute_of_day / 60.0

            # Base volatility and tick volume by session
            if 0.0 <= hour_utc < 7.0:
                # Asian Range accumulation around asian_center
                pull = (asian_center - price) * 0.08
                sigma = 0.22
                base_vol = rng.uniform(45.0, 95.0)
                spread = rng.uniform(0.16, 0.24)
            elif 7.0 <= hour_utc <= 10.5:
                # London Killzone: engineer a sweep around 07:35 - 08:00 UTC
                sigma = 0.42
                base_vol = rng.uniform(110.0, 210.0)
                spread = rng.uniform(0.14, 0.22)
                if 455 <= minute_of_day <= 470:
                    target = (asian_low - 1.40) if london_bull_sweep else (asian_high + 1.40)
                    pull = (target - price) * 0.35
                    base_vol *= 2.1
                elif 471 <= minute_of_day <= 485:
                    if london_reverts:
                        target = asian_center + (2.5 if london_bull_sweep else -2.5)
                        pull = (target - price) * 0.30
                        base_vol *= 2.4
                    else:
                        target = (asian_low - 5.0) if london_bull_sweep else (asian_high + 5.0)
                        pull = (target - price) * 0.20
                elif 486 <= minute_of_day <= 600 and london_reverts:
                    target = (asian_high + 2.0) if london_bull_sweep else (asian_low - 2.0)
                    pull = (target - price) * 0.06
                else:
                    pull = (asian_center - price) * 0.03
            elif 12.5 <= hour_utc <= 16.0:
                # New York Killzone: engineer a sweep around 13:10 - 13:25 UTC
                sigma = 0.48
                base_vol = rng.uniform(130.0, 250.0)
                spread = rng.uniform(0.15, 0.25)
                if 790 <= minute_of_day <= 804:
                    target = (asian_low - 1.60) if ny_bull_sweep else (asian_high + 1.60)
                    pull = (target - price) * 0.35
                    base_vol *= 2.2
                elif 805 <= minute_of_day <= 820:
                    if ny_reverts:
                        target = asian_center + (3.0 if ny_bull_sweep else -3.0)
                        pull = (target - price) * 0.32
                        base_vol *= 2.5
                    else:
                        target = (asian_low - 6.0) if ny_bull_sweep else (asian_high + 6.0)
                        pull = (target - price) * 0.22
                elif 821 <= minute_of_day <= 950 and ny_reverts:
                    target = (asian_high + 3.0) if ny_bull_sweep else (asian_low - 3.0)
                    pull = (target - price) * 0.06
                else:
                    pull = 0.0
            else:
                sigma = 0.25
                base_vol = rng.uniform(40.0, 85.0)
                spread = rng.uniform(0.22, 0.45) if (20.9 <= hour_utc <= 22.2) else rng.uniform(0.18, 0.26)
                pull = (asian_center - price) * 0.02

            open_px = price
            delta = pull + rng.gauss(0.0, sigma)
            close_px = max(1800.0, open_px + delta)

            wick_up = abs(rng.gauss(0.0, sigma * 0.85))
            wick_dn = abs(rng.gauss(0.0, sigma * 0.85))
            if minute_of_day in (470, 471, 804, 805):
                # Pronounced institutional rejection wick on sweep/reclaim bars
                if (minute_of_day in (470, 471) and london_bull_sweep) or (
                    minute_of_day in (804, 805) and ny_bull_sweep
                ):
                    wick_dn += rng.uniform(0.80, 1.60)
                else:
                    wick_up += rng.uniform(0.80, 1.60)

            high_px = max(open_px, close_px) + wick_up
            low_px = min(open_px, close_px) - wick_dn
            price = close_px

            m1_bars.append(
                OhlcvBar(
                    timestamp_utc=ts,
                    open=round(open_px, 2),
                    high=round(high_px, 2),
                    low=round(low_px, 2),
                    close=round(close_px, 2),
                    tick_volume=round(base_vol, 0),
                    real_volume=0.0,
                    spread_usd=round(spread, 3),
                )
            )

    return m1_bars
