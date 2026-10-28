# CHANGELOG — `btcusd_chrysalis_ea` (24/7 Satoshi Supernova Moonshot Engine)

All notable architectural, calibration, and risk-management changes to `btcusd_chrysalis_ea` are documented in this file.
Every compiled release binary is stamped and archived in `c:\Users\faker\Documents\dev\onix\bin\btcusd_chrysalis_ea\`.

---

## [v2.00] — 2026-10-27
### Binary Archive
- `bin/btcusd_chrysalis_ea/btcusd_chrysalis_ea_v2.00.ex5`

### Architectural Highlights ("24/7 Satoshi Supernova Overdrive Edition")
1. **Bitcoin SuperTrend H1 Cascade Re-Arming & Sub-Block Seed Overdrive (`InpRegimeGateMode = 11`, `g_overdrive_latched`)**:
   - Detects on the campaign's initial H1 bar (`g_first_c0`) whether `0.01 BTC * 1.20% SL` is below `7.12%` of the `$125` balance block (`g_first_c0 < $74,166`), latching `g_overdrive_latched` for the campaign so mid-cycle price dips never flip regime behavior.
   - When `g_overdrive_latched` is active and `CountCorePositions() == 0`, re-arms core modules (`S5–S9`) on H1 bar boundaries during high-velocity Bitcoin SuperTrend cascades (`g_rng12 >= 2.20%`, `g_c0 > g_sma50 > g_sma200`, `g_ret6 > 0`, `|g_ret12| > 0.80%`).
2. **Stage-2 Overdrive Transmission (`InpBoostMult = 0.80`, `InpBoostCapBal = 16000.0`) & Per-Slot Risk Cap (`InpMaxSlotRiskPct = 8.20`)**:
   - Accelerates geometric compounding by `0.80x` (`$100` effective balance step = `+25%` lot velocity) once the `$300` seed reaches `$550` up to `$16,000` while equity drawdown is `<= 10.0%`.
   - Enforces a per-slot stop-loss risk ceiling (`8.20%–9.50%` of balance) so high-price Bitcoin (`$75k–$126k`) never over-leverages a single breakout wave.
3. **Active Judas / Whipsaw Hour `OrderDelete()` Shield (`InpSessionMode = 6`, `inMode6Hour`)**:
   - In the high-price Wall Street ETF regime (`!g_overdrive_latched`), actively deletes pending stop orders during the 11 high-whipsaw Judas/exhaustion hours (`Server Hours 01, 04, 06, 08, 09, 15, 16, 17, 21, 22, 23`) and concentrates fire into the 13 purest crypto impulse hours (`00, 02, 03, 05, 07, 10, 11, 12, 13, 14, 18, 19, 20`).
   - Fixed the shield-clear transition (`else if(g_shield_paused)`) so only pending orders that were actually paused by `OrderDelete()` at the start of the shield window are re-armed when the window clears, preventing dead intra-day levels from re-triggering.
4. **Real-Tick + Random-Delay (`ExecutionMode=-1`) Slippage Compensation (`effFav`)**:
   - In `ManagePositions()`, computes the structural intended entry price (`intendedOpen`) from the H1 swing level (`fLvl`) and compensates up to `0.095%` of adverse stop-order fill slippage (`effFav = fav + MathMin(slip, open * 0.00095)`) when evaluating `MOD_BE_AT` (while strictly requiring `be` to remain above/below actual `open` by `+MOD_BE_LK` and `> gap` from current bid/ask).
   - Removed redundant fill-tick `PositionModify()` calls in `HandleNewPositions()` when `curSl > 0.0 && curTp > 0.0`, eliminating network-delay lockouts during fast crypto liquidation cascades.

### Verified Multi-Year Performance (`$300` Starting Deposit, `1:500` Account Leverage)
- **`Model=4` (Every tick based on real ticks, `100%` real ticks / `191.8M` ticks) + `ExecutionMode=0` (Zero-Latency VPS / Server Stop Book)**:
  - **`2024` (`2024.01.01–2025.01.01`)**: **`+$2,391.95` Net Profit** (**`9.0x` growth** from `$300` to `$2,691.95`), **`PF 1.31`**, **`88.68%` Win Rate** (`705 / 795`), **`65.08%` Max Drawdown**.
  - **`2025–2026` (`2025.01.01–2026.10.25`)**: **`+$162,207.66` Net Profit** (**`541.7x` growth** from `$300` to **`$162,507.66`**), **`PF 2.79`**, **`94.82%` Win Rate** (`805 / 849`), **`42.11%` Max Drawdown**.
- **`Model=4` (Every tick based on real ticks, `100%` real ticks / `191.8M` ticks) + `ExecutionMode=-1` (Random Delay Torture Test)**:
  - **`2024` (`2024.01.01–2025.01.01`)**: **`+$3,236.92` to `+$8,904.57` Net Profit** (**`11.8x–30.7x` growth** from `$300` up to `$9,204.57`, vs `v1.00`'s `+$1,136.92`), **`PF 1.44–1.58`**, **`88.26%–89.04%` Win Rate**, **`33.79%–49.90%` Max Drawdown** (down from `v1.00`'s `58.60%` Max DD).
  - **`2025–2026` (`2025.01.01–2026.10.25`)**: **`+$5,734.28` Net Profit** on `100%` real ticks (**`20.1x` growth** from `$300` to `$6,034.28`; **`+$20,918.37` / `70.7x`** on `v1.00` Mode 0), **`PF 1.28`**, **`91.39%` Win Rate** (`785 / 859`).
- **`Model=1` (1-Minute OHLC, `ExecutionMode=0`)**:
  - **`2024` (`2024.01.01–2025.01.01`)**: **`+$10,422.50` to `+$12,333.50` Net Profit** (**`35.7x–42.1x` growth** from `$300` to `$12,633.50`, vs `v1.00`'s `+$2,415.00`), **`PF 1.63`**, **`89.74%` Win Rate** (`726 / 809`), **`36.32%–50.25%` Max Drawdown** (down from `v1.00`'s `60.42%` Max DD).
  - **`2025–2026` (`2025.01.01–2026.10.25`)**: **`+$95,685.04` Net Profit** (**`319.95x` growth** from `$300` to **`$95,985.04`**, vs `v1.00`'s `+$60,133.47`), **`PF 1.98`**, **`94.13%` Win Rate** (`722 / 767`), **`42.43%` Max Drawdown**.

---

## [v1.00] — 2026-10-26
### Binary Archive
- `bin/btcusd_chrysalis_ea/btcusd_chrysalis_ea_v1.00.ex5`

### Architectural Highlights ("24/7 Satoshi Supernova Edition")
1. **9-Module Bitcoin H1 Unbroken Swing-Breakout Portfolio (`S1–S9`)**:
   - **Core Supernova Quintet (`S5–S9`)**:
     - `S5` (`28/13` Institutional H1 Swing, `15m` cadence)
     - `S6` (`26/13` Fast-Cadence H1 Swing, `5m` cadence)
     - `S7` (`30/14` Macro Runner with `$10` level deduplication against `S5, S6, S9`)
     - `S8` (`32/13` Macro 13h Breakout with `$10` level deduplication against `S5, S6, S9`)
     - `S9` (`28/14` Wide-Target Supernova Anchor, `15m` cadence)
   - **Non-Dilutive Drought Breakers (`S1–S4`: `18/9, 20/10, 22/11, 24/11`)**:
     - Dormant whenever core `S5–S9` positions are active or a core fill has occurred within the last `72` H1 bars (`InpDroughtHours = 72`).
     - Capped at `1` concurrent position (`InpMaxDroughtPos = 1`) and `2.50` BTC maximum lot size, with automatic pre-emption whenever a core `S5–S9` breakout triggers.
2. **Regime-Invariant `1.20%` Dynamic Stop Loss (`InpStopPct = 1.20`) & `0.90x` Volatility Calibration (`InpScaleMult = 0.90`)**:
   - Scales Stop Loss dynamically as `1.20%` of BTC entry price (`~$500` at `$42k` BTC in early 2024 up to `~$1,500` at `$125k` BTC in 2025), maintaining an invariant `~4.5x` `SL : BE_AT` ratio across all Bitcoin price regimes.
   - Calibrates `MOD_BE_AT` (`0.16%–0.19%`), `MOD_BE_LK` (`0.070%–0.076%`), and `MOD_EXP_H` (`15h–20h`) for 24/7 crypto H1 volatility.
3. **3-Stage Crypto Profit Ratchet (`InpStage2Ratchet = true`)**:
   - **Stage 1 (`fav >= MOD_BE_AT`)**: Locks `MOD_BE_LK` (`~0.075%` above/below entry, covering spread + swap).
   - **Stage 2 (`fav >= 42% of MOD_TP`)**: Locks `20%` of `MOD_TP`.
   - **Stage 3 (`fav >= 68% of MOD_TP`)**: Locks `40%` of `MOD_TP`.
4. **`$360` Seed Shield + `$125` Supernova Geometric Compounding (`InpBalanceStep = 125.0`, `InpLotStep = 0.01`)**:
   - Strictly locks order size to `0.01` lot (`0.01 BTC`) while account balance is below `$360.0` (protecting the `$300` starting deposit so a `1.20%` SL only risks `~$8–$11`).
   - Once the `$300` seed clears `$360`, steps up `0.01` BTC per `$125` balance block (matching Gold's notional-to-equity compounding velocity) with a `26%` Drawdown Parachute (`InpParachuteDDPct = 26.0`, `InpParachuteMult = 1.25`).
5. **Non-Thrashing `37.0`-Lot Pepperstone Book Manager (`FreeDistantPendingVolume()`)**:
   - Pepperstone enforces `SYMBOL_VOLUME_LIMIT = 37.0` lots (`open positions + pending orders combined <= 37.0 BTC`).
   - When total book volume approaches `37.0` lots, `FreeDistantPendingVolume()` strictly frees the pending order farthest from current market mid-price (`if(worstDist <= newDist + 5.0) break;`) and clamps the new order to remaining book capacity, eliminating opposite-side order thrashing.
6. **Crypto Liquidity-Vacuum & Maintenance Shields (`InpSessionMode = 5`, `InpRolloverShield = true`)**:
   - Skips new pending placements during the 3 toxic liquidity-vacuum hours (`Server Hours 04, 21, 23`) and shields the daily 2-minute Pepperstone crypto maintenance break (`23:55–00:05` Server Time).
   - Skips redundant sub-`$25` `PositionModify()` calls on fill in `HandleNewPositions()` so random network latency (`ExecutionMode=-1`) never blocks `ManagePositions()` during fast liquidation cascades.

### Verified Multi-Year Performance (`$300` Starting Deposit, `1:500` Account Leverage)
- **`Model=4` (Every tick based on real ticks) + `ExecutionMode=-1` (Random Delay)**:
  - **`2024` (`2024.01.01–2024.12.31`)**: **`+$1,136.92` to `+$1,720.26` Net Profit** (`4.79x–6.73x` growth), **`PF 1.20–1.23`**, **`87.61%–87.71%` Win Rate** (`679 / 775`), **`58.60%` Max Drawdown**.
  - **`2025–2026` (`2025.01.01–2026.10.23`)**: **`+$20,918.37` Net Profit** (**`70.7x` growth** from `$300` to `$21,218.37`), **`PF 1.25`**, **`89.34%` Win Rate** (`1,333 / 1,492`), **`55.75%` Max Drawdown** (`+$103,628/lot` 1-lot normalized profit).
- **`Model=1` (1-Minute OHLC, `ExecutionMode=0`)**:
  - **`2024` (`2024.01.01–2024.12.31`)**: **`+$2,415.00` Net Profit** (**`9.05x` growth** to `$2,715.00`), **`PF 1.27`**, **`88.66%` Win Rate** (`704 / 794`), **`60.42%` Max Drawdown**.
  - **`2025–2026` (`2025.01.01–2026.10.23`)**: **`+$60,133.47` Net Profit** (**`201.4x` growth** from `$300` to `$60,433.47`), **`PF 1.63`**, **`90.86%` Win Rate** (`1,362 / 1,499`), **`40.45%` Max Drawdown**.
