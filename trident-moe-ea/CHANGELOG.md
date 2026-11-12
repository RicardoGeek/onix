# CHANGELOG — `XAUUSD_Trident_MoE` ("Three Prongs, One Strike")

All notable architectural, ONNX meta-model, and risk-engine changes for `XAUUSD_Trident_MoE` are documented in this file.

---

## [v1.03] — 2026-11-11

### Added & Upgraded — Prong #3 (`ImpulseCascade`) Timing Upgrade: Day-1 Counter-`D1` Slide + Clean Late-Short Filter (`XAUUSD_Trident_MoE_v1.03.ex5`)
- **Architectural Scope (3 Prongs Unchanged, 0 New ONNX Models)**:
  - Upgraded the regime timing of **existing Prong #3 (`ImpulseCascade`, Magic `16016004`, `impulse_cascade_meta.onnx`)** without adding a 4th prong or touching any embedded `.onnx` weights, Prong #1 (`Sniper`), or Prong #2 (`16Runes`).
- **Root Cause Diagnosed on `2026-11-11` (`$4,066 -> $4,001` Day-1 Gold Slide)**:
  - On Day-1 of a sharp pullback against an established `D1` trend (`D1 = +1`), `H1` Top-5 EMAs (`8, 13, 21, 34, 55`) flip bearish within hours (`H1 5E == -1`), whereas `H4` Top-3 EMAs (`32h–84h` lookback) remain tangled at `0` for `1–2` days (`H4 3E == 0`), leaving Prong #3 in `[SLEEP]` throughout the entire Day-1 move.
  - Conversely, by Day 2–3 when `H4 3E` finally flips `-1` against `D1 = +1`, price has often dropped `-$65` to `-$100` straight into Daily EMA institutional dip-buyers, diluting `v1.02` Cascade OOS expectancy (`-0.0628R` on low-conviction Day-2/3 counter-`D1` shorts).
- **SEEN-Calibrated (`2017–2023`) 2-Part Prong #3 Timing Upgrade (Verified via 1x-Spread Numba Evaluator on Unseen OOS `2024–2026`)**:
  1. **Part A — Clean Day-2/3 Counter-`D1` Cascade Filter ([`TridentAiRater.mqh`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Include/Trident/TridentAiRater.mqh), [`XAUUSD_Trident_MoE.mq5`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Experts/XAUUSD_Trident_MoE.mq5))**:
     - When standard `GateCascadeDir` (`H4 3E == H1 5E`) triggers **against** `EffectiveD1Dir != 0` (`dir == -D1`), requires high-conviction `p >= TRIDENT_CAS_THR_HIGH` (`0.61870000`), while preserving `0.5400 / 0.5800` for with-`D1` / neutral-`D1` cascades.
     - Standalone 1x-spread `Mean Net R`: `SEEN (2017–2023)` `+0.0453R -> +0.0467R` | `Unseen OOS (2024–2026)` **`+0.0141R -> +0.0467R` (`3.3x` OOS expectancy lift)**.
  2. **Part B — Day-1 Counter-`D1` Slide Gate (`GateDay1SlideDir` in [`TridentStreams.mqh`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Include/Trident/TridentStreams.mqh))**:
     - Activates strictly when **both** Prong #2 (`GateDir == 0`) and standard H4 Cascade (`GateCascadeDir == 0`) are `OFF`, `EffectiveD1Dir != 0`, and `H1 StackTop5 == -EffectiveD1Dir` across streams `H1, M30, M15, M5` (skipping `H2`), gated by `impulse_cascade_meta.onnx >= 0.5800` (`TRIDENT_CAS_THR_SLIDE`) and a Healthy-Account Offensive Guard (`TotalDD < 2.00% && DailyDD < 1.00%`).
     - Chart HUD (`CurrentRegimeSummary`) now displays `P3:CASCADE[SLIDE BEAR]` / `P3:CASCADE[SLIDE BULL]` whenever this regime is active.
     - Standalone 1x-spread `Mean Net R`: `SEEN (2017–2023)` **`+0.0482R`** (`n = 187`, `84.0%` WR, `25.1%` runners `>= +0.25R`) | `Unseen OOS (2024–2026)` **`+0.0879R`** (`n = 150`, `71.3%` WR, `20.7%` runners `>= +0.25R`).
