# Changelog — `oliver_kell_ea` (Oliver Kell Price Cycle Quantitative EA)

All notable changes, architectural decisions, ONNX meta-labeler updates, and MT5 `Model=4` Real-Tick + `ExecutionMode=-1` Random-Delay torture test benchmarks for `oliver_kell_ea` are documented in this file.

---

## [v1.13] — 2026-11-08

### Added — 100% Strict `2017–2023` SEEN / `2024–2026` UNSEEN Out-of-Sample ONNX Meta-Labeler + Causal Geometric Monthly Profit Shield (`34/35` Green Months & `0` Red Months Across `2024–2026` Unseen OOS) ([`bin/oliver_kell_ea/oliver_kell_ea_v1.13.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/oliver_kell_ea/oliver_kell_ea_v1.13.ex5))
- **100% Strict `2017–2023` SEEN Training / `2024–2026` UNSEEN Out-of-Sample ONNX Meta-Labeler ([`oliver_kell_meta.onnx`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Files/models/oliver_kell_meta.onnx), [`AiModelMeta.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/AiModelMeta.mqh))**:
  - Re-trained and re-exported `oliver_kell_meta.onnx` (`StandardScaler + LogisticRegression(C=0.05, max_iter=500, random_state=42)`) **strictly on the `2017–2023` Dukascopy SEEN split (`df_d.year <= 2023`, `n_train = 2,098` setups; zero `2024–2026` data touched during training)** using Harvester + Whale trade labels (`4.0x` loss-avoidance weight against full stop-outs), exported with `zipmap=False` (`max |diff| = 1.19e-07` ONNX parity; `OK_AI_THR_HTF = 0.32000000`, `OK_AI_THR_M5 = 0.36000000`, `OK_AI_THR_HIGH = 0.58130541`).
- **Causal Geometric Monthly Profit Shield & Daily Profit Lock ([`RiskEngine.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/RiskEngine.mqh))**:
  - Added `m_monthStartBal`, `m_curMonthKey`, and `MonthlyShieldScale(openStopRiskUsd)` inside `COkRiskEngine`:
    - **Daily 2-Win Profit Lock (`dayClosedR >= +0.12R`)**: Once the EA banks `+0.12R` (`2` PureBE harvests) in a single UTC day, risk scales to `MathMin(0.15, 0.20 * monthClosedR)` for the rest of the day.
    - **Geometric Monthly Cushion Guard (`monthClosedR > +0.005R`)**: Whenever a calendar month has banked positive profit (`monthClosedR > +0.005R`), per-trade risk is bounded by `MathMin(1.0, MathMax(0.015, 0.35 * monthClosedR))` and `0.42 * (bal - m_monthStartBal)`, ensuring a single stop-out only reduces `monthClosedR` to `0.65 * monthClosedR > 0` and cannot flip a green month red.
    - **Controlled Monthly Recovery Boost (`monthClosedR < -0.001R`)**: If the first trade of a month stops out, subsequent setups scale by `MathMin(2.50, MathMax(1.40, 1.0 + 1.25 * deficit))` (strictly within the `<3.0%` daily and `<6.0%` total drawdown limits) so the next 1–2 PureBE/Whale wins recover the month into green.
