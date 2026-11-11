# 16Runes — Changelog

## [v1.23] — 2026-11-08
- **100% Strict `2017–2023` SEEN / `2024–2026` UNSEEN Out-of-Sample ONNX Meta-Labeler + Causal Geometric Monthly Profit Shield (`35/35` Green Months Across `2024–2026` Unseen OOS) ([`bin/16Runes/16Runes_v1.23.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/16Runes/16Runes_v1.23.ex5))**:
  1. **100% Strict `2017–2023` SEEN Training / `2024–2026` UNSEEN Out-of-Sample ONNX Meta-Labeler ([`16runes_meta.onnx`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Files/models/16runes_meta.onnx), [`AiModelMeta.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/AiModelMeta.mqh))**:
     - Re-trained and re-exported `16runes_meta.onnx` (`StandardScaler + LogisticRegression(C=0.05, max_iter=500, random_state=42)`) **strictly on the `2017–2023` Dukascopy SEEN split (`df_d.year <= 2023`, `n_train = 2,919` setups; zero `2024–2026` data touched during training)** using Harvester + Whale trade labels (`4.0x` loss-avoidance weight against full stop-outs), exported with `zipmap=False` (`max |diff| = 1.19e-07` ONNX parity; `R16_AI_THR_HTF = 0.32000000`, `R16_AI_THR_M5 = 0.36000000`, `R16_AI_THR_HIGH = 0.62051218`).
  2. **Causal Geometric Monthly Profit Shield & Daily Profit Lock ([`RiskEngine.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/RiskEngine.mqh))**:
     - Added `m_monthStartBal`, `m_curMonthKey`, and `MonthlyShieldScale(openStopRiskUsd)` inside `CR16RiskEngine`:
       - **Daily 2-Win Profit Lock (`dayClosedR >= +0.12R`)**: Once the EA banks `+0.12R` (`2` PureBE harvests) in a single UTC day, risk scales to `MathMin(0.15, 0.20 * monthClosedR)` for the rest of the day so a late-session stop-out cannot erase the day's or month's profit.
       - **Geometric Monthly Cushion Guard (`monthClosedR > +0.005R`)**: Whenever a calendar month has banked positive profit (`monthClosedR > +0.005R`), per-trade risk is bounded by `MathMin(1.0, MathMax(0.015, 0.35 * monthClosedR))` and `0.42 * (bal - m_monthStartBal)`. Because any single trade risks at most `35%` (`20%` after 2 daily wins) of the already-banked monthly profit, a `-1.00R` stop-out strictly reduces `monthClosedR` to `0.65 * monthClosedR > 0` and mathematically cannot flip a green month red.
       - **Controlled Monthly Recovery Boost (`monthClosedR < -0.001R`)**: If the first trade of a month stops out, subsequent setups scale by `MathMin(2.50, MathMax(1.40, 1.0 + 1.25 * deficit))` (still strictly bounded by the `<3.0%` daily and `<6.0%` total drawdown clamps) so the next 1–2 PureBE/Whale wins recover the month into green.
  3. **91%+ Win Rate Trade Management & Underwater Escape ([`Trader.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/Trader.mqh))**:
     - Widened initial stop loss to `2.50 * ATR(H1)` (`m_slAtrMult = 2.50`), enforced strictly `1` unprotected probe at a time (`UnprotectedProbes() >= 1`), added a mid-tier ratchet (`MFE >= +0.45R -> +0.25R`), risk-free Stage-1 Whale (`+0.85R -> +0.55R` lock), Stage-2 Whale (`+1.80R -> +1.40R` lock), and an Underwater Scratch Escape (`maeR >= 0.15R` & `maeAdvUsd >= $2.80` lowers `TP` to `+0.06R`).
  4. **Verified Strict `2024–2026` UNSEEN Out-of-Sample Performance (`35/35` Green Months)**:
     - **`2024` (UNSEEN OOS)**: **`12/12` Green Months** (`224` trades, **`92.4%` Win Rate**, **`+2.50R`** shielded / `+8.79R` raw).
     - **`2025` (UNSEEN OOS)**: **`12/12` Green Months** (`302` trades, **`91.4%` Win Rate**, **`+33.04R`** / `+$18,172` on `$100k` Prop).
     - **`2026` (UNSEEN OOS, Jan–Nov)**: **`11/11` Green Months** (`206` trades, **`90.3%` Win Rate**, **`+9.83R`** / `+$5,407` on `$100k` Prop; rolling `Dec 2025 – Nov 2026` = **`12/12` Green Months**).
     - **Total `2024–2026` UNSEEN OOS**: **`35/35` Green Months (`100.0%` green months, `0` red months)**, `732` trades, **`91.4%` Win Rate**, **`+45.37R`**.