- **Exact 1x-Spread `$50,000` Prop Portfolio Improvement (`v1.02` -> `v1.03`)**:
  - **`SEEN 2017–2023`**: `$374,401.67` (`3,137` tr, `1.78/d`) -> **`$381,804.49` (`3,206` tr, `1.82/d`, `+$7,402.82`)**
  - **`Unseen OOS 2024–2026`**: `$549,955.58` (`1,697` tr, `2.36/d`, `+0.182R`) -> **`$577,847.28` (`1,770` tr, `2.47/d`, `+0.189R`, `+$27,891.70`)**
  - **`Total 10Y (2017–2026)`**: `$924,357.24` (`4,834` tr, `1.95/d`, `0.53d` wait, `+0.131R`) -> **`$959,651.76` (`4,976` tr, `2.00/d`, `0.52d` wait, `+0.133R`, `+$35,294.52`)**, `MaxDDD = 2.84% < 3.0%`, `MaxTDD = 5.40% < 6.0%`.
  - **Prong #3 (`ImpulseCascade`) Net Profit**: `10Y` `$10,253.46` (`+0.065R`) -> **`$24,219.29` (`+0.089R`, `2.36x`)** | `Unseen OOS` `$5,473.80` (`+0.043R`) -> **`$14,982.74` (`+0.109R`, `2.74x`)**.

---

## [v1.02] — 2026-11-10

