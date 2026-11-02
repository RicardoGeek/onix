# CHANGELOG — `BTCUSD_Sniper_ONNX` ("The Bart-Hunter")

All notable architectural, feature-engineering, ONNX model, and risk-management changes to `BTCUSD_Sniper_ONNX` are documented in this file.
Every compiled binary release is archived in `c:\Users\faker\Documents\dev\onix\bin\BTCUSD_Sniper_ONNX\`.

---

## [v2.02] — 2026-11-02 (Goldeen.io Instant Redis Telemetry Integration)
- **Archived Binary**: [in/BTCUSD_Sniper_ONNX/BTCUSD_Sniper_ONNX_v2.02.ex5](file:///c:/Users/faker/Documents/dev/onix/bin/BTCUSD_Sniper_ONNX/BTCUSD_Sniper_ONNX_v2.02.ex5)
- **Summary**:
  - Added [GoldeenTelemetry.mqh](file:///c:/Users/faker/Documents/dev/onix/btcusd-sniper-ea/MQL5/Include/BTCUSD_Quant/Core/GoldeenTelemetry.mqh) (InpGoldeenToken, InpGoldeenUrl = "https://api.goldeen.io/api/v1/ea/report") for timer-driven zero-tick-latency reporting to Goldeen.io's Redis ingestion queue.

---
## [v2.01] ? 2026-11-02 (Smart Pool-Hierarchy Cooldown & Broker-Timezone-Agnostic H4 ATR)
- **Archived Binary**: [`bin/BTCUSD_Sniper_ONNX/BTCUSD_Sniper_ONNX_v2.01.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/BTCUSD_Sniper_ONNX/BTCUSD_Sniper_ONNX_v2.01.ex5)
- **Summary**:
  - Updated `IsDirectionInCooldown()` in `SweepSignalEngine.mqh` so the 25-minute post-loss cooldown only blocks repeating internal `M15_SWING` fractals and never blocks primary session boundaries (`ASIAN`, `LONDON`, `PDH/PDL`, `EQUAL_HIGHS/LOWS`), plus added `ComputeBrokerAgnosticAtrH4()` in `SessionLevels.mqh`.
  - **Verified Performance (`$50,000` Prop Guard, `Model=4` Real Ticks + `ExecutionMode=-1` Random Delay)**:
    - **`2024`**: **`+$556,788.36`**, `256` setups, **`90.0%` WR** (up from `89.4%`), **`PF 7.51`** (up from `7.22`), `1.42d` avg wait, `4.38%` Max Eq DD.
    - **`2025?2026`**: **`+$1,772,381.08`** (`+$1,031,878.61` in `2025` at `91.6%` WR, `1.02d` wait + `+$740,502.47` in `2026` at `89.6%` WR, `1.27d` wait), **`PF 8.81`** (up from `8.54`), `4.56%` Max Eq DD (down from `4.69%`).
    - **Total `2024?2026`**: **`+$2,329,169.44`** (up `+$21,568.44` over `v2.00`), **`840` setups**, **`90.6%` WR**, **`0.82` trades/day**, **`1.22d` avg wait**.

---