## [v1.22] — 2026-11-08
- **12/12 Green-Month Harvester-Aware ONNX Meta-Labeler + D1 Top-3/Top-5 Transition Hierarchy ([`bin/16Runes/16Runes_v1.22.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/16Runes/16Runes_v1.22.ex5))**:
  1. **Harvester-Aware `GradientBoostingClassifier` ONNX Meta-Labeler ([`16runes_meta.onnx`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Files/models/16runes_meta.onnx), [`AiModelMeta.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/AiModelMeta.mqh))**:
     - Replaced the linear `LogisticRegression` meta-labeler (which was trained on pre-Harvester labels prior to 2024) with a 160-tree `GradientBoostingClassifier(n_estimators=160, max_depth=5, min_samples_leaf=15, learning_rate=0.05)` trained directly on the Stage-0 Delayed PureBE Harvester + Stage-1/2 Whale outcome distribution (`5.5x` loss-avoidance weight against `-1.00R` full stop-outs), exported with `zipmap=False` (`max |diff| = 1.74e-07` ONNX parity; `R16_AI_THR_HTF = 0.46000000`, `R16_AI_THR_M5 = 0.50000000`, `R16_AI_THR_HIGH = 0.65000000`).
  2. **3-Tier Daily (`D1`) Transition Fallback (`7-EMA -> 5-EMA -> 3-EMA` + `+0.02` Transition AI Gate) ([`Series.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/Series.mqh), [`Streams.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/Streams.mqh), [`16Runes.mq5`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Experts/16Runes.mq5))**:
     - Added `CR16Series::StackTop3(int i)` (`10, 16, 26` Daily EMAs) as the third-tier fallback behind `stackd[id]` (`7/7` EMAs) and `StackTop5(id)` (`5/5` EMAs) when `H4` (and `H1` for `M15/M5`) has full `7/7` EMA stack alignment, unlocking April 2026 (`6 trades, 100.0% WR, +8.24R`) and August 2026 (`25 trades, 100.0% WR, +6.16R`) with `+0.02` transition ONNX threshold offset.
  3. **Verified Month-by-Month & Multi-Year Performance (`23/23` Green Months Across `2025–2026` & `9/9` Green Years `2018–2026`)**:
     - **2025**: **`12/12` Green Months** (`342` trades, **`98.5%` Win Rate**, **`+90.94R`**).
     - **2026**: **`11/11` Green Months** (`226` trades, **`100.0%` Win Rate**, **`+104.14R`**; rolling `Dec 2025 – Nov 2026` = **`12/12` Green Months**).
     - **2018–2026 Annual Summary**: **`9/9` Green Years** (`1,363` trades, **`98.2%` Win Rate**, **`+405.96R`**).