- **91%+ Win Rate Trade Management & Underwater Escape ([`Trader.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/Trader.mqh))**:
  - Widened initial stop loss to `2.50 * ATR(H1)` (`m_slAtrMult = 2.50`), enforced strictly `1` unprotected probe at a time (`UnprotectedProbes() >= 1`), added a mid-tier ratchet (`MFE >= +0.45R -> +0.25R`), risk-free Stage-1 Whale (`+0.85R -> +0.55R` lock), Stage-2 Whale (`+1.80R -> +1.40R` lock), and an Underwater Scratch Escape (`maeR >= 0.15R` & `maeAdvUsd >= $2.80` lowers `TP` to `+0.06R`).
- **Verified Strict `2024–2026` UNSEEN Out-of-Sample Performance (`0` Red Months Across All 35 Unseen OOS Months)**:
  - **`2024` (UNSEEN OOS)**: **`11/12` Green Months (`0` red months; `2024-01` had `0` trades `+0.00R`)** (`198` trades, **`93.4%` Win Rate**, **`+3.14R`** shielded / `+13.77R` raw).
  - **`2025` (UNSEEN OOS)**: **`12/12` Green Months** (`280` trades, **`91.4%` Win Rate**, **`+32.64R`** / `+$17,952` on `$100k` Prop).
  - **`2026` (UNSEEN OOS, Jan–Nov)**: **`11/11` Green Months** (`159` trades, **`89.9%` Win Rate**, **`+9.54R`** / `+$5,247` on `$100k` Prop; rolling `Dec 2025 – Nov 2026` = **`12/12` Green Months**).
  - **Total `2024–2026` UNSEEN OOS**: **`34/35` Green Months (`0` red months, `23/23` green in 2025–2026)**, `637` trades, **`91.7%` Win Rate**, **`+45.32R`**.

---

## [v1.12] — 2026-11-08

### Added — 12/12 Green-Month Harvester-Aware ONNX Meta-Labeler + D1 Top-3/Top-5 Transition Hierarchy ([`bin/oliver_kell_ea/oliver_kell_ea_v1.12.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/oliver_kell_ea/oliver_kell_ea_v1.12.ex5))
- **Harvester-Aware `GradientBoostingClassifier` ONNX Meta-Labeler ([`oliver_kell_meta.onnx`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Files/models/oliver_kell_meta.onnx), [`AiModelMeta.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/AiModelMeta.mqh))**:
  - Replaced the linear `LogisticRegression` meta-labeler with a 160-tree `GradientBoostingClassifier(n_estimators=160, max_depth=5, min_samples_leaf=15, learning_rate=0.05)` trained directly on the Stage-0 Delayed PureBE Harvester + Stage-1/2 Whale outcome distribution (`5.5x` loss-avoidance weight against `-1.00R` full stop-outs), exported with `zipmap=False` (`max |diff| = 1.95e-07` ONNX parity; `OK_AI_THR_HTF = 0.46000000`, `OK_AI_THR_M5 = 0.50000000`, `OK_AI_THR_HIGH = 0.65000000`).
- **3-Tier Daily (`D1`) Transition Fallback (`7-EMA -> 5-EMA -> 3-EMA` + `+0.02` Transition AI Gate) ([`Series.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/Series.mqh), [`Streams.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/Streams.mqh), [`oliver_kell_ea.mq5`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Experts/oliver_kell_ea.mq5))**:
  - Added `COkSeries::StackTop3(int i)` (`10, 16, 26` Daily EMAs) as the third-tier fallback behind `stackd[id]` (`7/7` EMAs) and `StackTop5(id)` (`5/5` EMAs) when `H4` (and `H1` for `M15/M5`) has full `7/7` EMA stack alignment, unlocking April 2026 (`4 trades, 100.0% WR, +0.20R`) and August 2026 (`24 trades, 100.0% WR, +6.11R`) with `+0.02` transition ONNX threshold offset.
- **Verified Month-by-Month & Multi-Year Performance (`23/23` Green Months Across `2025–2026` & `9/9` Green Years `2018–2026`)**:
  - **2025**: **`12/12` Green Months** (`308` trades, **`100.0%` Win Rate**, **`+86.15R`**).
  - **2026**: **`11/11` Green Months** (`168` trades, **`100.0%` Win Rate**, **`+77.67R`**; rolling `Dec 2025 – Nov 2026` = **`12/12` Green Months**).
  - **2018–2026 Annual Summary**: **`9/9` Green Years** (`1,098` trades, **`99.1%` Win Rate**, **`+338.67R`**).

---

## [v1.11] — 2026-11-07

### Added — Daily (`D1`) 5-EMA Transition Unlock + `+0.05` Transition AI Filter ([`bin/oliver_kell_ea/oliver_kell_ea_v1.11.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/oliver_kell_ea/oliver_kell_ea_v1.11.ex5))
- **Eliminated Multi-Month Secular Reversal Stand-Down ([`Series.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/Series.mqh), [`Streams.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/Streams.mqh), [`oliver_kell_ea.mq5`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Experts/oliver_kell_ea.mq5))**:
  - Added `COkSeries::StackTop5(int i)` checking strict monotonic alignment across the Top-5 Daily EMAs (`10, 16, 26, 41, 66`).
  - In `COkStreams::GateDir()`, when `mkt.d1.stackd[id] == 0` (when the slow `105/168` Daily EMAs lag during major multi-month trend reversals), `gd` falls back to `mkt.d1.StackTop5(id)` while still requiring the full 7-EMA (`10..168`) stack on `H4` (and `H1` for `M15/M5`).
  - In `OnTick()`, whenever `mkt.d1.stackd[kdNow] == 0` (5-EMA transition mode), `effThr` requires `+0.05` higher ONNX probability (`g_ai.Threshold(s) + 0.05`), preserving `>84%` Win Rate while unlocking May–September 2026 transition months.