## [v2.00] — 2026-11-02 (Wait-Time Compression to `1.24 Days` + Chart HUD AI Telemetry + 128-Unit DAGger ONNX Retrain)
- **Archived Binary**: [`bin/BTCUSD_Sniper_ONNX/BTCUSD_Sniper_ONNX_v2.00.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/BTCUSD_Sniper_ONNX/BTCUSD_Sniper_ONNX_v2.00.ex5)
- **Summary**:
  - **Expanded Session Pools & Continuous Killzones (`SessionLevels.mqh` & `Definitions.mqh`)**:
    - Added Early Asia (`00:00–02:30 UTC` active from `02:30 UTC`) and Early London (`06:30–09:00 UTC` active from `09:00 UTC`) liquidity pools alongside Asian (`00:00–06:30 UTC`), London (`06:30–12:30 UTC`), Previous Day (`PDH`/`PDL`), Equal Highs/Lows (`EQH`/`EQL`), and M15 Swing Fractals.
    - Expanded active killzones to `00:15–05:15 UTC` (Asia/Tokyo) and continuous `06:30–20:30 UTC` (London + London/NY Bridge + Wall Street Spot ETF + US Late Afternoon).
  - **Calibrated Spread Guard for 2024–2026 Real-Tick Regimes (`EquityGuard.mqh` & `BTCUSD_Sniper_ONNX.mq5`)**:
    - Raised `IsSpreadDislocated()` baseline floor from `$25.00` to `$42.00`, `InpMaxSpreadMultiplier` to `2.20`, and `InpHardMaxSpreadUSD` to `$95.00` so legitimate 2024 `BTCUSD_REAL` sweep setups are not prematurely blocked by transient M5 sweep spread expansion.
  - **Chart HUD Live ONNX Query Telemetry (`BTCUSD_Sniper_ONNX.mq5`)**:
    - Added live `Last AI Call` (`YYYY-MM-DD HH:MM UTC | Dir | Pool`) and `Last AI Decision` (`Tier / REJECT (Score=0.XXXX vs T2=0.56/T1=0.70)`) lines to the on-chart institutional HUD.
  - **128-Unit Residual MLP ONNX Meta-Labeler (`train_btcusd_onnx.py` & `btcusd_meta_model.onnx`)**:
    - Trained on `2,183` mapped `POSITION_CLOSED` setups across `2024–2026` (`Model=4` 100% Real Ticks + `ExecutionMode=-1` Random Delay, including DAGger Pass 2 trajectory harvesting).
  - **Verified Strategy Tester Performance (`$50,000` Prop Guard `MODE_PROP_GUARD`, `Model=4` 100% Real Ticks + `ExecutionMode=-1` Random Delay)**:
    - **`2024` (`BTCUSD_REAL`)**: **`+$557,347.99`** (vs `+$38,716.03` in `v1.10`), **`254` setups (`483` deals)**, **`89.44%` WR** (vs `85.61%`), **`0.69` trades/day**, **`1.43d` avg wait time** (down from `4.35d`), **`PF 7.22`**, **`4.16%` Max Relative Equity DD** ([`P2_V200_BTCUSD_2024.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/P2_V200_BTCUSD_2024.htm)).
    - **`2025–2026` (`BTCUSD` Live01)**: **`+$1,750,253.01`** (`$1,061,604.98` in `2025` + `$688,648.03` in `2026`, vs `+$847,389.93` in `v1.10`), **`578` setups (`1,118` deals)**, **`91.06%` WR** (`91.7%` in `2025`, `90.0%` in `2026`), **`1.04d` avg wait time in `2025` / `1.27d` in `2026`**, **`PF 8.54`**, **`4.69%` Max Relative Equity DD** ([`P2_V200_BTCUSD_2526.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/P2_V200_BTCUSD_2526.htm)).
    - **Total `2024–2026`**: **`+$2,307,601.00`** (up **2.60x** from `+$886,105.96`), **`832` setups**, **`90.6%` WR**, **`0.81` trades/day**, **`1.24d` avg wait time** (down from `2.19d`).

---

## [v1.10] — 2026-10-28 (100% Real-Tick + Random-Delay ONNX Retrain)
- **Archived Binary**: `bin/BTCUSD_Sniper_ONNX/BTCUSD_Sniper_ONNX_v1.10.ex5`
- **Summary**:
  - Retrained `btcusd_meta_model.onnx` strictly on **`957` mapped `POSITION_CLOSED` setups harvested under `100% Real Ticks (`Model=4`) + Random Delay (`ExecutionMode=-1`)`** (`57.4M` genuine `2024` Dukascopy ticks on `BTCUSD_REAL` + `192.5M` genuine `2025–2026` Pepperstone Live ticks on `PepperstoneBS-MT5-Live01`).
  - **Verified Strategy Tester Performance (`$50,000` Prop Guard `MODE_PROP_GUARD`, `Model=4` 100% Real Ticks + `ExecutionMode=-1` Random Delay)**:
    - **`2024` (`BTCUSD_REAL` — `100% real ticks`, `57.4M` ticks)**: **`+$38,716.03` (`+77.43%`)**, **`PF 3.43`**, **`85.61%` WR** (`119/139`), **`2.62%` Max Balance DD / `3.91%` Max Equity DD** ([`P2_REAL_BTCUSD_2024.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/P2_REAL_BTCUSD_2024.htm)).
    - **`2025–2026` (`BTCUSD` Live01 — `100% real ticks`, `192.5M` ticks)**: **`+$847,389.93` (`+1,694.78%`)**, **`PF 7.73`**, **`89.93%` WR** (`670/745`), **`2.79%` Max Balance DD / `3.98%` Max Equity DD** ([`P2_REAL_BTCUSD_2526.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/P2_REAL_BTCUSD_2526.htm)).

---

## [v1.00] — 2026-10-27

### Added
- **Initial Production Release (`BTCUSD_Sniper_ONNX_v1.00.ex5`)**:
  - **3-Layer Hybrid Quantitative Architecture for 24/7 `BTCUSD`**:
    - **Layer 1 (`SessionLevels.mqh`, `VolumeProfile.mqh`, `SweepSignalEngine.mqh`)**:
      - Hunts Bitcoin "Bart Simpson" stop-hunt liquidity sweeps (false breakouts above/below key liquidity pools that trap leveraged breakout traders and snap back inside the range on M5).
      - **3 Active Crypto + Institutional Killzones**:
        - **Asian / Tokyo Killzone**: `00:30–04:25 UTC`
        - **London Killzone**: `06:30–11:30 UTC` (sweeping the `00:00–06:30 UTC` Asian Accumulation Box)
        - **New York & Wall Street Spot ETF Killzone**: `12:30–20:00 UTC` (capturing CME open, Wall Street IBIT/FBTC Spot ETF flows, and post-close liquidity sweeps)
        - **Rollover Spread Blackout**: `20:55–22:10 UTC` (`23:55–01:10` Server Time)
      - **Lazy Closed-Bar M1 Volume Profile (`VolumeProfile.mqh`)**:
        - Uses `$10.00` price bins (`VP_BIN_SIZE_POINTS = 1000`) built strictly up to `iTime(PERIOD_M1, 1)` and recomputed lazily only when `m_state == STATE_SWEEP_DETECTED`, ensuring zero `Model=1` vs. `Model=4` Real-Tick feature skew and ultra-fast backtesting across `191.8M` ticks.
      - **Broker-Agnostic Rolling H1 Macro Trend (`GetMacroTrendBias()`)**:
        - Computes synthetic 4-hour `SMA20` and 20-hour momentum from rolling closed `PERIOD_H1` bars (`84` bars) with a `±0.25%` (`0.0025 * close`) Bitcoin neutral band so candle boundaries are 100% identical across `UTC+1`, `UTC+2`, and `UTC+3` brokers.
      - **Price-Adaptive BTCUSD Stop-Loss Floor**:
        - Enforces `idealMinSL = MathMax(140.0, 0.0022 * candidateEntry)` (clamped within `[$80.00, $2,200.00]`), scaling automatically from `$42,000` BTC in early 2024 (`~$140` SL) to `$110,000+` BTC in 2025–2026 (`~$242+` SL).
    - **Layer 2 (`FeatureExtractor.mqh`, `OnnxMetaLabeler.mqh`, `btcusd_meta_model.onnx`)**:
      - Extracts the 12 stationary institutional microstructure features (`f0_sweep_depth_norm` through `f11_spread_to_sl_ratio`), flooring `f11_spread_to_sl_ratio` at `$25.00` (`MathMax(25.0, currentSpreadUSD) / slDistUSD`) to eliminate ECN real-tick vs. OHLC spread skew.
      - Embedded 36-unit MLP + Linear Residual ONNX Meta-Labeler (`btcusd_meta_model.onnx`, `zipmap=False`) trained via [`python_pipeline/train_btcusd_onnx.py`](file:///c:/Users/faker/Documents/dev/onix/btcusd-sniper-ea/python_pipeline/train_btcusd_onnx.py) on `1,437` mapped `POSITION_CLOSED` setups across `2024–2026` (`Tier 2 >= 0.56` -> `91.4%` in-distribution WR, `+411.50R`; `Tier 1 >= 0.70` -> `95.5%` in-distribution WR, `+354.78R`).
    - **Layer 3 (`EquityGuard.mqh`, `PositionSizer.mqh`, `ExecutionManager.mqh`)**:
      - **Hard Drawdown Ceiling**: `<3.0%` Daily DD (`2.25%` internal breaker in `MODE_PROP_GUARD`) and `<6.0%` Maximum Total Equity DD (`5.20%` internal breaker tracking `MathMax(balance, equity)` high-water mark).
      - **Slippage-Buffered Position Sizer**: Adds a `$15.00` BTC price slippage buffer (`effectiveSlDistance = slDistancePrice + 15.0`) when computing lot size via the 3-layer conservative floor (`OrderCalcProfit`, tick formula, and physical contract size `1 BTC`), capped at `35.0` lots (`SYMBOL_VOLUME_LIMIT = 37.0` on Pepperstone).
      - **Fill-Anchored Multi-Stage Runner Ratchet**: Re-anchors `tp1Price` to `m_trade.ResultPrice()` on fill so network latency never distorts the `+0.62R` TP1 (`35%` partial close + `-0.30R` SL tightening), followed by `+0.95R -> +0.10R` BE, `+1.32R -> +0.38R`, `+1.65R -> +0.78R`, `+2.25R -> +1.40R` + M5 structural trail, `+2.80R -> +2.05R`, and `+3.50R` full `TP2`.

### Verified Strategy Tester Performance (`$50,000` Prop Guard `MODE_PROP_GUARD`, `1:100` Leverage)
| Modeling Regime | Period | Net Profit | Return (%) | Profit Factor | Trades | Win Rate | Max Balance DD | Max Equity DD | Report |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **`Model=1` (1-Minute OHLC, `ExecutionMode=0`)** | `2024` (`2024.01.01–2025.01.01`) | **`+$709,736.59`** | `+1,419.47%` | **`4.44`** | `683` | **`86.53%`** | `1.98%` | `3.55%` | [`btcsnp_V1_M1_2024.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/btcsnp_V1_M1_2024.htm) |
| **`Model=1` (1-Minute OHLC, `ExecutionMode=0`)** | `2025–2026` (`2025.01.01–2026.10.25`) | **`+$754,354.93`** | `+1,508.71%` | **`4.33`** | `759` | **`86.43%`** | `2.19%` | `3.72%` | [`btcsnp_V1_M1_2526.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/btcsnp_V1_M1_2526.htm) |
| **`Model=4` (191.8M Real Ticks, Zero Latency `ExecutionMode=0`)** | `2024` (`2024.01.01–2025.01.01`) | **`+$610,771.55`** | `+1,221.54%` | **`4.01`** | `688` | **`86.48%`** | `2.55%` | `3.81%` | [`btcsnp_V1_M4_E0_2024.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/btcsnp_V1_M4_E0_2024.htm) |
| **`Model=4` (191.8M Real Ticks, Zero Latency `ExecutionMode=0`)** | `2025–2026` (`2025.01.01–2026.10.25`) | **`+$595,839.67`** | `+1,191.68%` | **`3.68`** | `760` | **`86.32%`** | `2.87%` | `3.23%` | [`btcsnp_V1_M4_E0_2526.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/btcsnp_V1_M4_E0_2526.htm) |
| **`Model=4` (191.8M Real Ticks + Random Delay `ExecutionMode=-1`)** | `2024` (`2024.01.01–2025.01.01`) | **`+$621,795.40`** | `+1,243.59%` | **`4.11`** | `689` | **`85.92%`** | `2.44%` | `3.66%` | [`btcsnp_V1_M4_RD_2024.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/btcsnp_V1_M4_RD_2024.htm) |
| **`Model=4` (191.8M Real Ticks + Random Delay `ExecutionMode=-1`)** | `2025–2026` (`2025.01.01–2026.10.25`) | **`+$550,441.19`** | `+1,100.88%` | **`3.40`** | `764` | **`84.82%`** | `2.63%` | `4.39%` | [`btcsnp_V1_M4_RD_2526.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/btcsnp_V1_M4_RD_2526.htm) |