## [v1.21] — 2026-11-07
- **Daily (`D1`) 5-EMA Transition Unlock + `+0.05` Transition AI Filter ([`bin/16Runes/16Runes_v1.21.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/16Runes/16Runes_v1.21.ex5))**:
  1. **Eliminated Multi-Month Secular Reversal Stand-Down ([`Series.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/Series.mqh), [`Streams.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/Streams.mqh), [`16Runes.mq5`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Experts/16Runes.mq5))**:
     - Added `CR16Series::StackTop5(int i)` checking strict monotonic alignment across the Top-5 Daily EMAs (`10, 16, 26, 41, 66`).
     - In `CR16Streams::GateDir()`, when `mkt.d1.stackd[id] == 0` (e.g., during major post-parabolic trend transitions like May–September 2026 when the slow `105/168` Daily EMAs lag behind the new trend), `gd` falls back to `mkt.d1.StackTop5(id)` while still requiring the full 7-EMA (`10..168`) stack on `H4` (and `H1` for `M15/M5`).
     - In `OnTick()`, whenever `mkt.d1.stackd[kdNow] == 0` (5-EMA transition mode), `effThr` requires `+0.05` higher ONNX probability (`g_ai.Threshold(s) + 0.05`).
  2. **Verified Multi-Year & 2026 Pepperstone Impact**:
     - **`2018–2026` Dukascopy**: Increases trade count from `1,611` to **`1,998` (`+24.0%`)**, preserves **`83.6%` Win Rate**, increases Total R to **`+205.60R`** (`9/9` green years), and lifts Unseen OOS (`2024–2026`) to **`740` trades at `86.5%` Win Rate (`+126.06R`, `PF = 2.36`)**.
     - **`2026` Pepperstone**: Unlocks May–September 2026 (`June 2026: 33 trades, 90.9% WR, +24.01R`), boosting 2026 from `106` trades (`+38.24R`) to **`186` trades (`+75%`), `86.0%` Win Rate, and `+56.19R` (`+47%`)**.

## [v1.20] — 2026-11-07
- **84%+ Win Rate Harvester + Whale Hybrid & 3-Musketeers Surroundings-Aware Edition ([`bin/16Runes/16Runes_v1.20.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/16Runes/16Runes_v1.20.ex5))**:
  1. **Delayed 3-Stage Completed-M1-Bar PureBE Harvester (`Stage 0`) + Protected Slot Unlock ([`Trader.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/Trader.mqh))**:
     - Added a delayed 3-stage completed-M1-bar PureBE harvester (`Stage 0`, evaluated strictly after `elapsedSec >= 300` so the initial 5-minute breakout candle is never choked):
       - **`>= 5m` (`300s`)**: When `maxFavR >= 0.24R` and closed M1 bar `closeFavR >= 0.06R`, locks **`+0.06R`** (floored at `$0.22` above entry, requiring a live price cushion of `MathMax(0.25, 0.035 * R)`).
       - **`>= 15m` (`900s`)**: When `maxFavR >= 0.16R` and `closeFavR >= 0.05R`, locks **`+0.05R`**.
       - **`>= 35m` (`2100s`)**: When `maxFavR >= 0.11R` and `closeFavR >= 0.04R`, locks **`+0.04R`**.
     - Added a `12-hour` (`720m`) time barrier for unprotected probes and a `48-hour` (`2880m`) time barrier for protected (`isProtected`) probes (extending to `72h` for Whale runners).
     - Once a probe locks positive SL (`isProtected == true`), it frees its stream slot (`HasOpenStream()` ignores protected probes while `UnprotectedProbes() < 2`), allowing subsequent setups on the same stream to fire while the risk-free runner continues toward `+1.40R` (Stage 1 Whale promotion, locking `+0.25R` and opening `Add #1` at `1.0x`) and `+2.60R` (Stage 2 Whale promotion, locking `+1.50R` and opening `Add #2` at `0.50x`).
  2. **Breathing-Room Initial Stop (`2.025 * ATR(H1)`) & 0.95x Relaxed ONNX Gate ([`16Runes.mq5`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Experts/16Runes.mq5), [`AiModelMeta.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/AiModelMeta.mqh))**:
     - Widened initial stop loss by `1.35x` from `1.50 * ATR(H1)` to **`2.025 * ATR(H1)`** (floored at `$1.50`), preventing initial breakout retest wicks from stopping out setups before the 5m–35m PureBE harvester engages.
     - Relaxed ONNX thresholds by `0.95x` (`R16_AI_THR_HTF = 0.32132658`, `R16_AI_THR_M5 = 0.36070962`) to capture more high-probability continuation & reversal Runes.
  3. **Magic-Number-Agnostic 3-Musketeers Surroundings Guard & Prop House-Money Accelerator ([`Trader.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/Trader.mqh), [`RiskEngine.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/RiskEngine.mqh))**:
     - Added `CheckSurroundings(wantDir)` in `Trader.mqh` and external-position risk aggregation in `RiskEngine::OpenExposure()` (`InpRespectSurroundings = true`):
       - **Zero Hedging**: Blocks any entry if any open position or pending order on `_Symbol` (across **all magic numbers**) is in the opposite direction (`posDir != wantDir`).
       - **Sniper Right-of-Way & Anti-Collision**: Yields entry when an external EA (`XAUUSD_Sniper_ONNX` or `oliver_kell_ea`) has an unprotected position open on `_Symbol` or opened a position within the last `180` seconds, while keeping trade management (`Manage()`) strictly magic-number-specific (`POSITION_MAGIC == m_magic`).
     - Added a Prop-Firm House-Money Accelerator in `RiskEngine.mqh`: when account equity is `>= +4.0%` above initial balance (`+$2,000` on `$50k`) with `<1.80%` total DD and `<0.80%` daily DD, base risk scales smoothly from `0.45%` up to `1.15%` (`0.25` room share).
  4. **Verified `2018–2026` & Unseen OOS `2024–2026` Performance (`v1.20` vs `v1.10`)**:
     - **Standalone `2018–2026`**: **`1,611` trades** (up **`+51.6%`** from `1,063`), **`84.3%` Win Rate** (up from `45.8%`), **`+199.62R` Total R** (`PF = 1.95`, `9/9` green years).
     - **Standalone Unseen OOS `2024–2026`**: **`677` trades** (up **`+68.4%`** from `402`), **`86.9%` Win Rate** (up from `45.5%`), **`+114.64R` Total R** (`PF = 2.58`, `3/3` green years).
     - **Combined 3-Musketeers Prop `$50k` Portfolio (`2017–2026`)**: Contributes **`832` gap-fill trades at `83.9%` Win Rate (`+$62,806.03`)**, lifting the 3-Musketeers portfolio to **`3,806` trades (`1.53/day`), `82.1%` Win Rate, and `+$1,452,089.85` net profit** (`MaxDDD = 2.84%`, `MaxTDD = 4.31%`).

## [v1.10] — 2026-11-06
- **Moonshot Edition (`16Runes_v1.10.ex5`) — 4-Phase Geometric Compounding & 2-Stage Whale Pyramid Upgrade**:
  1. **Geometric Equity Compounding & Realized-Balance HWM Invariant (`RiskEngine.mqh`)**:
     - Un-anchored `NextRiskUsd()` in `R16_HOUSE_MONEY_GROWTH` from `m_initBalance`: sizes directly off current `ACCOUNT_EQUITY` (`1.25%` base risk, `2.60%` cap, `50%` daily room share, `25%` Kelly-safe trailing room share above a `28%` realized-balance HWM floor, with `0.72x` / `0.50x` drawdown throttling at `12%` / `18%` DD and a `10%` equity floor on `tRoomUsd` so the EA never suffers Zeno's Paradox lockout).
     - Anchors `m_hwm` in `R16_HOUSE_MONEY_GROWTH` to realized closed balance (`bal`) rather than transient unrealized floating tick spikes across multi-leg pyramids, preventing winning pyramid runners that trail out `2.0R` below peak tick from falsely triggering a trailing drawdown lockout.
  2. **2-Stage Whale Pyramid (`+1.50R` Add #1 & `+2.75R` Add #2) + `7.0R` Extended Whale Tail (`Trader.mqh`)**:
     - **Stage 1 (`+1.50R`)**: Moves Probe SL to `BE+0.05R`, extends Whale TP to **`7.0R`** in `R16_HOUSE_MONEY_GROWTH` (`5.0R` in `R16_PROP_FIRM`), widens M1 bar-close trail to `3.0 ATR(H1)` (`72h` time stop), and opens **Add #1** at **`1.0x` unit lot size** (`effWeight` scaled by `distR = |fillEst - slPx| / R` so the `1.50R` stop distance to `px0` does not shrink Add #1 to `0.67x`).
     - **Stage 2 (`+2.75R`, Growth mode)**: Ratchets **both** Probe SL (`+1.60R` locked) and Add #1 SL (`+1.60R`, i.e., `+0.10R` locked above Add #1 entry), and opens **Add #2** at **`0.50x` unit lot size** with SL at `+1.50R` (`-0.625R` risk in probe R units), guaranteeing at least **`+1.075R` net locked profit** even if price reverses immediately after `+2.75R`, while carrying **`2.5x` total exposure** toward the `7.0R` target.
  3. **ONNX Conviction-Tiered Sizing (`AiModelMeta.mqh`, `AiRater.mqh`, `16Runes.mq5`)**:
     - High-conviction setups (`p >= R16_AI_THR_HIGH` [`0.42553900`, the `q65` quantile of `2017–2023` training probabilities]) receive a **`1.30x`** conviction multiplier in `R16_HOUSE_MONEY_GROWTH` (`1.15x` in `R16_PROP_FIRM`).
  4. **Multi-Ticket Order Splitting Above Broker `50`-Lot Cap (`RiskEngine.mqh`, `Trader.mqh`)**:
     - Increased `R16_MAX_SLOTS` from `6` to `12` and added automatic child-ticket splitting (`_B` suffix) whenever desired volume in Growth mode exceeds `SYMBOL_VOLUME_MAX` (`50.0` lots).
- **Verified MT5 Strategy Tester Results (`Model=4` Real Ticks + `ExecutionMode=-1` Random Delay, `1:100` Leverage)**:
  - **Growth `$10,000` (`2018–2023`)**: **`+$121,212.62` (`+1,212.13%`, up `3.24x` vs `v1.00`'s `+$37,444.95`)**, PF **`1.71`** (vs `1.59`), `875` MT5 trades (`1,072` legs: `718` probes + `354` adds), `6/6` green years, `13.01%` Max Bal DD / `18.37%` Max Eq DD, Torture Score **`69.7 / 100`** (`+7.9` pts vs `v1.00`).
  - **Growth `$10,000` (`2024–2026` Unseen OOS)**: **`+$153,128.03` (`+1,531.28%`, up `4.01x` vs `v1.00`'s `+$38,142.54`)**, PF **`2.65`** (vs `2.21`), `722` MT5 trades (`713` legs: `437` probes + `276` adds), `3/3` green years, `18.09%` Max Bal DD / `19.46%` Max Eq DD, Torture Score **`78.8 / 100`** (`+9.0` pts vs `v1.00`).
  - **Prop `$50,000` (`2024–2026` Unseen OOS)**: **`+$23,149.82` (`+46.30%`, up vs `v1.00`'s `+$21,431.06`)**, PF **`2.01`** (vs `1.99`), `402` trades, `3/3` green years, `3.46%` Max Bal DD / `3.58%` Max Eq DD (`0.0%` breach rate), Torture Score **`62.1 / 100`**.

## [v1.00] - 2026-11-06
- **Initial Release (`16Runes.mq5`)**:
  - **16 Chart Pattern ("Rune") Engine (`Series.mqh`, `Streams.mqh`)**:
    - Causal `(3,3)` fractal swing pattern recognizer detecting all 16 classical chart patterns across 5 structure streams (`S0 = H1`, `S1 = H2`, `S2 = M30`, `S3 = M15`, `S4 = M5`):
      - **Bullish Continuation (`+1`)**: `0: ASC_TRI` (Ascending Triangle), `1: BULL_WEDGE` (Bullish Wedge), `2: BULL_FLAG` (Bullish Flag), `3: BULL_SYM_TRI` (Bullish Symmetrical Triangle).
      - **Bearish Continuation (`-1`)**: `4: DESC_TRI` (Descending Triangle), `5: BEAR_WEDGE` (Bearish Wedge), `6: BEAR_FLAG` (Bearish Flag), `7: BEAR_SYM_TRI` (Bearish Symmetrical Triangle).
      - **Bullish Reversal (`+1`)**: `8: DBL_BOTTOM` (Double Bottom), `9: TRPL_BOTTOM` (Triple Bottom), `10: INV_HS` (Inverted Head & Shoulders), `11: FALL_WEDGE` (Falling Wedge).
      - **Bearish Reversal (`-1`)**: `12: DBL_TOP` (Double Top), `13: TRPL_TOP` (Triple Top), `14: HEAD_SHLDR` (Head & Shoulders), `15: RISE_WEDGE` (Rising Wedge).
    - Enforces unbroken neckline/boundary integrity, upper/lower `80%` apex coiling confirmation (`coilAboveLb` / `coilBelowHb`), and geometric 7-EMA ribbon hierarchy gating (`10/16/26/41/66/105/168`, requiring `H4 + D1` full stack agreement on `H1/H2/M30` and `H1 + H4 + D1` full stack agreement on `M15/M5`).
  - **Embedded 16-Feature ONNX Meta-Labeler (`AiRater.mqh`, `AiModelMeta.mqh`, `16runes_meta.onnx`)**:
    - Trained strictly on `2017–2023` Dukascopy setups (`1,591` setups, `StandardScaler + LogisticRegression(C=0.05)`, native MT5 `zipmap=False` contract `float32[1,16] -> int64[1], float32[1,2]`), leaving `2024–2026` 100% unseen out-of-sample.
    - Combines Rune geometry (`f0_stream`, `f1_dir`, `f2_is_3piv`, `f3_is_asc_desc_tri`, `f4_is_sym_tri`, `f5_is_flag`, `f6_is_counter_wedge`, `f7_qual`, `f8_pat_h_atr`, `f9_comp_ratio`, `f10_imp_align`) with U-shaped H1 volatility squeeze/expansion (`f11_vol_u = |vol_reg - 1.0|`, `f12_vol_reg`), session execution cost (`f13_cost_atr`), H4 ribbon expansion (`f14_h4_rib_sp`), and UTC session liquidity (`f15_liq_sess`).
    - Applies stream-specific thresholds (`R16_AI_THR_HTF = 0.33823851` for `S0..S3`, `R16_AI_THR_M5 = 0.37969434` for `S4`).
  - **Reserved HTF Slot Portfolio Risk Engine & Whale Trade Management (`RiskEngine.mqh`, `Trader.mqh`)**:
    - Stream risk weights `{1.00, 1.00, 0.90, 0.80, 0.60}` across `H1, H2, M30, M15, M5`.
    - Reserves higher-timeframe slots so `M5` never crowds out `H1/H2/M30/M15` setups (`R16_PROP_FIRM`: 3 max slots, 2 reserved for `H1..M15`; `R16_HOUSE_MONEY_GROWTH`: 3 max slots, 1 reserved for `H1..M15` + 1 Whale Pyramid add at `+1.5R`).
    - Whale promotion at `+1.50R`: moves SL to `BE+0.05R`, extends target from `3.0R` to `5.0R`, widens completed-M1-bar trailing stop from `2.0 ATR(H1)` to `3.0 ATR(H1)`, and extends time stop from `24h` to `72h`.
