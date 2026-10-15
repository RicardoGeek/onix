# AGENTS.md — Institutional Memory, System Invariants & Session Recovery Guide

This document contains the complete system context, Windows VM paths, architectural invariants, post-mortem lessons learned, and operational commands required to immediately resume development or troubleshooting on `XAUUSD_Sniper_ONNX` without losing context.

---

## 1. Windows VM Environment & Exact File Paths

- **Repository Root**: `c:\Users\faker\Documents\dev\onix`
- **EA & Python Pipeline Root**: `c:\Users\faker\Documents\dev\onix\xauusd-quant-ea`
- **External Artifacts & Telemetry Archive (Non-Repo)**: `C:\Users\faker\Documents\onix_artifacts`
  - `C:\Users\faker\Documents\onix_artifacts\reports\` — Strategy Tester HTML reports (`pass_2024_10k.htm`, `pass_2024_50k.htm`, `pass2a_prop.htm`, `pass2b_growth.htm`) & run journals
  - `C:\Users\faker\Documents\onix_artifacts\ini\` — Automated Strategy Tester `.ini` configurations (`tester_2024_10k.ini`, `tester_2024_50k.ini`, `tester_pass2a_prop.ini`, `tester_pass2b_growth.ini`, `tester_collect.ini`, `tester_collect_2024.ini`)
  - `C:\Users\faker\Documents\onix_artifacts\telemetry\` — Preserved multi-year telemetry CSVs (`all_2023_2026_setup_telemetry.csv`, `pass1_setup_telemetry.csv`, `pass2a_v2_setup_telemetry.csv`, `xauusd_setup_telemetry.csv`)
  - `C:\Users\faker\Documents\onix_artifacts\logs\` — MetaEditor compilation logs
- **Python Virtual Environment**: `C:\Users\faker\mlv\Scripts\python.exe`
  - Installed packages: `numpy`, `pandas`, `scikit-learn`, `lightgbm`, `onnx`, `onnxruntime`, `skl2onnx`, `onnxmltools`, `MetaTrader5`
- **MetaTrader 5 Executables**:
  - Primary Terminal: `C:\Program Files\Pepperstone MetaTrader 5\terminal64.exe`
  - Primary Compiler: `C:\Program Files\Pepperstone MetaTrader 5\MetaEditor64.exe`
  - Secondary Terminal: `C:\Program Files\MetaTrader 5\terminal64.exe`
- **MetaTrader 5 Terminal Data Folders (`%APPDATA%\MetaQuotes\Terminal\`)**:
  - Primary (Pepperstone): `C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\73B7A2420D6397DFF9014A20F1201F97`
  - Default MT5: `C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075`
  - BreakFree Lab: `C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\32B1B264C2ABDCF82237DF1469803C70`
  - MT5 Tests: `C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\F0A0D5F097CACFBD0434000E2EB7B106`
  - Shared Common Files: `C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\Common\Files`
    - Also contains `of_pep_XAUUSD_20230101.csv` (full Pepperstone M1 bar history from 2023–2026).

---

## 2. Hard Non-Negotiable System Invariants

1. **Daily Drawdown Hard Ceiling (< 3.0%)**:
   - Calculated against `MathMax(DayStartBalance, DayStartEquity)` to comply with strict prop firm rules.
   - Internal emergency circuit breaker in `EquityGuard.mqh` liquidates and halts trading for the day at **`2.25%`** (`MODE_PROP_GUARD`) or **`2.40%`** (`MODE_ASYMMETRIC_GROWTH`).
2. **Maximum Total Drawdown Hard Ceiling (< 6.0%)**:
   - Calculated against the account High-Water Mark (`m_highWaterMark`).
   - Internal emergency circuit breaker trips at **`5.20%`** (`MODE_PROP_GUARD`) or **`5.40%`** (`MODE_ASYMMETRIC_GROWTH`).
3. **Strictly One Position / Pending Order at a Time**:
   - Zero grid, zero martingale, zero loss-averaging.
4. **Zero Training-Serving Skew (12 Stationary Features)**:
   - The 12 features in `FeatureExtractor.mqh` and `python_pipeline/feature_engineering.py` must remain 100% identical in order and normalization:
     - `f0_sweep_depth_norm`
     - `f1_wick_body_ratio`
     - `f2_bars_outside_level`
     - `f3_rel_tick_volume`
     - `f4_vpoc_distance_norm`
     - `f5_value_area_width_norm`
     - `f6_h1_adx`
     - `f7_hurst_exponent`
     - `f8_volatility_ratio`
     - `f9_hour_sin`
     - `f10_hour_cos`
     - `f11_spread_to_sl_ratio`
5. **Native MT5 ONNX Contract (`zipmap=False`)**:
   - Input 0: `"input_features"` -> `float32[1, 12]`
   - Output 0: `"label"` -> `int64[1]`
   - Output 1: `"probabilities"` -> `float32[1, 2]`

---

## 3. Critical Engineering Lessons Learned (Do Not Regress!)

### Lesson 1: `MetaEditor64.exe` Asynchronous Exit Trap on Windows
- **Problem**: Invoking `MetaEditor64.exe /compile:...` directly in PowerShell returns control to the shell before compilation finishes, causing scripts to read stale `.ex5` files or empty logs.
- **Rule**: Always invoke `MetaEditor64.exe` using `Start-Process -FilePath $metaeditor -ArgumentList "/compile:..." -Wait`.

### Lesson 2: `#resource` Embeds the ONNX Model at Compile Time
- **Problem**: `XAUUSD_Sniper_ONNX.mq5` uses `#resource "\\Files\\models\\xauusd_meta_model.onnx" as uchar ExtOnnxModelData[]`. Simply replacing `xauusd_meta_model.onnx` on disk does **not** update the model used by `XAUUSD_Sniper_ONNX.ex5`.
- **Rule**: Every time you export a new `xauusd_meta_model.onnx`, copy it into the MT5 Data Folder (`MQL5\Files\models\xauusd_meta_model.onnx`) AND recompile `XAUUSD_Sniper_ONNX.mq5` with `MetaEditor64.exe`.

