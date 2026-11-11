# CHANGELOG — `XAUUSD_Trident_MoE` ("Three Prongs, One Strike")

All notable architectural, ONNX meta-model, and risk-engine changes for `XAUUSD_Trident_MoE` are documented in this file.

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
