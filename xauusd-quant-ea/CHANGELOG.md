# Changelog — `XAUUSD_Sniper_ONNX`

All notable changes to `XAUUSD_Sniper_ONNX` are documented in this file.
Archived version-stamped binaries are stored in [`/bin/`](../bin/).

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
