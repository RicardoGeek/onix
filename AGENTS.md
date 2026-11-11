# AGENTS.md — Institutional Memory, System Invariants & Session Recovery Guide

This document contains the complete system context, Windows VM paths, architectural invariants, post-mortem lessons learned, and operational commands required to immediately resume development or troubleshooting on `XAUUSD_Sniper_ONNX` without losing context.

---

## 1. Windows VM Environment & Exact File Paths

- **Repository Root**: `c:\Users\faker\Documents\dev\onix`
- **Versioned Binary Archive (`bin/`)**: `c:\Users\faker\Documents\dev\onix\bin`
  - Organized into per-EA subfolders (`bin/XAUUSD_Sniper_ONNX/`, `bin/USDJPY_Sniper_ONNX/`, `bin/BTCUSD_Sniper_ONNX/`, `bin/xauusd_chrysalis_ea/`, `bin/usdjpy_chrysalis_ea/`, `bin/btcusd_chrysalis_ea/`, `bin/aegis_regime_hunter_ea/`).
  - Every compiled EA release must have its version stamped into the binary filename inside its `bin/<EA_Folder>/` subfolder (e.g., `bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.21.ex5`, `bin/aegis_regime_hunter_ea/aegis_regime_hunter_ea_v4.00.ex5`) and documented in the corresponding EA's root `CHANGELOG.md`.
- **EA Directories**:
  - `c:\Users\faker\Documents\dev\onix\xauusd-quant-ea` (`XAUUSD_Sniper_ONNX`, `CHANGELOG.md`)
  - `c:\Users\faker\Documents\dev\onix\usdjpy-sniper-ea` (`USDJPY_Sniper_ONNX`, `CHANGELOG.md`)
  - `c:\Users\faker\Documents\dev\onix\btcusd-sniper-ea` (`BTCUSD_Sniper_ONNX`, `CHANGELOG.md`)
  - `c:\Users\faker\Documents\dev\onix\chrysalis-moonshot-ea` (`chrysalis_ea`, `CHANGELOG.md`)
  - `c:\Users\faker\Documents\dev\onix\usdjpy-moonshot-ea` (`usdjpy_chrysalis_ea`, `CHANGELOG.md`)
  - `c:\Users\faker\Documents\dev\onix\btcusd-moonshot-ea` (`btcusd_chrysalis_ea`, `CHANGELOG.md`)
  - `c:\Users\faker\Documents\dev\onix\aegis-regime-hunter-ea` (`aegis_regime_hunter_ea`, `CHANGELOG.md`)
  - `c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea` (`XAUUSD_SevenWave`, `CHANGELOG.md`, `REPORT.md`; binaries in `bin/XAUUSD_SevenWave/`)
  - `c:\Users\faker\Documents\dev\onix\7wave` (`7Wave` indicator in `MQL5/Indicators/7Wave/`, `7Wave_EA` in `MQL5/Experts/7Wave/`, `RULES.md`, `CHANGELOG.md`; binaries in `bin/7Wave/`).
    This is the user's own manual strategy, built in steps the user checks: indicator, then an EA that follows it, then a small risk engine.
    It is not the AI-designed `xauusd-sevenwave-ea`, so don't import its logic. `RULES.md` is the spec.
  - `c:\Users\faker\Documents\dev\onix\16runes-ea` (`16Runes`, `CHANGELOG.md`, `REPORT.md`; binaries in `bin/16Runes/`, embedded ONNX `MQL5/Files/models/16runes_meta.onnx`, research & parity tools in `python_pipeline/`).
  - `c:\Users\faker\Documents\dev\onix\oliver-kell-ea` (`oliver_kell_ea`, `CHANGELOG.md`, `REPORT.md`; binaries in `bin/oliver_kell_ea/`, embedded ONNX `MQL5/Files/models/oliver_kell_meta.onnx`, research & parity tools in `python_pipeline/`).
  - `c:\Users\faker\Documents\dev\onix\trident-moe-ea` (`XAUUSD_Trident_MoE`, `CHANGELOG.md`, `README.md`; binaries in `bin/XAUUSD_Trident_MoE/`, 3 embedded Strict-OOS ONNX models `xauusd_meta_model.onnx`, `16runes_meta.onnx`, `impulse_cascade_meta.onnx`).
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
6. **Binary Version Archiving (`bin/<EA_Folder>/`), Terminal Deployment & Per-EA `CHANGELOG.md` Rule**:
   - Whenever any EA is modified and compiled to a new version (`#property version "X.YY"`):
     1. Archive the compiled `.ex5` binary in `c:\Users\faker\Documents\dev\onix\bin\<EA_Folder>\<EA_Name>_v<X.YY>.ex5` so any historical version can be restored at any time.
     2. Deploy `<EA_Name>_v<X.YY>.ex5` (and sync `<EA_Name>.ex5`) to `MQL5\Experts\` across **every** MT5 terminal (`Pepperstone`, `Upcomers`, `GetLeveraged`, `BreakFree`, `MT5 Tests`) and **remove any older versioned `<EA_Name>_v*.ex5` files** from every terminal's `MQL5\Experts\` folder so only the latest versioned binary is present.
     3. Add a new version section (`## [vX.YY] ? YYYY-MM-DD`) at the top of that EA's root `CHANGELOG.md` explaining the architectural and parameter changes.
   - **Exception: 7Wave** (`7wave/`, indicator and later its EA) is installed in the **Pepperstone terminal only** (user decision, 2026-11-06).
     The indicator keeps one unversioned copy there (`MQL5\Indicators\7Wave\7Wave.ex5`); its version shows in the indicator name on the chart.

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

