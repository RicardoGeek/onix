# Changelog — `chrysalis_ea` (XAUUSD Moonshot EA)

All notable changes to `chrysalis_ea` are documented in this file.
Archived version-stamped binaries are stored in [`/bin/`](../bin/).

---

## [v3.00] — 2026-10-26 (9-Module Supernova Moonshot & Zero-Interference Drought-Breaker Edition)
- **Archived Binary**: `bin/xauusd_chrysalis_ea/chrysalis_ea_v3.00.ex5`
- **Summary**:
  - **Expanded 9-Module H1 Unbroken Swing Matrix (`S1–S9`)**:
    - Added 4 inner-swing Drought-Breaker modules (`S1: 18/9 @ 0.32% TP`, `S2: 20/10 @ 0.34% TP`, `S3: 22/11 @ 0.36% TP`, `S4: 24/11 @ 0.40% TP`) alongside the 5 Core Supernova modules (`S5–S9: 25/13 to 28/14`).
  - **True Open-Market H1 Bar Drought Counter (`iBarShift >= InpDroughtHours`)**:
    - Replaced calendar-second subtraction (`TimeCurrent() - g_last_fill_t`, which falsely counted 48 hours of closed weekend market as drought time on Mondays) with `iBarShift(_Symbol, PERIOD_H1, g_last_fill_t, false) >= InpDroughtHours` (`72` open-market H1 bars).
  - **Non-Duplicate Level Gate & Zero-Interference Scout Architecture**:
    - `S1–S4` only arm when their unbroken inner H1 swing (`9–11` bars) is distinct (`> $0.50`) from all Core `S5–S9` levels (`12–14` bars), and automatically retire their pending order as soon as `S5–S9` can see the level.
    - `S1–S4` are capped at `InpMaxDroughtPos = 1` concurrent scout position (`open + pending`), never dilute `S5–S9`'s `InpMaxPositions = 6` core stack cap, never delete `S5–S9`'s 60-hour multi-level pending order ladder (`MOD_MAXPND = 2..3`), and automatically step aside once account lot sizing exceeds `12.0` lots (`$360,000+` equity).
  - **Verified `Model=4` Real-Tick + `ExecutionMode=-1` Random-Delay Performance (`$300` Start, `1:500`)**:
    - **`2024` (`2024.01.01–2024.12.31`)**: **`+$3,900.52` Net Profit** (`+20.7%` vs `v2.00`'s `+$3,231.67`), **`PF 1.30`** (vs `1.26`), **`81.18%` Win Rate**, **`67.09%` Max Balance DD** (vs `67.80%`), with `100.0%` Win Rate (`3/3`) on `S1–S4` drought breakers and top trade gaps reduced from `[10.17, 10.01, 9.61, 8.00, 7.48]` days down to `[9.61, 7.94, 7.35, 6.77, 6.68]` days.
    - **`2025–2026` (`2025.01.01–2026.10.23`)**: **`+$4,227,663.69` Net Profit** (`14,093x` return from `$300`), **`PF 2.93`**, **`80.16%` Win Rate**, **`11.11%` Max Balance DD**, with `83.3%` Win Rate (`5/6`, `+$1,710.12`) on `S1–S4` drought breakers and sub-8-day maximum trade gaps throughout the entire `$300 -> $360,000` growth phase.

---

## [v2.00] — 2026-10-26 (Baseline Archive)
- **Archived Binary**: `bin/xauusd_chrysalis_ea/chrysalis_ea_v2.00.ex5`
- **Summary**:
  - 7-Module XAUUSD H1 Structural Breakout & Momentum Compounding EA (`S1–S7`) designed for high-asymmetry small-account moonshot runs (`$300` start).
  - H1 swing high/low breakout pending orders (`BUY_STOP` / `SELL_STOP`) with pre-level entry offsets, multi-stage profit ratchets, and equity compounding across modules.
