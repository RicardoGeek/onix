# Changelog — `usdjpy_chrysalis_ea` (USDJPY Marsshot EA)

All notable changes to `usdjpy_chrysalis_ea` are documented in this file.
Archived version-stamped binaries are stored in [`/bin/`](../bin/).

---

## [v3.10] — 2026-10-26 (Baseline Archive)
- **Archived Binary**: `bin/usdjpy_chrysalis_ea/usdjpy_chrysalis_ea_v3.10.ex5`
- **Summary**:
  - 9-Module USDJPY H1 Heavy-Weight Marsshot Matrix (`S1` 22/11 Chop Market Milker, `S2` 24/11 Trend Pullback Follower, `S3–S9` 25h–34h Structural Breakouts).
  - Verified on `Model=4` (Every tick based on real ticks) + `ExecutionMode=-1` (Random Delay) and `Spread=20`: `H1` bar-boundary runner management (`ManagePositions`), `REFILL_SEC=0` duplicate-order shield, and Per-Slot `1:100` Margin + SL Risk Survival Cap (`OrderLots`).
  - Active `OrderDelete()` shielding during Exhaustion/WMR Fix hours (`11, 18, 19`), Full Rollover Hour (`00:00–00:59`), and Judas hours.