### Lesson 14: `BTCUSD` 24/7 Satoshi Supernova EA (`btcusd_chrysalis_ea v2.00`) — `37.0`-Lot Book Limit, SuperTrend Overdrive & Active Judas Shield
- **Directory**: `c:\Users\faker\Documents\dev\onix\btcusd-moonshot-ea\MQL5\Experts\btcusd_chrysalis_ea.mq5` (`bin/btcusd_chrysalis_ea/btcusd_chrysalis_ea_v2.00.ex5` and `btcusd_chrysalis_ea_v1.00.ex5`)
- **Key Engineering Invariants on Pepperstone `BTCUSD`**:
  1. **Contract Specification & `$360` Seed Shield + `0.80x` Stage-2 Overdrive (`InpBalanceStep = 125.0`, `InpBoostMult = 0.80`)**: On Pepperstone `BTCUSD`, `SYMBOL_TRADE_CONTRACT_SIZE = 1` (`0.01` lot = `0.01 BTC`, `~$1.06–$2.34` margin), which has `3x–5x` less notional exposure per `0.01` lot than Gold (`1 oz`). `OrderLots()` locks lot size to `0.01` BTC while `balance < $360.0` (protecting the `$300` starting deposit), accelerates to `$100` effective blocks (`0.80x` overdrive) between `$550` and `$16,000` when `dd_pct <= 10.0%`, enforces a per-slot SL risk ceiling (`8.20%–9.50%`), and engages a `26%` Drawdown Parachute (`1.25x`).
  2. **Non-Thrashing `37.0`-Lot `SYMBOL_VOLUME_LIMIT` Book Manager (`FreeDistantPendingVolume()`)**: Pepperstone caps total `open positions + pending orders` on `BTCUSD` at `37.0` lots. Never use an opposite-side deletion bias in `FreeDistantPendingVolume()` (which causes `s=0` `BUY_STOP` and `s=1` `SELL_STOP` to thrash-delete each other once order size exceeds `2.0` lots). Strictly free only pending orders farther from current mid-price than the new order (`if(worstDist <= newDist + 5.0) break;`) and clamp to remaining book volume.
  3. **Regime-Invariant `1.20%` Dynamic SL + Real-Tick Slippage Compensation (`effFav`) + Active Judas `OrderDelete()` Shield (`InpSessionMode = 6`)**: `EffectiveStopDist()` scales SL as `1.20%` of BTC price (`InpStopPct = 1.20`), `ManagePositions()` compensates up to `0.095%` of `ExecutionMode=-1` stop-order fill slippage (`effFav`) when evaluating `MOD_BE_AT`, and `InpSessionMode = 6` actively shields the 11 high-whipsaw Judas hours (`01, 04, 06, 08, 09, 15, 16, 17, 21, 22, 23`) in the Wall Street ETF regime while preserving `g_trig` strictly for orders actually paused at shield start.

### Lesson 15: `BTCUSD_Sniper_ONNX v1.00` ("The Bart-Hunter") — 3-Killzone Crypto + Spot ETF Liquidity Sweep Sniper
- **Directory**: `c:\Users\faker\Documents\dev\onix\btcusd-sniper-ea\MQL5\Experts\BTCUSD_Sniper_ONNX.mq5` (`#resource "\\Files\\models\\btcusd_meta_model.onnx"`, archived at `bin/BTCUSD_Sniper_ONNX/BTCUSD_Sniper_ONNX_v1.00.ex5`)
- **Key Engineering Invariants on `BTCUSD` Sniper**:
  1. **3 Crypto + Institutional Killzones (`SessionLevels.mqh`)**: Operates during Asian/Tokyo (`00:30–04:25 UTC`), London (`06:30–11:30 UTC`), and New York / Wall Street Spot ETF (`12:30–20:00 UTC`), with Rollover Blackout (`20:55–22:10 UTC`).
  2. **Zero `Model=1` vs. `Model=4` Real-Tick Feature Skew (`VolumeProfile.mqh` & `FeatureExtractor.mqh`)**: Builds session M1 Volume Profile (`$10.00` bin width) lazily only when `m_state == STATE_SWEEP_DETECTED` and strictly up to closed M1 bar `iTime(PERIOD_M1, 1)`, and floors `f11_spread_to_sl_ratio` at `$25.00` (`MathMax(25.0, currentSpreadUSD) / slDistUSD`).
  3. **Price-Adaptive SL Floor, `$15.00` Slippage Cushion & Floating-Equity HWM (`SweepSignalEngine.mqh`, `PositionSizer.mqh`, `EquityGuard.mqh`)**: Enforces `idealMinSL = MathMax(140.0, 0.0022 * candidateEntry)` (`[$80, $2,200]`), adds `$15.00` BTC slippage cushion in `PositionSizer.mqh`, re-anchors `tp1Price` to fill price in `ExecutionManager.mqh`, and tracks `m_highWaterMark` via `MathMax(balance, equity)` on every tick so `STAT_EQUITY_DDREL_PERCENT` stays strictly inside `<5.20%` (`3.23%–4.39%` across `191.8M` real ticks).

