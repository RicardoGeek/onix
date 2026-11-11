# `XAUUSD_Trident_MoE` — 3-Prong Mixture-of-Experts Master EA ("Three Prongs, One Strike")

`XAUUSD_Trident_MoE` (`v1.00`) is the flagship Mixture-of-Experts (MoE) Expert Advisor for `XAUUSD`, uniting **3 strictly orthogonal regime specialists** inside a single `.ex5` binary with **3 embedded `#resource` ONNX Meta-Labelers** (`100%` trained on `2017–2023` SEEN data and verified on `2024–2026` Unseen Out-of-Sample).

---

## 1. The 3 Orthogonal Prongs & Hourly AI Regime Router

| Prong | Market Corner | Regime Activation Rule | Embedded ONNX Model | Magic Number & Tag |
| :--- | :--- | :--- | :--- | :--- |
| **Prong #1: `Sniper`** | **Corner #1: Killzone Stop-Hunt Reversals** | Active during London (`06:30–10:55 UTC`) & NY (`12:00–15:55 UTC`) Killzones on M15/Session liquidity sweeps + M1 Volume Profile absorption. | `xauusd_meta_model.onnx` (`float32[1,12]`) | `20260401` (`"Sniper"`) |
| **Prong #2: `16Runes`** | **Corner #2: Macro Stacked-EMA Trend Coils** | Active when `H4` 7-EMA stack aligns with `D1` stack (and `H1` stack on `M15/M5`). Trades 16 structural chart patterns across `H1, H2, M30, M15, M5`. | `16runes_meta.onnx` (`float32[1,16]`) | `16016001` (`"P2_R16_..."`) |
| **Prong #3: `ImpulseCascade`** | **Corner #4: Fast Crash & V-Reversal Cascades** | Active **strictly when Prong #2 (`16Runes`) is `OFF` (`GateDir == 0`)** AND `H4` Top-3 EMA stack == `H1` Top-5 EMA stack AND `H1 VolRegime >= 0.85`. | `impulse_cascade_meta.onnx` (`float32[1,16]`) | `16016004` (`"P3_CAS_..."`) |
| **Corner #3: `Tangled Chop`** | **Dead-Flat Tangled Macro Chop** | Both `GateDir == 0` and `GateCascadeDir == 0` outside Killzone sweeps -> **All 3 Prongs sit out** to protect capital and keep the slot free for Prong #1. | — | — |

---

## 2. Included `.set` Presets (`MQL5/Presets/`)

1. **`XAUUSD_Trident_MoE_50k_Prop_Full3Prong.set`**: All 3 Prongs `ON` (`InpEnableProng1_Sniper=true`, `InpEnableProng2_16Runes=true`, `InpEnableProng3_Cascade=true`) — full 3-Prong Mixture-of-Experts harmonization on a single `XAUUSD M5` chart.
2. **`XAUUSD_Trident_MoE_Prong1_Sniper_Solo.set`**: Prong #1 (`Sniper`) Solo.
3. **`XAUUSD_Trident_MoE_Prong2_16Runes_Solo.set`**: Prong #2 (`16Runes`) Solo.
4. **`XAUUSD_Trident_MoE_Prong3_Cascade_Solo.set`**: Prong #3 (`ImpulseCascade`) Solo.