### Lesson 3: Broker Tick-Step Price Quantization (`10015` / `10016` Prevention)
- **Problem**: Using standard `NormalizeDouble(price, _Digits)` only rounds to decimal places (`0.01`), ignoring `SYMBOL_TRADE_TICK_SIZE`. On brokers where `SYMBOL_TRADE_TICK_SIZE` is `0.05`, `0.25`, or `0.50`, sending an unquantized Stop Loss or Entry Price triggers `10015 (TRADE_RETCODE_INVALID_PRICE)` or `10016 (TRADE_RETCODE_INVALID_STOPS)`.
- **SolutionImplemented**:
  - `NormalizeSymbolPrice()` in `Definitions.mqh` uses `NormalizeDouble(MathRound(price / tickSize) * tickSize, digits)`.
  - `ValidateModifyDistance()` and M5 trailing-stop steps in `ExecutionManager.mqh` enforce `MathMax(minStep, tickSize)`.

### Lesson 4: Prop-Firm Anti-10x Lot Sizing (`OrderCalcProfit` + 3-Layer Floor)
- **Problem**: Different brokers and prop firms (e.g., Pepperstone vs. Upcomers) configure `SYMBOL_TRADE_TICK_VALUE` differently, which can cause a 10x lot size explosion that blows a prop challenge on a single trade.
- **Solution Implemented in `PositionSizer.mqh`**:
  1. Query MT5's native profit simulator: `OrderCalcProfit(calcOrderType, m_symbol, 1.0, entryPrice, stopLossPrice, orderCalcOneLotPL)`.
  2. Compute the tick-formula loss: `(slDistancePrice / tickSize) * ResolveLossTickValue(tickSize)`.
  3. Compute the physical contract floor: `contractSize * slDistancePrice`.
  4. Take the conservative maximum of all three (`MathMax(lossPerLotOrderCalc, MathMax(lossPerLotTickFormula, lossPerLotContractFloor))`) and verify the final rounded lot size again via `OrderCalcProfit()` before returning.