### Lesson 16: `ADR(20)` Volatility-Proportional Geometry (`v4.24`) & Mandatory `Model=4` Torture Report Standard
- **Volatility-Proportional Regime Detection (`SessionLevels.mqh` & `SweepSignalEngine.mqh`, `v4.24`)**:
  - Never hardcode nominal dollar price thresholds (such as `>= $3,900`) to switch between tight-range and expanded-range order geometry. Instead, use **`CSessionLevels::GetAdr20() >= 55.0`** (`14.5x` the `$3.80` baseline `maxImmediateSL` floor). When `ADR(20) >= 55.0` (e.g., May 2025 at `$3,360` Gold with `$80` ADR, or Oct 2025–2026 with `$60–$239` ADR), `BuildSniperOrderGeometry()` anchors pullback limit orders to `m_tracker.levelPrice` (or FVG proximal on the reclaimed side of `m_tracker.levelPrice`) up to `HARD_MAX_SL_DISTANCE_USD`, and `DetectReversalFVGAndMSS()` permits primary-pool (`LIQ_ASIAN_LOW`, `LIQ_PDL`, `LIQ_EQUAL_LOWS` after `10:00 UTC`) displacement reclaims (`m5[0].close > m5[1].high` and body `>= 50%` of range).
- **Mandatory Backtest Reporting Standard (`Model=4` Torture Standard + `0–100` Score)**:
  - **Always present `Model=4` (`99%–100%` Real Ticks) + `ExecutionMode=-1` (Random Delay) Torture Results** (both for telemetry generation and verification).
  - For every backtest report, present **year-by-year (`2024`, `2025`, `2026 YTD`) and aggregate** metrics:
    1. **Net Profit each year**
    2. **Trades Opened each year** (actual positions opened `Deals In`, plus MT5 deal legs)
    3. **Average Trades Per Day** (per trading day `[252/yr]` and per calendar day `[365/yr]`)
    4. **Average Waiting Time Between Trades** (active market trading days/hours and calendar days/hours)
    5. **`0–100` Torture Score & Version Delta (`Score / ±Delta`)**:
       - Sum of 4 rational-saturation sub-scores (`25` pts each):
         - $S_{\text{profit}} = 25 \times \frac{\text{AnnProfit}}{\text{AnnProfit} + 30000}$
         - $S_{\text{trades}} = 25 \times \frac{\text{AnnTrades}}{\text{AnnTrades} + 35}$
         - $S_{\text{freq}} = 25 \times \frac{\text{TradesPerTradingDay}}{\text{TradesPerTradingDay} + 0.15}$
         - $S_{\text{wait}} = 25 \times \frac{4.0}{\text{WaitTradingDays} + 4.0}$
       - Always state the score and delta vs. the previous version (e.g., `67.0 / +0.2`).

---

