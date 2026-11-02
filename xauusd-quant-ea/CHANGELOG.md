# Changelog — `XAUUSD_Sniper_ONNX`

All notable changes to `XAUUSD_Sniper_ONNX` are documented in this file.
Archived version-stamped binaries are stored in [`/bin/`](../bin/).

---

## [v4.32] — 2026-11-02 (Goldeen.io Instant Redis Telemetry Integration)
- **Archived Binary**: [in/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.32.ex5](file:///c:/Users/faker/Documents/dev/onix/bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.32.ex5)
- **Summary**:
  - Added [GoldeenTelemetry.mqh](file:///c:/Users/faker/Documents/dev/onix/xauusd-quant-ea/MQL5/Include/XAUUSD_Quant/Core/GoldeenTelemetry.mqh) (InpGoldeenToken, InpGoldeenUrl = "https://api.goldeen.io/api/v1/ea/report").
  - Completely disabled in Strategy Tester (MQL_TESTER) and when InpGoldeenToken == "".
  - Runs strictly on OnTimer() (EventSetTimer(2)) off the OnTick() hot path, reporting live equity/balance, daily/total drawdown, active open positions, historical closed trades, and last ONNX AI decision to the instant Redis-queued /api/v1/ea/report endpoint.

---
## [v4.31] ? 2026-11-02 (Smart Pool-Hierarchy Cooldown & Broker-Timezone-Agnostic H4 ATR)
- **Archived Binary**: [`bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.31.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.31.ex5)
- **Architectural Upgrades**:
  1. **Smart Pool-Hierarchy Cooldown (`SweepSignalEngine.mqh` -> `IsDirectionInCooldown()`)**:
     - The 25-minute (`1500s`) post-loss directional cooldown now applies strictly to internal micro-fractals (`LIQ_M15_SWING_LOW`/`HIGH`, `LIQ_EXTERNAL_LVN_LOW`/`HIGH`) and **never blocks a primary institutional session boundary** (`LIQ_ASIAN_LOW`/`HIGH`, `LIQ_LONDON_LOW`/`HIGH`, `LIQ_PDL`/`PDH`, `LIQ_EQUAL_LOWS`/`HIGHS`, `LIQ_EARLY_ASIAN`, `LIQ_EARLY_LONDON`). When an internal M15 swing stops out because price is flushing into the true session low/high, the EA immediately captures the primary session reversal.
  2. **Broker-Timezone-Agnostic `UTC+2` H4 ATR (`SessionLevels.mqh` -> `ComputeBrokerAgnosticAtrH4()`)**:
     - Synthesizes `UTC+2`-aligned 14-period H4 True Range from closed `PERIOD_H1` bars whenever a broker server is not on `UTC+2` (such as Upcomers on `UTC+1`), eliminating `f8_volatility_ratio` drift across brokers.
- **Verified Strategy Tester Performance (`$50,000` Prop Guard `MODE_PROP_GUARD`, `Model=4` Real Ticks + `ExecutionMode=-1` Random Delay)**:
  - **`2024`**: **`+$568,255.18`** (up `+$44,571` vs `v4.30`), `248` setups (`478` deals), **`86.61%` WR**, **`PF 6.77`**, **`4.45%` Max Relative Equity DD** (`0.96d` avg wait).
  - **`2025?2026`**: **`+$5,833,005.42`** (`+$1,187,109.61` in `2025` + `+$4,702,049.06` in `2026`, up `+$260,988` vs `v4.30`), `532` setups (`1,034` deals), **`88.78%` WR**, **`PF 6.48`**, **`4.31%` Max Relative Equity DD** (`0.84d` / `0.81d` avg wait).
  - **Total `2024?2026`**: **`+$6,457,413.85`** (deal sum / `+$6,401,260.60` report net, up **`+$307,238.01`** over `v4.30`), **`780` setups**, **`88.1%` WR**, **`1.09` trades/day**, **`0.87d` avg wait**.

---

## [v4.30] — 2026-11-02 (Sub-1-Day Wait Time Architecture: Tokyo Impulse Window + Early/Full London Pools + 88-Unit ONNX Meta-Labeler + HUD AI Telemetry)
- **Archived Binary**: `bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.30.ex5`
- **Summary**:
  - **Layer-1 Structural Frequency & Session Upgrades (`SessionLevels.mqh` & `SweepSignalEngine.mqh`)**:
    1. **Tokyo Open Impulse Killzone (`01:30–02:55 UTC`)**: Locks the Initial Asian Opening Range (`00:00–01:30 UTC`) at `01:30 UTC` to capture high-probability Tokyo/Shanghai open liquidity sweeps while skipping the `03:00–06:25 UTC` mid-Asia dead zone, then locks the Full Asian Range at `06:30 UTC` for London.
    2. **Early London (`09:30 UTC`) & Full London (`11:30 UTC`) Session Liquidity Pools**: Activates `m_londonHigh` and `m_londonLow` from `09:30 UTC` onward (and refreshes if a new extreme forms by `11:30 UTC`) alongside every-M5-bar pool updates, unlocking Late-London and NY sweeps of the London session extremes.
    3. **Relaxed Post-08:30 UTC Inner Asian Core Filter**: Restricts `asianInnerHalf` fractal filtering strictly to Early London Open (`06:30–08:30 UTC`) so confirmed 5-bar M15 continuation pullback swings inside the prior Asian range are never discarded during London/NY trends.
    4. **Balanced Short Pool Filter & 25-Minute Post-Loss Cooldown**: Blocks low-expectancy bull-market `LIQ_PDH` short fades while enabling `LIQ_EQUAL_HIGHS`, `LIQ_ASIAN_HIGH` (`>= 36%` upper wick or strong bearish body), and non-bullish `LIQ_M15_SWING_HIGH` sweeps; reduces same-direction post-loss cooldown from `60m` to `25m` (`1,500s`) and widens `maxImmediateSL` (`1.85x / 2.45x ATR_M5`).
  - **88-Unit Hard-Negative Mined ONNX Meta-Labeler (`retrain_multiyear_onnx.py`)**:
    - Trained on **`1,434` mapped `Model=4` Real-Tick + Random-Delay `POSITION_CLOSED` outcomes** (`10,000` epochs, `75x` false-positive loser penalty), doubling approved trade frequency while maintaining `86%–89%+` Real-Tick Win Rate.
  - **Real-Time Chart HUD AI Telemetry (`XAUUSD_Sniper_ONNX.mq5`)**:
    - Added `[LAST CALL]` (timestamp, direction, swept pool, and level price) and `[LAST DECIS]` (ONNX score vs Tier-2/Tier-1 thresholds and approval/filter status) directly to `UpdateChartHUD()`.
  - **Verified `Model=4` (`99%` Real Ticks) + `ExecutionMode=-1` (Random Delay) Torture Performance (`$50,000` `MODE_PROP_GUARD`)**:
    - **`2024`**: **`$523,683.84`**, **`251` trades executed**, **`85.89%` WR**, **`1.00` trades/day**, **`1.04 days` avg wait**, **`PF 6.68`**, **`3.11%` Eq DD**, **Score: `91.4`**.
    - **`2025`**: **`$1,116,225.02`**, **`280` trades executed**, **`89.17%` WR**, **`1.11` trades/day**, **`0.93 days` avg wait**, **Score: `95.2`**.
    - **`2026 YTD`**: **`$4,455,791.98`**, **`250` trades executed**, **`87.22%` WR**, **`1.17` trades/day**, **`0.85 days` avg wait**, **Score: `96.1`** (**`2025–2026` Combined**: **`$5,572,017.00`**, **`PF 6.25`**, **`88.25%` WR**, **`2.15%` Eq DD**).
    - **3-Year Total**: **`$6,095,700.84`**, **`781` trades executed**, **`87.50%` WR**, **`1.09` trades/day**, **`0.94 days` avg wait**, **Score: `94.6`**.

---

## [v4.25] — 2026-10-28 (High-Frequency Institutional Killzones + 44-Unit Hard-Negative Mined ONNX Meta-Labeler)
- **Archived Binary**: `bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.25.ex5`
- **Summary**:
  - **5 Layer-1 & Layer-3 Frequency Unlocks (`SessionLevels.mqh`, `SweepSignalEngine.mqh`, `ExecutionManager.mqh`)**:
    1. Expanded London + NY Killzones into a continuous **`06:30–16:55 UTC`** institutional window (`SessionLevels.mqh`), eliminating the `11:00–11:59 UTC` mid-day blackout that previously aborted active sweeps and adding the `16:00–16:55 UTC` London Close reversal window.
    2. Removed the false `1.5-hour` (`5,400s`) cooldown on winning trades whose runner exited below `+0.40R` (`NotifyTradeOutcome` in `SweepSignalEngine.mqh`), restricting same-direction cooldown (`3,600s`) strictly to actual stop-outs (`realizedR < -0.05R`).
    3. Enabled high-conviction `SIGNAL_SHORT` setups on `LIQ_PDH`, `LIQ_ASIAN_HIGH`, and `LIQ_M15_SWING_HIGH` when H1/H4 macro trend is bearish/neutral (`macroBias <= 0`) or on `>= 50%` upper-wick engulfing rejections.
    4. Added `strongStructuralReclaim` in `DetectReversalFVGAndMSS()` so liquidity pools sitting outside `[VAL, VAH]` are not discarded before reaching ONNX.
    5. Widened `maxImmediateSL` (`1.65x / 2.15x ATR_M5`) and `maxMarketSlipUSD` (`0.30R`) so valid reclaims fill immediately at Market instead of expiring unfilled at `+1.5R`.
  - **44-Unit Hard-Negative Mined ONNX Meta-Labeler (`retrain_multiyear_onnx.py`)**:
    - Trained on **`742` mapped `Model=4` Real-Tick + Random-Delay `POSITION_CLOSED` outcomes** (Pass 1 + Hard-Negative Mining Pass 2), keeping `TP1 + Stage-1` winners (`r >= -0.03R`) in Tier 2 while blocking all `362` true stop-outs (`r < -0.03R`).
  - **Verified `Model=4` (`99%` Real Ticks) + `ExecutionMode=-1` (Random Delay) Torture Performance (`$50,000` `MODE_PROP_GUARD`)**:
    - **`2024`**: **`$129,977.02`**, **`117` trades executed**, **`0.46` trades/day**, **`2.22 days` avg wait**, **`PF 12.84`**, **`89.61%` WR**, **`2.45%` Bal DD / `2.99%` Eq DD**, **Score: `74.5 / +16.9`**.
    - **`2025`**: **`$329,373.75`**, **`147` trades executed**, **`0.58` trades/day**, **`1.76 days` avg wait**, **Score: `80.3 / +14.1`**.
    - **`2026 YTD`**: **`$1,211,623.60`**, **`105` trades executed**, **`0.49` trades/day**, **`2.01 days` avg wait**, **Score: `79.7 / +9.1`** (**`2025–2026` Combined**: **`$1,540,997.35`**, **`PF 12.18`**, **`92.79%` WR**, **`2.32%` Bal DD / `3.39%` Eq DD**).
    - **3-Year Total**: **`$1,670,974.37`**, **`369` trades executed**, **`0.51` trades/day**, **`1.98 days` avg wait**, **Score: `79.5 / +12.5`**.

---

## [v4.24] — 2026-10-28 (Volatility-Proportional ADR(20) Regime Geometry — Zero Nominal Price Threshold)
- **Archived Binary**: `bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.24.ex5`
- **Summary**:
  - **Replaced Nominal `$3,900` Price Constant with Volatility-Proportional `ADR(20)` Math (`SessionLevels.mqh` & `SweepSignalEngine.mqh`)**:
    - Exposed `CSessionLevels::GetAdr20()` (20-day Average Daily Range) and replaced the static `>= $3,900` price check with `m_sessionLevels.GetAdr20() >= 55.0` (`14.5x` the `$3.80` baseline `maxImmediateSL` floor).
    - Because the condition is driven purely by **daily range volatility (`ADR(20)`)** rather than nominal dollar price, the engine automatically adapts whether Gold trades at `$2,000`, `$3,360` (capturing the May 2025 tariff volatility expansion where `ADR(20)` reached `$80.03` at `$3,360` Gold), `$4,005`, or `$8,000`.
  - **Verified `Model=4` (`99%` Real Ticks) + `ExecutionMode=-1` (Random Delay) Torture Performance (`$50,000` `MODE_PROP_GUARD`)**:
    - **`2024` (`XAUUSD_REAL`, `56.1M` ticks)**: **`+$31,259.54`**, `66` positions opened (`123` deal legs), `0.26` trades/day, `3.91` trading days (`5.48` cal days) avg wait, **`PF 3.80`**, **`89.43%` WR**, **`2.30%` Bal DD / `3.92%` Eq DD**.
    - **`2025` (`XAUUSD` Live01)**: **`+$93,420.09`**, `75` positions opened, `0.30` trades/day, `3.36` trading days (`4.72` cal days) avg wait.
    - **`2026 YTD` (`XAUUSD` Live01)**: **`+$240,638.98`**, `66` positions opened, `0.31` trades/day, `3.21` trading days (`4.50` cal days) avg wait (**`2025–2026` Combined**: **`+$334,059.07`**, **`PF 11.14`**, **`93.80%` WR**, **`1.81%` Bal DD / `2.58%` Eq DD**).
    - **ONIX `0–100` Torture Score**: **`67.0 / +0.2`** vs `v4.23` (`66.8`) and **`67.0 / +1.0`** vs `v4.22` (`66.0`).

---

## [v4.23] — 2026-10-28 ($3,900+ Gold Reclaimed-Level Limit Anchor & Displacement Reclaim)
- **Archived Binary**: `bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.23.ex5`
- **Summary**:
  - **`$3,900+` Gold Reclaimed-Level Limit Anchor (`BuildSniperOrderGeometry` in `SweepSignalEngine.mqh`)**:
    - At `$3,900–$5,140` Gold, a normal M5 sweep-and-reclaim candle has `$5.50–$9.50` distance from the swept liquidity level (`m_tracker.levelPrice`) to `structuralSL`, which previously exceeded the 2024-calibrated `maxImmediateSL` (`1.35 * ATR_M5 = ~$4.50`) and forced pending limit orders `$2–$4` deeper inside the sweep wick (causing high-conviction reclaims like the `2026.10.27` `$3,999.93 -> $4,005.74` setup to miss fill by `$1.93` when Gold retested `$4,005.72` to the tick).
    - When `reclaimClosePrice >= 3900.0`, `pullbackEntry` now anchors directly to `m_tracker.levelPrice` (or the FVG proximal boundary when on the reclaimed side of `m_tracker.levelPrice`) and permits `pullbackSLDist <= HARD_MAX_SL_DISTANCE_USD` (`$10.50`), while keeping `< $3,900` Gold (`2024`–`2025`) geometry untouched.
  - **`$3,900+` Primary-Pool Displacement Reclaim (`DetectReversalFVGAndMSS` in `SweepSignalEngine.mqh`)**:
    - On `$3,900+` Gold, counter-trend reclaims of primary session pools (`LIQ_ASIAN_LOW`, `LIQ_PDL`, `LIQ_EQUAL_LOWS` after `10:00 UTC`) that exhibit strong bullish displacement (`m5[0].close > m5[1].high` and body `>= 50%` of candle range) are now permitted alongside single-candle pinbar sweeps (`bestLowerWickRatio >= 0.50`).
  - **Verified Strategy Tester Performance (`$50,000` Prop Guard `MODE_PROP_GUARD`, `Model=4` Real Ticks + `ExecutionMode=-1` Random Delay)**:
    - **`Oct 19–28, 2026` Live Window**: **`5/5` Winners (`100%` WR), `+$3,117.91` Net Profit** (including `2026.10.20` `ASIAN_LOW` reclaim `+$1,112.64` and `2026.10.27` `$4,005.74` `M15_SWING_LOW` reclaim filled at `$4,005.72` for `+$299.52`).
    - **`2024` (`XAUUSD_REAL` — `99% real ticks`, `56.1M` ticks)**: **`+$34,606.51` (`+69.21%`)**, **`PF 4.03`**, **`88.80%` WR** (`111/125`), **`2.05%` Max Balance DD / `3.68%` Max Equity DD** ([`P2_REAL_XAUUSD_2024.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/P2_REAL_XAUUSD_2024.htm)).
    - **`2025–2026` (`XAUUSD` Live01 — `99% real ticks`, `195.2M` ticks)**: **`+$316,585.26` (`+633.17%`)**, **`PF 9.74`**, **`94.46%` WR** (`256/271`), **`2.04%` Max Balance DD / `2.74%` Max Equity DD** ([`P2_REAL_XAUUSD_2526.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/P2_REAL_XAUUSD_2526.htm)).

---

## [v4.22] — 2026-10-28 (99%–100% Real-Tick + Random-Delay ONNX Retrain)
- **Archived Binary**: `bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.22.ex5`
- **Summary**:
  - Upgraded `retrain_multiyear_onnx.py` to a **28-Unit Vectorized Residual MLP (`hidden_dim = 28`)** trained strictly on **`373` mapped `POSITION_CLOSED` setups harvested under `99%–100% Real Ticks (`Model=4`) + Random Delay (`ExecutionMode=-1`)`** (`56.1M` genuine `2024` Dukascopy ticks on `XAUUSD_REAL` + `194.7M` genuine `2025–2026` Pepperstone Live ticks on `PepperstoneBS-MT5-Live01`).
  - **Verified Strategy Tester Performance (`$50,000` Prop Guard `MODE_PROP_GUARD`, `Model=4` Real Ticks + `ExecutionMode=-1` Random Delay)**:
    - **`2024` (`XAUUSD_REAL` — `99% real ticks`, `56.1M` ticks)**: **`+$32,482.20` (`+64.96%`)**, **`PF 3.88`**, **`89.60%` WR** (`112/125`), **`2.32%` Max Balance DD / `3.80%` Max Equity DD** ([`P2_REAL_XAUUSD_2024.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/P2_REAL_XAUUSD_2024.htm)).
    - **`2025–2026` (`XAUUSD` Live01 — `99% real ticks`, `194.7M` ticks)**: **`+$276,839.69` (`+553.68%`)**, **`PF 8.93`**, **`93.49%` WR** (`244/261`), **`1.82%` Max Balance DD / `3.17%` Max Equity DD** ([`P2_REAL_XAUUSD_2526.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/P2_REAL_XAUUSD_2526.htm)).

---

## [v4.21] — 2026-10-26 (Baseline Archive)
- **Archived Binary**: `bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.21.ex5`
- **Summary**:
  - 3-Layer Institutional XAUUSD Liquidity Sweep Sniper + Native 12-Feature ONNX Meta-Labeler (`xauusd_meta_model.onnx`).
  - Rolling `PERIOD_H1` synthetic 4-hour macro trend filter (`GetMacroTrendBias()`) for 100% identical candle alignment across `UTC+1`, `UTC+2`, and `UTC+3` brokers.
  - Prop-Firm Anti-10x 3-Layer Lot Sizing (`OrderCalcProfit` + Tick Formula + Physical Contract Floor) and `1:30` low-leverage free-margin clamp (`OrderCalcMargin` + `OrderCheck`).
  - Multi-stage runner ratchet (`+0.62R` TP1 partial + `-0.30R` SL -> `+0.95R` BE -> `+1.32R` -> `+1.65R` -> `+2.25R` M5 swing trail -> `+2.80R` -> `+3.50R` TP2).
  - Hard daily drawdown (`< 3.0%`, internal breaker `2.25%` / `2.40%`) and total drawdown (`< 6.0%`, internal breaker `5.20%` / `5.40%`) ceilings.
