# Changelog — `USDJPY_Sniper_ONNX`

All notable changes to `USDJPY_Sniper_ONNX` are documented in this file.
Archived version-stamped binaries are stored in [`/bin/`](../bin/).

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