### Lesson 17: 10-Year (`2017–2026`) Out-of-Sample Validation & `XAUUSD_Sniper_ONNX v4.40` Unbroken H1 Swing Engine
- **Validation Harness (`C:\Users\faker\Documents\goldie_research\sniper\`)**:
  - `sniper_runs.ps1` runs 5 isolated MT5 backtest windows across 10 years (`duka_2017_2019`, `duka_2020_2021`, `duka_2022_2023` on `XAUUSD_D` Dukascopy M1 `Model=0`; `real_2024` on `XAUUSD_REAL` `Model=4`; `live_2025_2026` on `XAUUSD` `Model=4`).
  - `compare_runs.py` parses deal-level `$/0.01 lot`, win rate, median R, and per-year statistics; `oos_filter_test.py` tests cross-year out-of-sample ONNX probability filtering.
- **`XAUUSD_Sniper_ONNX v4.40` Architecture (`SweepSignalEngine.mqh`, `ExecutionManager.mqh`, `PositionSizer.mqh`)**:
  - Replaced the in-sample overfitted M5 sweep + ONNX memorizer (`v4.31/v4.32`) with a scale-invariant **6-Tier Unbroken H1 Structural Swing Breakout (`28/13, 26/13, 22/11, 18/9, 15/7, 12/6`) + `-0.045%` Pre-Level Offset + Velocity/Climax Filter (`vel60m <= 2.10 && !(vel15m > 2.38 && vel60m > 1.48) && !(t_used >= 3 && trend34 > 3.80)`) + 6-Stage Completed-M1-Bar Positive R-Ratchet (`+0.10R` to `+0.85R`, `SL = -0.435%`, `TP2 = +0.580%`)**.
  - Verified profitable across **all 10 individual years (`2017–2026`)**: `1,447` trades, `84.0%` WR, `+92.8R` (`t = +4.34`), with unseen `2026 H2` (`83.8%` WR, `+0.70 $/0.01`) outperforming seen `2026 H1` (`80.0%` WR, `+0.53 $/0.01`).
  - **On-Hold Next-Step Levers for Higher Unseen Return**: (1) Failed-breakout time-decay cut (`-0.45R` after `20–30m` instead of `-1.00R`), (2) `50%` ratchet + `50%` structural wave runner, (3) Confluence-weighted risk sizing (`conf >= 3`), (4) Dual-engine regime coverage (Breakout + Climax Sweep Fade).

### Lesson 18: `XAUUSD_SevenWave v1.00`: 7-EMA Hierarchy x Liquidity-Pool Breakouts (new design, 2026-11-03)
- **Directory**: `c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea` (`MQL5/Experts/XAUUSD_SevenWave.mq5`, includes in
  `MQL5/Include/SevenWave/`, `#resource "\\Files\\models\\sevenwave_rater.onnx"`, research in `python_pipeline/`, data caches in
  `C:\Users\faker\Documents\goldie_research\sevenwave\`).
- **Research verdict (10y, hostile costs)**: raw M15 7-EMA alignment timing has no edge in any variant. The edge comes from stop entries at
  aged, unbroken H1/H2 fractal swing pools, gated by H4(+D1) 7-EMA stacks: +0.14..+0.39R per trade, positive in 7-9/10 years. The same pools
  without the gate have ~0 edge.
- **Invariants**: H4 is rebuilt from H1 anchored to the 17:00-NY close, H2 from H1 on even UTC hours, D1 from broker daily bars. The broker clock is
  learned from the daily-break hour (`Clock.mqh`). The AI uses 17 features `float32[1,17]` and works as a veto only (threshold `AiModelMeta.mqh`).
  The tester supplies only ~1 year of warm-up history before the start date.
- **Parity tool**: `python_pipeline/sw_parity.py <events.csv>` compares the EA's tester event log with the Python replay (target: >95% of
  triggers matched, AI correlation >0.98).
- **v1.10 (2026-11-04)**: geometric ribbon 10/16/26/41/66/105/168, streams A/B/G/P, 2/3 concurrent positions, portfolio budget with a
  room fraction of 15% for Prop (Kelly-safe near a trailing floor; 40-50% froze the account) and 50% for Growth, Prop daily consistency lock
  at 80% of the daily limit. Judge with `python_pipeline/sw_tradelog.py <sevenwave_trades.csv>`; deal-based parsers break with
  concurrent positions. Always validate streams with a TIME-ORDERED portfolio replay: independent-outcome averages overstate
  clustered signals (M15 fresh-wave: +0.18R independent, ~0R in a portfolio).
- **v1.20 (2026-11-04)**: whale pyramid, Growth only.
  - Rule: when a position first reaches +1.5R, add one unit of the same size. The add's stop sits at the first entry, its target
    is the probe's 3R target, and the probe is secured at BE+0.05R first.
  - Adds don't use a slot but do use the never-breach budget. They are tagged `<stream>+` and re-linked after a restart.
  - Prop never pyramids: it froze the 6% trailing account in the research replay.
  - Verified in MT5: Growth $1k +461% / +455% vs v1.10 +335% / +254% (2018-23 / 2024-26). Parity: add stop = 1.50R median.
  - Rejected ideas live in REPORT.md "Ideas tested after v1.10" (retest scalps, early entries, ribbon-calculus whale trigger
    incl. its ATR+EMA200 "fix"). Don't re-test them.
- **v1.30/v1.31 (2026-11-04)**: whale handling.
  - Rule: at +1.5R a trade is secured at BE+0.05R, aims for 5R, may run 72h and trails 3 ATR(H1), in both modes; Growth also adds.
  - Trade management (letting verified winners run) produced the biggest honest gains of the project.
  - Research round 2 (web papers, MQL5 CodeBase, Kronos, a 31-feature walk-forward AI) is logged in REPORT.md.
    Entry prediction stayed at AUC ~0.5.
  - The "overfit" Sniper v4.31 numbers come from an in-sample ONNX: W/L 1.05 at 86.6% WR. Its honest v4.40 rebuild makes
    +0.064R per trade.
- **v1.32 (2026-11-04)**: optional `InpSkipNewsDays` (default off) skips new trades on key US release days.
  - It gives smoother results with lower drawdown, but gives up 2024-26 return.
  - The calendar comes from `MQL5/Scripts/SW_CalendarExport.mq5` (run via a terminal `[StartUp] Script=... ShutdownTerminal=1` ini).
    `python_pipeline/sw_newsdays.py` regenerates `NewsDays.mqh` / `NfpTable.mqh`.
- **Calendar trap**: MQL5 economic-calendar times (`MqlCalendarValue.time`) are **UTC**, not broker server time.
  - Verified: the M1 range is 15x normal at the raw NFP minute.
  - Converting them as server time shifted releases 2-3h early and produced a fake +0.40R NFP edge (look-ahead).
- **Tester trap**: `.ini [TesterInputs]` only overrides the inputs it lists; unlisted inputs keep the previous run's values. Always pass every input.
- **v1.33 (2026-11-04)**: the AI veto is off (`SW_AI_VETO false`), and Growth bets at most 25% of the trailing room (`SW_GROWTH_TOT_FRAC 0.25`).
  - **In-sample trap**: the shipped ONNX rater was trained on 2017-2023. So every 2018-2023 MT5 run of v1.10-v1.32 was partly in-sample.
    On unseen 2024-26 its vetoed setups beat the traded ones (+0.43R vs +0.29R). Check `SW_AI_TRAIN_STAMP` before trusting any
    MT5 window that overlaps the training years.
  - **Freeze trap**: a Growth share of 0.5 froze the honest 2018-23 account at its 30% floor in Aug 2022 (min lot no longer fitted).
    Shares above ~0.25 over-bet the room near a floor.
  - **Honest MT5 results at the defaults**: Prop $50k +28.9% (2018-23) / +48.2% (2024-26); Growth $10k +$53,812 / +$280,058.
  - **Risk frontier, Growth $10k 2024-26:** 2% / 15% / 50% gives +$3.19M; 3% / 20% / 60% gives +$7.4M with a 0.5 share, but its equity
    DD reached 59.4% of a 60% limit in 2018-23. Pepperstone caps one XAUUSD order at 50 lots.
- **Outside data (round 4, `sw_study46-52`)**: none of it helps as a filter or a signal. That covers CFTC COT, Geopolitical Risk, EPU,
  CBOE GVZ/VIX, Treasury real yields, GDELT news tone, strategy momentum, failed-breakout exits, the Asia night effect and Baur's
  autumn effect.
  - Parse outside data with `python_pipeline/sw_outside.py` (conservative publication times).
  - FRED blocks this VM, and SPDR no longer serves GLD holdings history.

### Lesson 19: 7Wave signals are coin-flip waves at the signal (scorecard, 2026-11-06)
- **What it covers**: every 7Wave v1.20 star and arrow on XAUUSD H1 and M15, 2018-2026, hostile costs.
  - Code: `7wave/research/wave_scorecard.py`. Report: `7wave/research/SCORECARD.md`.
- **Wave sizes**: after a signal, gold runs 3R / 5R / 10R before -1R about as often as a random walk.
  - H1: 22% / 14% / 6%. M15: 22% / 15% / 9%. Random walk: 25% / 17% / 9%.
- **Taking everything loses**: -0.20R per signal with a 3R/1R bracket, -0.11 to -0.16R with whale holding.
- **No separator at the signal**: no context visible at the signal holds across seen/unseen years.
  - H4/H1 ribbon agreement flips between 2018-21 and 2022-26.
  - Walk-forward LightGBM: AUC 0.503 (H1), 0.519 (M15).
  - Only small consistent effects: H1 volatility expansion (ATR14/ATR100 > ~1.12, 8 of 9 years); M15 signals in the
    17-22 UTC evening are worst (8 of 9 years).
- **Rules**: the Python rules in `7wave/tools/wave_rules.py` are the ones the user checked on the chart; reuse them.
  Don't spend GPU on predicting these signals from chart context.
- **Blind-replay trainer** (tests whether the user's eye beats chance at the signal):
  - `7wave/trainer/build_trainer.py` writes `7wave_trainer.html`: 400 random signals, future/date/price hidden,
    seed 2026. The page is generated and gitignored. The answer key is `goldie_research\7wave\trainer_pack.csv`.
  - In the app, run it via `.claude/launch.json`, preview `7wave-trainer` (http://localhost:8765). The browser pane
    refuses `file://` pages that were not written by Claude directly.
  - `7wave/trainer/score_trainer.py <export.csv>` scores the user's export: takes vs skips and an eye AUC with 95%
    bootstrap intervals.
  - **Round 1 result** (400 decisions, 2026-11-06, `7wave/research/TRAINER_RESULTS.md`): eye AUC 0.479 (0.418-0.540),
    coin flip like the AI. Strong takes were the worst group (-0.40R). The second half looked better (AUC 0.522), but
    that is unproven.
- **Gate test** (`7wave/research/gate_test.py`, `GATE_TEST.md`): the 7Wave ribbon works as the TREND FILTER for the
  SevenWave stream-A entry. That entry is a stop order 0.15 ATR before an unbroken H1 fractal pool aged 12-48 bars,
  with growth management.
  - All 7 lines stacked on H4 + D1 give +0.255R per trade on Dukascopy 2017-26: +0.249 seen, +0.262 unseen,
    8 of 10 years green.
  - Pepperstone 2023-26: +0.315R.
  - The breakout with no filter: -0.006R. The tuned SevenWave ribbon (reference): +0.328R.
  - $10k at 1%, one position at a time: +119% over 2017-26, max DD 11.1%, 0.12 trades a day.
  - Indicator v1.30 draws this setup on H1 charts (rules 5-6).
  - `7wave/tools/setup_check.py` is its Python copy on broker bars. It matches the research engine on 94% of
    entries; the rest come from the research's 1.25x spread.
- **7Wave_EA** (`7wave/MQL5/Experts/7Wave/`, the user's tester run 2026-11-06):
  - `7wave/tools/ea_check.py` checks the trade log: all 71 exits match a minute-by-minute replay of the rules; on
    599 of 608 flat bars the EA placed exactly the order the indicator copy armed.
  - +0.496R per trade; at 1% risk, 2025 +38.1%, matching the research.
  - v1.01 retries stop orders the broker rejects (error 10015 at the Fed hour), turning them into market orders at the
    level.
  - MT5 Python API trap: plain `datetime` arguments to `copy_rates_range` are read as LOCAL time. Pass epoch seconds,
    or fetch a wide range and match bars by their own `time`.
- **Stop study** (`7wave/research/stop_study.py`):
  - "Stopped, then +3R anyway" happens on 55-62% of 1.5 ATR stop-outs, and equally for random entries.
  - Wider stops (4 ATR) improve avg R for 7Wave and random entries alike, through lower cost drag in R. Wider stops
    are not an edge.

### Lesson 20: `16Runes v1.00` — 16 Chart Pattern Engine, L2 Logistic Meta-Labeler & Reserved HTF Slot Rule (2026-11-06)
- **Directory**: `c:\Users\faker\Documents\dev\onix\16runes-ea` (`MQL5/Experts/16Runes.mq5`, includes in `MQL5/Include/16Runes/`, `#resource "\\Files\\models\\16runes_meta.onnx"`, binaries in `bin/16Runes/16Runes_v1.00.ex5`, research in `python_pipeline/`).
- **10-Year Research Verdict (`runes_study1.py` – `runes_study9.py`)**:
  - Raw M15/M30/H1 chart patterns lose `-0.05R` to `-0.10R` after spread/slippage. Requiring the **geometric 7-EMA ribbon (`10/16/26/41/66/105/168`)** to be stacked in the breakout direction (`H4+D1` on `H1/H2/M30`, `H1+H4+D1` on `M15/M5`) plus **upper/lower 80% apex coil confirmation** (`coilAboveLb` / `coilBelowHb` in `Series.mqh`) turns all 5 streams positive across both `2017–2023` (`+0.196R/trade`) and unseen `2024–2026` (`+0.408R/trade`).
  - **Why `StandardScaler + LogisticRegression(C=0.05)` Beats `LightGBM` for the Meta-Labeler**: Tree models overfitted `2017–2023` and inverted on unseen `2024–2026`. By contrast, `StandardScaler + LogisticRegression(C=0.05)` with the U-shaped volatility squeeze/expansion feature `f11_vol_u = |vol_reg - 1.0|` and Rune geometry features improved both `2017–2023` leave-one-year-out CV (`+0.211R` kept vs `+0.108R` vetoed) AND unseen `2024–2026` (`+0.443R` kept vs `+0.150R` vetoed — a `+0.293R/trade` out-of-sample separation).
  - **Reserved HTF Slot Rule (`RiskEngine.mqh`, `CanOpenStream`)**: Allowing `S4 (M5)` to fill all portfolio slots crowds out `H1/H2/M30/M15` setups. Reserving higher-timeframe slots (`S0..S3` use up to 3 slots at `p >= 0.3382`; `S4 [M5]` requires `p >= 0.3797` and only opens when `openProbes == 0` in Prop [reserving 2 slots] or `openProbes <= 1` in Growth [reserving 1 slot], with weights `{1.0, 1.0, 0.90, 0.80, 0.60}`) achieved **`9/9` green years (`2018–2026`) in MT5 `Model=4` Real Ticks + Random Delay**:
    - **Prop `$50k`**: `+$14,853.67` (`+29.7%`, PF `1.53`, `3.53%` Bal DD / `4.84%` Eq DD) in `2018–2023` and `+$21,431.06` (`+42.9%`, PF `1.99`, `3.22%` Bal DD / `3.40%` Eq DD, `39.3%` weekly challenge pass rate, `0.0%` breaches) in unseen `2024–2026`.
    - **Growth `$10k`**: `+$37,444.95` (`+374.4%`, PF `1.59`, `10.08%` Bal DD / `15.77%` Eq DD) in `2018–2023` and `+$38,142.54` (`+381.4%`, PF `2.21`, `14.41%` Bal DD / `16.50%` Eq DD) in unseen `2024–2026`, with all 5 streams (`H1, H2, M30, M15, M5`) and all 5 Whale Pyramid add streams (`H1+, H2+, M30+, M15+, M5+`) positive in both windows.
  - **Parity (`runes_parity.py`)**: `94.8%` trigger match (`946/998`), ONNX score correlation `r = 0.9759` (`median |diff| = 0.00000`).
  - **`v1.10` Moonshot Upgrade (`bin/16Runes/16Runes_v1.10.ex5`, `RiskEngine.mqh`, `Trader.mqh`, `AiRater.mqh`)**:
    1. **Realized-Balance HWM on Pyramided Personal Growth Accounts**: In `R16_HOUSE_MONEY_GROWTH`, `m_hwm` tracks realized closed balance (`bal`) rather than transient unrealized floating tick spikes across multi-leg pyramids (preventing winning pyramid runners that trail out `2.0R` below peak tick from falsely triggering a trailing drawdown lockout), while `R16_PROP_FIRM` tracks `MathMax(bal, eq)`.
    2. **2-Stage Whale Pyramid (`+1.50R` Add #1 at `1.0x` unit & `+2.75R` Add #2 at `0.50x` unit) + `7.0R` Extended Tail + `1.30x` ONNX Tiering**: At `+1.50R`, Probe SL moves to `BE+0.05R`, TP extends to `7.0R` in Growth (`5.0R` in Prop), and Add #1 opens at `1.0x` unit size (`effWeight` scaled by `distR = |fillEst - slPx| / R`). At `+2.75R` (Growth), both Probe SL (`+1.60R` locked) and Add #1 SL (`+1.60R`, i.e., `+0.10R` locked above Add #1 entry) ratchet up, and Add #2 opens at `0.50x` unit size with SL at `+1.50R` (`-0.625R` risk in probe R units), guaranteeing at least `+1.075R` net locked profit even if price reverses immediately after `+2.75R`. Setups with `p >= R16_AI_THR_HIGH` (`0.42553900`) receive a `1.30x` conviction boost in Growth mode (`1.15x` in Prop mode).
    3. **Verified MT5 `Model=4` Real Ticks + Random Delay Results (`v1.10` vs `v1.00`)**:
       - **Growth `$10k` (`2018-2023`)**: **`+$121,212.62` (`+1,212.13%`, up `3.24x` vs `v1.00`'s `+$37,444.95`)**, PF **`1.71`** (vs `1.59`), `13.01%` Bal DD / `18.37%` Eq DD, `6/6` green years, Torture Score **`69.7 / 100`** (`+7.9` pts vs `v1.00`).
       - **Growth `$10k` (`2024-2026` Unseen OOS)**: **`+$153,128.03` (`+1,531.28%`, up `4.01x` vs `v1.00`'s `+$38,142.54`)**, PF **`2.65`** (vs `2.21`), `18.09%` Bal DD / `19.46%` Eq DD, `3/3` green years, Torture Score **`78.8 / 100`** (`+9.0` pts vs `v1.00`).
       - **Prop `$50k` (`2024-2026` Unseen OOS)**: **`+$23,149.82` (`+46.30%`, up vs `v1.00`'s `+$21,431.06`)**, PF **`2.01`** (vs `1.99`), `3.46%` Bal DD / `3.58%` Eq DD (`0.0%` breach rate), Torture Score **`62.1 / 100`**.

### Lesson 21: `oliver_kell_ea` (`v1.00`) — Oliver Kell Price Cycle, Confirmed `(3,3)` Fractal Coils & Unified House-Money Scale-In Stops
- **Directory**: `c:\Users\faker\Documents\dev\onix\oliver-kell-ea` (`MQL5/Experts/oliver_kell_ea.mq5`, `MQL5/Include/OliverKell/*.mqh`, `MQL5/Files/models/oliver_kell_meta.onnx`, `python_pipeline/kell_study1..8.py`, `kell_export.py`, `kell_parity.py`, `kell_tradelog.py`, `kell_summary.py`)
- **Key Architectural & Post-Mortem Invariants**:
  1. **Confirmed `(3,3)` Fractal Pivots + Upper/Lower 80% Coil + `10/20 EMA` Cycle Band**: Unconfirmed rolling N-bar consolidation boxes on M5/M15/M30 trigger on noisy micro-bars, whereas requiring confirmed `(3,3)` fractal swings with `coil_above_lb` / `coil_below_hb` plus `10/20 EMA` cycle alignment and `EMA10` reclaim on Double Bottom/Top reversals produces positive expectancy across all 5 streams (`H1, H2, M30, M15, M5`).
  2. **First-Class Slots for Scale-In Pyramid Legs (`OK_MAX_SLOTS = 12`) + Unified House-Money Stops (`Trader.mqh`)**:
     - Every position (`probe`, `Add #1` at `+1.50R`, `Add #2` at `+2.75R`, and `>50 lot` splits) must occupy its own independent slot in `m_slots[]` so the completed-M1-bar `3.0 ATR(H1)` trailing stop trails scale-in adds alongside the probe.
     - Never multiply `effWeight` by `distR` on scale-in legs (`OrderLots` already divides by `LossPerLot(entryPx, slPx)`). Unifying the Stage-1 stop at `+0.25R` (`m_beLockR = 0.25`, `stageScale = 0.85`) and Stage-2 stop at `+1.60R` (`m_stage2LockR = 1.60`, `stageScale = 0.55`) prevents `+1.50R` winners that pull back in tighter range years (like `2024`) from turning into `-1.45R` net losers.
  3. **MT5 `Model=4` Real-Tick + `ExecutionMode=-1` Random-Delay Verification (`Leverage=100`, `97.2%` trigger match, `r = 0.9744`, `0.00000` median ONNX diff)**:
     - **Growth Moonshot `$10k` (`2018–2023`)**: **`+$101,167.03` (`+1,011.67%`, `PF = 1.36`, `921` trades, `6/6` green years, Bal DD `21.41%`, Torture Score `66.8/100`)**.
     - **Growth Moonshot `$10k` (`2024–2026` Unseen OOS)**: **`+$94,252.66` (`+942.53%`, `PF = 2.01`, `741` trades, `3/3` green years, Bal DD `24.03%`, Torture Score `76.9/100`; `2025` single-year Torture Score `80.0/100` at `+295.02%`)**, and `+$155,381.88` (`+1,553.82%`, `2026: +$117,512.24`) prior to M15/M30 crossback pruning.
     - **Prop Firm `$50k` (`2024–2026` Unseen OOS)**: **`+$23,984.21` (`+47.97%`, `PF = 1.97`, `377` trades, `3/3` green years, Bal DD `2.24%` / Eq DD `2.70%`, `24.8%` 180d challenge pass rate with `0.0%` breach rate, Torture Score `61.4/100`)**.

---

### Lesson 22: "The 3 Musketeers" (`XAUUSD_Sniper_ONNX v4.62` + `16Runes v1.23` + `oliver_kell_ea v1.13`) — Magic-Number-Agnostic Surroundings Guard, Strict `2017–2023` SEEN / `2024–2026` UNSEEN ONNX Meta-Labeler, Causal Geometric Monthly Profit Shield & D1 Top-3/Top-5 Transition Unlock (2026-11-08)
- **Archived Binaries**:
  - `c:\Users\faker\Documents\dev\onix\bin\XAUUSD_Sniper_ONNX\XAUUSD_Sniper_ONNX_v4.62.ex5` (Default Magic: `20260401`)
  - `c:\Users\faker\Documents\dev\onix\bin\16Runes\16Runes_v1.23.ex5` (Default Magic: `16016001`)
  - `c:\Users\faker\Documents\dev\onix\bin\oliver_kell_ea\oliver_kell_ea_v1.13.ex5` (Default Magic: `19830983`)
- **Key Architectural Invariants**:
  1. **Magic-Number-Agnostic Surroundings Guard on Entry vs. Magic-Number-Specific Trade Management**:
     - When running all 3 EAs on 3 separate `XAUUSD` chart tabs on the same account (`InpRespectSurroundings = true`), **entry evaluation** (`CanOpenNewPosition()` in `ExecutionManager.mqh`, `CheckSurroundings()` in `Trader.mqh`, and `OpenExposure()` in `RiskEngine.mqh`) inspects `PositionsTotal()` and `OrdersTotal()` on `_Symbol` across **all magic numbers**:
       - **Zero Hedging**: Blocks any new entry if any open position or pending order on `_Symbol` (regardless of magic number) is in the opposite direction (`posDir != wantDir`).
       - **Sniper Right-of-Way & Single Unprotected Probe Rule**: `16Runes v1.23` and `oliver_kell_ea v1.13` yield entry when an external EA has an **unprotected** position open on `_Symbol` or opened a position within `180` seconds, include external open risk/margin inside `RiskEngine::OpenExposure()`, and enforce strictly `1` unprotected probe at a time (`UnprotectedProbes() >= 1`). Once a position locks positive SL (`isProtected == true`), same-direction gap-fill setups are unlocked.
       - **Isolated Trade Management**: `Manage()` / `ManageOpenPositionRatchet()` remain strictly filtered by `POSITION_MAGIC == m_magic` so each EA only trails and ratchets its own tickets.
  2. **100% Strict `2017–2023` SEEN / `2024–2026` UNSEEN ONNX Meta-Labeler + Causal Geometric Monthly Profit Shield + Underwater Escape (`16Runes v1.23` & `oliver_kell_ea v1.13`)**:
     - Both `16runes_meta.onnx` (`R16_AI_THR_HTF = 0.32`, `R16_AI_THR_M5 = 0.36`, `R16_AI_THR_HIGH = 0.62051218`) and `oliver_kell_meta.onnx` (`OK_AI_THR_HTF = 0.32`, `OK_AI_THR_M5 = 0.36`, `OK_AI_THR_HIGH = 0.58130541`) are `StandardScaler + LogisticRegression(C=0.05)` models trained **100% strictly on `2017–2023` (`year <= 2023`, zero `2024–2026` OOS leakage)** with `4.0x` loss-avoidance sample weighting on Harvester + Whale outcomes.
     - Combined with `2.50 * ATR(H1)` initial stops, the Delayed 3-Stage Completed-M1-Bar PureBE Harvester (`5m/+0.22R -> +0.10R`, `15m/+0.16R -> +0.08R`, `35m/+0.12R -> +0.06R`), Mid-Tier Ratchet (`MFE >= 0.45R -> +0.25R`), Underwater Scratch Escape (`maeR >= 0.15R` & `maeAdvUsd >= $2.80` lowers `TP` to `+0.06R`), 3-Tier `D1` EMA Transition Fallback (`7-EMA -> 5-EMA -> 3-EMA`), and the **Causal Geometric Monthly Profit Shield** (`MonthlyShieldScale()` in `RiskEngine.mqh`, which caps per-trade risk at `0.35 * monthClosedR` whenever `monthClosedR > 0.005R` and `0.20 * monthClosedR` after 2 daily wins `dayClosedR >= 0.12R`, while scaling recovery risk `1.40x–2.50x` if `monthClosedR < -0.001R`), both EAs achieve **zero red months across the entire `2024–2026` unseen Out-of-Sample window**:
       - **`16Runes v1.23` (Strict `2024–2026` Unseen OOS)**: **`35/35` Green Months (`12/12` in 2024, `12/12` in 2025, `11/11` in 2026)** | `732` OOS trades | **`91.4%` Win Rate** | **`+45.37R`** (`2025`: `302` trades, `91.4%` WR, `+33.04R`; `2026`: `206` trades, `90.3%` WR, `+9.83R`).
       - **`oliver_kell_ea v1.13` (Strict `2024–2026` Unseen OOS)**: **`34/35` Green Months (`0` red months; `2024-01` flat `0` trades, `11/11` green active in 2024, `12/12` in 2025, `11/11` in 2026)** | `637` OOS trades | **`91.7%` Win Rate** | **`+45.32R`** (`2025`: `280` trades, `91.4%` WR, `+32.64R`; `2026`: `159` trades, `89.9%` WR, `+9.54R`).

---

## 4. One-Block Restore & Retrain Command Reference

```powershell
# 1. Retrain XAUUSD, USDJPY & BTCUSD ONNX models from preserved + latest MT5 telemetry
C:\Users\faker\mlv\Scripts\python.exe "c:\Users\faker\Documents\dev\onix\xauusd-quant-ea\python_pipeline\retrain_multiyear_onnx.py"
C:\Users\faker\mlv\Scripts\python.exe "c:\Users\faker\Documents\dev\onix\usdjpy-sniper-ea\python_pipeline\train_usdjpy_onnx.py"
C:\Users\faker\mlv\Scripts\python.exe "c:\Users\faker\Documents\dev\onix\btcusd-sniper-ea\python_pipeline\train_btcusd_onnx.py"

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

---

## 5. Queued Roadmap & Upcoming Session Items

1. **Chart HUD — Last ONNX Query Telemetry (Next Sniper Version)**:
   - Add persistent HUD fields in `UpdateChartHUD()` across the Sniper EAs (`XAUUSD_Sniper_ONNX`, `USDJPY_Sniper_ONNX`, `BTCUSD_Sniper_ONNX`):
     - `Last Model Call`: Timestamp (`YYYY-MM-DD HH:MM UTC`) + Setup Direction & Swept Liquidity Pool (`e.g., LONG @ ASIAN_LOW`).
     - `Last Model Decision`: `P(Win)` score vs. active threshold & resulting action (`e.g., P=0.742 vs 0.58 -> APPROVED [TIER 1]` or `P=0.412 vs 0.58 -> FILTERED`).
2. **Weekend Sanity Check for November Live Deployment**:
   - Run full `Model=4` Torture Report + sanity audit on `usdjpy_chrysalis_ea` and `USDJPY_Sniper_ONNX` ahead of November live deployment.

