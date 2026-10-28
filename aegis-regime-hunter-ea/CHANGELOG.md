# Changelog — `aegis_regime_hunter_ea` (XAUUSD Regime Hunter Breakout EA)

All notable changes to `aegis_regime_hunter_ea` are documented in this file.
Archived version-stamped binaries are stored in [`/bin/aegis_regime_hunter_ea/`](../bin/aegis_regime_hunter_ea/).

---

## [v4.00] — 2026-10-26
- **Archived Binary**: `bin/aegis_regime_hunter_ea/aegis_regime_hunter_ea_v4.00.ex5`
- **Verified Benchmark (`2025–2026` `$50k` Prop Mode, `Model=4` Real Ticks + `ExecutionMode=-1` Random Delay)**:
  - **Total Net Profit**: **`+$62,373.24` (`+124.75%`)** (vs `+$47,135.43` in `v3.53`, **`+32.3%` higher return**)
  - **Profit Factor**: **`1.83`** (vs `1.77` in `v3.53`)
  - **Average Profit Trade**: **`+$940.52`** (vs `+$715.02` in `v3.53`)
  - **Prop Compliance**: **`0` breaches across all 4 daily reset conventions** (`-2.28%` worst server/NY/CET day, `-2.38%` worst UTC day vs `-3.00%` limit; `0.86%` buffer above the `6.00%` trailing floor).
- **Summary of Architectural Upgrades**:
  1. **Asymmetric Bull/Bear H4 Regime Filter (`OnNewBar()`)**:
     - Preserves full sensitivity for `LONG` breakouts (`tr_close > EMA20 > EMA50` and `g_stretch < 6.0`), while requiring genuine macro bearish displacement for `SHORT` breakouts (`(EMA50 - EMA20) >= 0.55 * H4_ATR` and `1.15 <= g_stretch < 4.50`). Filters out shallow bull-market dip fakeouts while still capturing real crash months (`2026.03 +$8,652` and `2026.06 +$9,418`).
  2. **London Open (`07:00 UTC`) + NY Data-Hour (`13:00 UTC`) Session Range Breakouts (`LonSignal()` & `NySignal()`)**:
     - Added `LonSignal()` (`07:00–08:00 UTC` range breakout during `08:00–11:00 UTC`) alongside `NySignal()` (`13:00–14:00 UTC` range breakout), doubling the daily high-R tight-stop institutional range-expansion opportunities.
  3. **Earlier 2nd-Unit Pyramid Unlock (`+4.2 ATR` Breakeven Lock in `ManageOnBarClose()`)**:
     - Moves Unit 1's Stop Loss to `open +/- 0.05 * ATR` (risk-free) once a closed M15 bar reaches `>= +4.2 ATR` (instead of waiting for `+5.0 ATR`), keeping `> 4.15 ATR` of breathing room so the `5.0 ATR` Chandelier runner is never choked early while unlocking Unit 2 pyramiding faster.
  4. **Upgraded Prop Velocity Sizing (`3.2x` Room Governor + `0.90%` Default Prop Risk)**:
     - Relaxed `ROOM_DIVISOR` from `4.0` to `3.2` with `InpPropRiskPercent = 0.90%` and anti-Zeno `0.01` lot recovery, cutting challenge pass times down to `5d` (`2025.02`), `9d` (`2025.09`), `11d` (`2026.06`), `14d` (`2025.10`), `19d` (`2025.03`, `2026.03`) and flipping `2025.05` (`-$1,329 -> +$1,423`) and `2026.04` (`-$305 -> +$1,125`) from red to green.
  5. **Strict 120-Second Minimum Hold Guard (`ReanchorToFill()` & `GuardOpenGiveback()`)**:
     - Enforced `>= 120s` hold check before discretionary closes in both `ReanchorToFill()` and `GuardOpenGiveback()`.

---

## [v3.53] — 2026-10-26 (Baseline Archive)
- **Archived Binary**: `bin/aegis_regime_hunter_ea/aegis_regime_hunter_ea_v3.53.ex5`
- **Summary**:
  - Original Goldie Service `Aegis v3.53` XAUUSD M15 12h Donchian + 13:00 UTC NY range breakout EA with H4 EMA(20/50) trend filter, `3.0 ATR` SL, `8.0R` TP, `5.0 ATR` Chandelier trail, and 2-unit pyramiding.