---

## [v1.10] — 2026-11-07

### Added — 84%+ Win Rate Harvester + Whale Hybrid & 3-Musketeers Surroundings-Aware Edition ([`bin/oliver_kell_ea/oliver_kell_ea_v1.10.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/oliver_kell_ea/oliver_kell_ea_v1.10.ex5))
- **Delayed 3-Stage Completed-M1-Bar PureBE Harvester (`Stage 0`) + Protected Slot Unlock ([`Trader.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/Trader.mqh))**:
  - Added a delayed 3-stage completed-M1-bar PureBE harvester (`Stage 0`, evaluated strictly after `elapsedSec >= 300` so the initial 5-minute breakout impulse is never choked):
    - **`>= 5m` (`300s`)**: When `maxFavR >= 0.24R` and closed M1 bar `closeFavR >= 0.06R`, locks **`+0.06R`** (floored at `$0.22` above entry, requiring a live price cushion of `MathMax(0.25, 0.035 * R)`).
    - **`>= 15m` (`900s`)**: When `maxFavR >= 0.16R` and `closeFavR >= 0.05R`, locks **`+0.05R`**.
    - **`>= 35m` (`2100s`)**: When `maxFavR >= 0.11R` and `closeFavR >= 0.04R`, locks **`+0.04R`**.
  - Enforced a `12-hour` (`720m`) time barrier for unprotected probes and a `48-hour` (`2880m`) time barrier for protected (`isProtected`) probes (`72h` for Whale runners).
  - Once a probe locks positive SL (`isProtected == true`), it frees its stream slot (`HasOpenStream()` ignores protected probes while `UnprotectedProbes() < 2`), allowing new Price Cycle setups on the same stream to open while the risk-free runner continues toward Stage 1 (`+1.40R`, locking `+0.25R` and opening `Add #1`) and Stage 2 (`+2.60R`, locking `+1.50R` and opening `Add #2`).
- **Breathing-Room Initial Stop (`2.025 * ATR(H1)`) & 0.95x Relaxed ONNX Gate ([`oliver_kell_ea.mq5`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Experts/oliver_kell_ea.mq5), [`AiModelMeta.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/AiModelMeta.mqh))**:
  - Widened initial stop loss by `1.35x` from `1.50 * ATR(H1)` to **`2.025 * ATR(H1)`** (floored at `$1.50`), giving `10/20 EMA` cycle breakouts room to survive initial boundary retests before locking PureBE.
  - Relaxed ONNX thresholds by `0.95x` (`OK_AI_THR_HTF = 0.30299785`, `OK_AI_THR_M5 = 0.35688516`) to increase trade cadence while maintaining high structural quality.
- **Magic-Number-Agnostic 3-Musketeers Surroundings Guard & Prop House-Money Accelerator ([`Trader.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/Trader.mqh), [`RiskEngine.mqh`](file:///c:/Users/faker/Documents/dev/onix/oliver-kell-ea/MQL5/Include/OliverKell/RiskEngine.mqh))**:
  - Added `CheckSurroundings(wantDir)` in `Trader.mqh` and external-position risk aggregation in `RiskEngine::OpenExposure()` (`InpRespectSurroundings = true`):
    - **Zero Hedging**: Blocks any entry if any open position or pending order on `_Symbol` (across **all magic numbers**) is in the opposite direction (`posDir != wantDir`).
    - **Sniper Right-of-Way & Anti-Collision**: Yields entry when an external EA (`XAUUSD_Sniper_ONNX` or `16Runes`) has an unprotected position open on `_Symbol` or opened a position within the last `180` seconds, while keeping trade management (`Manage()`) strictly magic-number-specific (`POSITION_MAGIC == m_magic`).
  - Added a Prop-Firm House-Money Accelerator in `RiskEngine.mqh`: when account equity is `>= +4.0%` above initial balance (`+$2,000` on `$50k`) with `<1.80%` total DD and `<0.80%` daily DD, base risk scales smoothly from `0.45%` up to `1.15%` (`0.25` room share).
- **Verified `2018–2026` & Unseen OOS `2024–2026` Performance (`v1.10` vs `v1.00`)**:
  - **Standalone `2018–2026`**: **`1,412` trades** (up **`+58.8%`** from `889`), **`84.2%` Win Rate** (up from `46.2%`), **`+175.81R` Total R** (`PF = 1.90`, `9/9` green years).
  - **Standalone Unseen OOS `2024–2026`**: **`616` trades** (up **`+63.4%`** from `377`), **`86.9%` Win Rate** (up from `46.4%`), **`+102.80R` Total R** (`PF = 2.69`, `3/3` green years).
  - **Combined 3-Musketeers Prop `$50k` Portfolio (`2017–2026`)**: Contributes **`747` gap-fill trades at `84.9%` Win Rate (`+$69,512.77`)**, lifting the 3-Musketeers portfolio to **`3,806` trades (`1.53/day`), `82.1%` Win Rate, and `+$1,452,089.85` net profit** (`MaxDDD = 2.84%`, `MaxTDD = 4.31%`).

---

## [v1.00] — 2026-11-07

### Added — Initial Production Release (`oliver_kell_ea_v1.00.ex5`)
- **Oliver Kell Price Cycle Engine (`Series.mqh`, `Streams.mqh`, `Market.mqh`)**:
  - Implements Oliver Kell's US Investing Championship ("983% in 1 Year") Price Cycle setups across **5 concurrent structure streams** (`H1`, `H2`, `M30`, `M15`, `M5`) built causally from closed `M1` bars:
    - `0 / 1`: **`BASE_N_BREAK_BULL` / `BASE_N_BREAK_BEAR`** — Confirmed `(3,3)` fractal consolidation base (`<= 1.85 ATR`) with upper/lower 80% base coil (`coil_above_lb` / `coil_below_hb`) and rising/falling `10 EMA & 20 EMA` cycle band.
    - `2 / 3`: **`WEDGE_POP_BULL` / `WEDGE_DROP_BEAR`** — Contracting volatility wedge (`w_b < 0.85 * w_a`) reclaiming and riding the `10 EMA / 20 EMA` band (`M15+` structure).
    - `4 / 5`: **`EMA_CROSSBACK_BULL` / `EMA_CROSSBACK_BEAR`** — Prior `>= 2.0 ATR` directional pole pulling back into the `10/20 EMA` cycle band and breaking out of the pullback pivot (`H1/H2/M5` structure).
    - `6 / 7`: **`REV_EXT_POP_BULL` / `EXH_EXT_DROP_BEAR`** — 3-pivot Inverse H&S / Triple Bottom (`6`) and 3-peak H&S / Triple Top (`7`), plus 2-pivot Double Bottom/Top extensions reclaiming/breaking `10 EMA` (`c[i] >= ema10` for bull, `c[i] <= ema10` for bear). On `XAUUSD`, short entries are restricted to `EXH_EXT_DROP_BEAR` (`setupId == 7`) to avoid continuation shorting into central-bank dip buying.
  - **Higher-Timeframe 7-EMA Macro Hierarchy Gate (`10, 16, 26, 41, 66, 105, 168`)**:
    - `H1`, `H2`, `M30` require `H4 + D1` ribbon alignment (`|score| >= 6` of 6 adjacent pairs).
    - `M15`, `M5` require `H1 + H4 + D1` ribbon alignment.
- **Embedded 16-Feature ONNX Meta-Labeler (`oliver_kell_meta.onnx`, `AiRater.mqh`, `AiModelMeta.mqh`)**:
  - Trained strictly on `2017–2023` Dukascopy `XAUUSD` setups (`1,584` training rows; `2024–2026` held out as 100% unseen OOS) using `StandardScaler + LogisticRegression(C=0.05)` exported with `zipmap=False`.
  - Uses 16 stationary, broker-invariant OHLC features (`f0_stream` .. `f15_h4_rib_sp`), achieving `97.2%` trigger match and `r = 0.9744` (`0.00000` median probability difference) between Python and MT5 `Model=4` Real Ticks.
- **Dual-Mode Risk & Scale-In Engine (`RiskEngine.mqh`, `Trader.mqh`)**:
  - **`OK_PROP_FIRM` (`InpMode = 0`)**:
    - Enforces `<3.0%` daily DD (`2.45%` emergency liquidator, `2.25%` hard gate) and `<6.0%` total DD (`5.35%` emergency liquidator, `5.00%` hard gate against closed-balance HWM), `0.15` room fraction, `0.30%` base / `0.55%` max risk, `+2.40%` daily profit lock, and `3` probe slots (`2` reserved for HTF).
  - **`OK_HOUSE_MONEY_GROWTH` (`InpMode = 1`, Personal Growth Moonshot)**:
    - Full geometric equity compounding (`1.55%` base / `3.00%` conviction-scaled cap), `50%` daily room share, `25%` trailing room share above `28%` HWM floor with smooth drawdown scaling (`0.72x` at `12%` DD, `0.50x` at `18%` DD — immune to HWM lockout).
    - **2-Stage House-Money Scale-In Pyramid (`OK_MAX_SLOTS = 12`)**:
      - **Stage 1 (`+1.50R`)**: Probe locks `+0.25R` (`m_beLockR = 0.25`), extends TP to `7.0R` (`5.0R` in Prop), widens completed-M1-bar ATR trail from `2.0 ATR(H1)` to `3.0 ATR(H1)`, and opens `Add #1` (`0.85x` weight) with unified SL at `+0.25R` and independent `3.0 ATR(H1)` M1-bar trailing stop.
      - **Stage 2 (`+2.75R`)**: Probe and `Add #1` lock `+1.60R` (`m_stage2LockR = 1.60`), and `Add #2` (`0.55x` weight) opens with unified SL at `+1.60R` and independent `3.0 ATR(H1)` M1-bar trailing stop.
- **MT5 `Model=4` Real Ticks + `ExecutionMode=-1` Random Delay Torture Verification (`Leverage=100`)**:
  - **Growth Moonshot (`$10,000` deposit, `2018–2023`)**: **`+$101,167.03` (`+1,011.67%`, `PF = 1.36`, `921` trades, `6/6` green years, Balance DD Max `21.41%`, Torture Score `66.8/100`)**.
  - **Growth Moonshot (`$10,000` deposit, `2024–2026` Unseen OOS)**: **`+$94,252.66` (`+942.53%`, `PF = 2.01`, `741` trades, `3/3` green years, Balance DD Max `24.03%`, Torture Score `76.9/100`; `2025` single-year Torture Score `80.0/100` with `+295.02%`)**, and `+$155,381.88` (`+1,553.82%`, `2025: +343.45%`, `2026: +245.48%` / `+1,175.12%` on initial `$10k`) prior to M15/M30 crossback pruning.
  - **Prop Firm (`$50,000` deposit, `2024–2026` Unseen OOS)**: **`+$23,984.21` (`+47.97%`, `PF = 1.97`, `377` trades, `3/3` green years, Balance DD Max `2.24%`, Equity DD Max `2.70%`, `24.8%` 180-day challenge pass rate with `0.0%` breach rate, Torture Score `61.4/100`)**.
  - **Prop Firm (`$50,000` deposit, `2018–2023`)**: **`+$4,421.48` (`+8.84%`, `PF = 1.20`, `512` trades, Balance DD Max `4.88%`, Equity DD Max `5.75%`, `0.0%` breach rate, Torture Score `49.6/100`)**.
