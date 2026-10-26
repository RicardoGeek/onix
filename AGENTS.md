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
  - Secondary Terminal (Upcomers): `C:\Program Files\MetaTrader 5\terminal64.exe`
  - GetLeveraged Terminal: `C:\Program Files\GetLeveraged MT5 Terminal\terminal64.exe`
- **MetaTrader 5 Terminal Data Folders (`%APPDATA%\MetaQuotes\Terminal\`)**:
  - Primary (Pepperstone): `C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\73B7A2420D6397DFF9014A20F1201F97`
  - Default MT5 (Upcomers): `C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075`
  - GetLeveraged MT5: `C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\99B22614732346ADC2C7FD4EA1646D37`
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
- **Layer 1 Signal Filters (`SweepSignalEngine.mqh` & `SessionLevels.mqh`)**:
  - Active killzones: London (`06:30–10:55 UTC`) and New York (`12:00–15:55 UTC`), with Asian range completion at `06:30 UTC` (in-distribution with `xauusd_meta_model.onnx`).
  - `SIGNAL_SHORT` is allowed only on `LIQ_EQUAL_HIGHS` (or `LIQ_M15_SWING_HIGH` when H1/H4 is bearish/neutral). Strictly single-position (`HasActiveExposure()` blocks any concurrent trade — zero hedging).
  - Low-wick M15 fractal sweeps (`wick_body_ratio < 0.38` during `06:30–09:59 UTC` or `14:20–14:59 UTC`) and `LIQ_EXTERNAL_LVN_LOW` longs are filtered out.
- **Layer 3 Multi-Stage Ratchet (`ExecutionManager.mqh`)**:
  - Instant Market execution when entry price is within `maxMarketSlipUSD = MathMax($0.85, 0.22 * slDistanceUSD)` of live ask/bid (preserving exact `$0.85` pullback limit geometry in 2024–2025 while scaling up to `$1.10–$1.94` in `$4,500+` 2026 Gold so high-conviction V-reversals do not run away unfilled); stale pending orders cancel after `15` minutes (`3` M5 bars) or if price runs `+1.50R` away before fill.
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

### Lesson 10: Low-Leverage Prop Firm Margin Trap (`OrderCalcMargin(ORDER_TYPE_BUY_LIMIT)` Returns `$0` on `1:30` Accounts)
- **Problem**: On Upcomers (`1:30` account leverage + additional symbol margin multiplier on XAUUSD, requiring `~$83,000` margin per `1.00` lot at `$4,500` Gold), passing `ORDER_TYPE_BUY_LIMIT` / `ORDER_TYPE_SELL_LIMIT` to `OrderCalcMargin()` returns **`$0.00` required margin** because `SYMBOL_MARGIN_LIMIT` is `0.0` (pending orders do not consume margin until filled). As a result, `PositionSizer.mqh` did not scale down `1.00+` lot trades to fit inside `$50,000` free margin, causing every market order and triggered limit order to fail with `10019 (not enough money)`.
- **Solution Implemented in `PositionSizer.mqh` & `ExecutionManager.mqh`**:
  - Always evaluate margin using the **market deal order type (`ORDER_TYPE_BUY` / `ORDER_TYPE_SELL`)** via **both** `OrderCalcMargin(calcOrderType, ...)` AND `OrderCheck(simReq, simRes)` (`TRADE_ACTION_DEAL`), taking `MathMax(calcMargin, simRes.margin)` and automatically clamping `finalLots` to fit within `85%–88%` of `ACCOUNT_MARGIN_FREE`.

### Lesson 11: Same-Tick Exit Race Condition & Mid-Bar Post-Exit Guard (`ExecutionManager.mqh` & `SweepSignalEngine.mqh`)
- **Problem**:
  1. When an open position closes mid-bar (e.g., at `15:21:40` on `2024-09-06` NFP Friday), if `m_lastEvaluatedM5BarTime` was not updated at `15:20:00` while the trade was open, `EvaluateOnM5BarClose()` immediately runs mid-bar (`100` seconds late!) on the exact same tick the position closed.
  2. Furthermore, if `OnTick()` places a new pending limit order on the same tick that a prior position closed, MT5 fires `OnTradeTransaction(TRADE_TRANSACTION_DEAL_ADD)` for the old position's exit deal *after* `OnTick()`, and calling `m_ctx.Reset()` wipes `m_ctx.hasPendingOrder = true` while the new pending order is still live on the broker.
- **Solution Implemented**:
  - In `SweepSignalEngine.mqh` (`NotifyPendingOrderState()`), update `m_lastEvaluatedM5BarTime = iTime(m_symbol, PERIOD_M5, 0)` whenever `hasPendingOrOpenTrade` is `true`, ensuring that a mid-bar trade exit always waits for the next clean M5 bar close.
  - In `ExecutionManager.mqh` (`SyncBrokerState()` and `OnTradeTransaction()`), explicitly re-adopt live pending orders (`else if(foundOrderTicket > 0 && foundPosTicket == 0)`) and guard `m_ctx.Reset()` with `if(!m_ctx.hasPendingOrder)` followed by `SyncBrokerState()`.

### Lesson 12: Broker Timezone `PERIOD_H4` Candle-Boundary Trap (`GetMacroTrendBias()` in `SweepSignalEngine.mqh`)
- **Problem**: MT5 anchors `PERIOD_H4` candles to broker server midnight (`00:00, 04:00, 08:00, 12:00, 16:00, 20:00` Server Time). On `UTC+2` brokers (e.g., Upcomers), H4 candles close at `02, 06, 10, 14, 18, 22 UTC`, whereas on `UTC+3` brokers (e.g., GetLeveraged, or Pepperstone during US DST), H4 candles close at `01, 05, 09, 13, 17, 21 UTC`. During a fast sell-off between `13:00–14:00 UTC` (e.g., `2026-10-19`), a `UTC+2` server closes its H4 bar at `14:00 UTC` (`16:00` Server Time) and immediately detects `macroBias == -1` (blocking counter-trend falling-knife longs), whereas a `UTC+3` server is only 1 hour into its `16:00–20:00` Server H4 bar, leaving `h4[0]` frozen at `13:00 UTC` (pre-crash) for another 3 hours!
- **Solution Implemented in `SweepSignalEngine.mqh` (`v4.21`)**:
  - `GetMacroTrendBias()` computes the 20-period 4-hour SMA (`sma20H4`) and 5-bar H4 momentum (`h4Close0` vs `h4Close5`) from **rolling closed `PERIOD_H1` bars** (`CopyRates(m_symbol, PERIOD_H1, 1, 84, h1)`, sampling `h1[k * 4].close` for `k = 0..19` and `h1[20].close` for the 20-hour lookback). Because `PERIOD_H1` closes at `:00` of every hour on every broker regardless of GMT offset (`UTC+1`, `UTC+2`, `UTC+3`), macro trend detection is always up-to-the-hour and 100% identical across all brokers.

### Lesson 13: `USDJPY` EA Duo ("The Ninja") — Quote-Currency Risk Conversion, 9-Module Marsshot Matrix & Carry-Aware Killzones
- **Directories**:
  - **9-Module Marsshot EA (`S1–S9`, v3.10)**: `c:\Users\faker\Documents\dev\onix\usdjpy-moonshot-ea\MQL5\Experts\usdjpy_chrysalis_ea.mq5`
  - **Controlled-Risk Prop Sniper EA**: `c:\Users\faker\Documents\dev\onix\usdjpy-sniper-ea\MQL5\Experts\USDJPY_Sniper_ONNX.mq5` (`#resource "\\Files\\models\\usdjpy_meta_model.onnx"`)
- **Key Engineering Invariants on `USDJPY`**:
  1. **JPY -> USD Contract Risk Floor (`PositionSizer.mqh` & `StopCash()`)**: On `USDJPY`, `1.00` lot has `SYMBOL_TRADE_CONTRACT_SIZE = 100,000 USD`, so a `1.00 JPY` (`100 pip`) price move equals `100,000 JPY`, which in USD account currency is `(contractSize * slDistancePrice) / stopLossPrice` (`~$650 USD` at `154.00`, NOT `$100,000 USD`). Always divide `contractSize * slDistancePrice` by `MathMax(100.0, stopLossPrice)` on `JPY`-quoted FX pairs alongside `OrderCalcProfit()`.
  2. **9-Module `usdjpy_chrysalis_ea` (`S1–S9` v3.10 Heavy-Weight Marsshot Matrix)**:
     - **`S1` (`22/11` Chop Market Milker, `MOD_STYLE = 1`)**: Trades 11-hour right-hand H1 swings when the 12-hour range is compressed (`0.30–1.65 JPY`) and aligned with carry (`IsChopMilkerAligned()`).
     - **`S2` (`24/11` Trend Pullback Follower, `MOD_STYLE = 2`)**: Trades 11-hour H1 pullbacks when H1 trend is aligned (`IsBuyTrendAligned()`).
     - **`S3–S9` (`30/13, 34/14, 28/13, 26/13, 28/12, 25/13, 28/14`)**: Structural 25h–34h H1 swing breakouts with pre-level entry offsets (`0.048%–0.066%`) and active `OrderDelete()` shielding during Exhaustion/WMR Fix hours (`11, 18, 19`), Full Rollover Hour (`00:00–00:59`), and Judas hours (`3, 4, 8, 9, 12, 17, 18, 20, 21`).
     - **Real-Tick & `Spread=20` Heavy-Weight Invariants**:
       - `ManagePositions()` evaluates Stage-1 BE, Stage-2/3 Ratchet (`36% -> 60%`), and the 6-Hour Time-Decay Shield (`0.34 JPY` half-SL / `+0.00010` scratch) strictly on **H1 bar boundaries (`h1 != g_last_h1`, skipping `dt.hour == 0` rollover)** so intra-hour tick spikes and `20-point` spreads never prematurely choke runners.
       - `REFILL_SEC = 0` prevents intra-hour duplicate order machine-gunning in Real Ticks.
       - `OrderLots()` enforces a Per-Slot `1:100` Margin + SL Risk Survival Cap (`max_slot_risk_pct` & `max_slot_margin`) so increasing `InpLotStep` (`0.01 -> 0.02`) never causes a margin call or burns a `$300` account at `1:100` leverage.
  3. **Carry-Aware `USDJPY_Sniper_ONNX` (`v2.00` High-Velocity Prop Sniper — Verified on `Model=4` Real Ticks + `ExecutionMode=-1` Random Delay)**:
     - **Killzones**: Operates in the **3 post-impulse reversal windows**: Tokyo Post-Fix (`03:00–03:55 UTC`, trimming `04:00–04:15` dead zone), London Judas (`06:30–06:55` & `08:00–10:55 UTC`), and NY Post-Data + London Close (`13:00–16:45 UTC`), blocking counter-carry `ASIAN_HIGH` / `PDH` short fades.
     - **Zero `Model=1` vs `Model=4` Real-Tick Feature Skew (`FeatureExtractor.mqh` & `VolumeProfile.mqh`)**:
       - In `Model=1` (1-Minute OHLC), MT5 uses the `0.020 JPY` (`20-point` / `2.0-pip`) bar spread, whereas in `Model=4` (Every tick based on real ticks), raw ECN tick spread is `0.001–0.002 JPY` (`10x` smaller), which would shift `f11_spread_to_sl_ratio` by `-4.0` standard deviations out of distribution if unfloored. `FeatureExtractor.mqh` and `train_usdjpy_onnx.py` enforce `MathMax(0.020, currentSpreadUSD) / slDistUSD` (`2.0-pip` baseline spread floor), and `VolumeProfile.mqh` builds session profiles up to `currentM1BarTime` (`iTime(PERIOD_M1, 1)`), ensuring 100% identical features across `Model=1`, `Model=4` Real Ticks, and live accounts.
     - **Random-Delay (`ExecutionMode=-1`) Slippage Cushion & Re-Anchoring (`PositionSizer.mqh` & `ExecutionManager.mqh`)**:
       - `PositionSizer.mqh` adds a `1.5-pip` (`0.015 JPY`) Random-Delay slippage buffer (`effectiveSlDistance = slDistancePrice + 0.015`) when calculating lot size and removes the premature `riskCapitalUSD <= 0.0` return before the `minVol` (`0.01` lot) recovery check.
       - `ExecutionManager.mqh` re-anchors `tp1Price` to `m_trade.ResultPrice()` upon fill so random network delay never distorts the `+0.62R` TP1 distance.
     - **28-Unit Native ONNX Meta-Labeler (`train_usdjpy_onnx.py`)**: Trained on `516` closed MT5 Real-Tick + Random-Delay outcomes (`Tier 2 >= 0.56` @ `1.35%` Prop / `1.40%` Growth risk; `Tier 1 >= 0.70` @ `1.95%` Prop / `2.05%` Growth risk), delivering **`+$49,707` (`PF 8.30`, `92.80%` WR, `1.94%` Max Bal DD / `3.09%` Max Eq DD)** in `2024` and **`+$103,219` (`PF 7.82`, `93.21%` WR, `2.09%` Max Bal DD / `3.08%` Max Eq DD)** in `2025–2026` on `$50k` Prop Guard under **Every tick based on real ticks (`Model=4`) + Random Delay (`ExecutionMode=-1`)** with `34/34` green months.

---

## 4. One-Block Restore & Retrain Command Reference

```powershell
# 1. Retrain XAUUSD & USDJPY ONNX models from preserved + latest MT5 telemetry
C:\Users\faker\mlv\Scripts\python.exe "c:\Users\faker\Documents\dev\onix\xauusd-quant-ea\python_pipeline\retrain_multiyear_onnx.py"
C:\Users\faker\mlv\Scripts\python.exe "c:\Users\faker\Documents\dev\onix\usdjpy-sniper-ea\python_pipeline\train_usdjpy_onnx.py"

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