### Lesson 5: The "Zeno's Paradox" Drawdown Lockout on `$10,000` Accounts
- **Problem**: In our initial 2024 `$10,000` test, the EA flatlined after March 25, 2024 (`5.1673%` total DD vs. `5.20%` breaker). A multiplicative clamp (`safeTotalPct = remTotalPct * 0.45`) shrank allowed risk to `$1.47`. Because `0.01` lot (minimum volume) on XAUUSD risks `~$1.57–$2.50`, `PositionSizer` rounded every trade to `0.00` lots for the rest of the year (139 signals skipped in a row).
- **Solution Implemented in `PositionSizer.mqh`**:
  - Use a linear safety buffer `safeTotalPct = MathMax(0.0, remTotalPct - 0.08)` instead of `remTotalPct * 0.45`.
  - Allow `0.01` minimum-lot recovery trades whenever `minVolTrueLossUSD` fits within `remDailyPct - 0.02%` and `remTotalPct - 0.02%`.

### Lesson 6: Breakeven Scratches Must Not Trigger Consecutive Loss Penalties
- **Problem**: When a trade hits `TP1` (`+0.62R`), moves SL to breakeven, and closes at `-$0.39` (`-0.01R`) due to spread/commission, counting `netRealizedPnLUSD < 0` as a consecutive loss in `EquityGuard.mqh` falsely triggers the `0.38x` intraday risk clamp and the 2-loss daily halt.
- **Solution Implemented in `EquityGuard.mqh` & `PositionSizer.mqh`**:
  - Define `scratchFloorUSD = dayStartReference * 0.0015` (`0.15%` of day-start equity). Only real stop-outs exceeding `-scratchFloorUSD` increment `m_consecutiveLossesToday` or trigger the intraday post-loss clamp.

### Lesson 7: Layer 1 Structural Filters & Multi-Stage Runner Ratchet
- **Layer 1 Signal Filters (`SweepSignalEngine.mqh`)**:
  - Active killzones: London (`06:30–10:55 UTC`) and New York (`12:00–15:55 UTC`).
  - `SIGNAL_SHORT` is restricted to `LIQ_EQUAL_HIGHS` (exhaustion double-tops); counter-trend shorts against single levels in secular Gold bull regimes are blocked.
  - Low-wick M15 fractal sweeps (`wick_body_ratio < 0.55` during `06:00–09:59 UTC` or `14:20–14:59 UTC`) and `LIQ_EXTERNAL_LVN_LOW` longs are filtered out.
- **Layer 3 Multi-Stage Ratchet (`ExecutionManager.mqh`)**:
  - Instant execution when limit price is within `$0.85` of market ask/bid; stale pending orders cancel after `15` minutes (`3` M5 bars) or if price runs `+1.50R` away before fill.
  - **`+0.62R`**: Close `35%` at `TP1` and tighten runner SL to `-0.30R`.
  - **`+0.95R`**: Move runner SL to `+0.10R` (Breakeven + Commission).
  - **`+1.32R`**: Lock **`+0.38R`** (captures 2024-style tighter range swings that peak around `+1.35R–1.60R`).
  - **`+1.65R`**: Lock **`+0.78R`**.
  - **`+2.25R`**: Lock **`+1.40R`** + activate M5 structural swing trail.
  - **`+2.80R`**: Lock **`+2.05R`**.
  - **`+3.50R`**: Full `TP2` target.

### Lesson 8: Direct `timestamp_utc` Matching When Retraining ONNX
- **Problem**: In `xauusd_setup_telemetry.csv`, `setup_id` appends a 2-digit per-run counter (`timestamp_utc * 100 + counter`), which changes across separate Strategy Tester runs. However, on `POSITION_CLOSED` rows, `Logger.mqh` writes `m_activeSetup.signalTimeUTC` into `timestamp_utc`.
- **Rule**: Always map `POSITION_CLOSED` outcomes to `SIGNAL_TRIGGERED` candidates directly by `timestamp_utc` (as implemented in `python_pipeline/retrain_multiyear_onnx.py`).

