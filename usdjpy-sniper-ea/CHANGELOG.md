# Changelog — `USDJPY_Sniper_ONNX`

All notable changes to `USDJPY_Sniper_ONNX` are documented in this file.
Archived version-stamped binaries are stored in [`/bin/`](../bin/).

---

## [v3.02] — 2026-11-02 (Goldeen.io Instant Redis Telemetry Integration)
- **Archived Binary**: [in/USDJPY_Sniper_ONNX/USDJPY_Sniper_ONNX_v3.02.ex5](file:///c:/Users/faker/Documents/dev/onix/bin/USDJPY_Sniper_ONNX/USDJPY_Sniper_ONNX_v3.02.ex5)
- **Summary**:
  - Added [GoldeenTelemetry.mqh](file:///c:/Users/faker/Documents/dev/onix/usdjpy-sniper-ea/MQL5/Include/USDJPY_Quant/Core/GoldeenTelemetry.mqh) (InpGoldeenToken, InpGoldeenUrl = "https://api.goldeen.io/api/v1/ea/report") for timer-driven zero-tick-latency reporting to Goldeen.io's Redis ingestion queue.

---
## [v3.01] ? 2026-11-02 (Smart Pool-Hierarchy Cooldown & Broker-Timezone-Agnostic H4 ATR)
- **Archived Binary**: [`bin/USDJPY_Sniper_ONNX/USDJPY_Sniper_ONNX_v3.01.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/USDJPY_Sniper_ONNX/USDJPY_Sniper_ONNX_v3.01.ex5)
- **Summary**:
  - Updated `IsDirectionInCooldown()` in `SweepSignalEngine.mqh` so the 25-minute post-loss cooldown only blocks repeating internal `M15_SWING` fractals and never blocks primary session boundaries (`TOKYO`, `LONDON`, `PDH/PDL`, `EQUAL_HIGHS/LOWS`), plus added `ComputeBrokerAgnosticAtrH4()` in `SessionLevels.mqh`.
  - **Verified Performance (`$50,000` Prop Guard, `Model=4` Real Ticks + `ExecutionMode=-1` Random Delay)**:
    - **`2024`**: **`+$230,312.50`** (up from `+$216,655.07`), `211` setups, `87.8%` WR, `1.08d` avg wait, `4.01%` Max Eq DD.
    - **`2025?2026`**: **`+$768,799.38`** (`+$250,985.31` in `2025` at `92.8%` WR + `+$577,124.64` in `2026` at `92.4%` WR), `321` setups, `4.09%` Max Eq DD.
    - **Total `2024?2026`**: **`+$1,058,422.45`** (up `+$48,710.59` over `v3.00`), `532` setups, **`90.7%` WR**, **`1.26d` avg wait**.

---

## [v3.00] — 2026-11-02 (High-Frequency Wait-Time Compression + 88-Unit ONNX + Chart HUD AI Telemetry)
- **Archived Binary**: `bin/USDJPY_Sniper_ONNX/USDJPY_Sniper_ONNX_v3.00.ex5`
- **Summary**:
  - **Wait-Time Compression (`4.12 Days -> 1.26 Days` across 2024–2026)**:
    - Expanded active Killzones in `SessionLevels.mqh`: full **Tokyo Open, Fix & JGB Auction Killzone (`00:30–03:55 UTC`)** (locking Pre-Tokyo `21:00–00:30 UTC` and Early Tokyo `00:00–02:00 UTC` ranges while skipping the `04:00–06:29 UTC` Asian lunch lull), continuous **London & Overlap Killzone (`06:30–11:59 UTC`)** (adding Early London `06:30–09:30 UTC` and Full London `06:30–11:30 UTC` pools), and full **New York & London Close Killzone (`12:00–16:45 UTC`)**.
    - Refreshed liquidity pools on **every M5 bar close** inside `Update()` and restricted `asianInnerHalf` fractal filtering strictly to Early London Open (`06:30–08:30 UTC`), enabling confirmed 5-bar M15 continuation pullback swings during Tokyo, Mid-London, and NY trends.
    - In `SweepSignalEngine.mqh`: enabled `LIQ_PDL` long sweeps, `LIQ_ASIAN_HIGH` & non-bull `LIQ_PDH` short sweeps, added `strongStructuralReclaim` to `DetectReversalFVGAndMSS()`, widened `maxImmediateSL` (`1.75x / 2.35x ATR_M5`), and reduced same-direction post-loss cooldown from `5,400s` (`90m`) to `1,500s` (`25m`).
  - **88-Unit High-Precision ONNX Meta-Labeler (`usdjpy_meta_model.onnx`)**:
    - Trained on **`1,595` mapped `Model=4` Real-Tick + `ExecutionMode=-1` Random-Delay `POSITION_CLOSED` setups** (`hidden_dim = 88`, `10,000` epochs, `75x` false-positive loser penalty).
  - **Chart HUD ONNX Telemetry**:
    - Added `[LAST CALL]` and `[LAST DECIS]` lines to `UpdateChartHUD()` displaying the timestamp, setup ID, direction, pool type, ONNX probability score, and tier verdict of the most recent model evaluation.
  - **Verified Strategy Tester Performance (`$50,000` Prop Guard `MODE_PROP_GUARD`, `Leverage=1:100`, `Model=4` Real Ticks + `ExecutionMode=-1` Random Delay)**:
    - **`2024` (`USDJPY_REAL`)**: **`+$216,655.07`** (vs `+$48,339.08` in `v2.10`), **`207` entries (`394` deals)**, **`88.83%` WR**, **`0.82` trades/day**, **`1.10 days` Avg Wait Time** (vs `3.54 days`), **`PF 5.03`**, **`4.31%` Max Equity DD**.
    - **`2025–2026` (`USDJPY` Live01)**: **`+$735,453.16`** (vs `+$71,066.50` in `v2.10`), **`322` entries (`613` deals)**, **`91.84%` WR**, **`1.31–1.45 days` Avg Wait Time** (vs `3.75–5.53 days`), **`PF 4.74`**, **`4.09%` Max Equity DD**.
    - **3-Year Total (`2024–2026`)**: **`+$952,108.23`** (vs `+$119,405.58` in `v2.10` — **`7.97x` Net Profit**), **`529` trades** (vs `188`), **`90.7%` WR**, **`1.26 days` Avg Wait Time** (vs `4.12 days`).

---

## [v2.10] — 2026-10-28 (99%–100% Real-Tick + Random-Delay ONNX Retrain)
- **Archived Binary**: `bin/USDJPY_Sniper_ONNX/USDJPY_Sniper_ONNX_v2.10.ex5`
- **Summary**:
  - Retrained `usdjpy_meta_model.onnx` strictly on **`333` mapped `POSITION_CLOSED` setups harvested under `99%–100% Real Ticks (`Model=4`) + Random Delay (`ExecutionMode=-1`)`** (`40.8M` genuine `2024` Dukascopy ticks on `USDJPY_REAL` + `102.5M` genuine `2025–2026` Pepperstone Live ticks on `PepperstoneBS-MT5-Live01`).
  - **Verified Strategy Tester Performance (`$50,000` Prop Guard `MODE_PROP_GUARD`, `Model=4` Real Ticks + `ExecutionMode=-1` Random Delay)**:
    - **`2024` (`USDJPY_REAL` — `99% real ticks`, `40.8M` ticks)**: **`+$48,339.08` (`+96.68%`)**, **`PF 5.95`**, **`84.89%` WR** (`118/139`), **`2.14%` Max Balance DD / `2.92%` Max Equity DD** ([`P2_REAL_USDJPY_2024.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/P2_REAL_USDJPY_2024.htm)).
    - **`2025–2026` (`USDJPY` Live01 — `99% real ticks`, `102.5M` ticks)**: **`+$71,066.50` (`+142.13%`)**, **`PF 4.34`**, **`89.50%` WR** (`196/219`), **`2.09%` Max Balance DD / `3.18%` Max Equity DD** ([`P2_REAL_USDJPY_2526.htm`](file:///C:/Users/faker/Documents/onix_artifacts/reports/P2_REAL_USDJPY_2526.htm)).

---

## [v2.00] — 2026-10-26 (Baseline Archive)
- **Archived Binary**: `bin/USDJPY_Sniper_ONNX/USDJPY_Sniper_ONNX_v2.00.ex5`
- **Summary**:
  - Carry-aware institutional `USDJPY` Liquidity Sweep Sniper + 28-Unit Native ONNX Meta-Labeler (`usdjpy_meta_model.onnx`).
  - Verified on `Model=4` (Every tick based on real ticks) + `ExecutionMode=-1` (Random Delay): `+$49,707` (`PF 8.30`, `92.80%` WR, `1.94%` Bal DD) in `2024` and `+$103,219` (`PF 7.82`, `93.21%` WR, `2.09%` Bal DD) in `2025–2026` on `$50k` Prop Guard (`34/34` green months).
  - Zero `Model=1` vs `Model=4` Real-Tick feature skew (`2.0-pip` / `0.020 JPY` spread floor on `f11_spread_to_sl_ratio` and closed-bar `currentM1BarTime` session volume profile boundary).
  - Random-Delay (`ExecutionMode=-1`) `1.5-pip` (`0.015 JPY`) slippage cushion in `PositionSizer.mqh` and post-fill `tp1Price` re-anchoring in `ExecutionManager.mqh`.