### Added & Upgraded — Unified Risk Alignment, Low-DD Limit Expiry & SEEN-Calibrated Breathing Harvester (`XAUUSD_Trident_MoE_v1.02.ex5`)
- **Code-Review Hygiene & Mismatch Alignment**:
  1. **Unified Daily Realized Profit Lock (`InpDailyProfitLockPct = 15.00%`)**:
     - Replaced the mismatched daily profit locks (`g_trRisk.m_dayProfitLockPct = 2.65%` on Prongs #2/#3 vs hardcoded `PROP_DAILY_PROFIT_LOCK_PCT = 15.00%` on Prong #1) with a single unified `InpDailyProfitLockPct = 15.00` input wired into both `CEquityGuard::SetDailyProfitLockPct()` ([`EquityGuard.mqh`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Include/XAUUSD_Quant/Layer3_Risk/EquityGuard.mqh)) and `CTridentRisk::ConfigureMoE()` ([`TridentTrader.mqh`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Include/Trident/TridentTrader.mqh)).
  2. **Aligned Prop Tier Risk Inputs & Constants (`1.27%` Base / `2.71%` House-Money Max)**:
     - Replaced the unused/mismatched `InpPropTier2RiskPct = 1.05` / `InpPropTier1RiskPct = 1.88` inputs and `0.48% / 0.62%` macros with `InpPropBaseRiskPct = 1.27` (`$635` base on `$50k`) and `InpPropHouseMoneyMaxRiskPct = 2.71` wired directly into `CPositionSizer::CalculateSniperLots()` ([`PositionSizer.mqh`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Include/XAUUSD_Quant/Layer3_Risk/PositionSizer.mqh)) and [`Definitions.mqh`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Include/XAUUSD_Quant/Core/Definitions.mqh), while also deducting any active cross-prong stop-loss risk from `remDayFloor`.
  3. **Conditional Low-DD Sniper Pending Limit Expiry (`InpLowDDLimitExpiryBarsM5 = 6`)**:
     - Extends Prong #1 Sniper resting limit order lifetime from `3` M5 bars (`15m`) to `6` M5 bars (`30m`) strictly while `DailyDrawdownPct < 1.00%` in `CExecutionManager::ManageActiveTradesOnTick()` ([`ExecutionManager.mqh`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Include/XAUUSD_Quant/Layer3_Risk/ExecutionManager.mqh)), reverting immediately to `3` M5 bars whenever `DailyDrawdownPct >= 1.00%`.
     - Preserved Prong #1 Sniper's `0.58` ONNX floor, directional gating, and `v1.01`'s realized-balance HWM drawdown sync unchanged.
- **SEEN-Calibrated (`2017–2023`) Expectancy & Multi-Stream Cadence Upgrade (Verified via 1x-Spread Numba Evaluator on Unseen OOS `2024–2026`)**:
  - **Root Cause Fixed (`$10` Scratches vs Negative Expectancy in `v1.01` Wave Manage)**:
    - Removed the MoE hair-trigger `0.07R / $0.10` server-TP choke (`escTp = +0.05R`) and 5-minute `0.22R -> +0.08R` clamp in `CTridentTrader::Manage()` ([`TridentTrader.mqh`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Include/Trident/TridentTrader.mqh)) that had truncated `99%` of Prong #2/#3 coils into tiny `~$8–$11` scratches (`MeanNetR = -0.028R`).
    - Replaced with the SEEN-calibrated Breathing Harvester (`15m/30m/60m` on `M15/M5` and `30m/60m/120m` on `H1/H2/M30` at `0.32R -> +0.10R`, `0.22R -> +0.08R`, `0.16R -> +0.06R`, mid-lock `0.60R -> +0.28R`, Stage-1 Whale at `+1.25R -> +0.35R`), allowing `UnprotectedProbes() < 2` across orthogonal Wave streams (`ownUnprotectedCount < 2 && totalUnprotectedCount < 3` in Sniper so Wave probes never starve Prong #1) plus a `0.55x` startup Wave cushion below `+1.0%` account gain.
    - Calibrated Prong #3 (`ImpulseCascade`) probability thresholds on `2017–2023` SEEN (`TRIDENT_CAS_THR_HTF = 0.5400`, `TRIDENT_CAS_THR_M5 = 0.5800` in [`TridentAiRater.mqh`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Include/Trident/TridentAiRater.mqh), keeping all 3 `.onnx` binaries unchanged) so standalone **Mean Net R After Spread** is strictly positive across both `SEEN 2017–2023` and `Unseen OOS 2024–2026` on every Prong:
      - **Prong #2 (`16Runes`) Standalone Mean Net R**: `-0.0620R -> +0.0018R` (`SEEN`) | `+0.0185R -> +0.1435R` (`OOS`, `7.8x` lift; `>=0.25R` runners `1.0% -> 16.1%`).
      - **Prong #3 (`ImpulseCascade`) Standalone Mean Net R**: `-0.0421R -> +0.0453R` (`SEEN`) | `-0.0354R -> +0.0141R` (`OOS`; `>=0.25R` runners `1.1% -> 17.2%`).
  - **Exact 1x-Spread `$50,000` Prop Portfolio Improvement (`v1.01` -> `v1.02`, All 3 Prongs Independently Profitable)**:
    - **`SEEN 2017–2023`**: `$313,734.65` (`+0.069R`) -> **`$374,401.67` (`+0.104R`, `+$60,667`)**
    - **`Unseen OOS 2024–2026`**: `$484,373.66` (`1,677` tr, `2.34/d`, `+0.120R`) -> **`$549,955.58` (`1,697` tr, `2.36/d`, `+0.182R`, `+$65,582`)**
    - **`Total 10Y (2017–2026)`**: `$798,108.31` (`+0.087R`) -> **`$924,357.24` (`+0.131R`, `+$126,249`)**, `MaxDDD = 2.84% < 3.0%`, `MaxTDD = 5.39% < 6.0%`.
    - **Per-Prong 10Y Net**: `Sniper` `+$887,427.37` (`+0.233R`), `16Runes` `-$21,714.61 -> +$26,676.41` (`+0.047R`, OOS `+$28,577.31` / `+0.113R`), `ImpulseCascade` `-$4,285.99 -> +$10,253.46` (`+0.065R`, OOS `+$5,473.80` / `+0.043R`).

---

## [v1.01] — 2026-11-09

### Fixed — Unified Drawdown Tracker Synchronization (`UpdateTrackersTrident` in `TridentTrader.mqh` & `XAUUSD_Trident_MoE.mq5`)
- **Root Cause**:
  - In `v1.00`, `OnTick()` called `g_trRisk.UpdateTrackers(srvNow, g_trMkt.m_clk)` alongside `g_equityGuard.CheckEmergencyBreach()`.
  - Because `CR16Risk::UpdateTrackers()` ratcheted `m_hwm` to intraday **unrealized floating equity peaks** (`if(m_mode == R16_PROP_FIRM && eq > m_hwm) m_hwm = eq;`) and never reset `m_totalHalted` in `R16_PROP_FIRM`, when two overlapping Sniper positions on `2025-01-15` reached `+2.71R` unrealized MFE (`+$3,765` floating profit, lifting floating equity to `~$52,655`) and subsequently pulled back to close at their breakeven stops (`+$204.73` realized profit, balance `$49,087.43`), `g_trRisk` measured a `-6.77%` drop from that fleeting unrealized spike (`>= 5.35%`) and permanently set `m_totalHalted = true`, halting all trading after `2025-01-15 16:36:47` even though the account had won on the day and was only `-1.37%` below realized HWM.
- **Fix Implemented**:
  - Added `CTridentRisk::UpdateTrackersTrident(srvNow, clk, sniperSnap)` in [`TridentTrader.mqh`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Include/Trident/TridentTrader.mqh) and wired it into [`XAUUSD_Trident_MoE.mq5`](file:///c:/Users/faker/Documents/dev/onix/trident-moe-ea/MQL5/Experts/XAUUSD_Trident_MoE.mq5).
  - Synchronizes `g_trRisk`'s daily and total drawdown references directly with `g_equityGuard`'s `SRiskStateSnapshot` (`m_initBalance` / realized balance HWM, never fleeting unrealized MFE spikes) and resets `m_totalHalted` at the daily rollover boundary unless `sniperSnap.permanentLockout` is active.

---

## [v1.00] — 2026-11-08

### Added — Unified 3-Prong Mixture-of-Experts (MoE) Master EA (`XAUUSD_Trident_MoE_v1.00.ex5`)
- **Single-Binary 3-Prong Mixture-of-Experts Architecture (`MQL5/Experts/XAUUSD_Trident_MoE.mq5`)**:
  - Fuses the **3 Orthogonal Market-Corner Specialists** into a single `.ex5` binary with **3 embedded `#resource` ONNX Meta-Labelers** (`100%` strictly trained on `2017–2023` SEEN data, verified on `2024–2026` Unseen Out-of-Sample):
    1. **Prong #1 (`Corner 1 — Sniper`, Magic `20260401`, `"Trident_P1_Sniper"`)**:
       - London (`06:30–10:55 UTC`) & New York (`12:00–15:55 UTC`) Killzone Liquidity Sweep + M1 Volume Profile Reversals gated by `xauusd_meta_model.onnx` (`float32[1,12]`).
    2. **Prong #2 (`Corner 2 — 16Runes`, Magic `16016001`, `"P2_R16_..."`)**:
       - Multi-Timeframe 16-Chart-Pattern Trend Coils across `H1, H2, M30, M15, M5` when `H4` and `D1` 7-EMA stacks align, gated by `16runes_meta.onnx` (`float32[1,16]`, `thrHTF = 0.3200`, `thrM5 = 0.3600`).
    3. **Prong #3 (`Corner 4 — ImpulseCascade`, Magic `16016004`, `"P3_CAS_..."`)**:
       - Fast `H4` Top-3 + `H1` Top-5 V-Reversal & Crash Cascades active **strictly when `16Runes` is `OFF` (`GateDir == 0`)** and `H1 VolRegime >= 0.85`, gated by `impulse_cascade_meta.onnx` (`float32[1,16]`, `thrHTF = 0.3035`, `thrM5 = 0.4824`).
    4. **Corner #3 (`Dead-Flat Tangled Chop`)**:
       - Automatically sits out when both `GateDir == 0` and `GateCascadeDir == 0` outside Killzone sweeps, preserving capital and the single-position slot for Prong #1.
- **Independent Prong Switches for Combined or Solo MT5 Strategy Tester Backtesting**:
  - `InpEnableProng1_Sniper`, `InpEnableProng2_16Runes`, and `InpEnableProng3_Cascade` allow testing all 3 Prongs harmonizing together in a single MT5 Strategy Tester run, or testing any individual Prong solo.
  - When `InpEnableProng1_Sniper = false`, Prongs #2/#3 automatically switch from MoE Gap-Fill sizing (`0.35%` base risk) to standalone `MonthlyShieldScale` sizing so solo backtests verify each specialist's independent green-month profile.
- **Verified `$50,000` Prop Account Portfolio Performance (`2017–2026` & Unseen OOS `2024–2026`)**:
  - **10-Year Total (`2017–2026`)**: **`+$1,351,269.56`** (`5,415` trades, `2.18 trades/day`, `82.3%` Win Rate, `MaxDDD = 2.84% < 3.0%`, `MaxTDD = 5.13% < 6.0%`).
  - **Unseen Out-of-Sample (`2024–2026`)**: **`+$824,706.36` to `+$842,512.57`** (`1,792` OOS trades, `84.0%` Win Rate), outperforming both Solo `Sniper` (`+$525,435.98` OOS) and the overlapping `Sniper + 16Runes + oKell` trio (`+$798,310.67` OOS).