### Lesson 9: Automatic Quantized Broker GMT Offset Detection (`Definitions.mqh`)
- **Problem**: Different brokers use different server timezones (e.g., Pepperstone shifts between `GMT+2` in US Winter and `GMT+3` in US Daylight Saving Time; Upcomers uses `UTC+1`). However, naive integer division `(TimeCurrent() - TimeGMT()) / 3600` in MQL5 has three traps:
  1. **Tick-Lag Truncation**: If the last tick arrived 2 seconds ago (`10,798` seconds instead of `10,800` seconds on `GMT+3`), integer division `10798 / 3600` truncates to **`2` hours instead of `3` hours**.
  2. **Weekend / Quiet-Market Freeze**: On weekends, `TimeCurrent()` freezes on Friday's last tick while `TimeGMT()` continues advancing.
  3. **Strategy Tester Behavior**: Inside MT5 Strategy Tester (`MQLInfoInteger(MQL_TESTER)`), MT5 sets `TimeGMT() == TimeCurrent()`, so `TimeCurrent() - TimeGMT() == 0`.
- **Solution Implemented in `ResolveEffectiveGMTOffsetSeconds()` (`Definitions.mqh`)**:
  - In **Live / Demo / VPS (`!MQLInfoInteger(MQL_TESTER)`)**: Compares `TimeTradeServer()` (or `TimeCurrent()` when actively ticking within 5 minutes) against `TimeGMT()`, and **rounds to the nearest 15-minute (`900s`) timezone boundary** (`MathRound(diffSeconds / 900.0) * 900`). This is immune to tick lag, weekend freezes, and up to `±7` minutes of local PC/VPS clock drift, while automatically handling US DST shifts and any broker timezone (`UTC+1`, `UTC+2`, `UTC+3`).
  - In **Strategy Tester (`MQLInfoInteger(MQL_TESTER)`)**: Uses `InpBrokerGMTOffsetHours` (`2`) as the backtest fallback.

---

## 4. One-Block Restore & Retrain Command Reference

```powershell
# 1. Retrain ONNX model from preserved + latest MT5 telemetry
C:\Users\faker\mlv\Scripts\python.exe "c:\Users\faker\Documents\dev\onix\xauusd-quant-ea\python_pipeline\retrain_multiyear_onnx.py"

# 2. Sync sources & ONNX to Pepperstone MT5 Data Folder and compile
$repo = "c:\Users\faker\Documents\dev\onix\xauusd-quant-ea"
$mt5Mql5 = "C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\73B7A2420D6397DFF9014A20F1201F97\MQL5"
Copy-Item "$repo\MQL5\Experts\XAUUSD_Sniper_ONNX.mq5" "$mt5Mql5\Experts\XAUUSD_Sniper_ONNX.mq5" -Force
Copy-Item "$repo\MQL5\Include\XAUUSD_Quant" "$mt5Mql5\Include\" -Recurse -Force
Copy-Item "$repo\MQL5\Files\models\xauusd_meta_model.onnx" "$mt5Mql5\Files\models\xauusd_meta_model.onnx" -Force

Start-Process -FilePath "C:\Program Files\Pepperstone MetaTrader 5\MetaEditor64.exe" `
  -ArgumentList "/compile:`"$mt5Mql5\Experts\XAUUSD_Sniper_ONNX.mq5`" /log:`"C:\Users\faker\Documents\onix_artifacts\logs\compile.log`"" -Wait
Get-Content "C:\Users\faker\Documents\onix_artifacts\logs\compile.log" | Select-Object -Last 5

# 3. Copy compiled .ex5 back to repo and all MT5 terminals
Copy-Item "$mt5Mql5\Experts\XAUUSD_Sniper_ONNX.ex5" "$repo\MQL5\Experts\XAUUSD_Sniper_ONNX.ex5" -Force
```
