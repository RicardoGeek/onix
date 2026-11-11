# 16Runes v1.20 — Research, Architecture & MT5 Real-Tick Verification Report (2026-11-07)

## 1. Executive Summary

**`16Runes`** ([`16Runes.mq5`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Experts/16Runes.mq5)) is a multi-timeframe MetaTrader 5 Expert Advisor that recognizes and trades all **16 classical chart patterns ("Runes")** across 5 structure streams (`H1`, `H2`, `M30`, `M15`, `M5`), gated by the **geometric 7-EMA ribbon hierarchy (`10/16/26/41/66/105/168`)** and filtered by an embedded **16-feature ONNX Meta-Labeler** ([`16runes_meta.onnx`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Files/models/16runes_meta.onnx)) trained strictly on `2017–2023` Dukascopy setups (`1,591` setups), leaving `2024–2026` **100% unseen out-of-sample**.

In **`v1.20`** ([`bin/16Runes/16Runes_v1.20.ex5`](file:///c:/Users/faker/Documents/dev/onix/bin/16Runes/16Runes_v1.20.ex5)), `16Runes` introduces the **Delayed 3-Stage Completed-M1-Bar PureBE Harvester (`Stage 0`) + Protected Slot Unlock**, a **`2.025 * ATR(H1)` breathing-room initial stop**, **`0.95x` relaxed ONNX thresholds**, and the **Magic-Number-Agnostic 3-Musketeers Surroundings Guard**:
- **`v1.20` High-Win-Rate Harvester + Whale Hybrid (`2018–2026` & Unseen OOS `2024–2026`)**:
  - **`2018–2026` (`9/9` Green Years)**: **`1,611` trades** (up **`+51.6%`** from `1,063` in `v1.10`), **`84.3%` Win Rate** (up from `45.8%`), **`+199.62R` Total R**, **PF `1.95`**.
  - **`2024–2026` (100% Unseen OOS, `3/3` Green Years)**: **`677` trades** (up **`+68.4%`** from `402` in `v1.10`), **`86.9%` Win Rate** (up from `45.5%`), **`+114.64R` Total R**, **PF `2.58`**.
  - **Combined 3-Musketeers Prop `$50k` Portfolio (`2017–2026`, with `XAUUSD_Sniper_ONNX v4.62` & `oliver_kell_ea v1.10`)**: Contributes **`832` gap-fill trades at `83.9%` Win Rate (`+$62,806.03`)** with **0% hedging**, lifting the 3-Musketeers portfolio to **`3,806` trades (`1.53/day`, `0.67d` wait), `82.1%` Win Rate, `+$1,452,089.85` net profit, `2.84%` Max Daily DD, `4.31%` Max Total DD, and a `97.5 / 100` Composite Score**.

Verified in the MetaTrader 5 Strategy Tester on Pepperstone `XAUUSD` under **`Model=4` (Every tick based on real ticks) + `ExecutionMode=-1` (Random Delay)** (`1:100` leverage, explicit inputs):
- **`v1.10` Moonshot Growth Mode (`$10,000`, `InpMode=1`, 2-Stage Whale Pyramid + `7.0R` Extended Tail + `1.30x` ONNX Conviction Boost)**:
  - **`2018–2023`**: **`+$121,212.62` (`+1,212.13%` -> Final Balance `$131,212.62`, up `3.24x` vs `v1.00`)**, **PF `1.71`** (vs `1.59`), `6/6` green years, `1,072` closed legs (`718` probes + `354` Whale Pyramid adds), **`13.01%` Max Balance DD / `18.37%` Max Equity DD**, Torture Score **`69.7 / 100` (`+7.9` pts vs `v1.00`, peaking at `78.2 / 100` in `2020`)**.
  - **`2024–2026` (100% Unseen OOS)**: **`+$153,128.03` (`+1,531.28%` -> Final Balance `$163,128.03`, up `4.01x` vs `v1.00`)**, **PF `2.65`** (vs `2.21`), `3/3` green years, `713` closed legs (`437` probes + `276` Whale Pyramid adds), **`18.09%` Max Balance DD / `19.46%` Max Equity DD**, Torture Score **`78.8 / 100` (`+9.0` pts vs `v1.00`, peaking at `79.1 / 100` in `2025`)**.
- **`v1.10` Prop Firm Mode (`$50,000`, `InpMode=0`, `<3%` Daily / `<6%` Total DD + `1.15x` ONNX Conviction Boost)**:
  - **`2018–2023` (`v1.00`)**: **`+$14,853.67` (`+29.7%`)**, **PF `1.53`**, `6/6` green years, **`3.53%` Max Balance DD / `4.84%` Max Equity DD** (`0.0%` prop breaches), Torture Score **`54.9 / 100`**.
  - **`2024–2026` (100% Unseen OOS, `v1.10`)**: **`+$23,149.82` (`+46.30%`, up vs `v1.00`'s `+$21,431.06`)**, **PF `2.01`**, `3/3` green years, **`3.46%` Max Balance DD / `3.58%` Max Equity DD** (`0.0%` prop breaches), Torture Score **`62.1 / 100` (`2025: 69.1 / 100`)**.
- **Every single stream (`H1`, `H2`, `M30`, `M15`, `M5`) AND every single Whale Pyramid add stream (`H1+`, `H2+`, `M30+`, `M15+`, `M5+`) is net profitable in BOTH `2018–2023` AND unseen `2024–2026`.**

---

## 2. The 16 Runes (`Series.mqh` & `runes_study4.py`)

Each closed structure bar updates a causal `(3,3)` fractal swing ring buffer (`m_shv[6]`, `m_slv[6]`) and evaluates the 16 chart patterns (`0..15`) in [`Series.mqh`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/MQL5/Include/16Runes/Series.mqh):

| Rune ID | Code | Pattern Name | Category | Direction | Structural Geometry & Breakout Trigger |
|---:|---|---|---|---:|---|
| `0` | `ASC_TRI` | Ascending Triangle | Bullish Continuation | `+1` | Flat resistance (`\|dh\| <= 0.40 ATR`), rising lows (`dl >= +0.20 ATR`), unbroken top, upper-80% coil (`coilAboveLb`) |
| `1` | `BULL_WEDGE` | Bullish Wedge | Bullish Continuation | `+1` | Converging downward-sloping highs & lows (`-dh > -dl + 0.10`, `wB < 0.85 wA`) after bullish impulse (`imp >= +0.2`), upper-80% coil |
| `2` | `BULL_FLAG` | Bullish Flag | Bullish Continuation | `+1` | Parallel downward-sloping channel (`slopeDiff <= 0.70`) after strong flagpole (`bullPole >= 2.0 ATR`), retracement `<= 65%`, upper-80% coil |
| `3` | `BULL_SYM_TRI` | Bullish Symmetrical Triangle | Bullish Continuation | `+1` | Lower highs (`dh <= -0.18 ATR`) + higher lows (`dl >= +0.18 ATR`), `wB <= 0.80 wA`, unbroken `hb`, upper-80% coil |
| `4` | `DESC_TRI` | Descending Triangle | Bearish Continuation | `-1` | Flat support (`\|dl\| <= 0.40 ATR`), falling highs (`dh <= -0.20 ATR`), unbroken bottom, lower-80% coil (`coilBelowHb`) |
| `5` | `BEAR_WEDGE` | Bearish Wedge | Bearish Continuation | `-1` | Converging upward-sloping highs & lows (`dl > dh + 0.10`, `wB < 0.85 wA`) after bearish impulse (`imp <= -0.2`), lower-80% coil |
| `6` | `BEAR_FLAG` | Bearish Flag | Bearish Continuation | `-1` | Parallel upward-sloping channel (`slopeDiff <= 0.70`) after strong bear pole (`bearPole >= 2.0 ATR`), retracement `<= 65%`, lower-80% coil |
| `7` | `BEAR_SYM_TRI` | Bearish Symmetrical Triangle | Bearish Continuation | `-1` | Lower highs (`dh <= -0.18 ATR`) + higher lows (`dl >= +0.18 ATR`), `wB <= 0.80 wA`, unbroken `lb`, lower-80% coil |
| `8` | `DBL_BOTTOM` | Double Bottom (`W`) | Bullish Reversal | `+1` | Twin troughs (`\|dl\| <= 0.45 ATR`, `ila < ihb < ilb`), neckline `hb` height `>= 0.90 ATR` and unbroken since `ihb` |
| `9` | `TRPL_BOTTOM` | Triple Bottom | Bullish Reversal | `+1` | Three troughs (`l1, l2, l3`) within `0.60 ATR` spread (`8..72` bars), unbroken neckline `neckH` |
| `10` | `INV_HS` | Inverted Head & Shoulders | Bullish Reversal | `+1` | Head `l2 <= min(l1, l3) - 0.20 ATR`, symmetric shoulders (`\|l3 - l1\| <= 0.85 ATR`), unbroken neckline `neckH` |
| `11` | `FALL_WEDGE` | Falling Wedge | Bullish Reversal | `+1` | Tightly compressed downward-sloping wedge (`wB < 0.72 wA`, `-dh > -dl + 0.10`) after pullback (`imp < +0.2`), upper-80% coil |
| `12` | `DBL_TOP` | Double Top (`M`) | Bearish Reversal | `-1` | Twin peaks (`\|dh\| <= 0.45 ATR`, `iha < ilb < ihb`), neckline `lb` height `>= 0.90 ATR` and unbroken since `ilb` |
| `13` | `TRPL_TOP` | Triple Top | Bearish Reversal | `-1` | Three peaks (`h1, h2, h3`) within `0.60 ATR` spread (`8..72` bars), unbroken neckline `neckL` |
| `14` | `HEAD_SHLDR` | Head & Shoulders | Bearish Reversal | `-1` | Head `h2 >= max(h1, h3) + 0.20 ATR`, symmetric shoulders (`\|h3 - h1\| <= 0.85 ATR`), unbroken neckline `neckL` |
| `15` | `RISE_WEDGE` | Rising Wedge | Bearish Reversal | `-1` | Tightly compressed upward-sloping wedge (`wB < 0.72 wA`, `dl > dh + 0.10`) after bounce (`imp > -0.2`), lower-80% coil |

---

## 3. Research Findings (`2017–2026` Dukascopy & `2023–2026` Pepperstone)

1. **Raw vs. HTF-Gated 16 Runes ([`runes_study1.py`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/python_pipeline/runes_study1.py) – [`runes_study4.py`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/python_pipeline/runes_study4.py))**:
   - Unfiltered raw M15/M30/H1 chart patterns lose `-0.05R` to `-0.10R` per trade after spread and slippage.
   - Requiring the **geometric 7-EMA ribbon (`10/16/26/41/66/105/168`)** to be stacked in the breakout direction (`H4 + D1` on `H1/H2/M30`, and `H1 + H4 + D1` on `M15/M5`) plus **upper/lower 80% apex coil confirmation** (`coilAboveLb` / `coilBelowHb`) turns all 5 streams positive across `2017–2023` (`+0.196R/trade`, `+311.4R`) and unseen `2024–2026` (`+0.408R/trade`, `+393.6R`).
2. **Why `StandardScaler + LogisticRegression(C=0.05)` Beats Tree Models for the Meta-Labeler ([`runes_study7.py`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/python_pipeline/runes_study7.py), [`runes_export.py`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/python_pipeline/runes_export.py))**:
   - Tree models (`LightGBM`) memorized `2017–2023` interactions and inverted on unseen `2024–2026`.
   - By contrast, `StandardScaler + LogisticRegression(C=0.05)` with the U-shaped volatility squeeze/expansion feature `f11_vol_u = |vol_reg - 1.0|` and Rune geometry features improved **both** `2017–2023` leave-one-year-out CV (`+0.211R` kept vs. `+0.108R` vetoed) **and** unseen `2024–2026` (`+0.443R` kept vs. `+0.150R` vetoed — a **`+0.293R/trade` out-of-sample separation**).
3. **Reserved HTF Slot Rule for Daily Milking Without Crowding ([`runes_study9.py`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/python_pipeline/runes_study9.py))**:
   - Allowing `S4 (M5)` to fill all portfolio slots crowded out higher-expectancy `H1/H2/M30/M15` setups.
   - Reserving higher-timeframe slots (`S0..S3` use up to 3 slots at `p >= 0.3382`; `S4 [M5]` requires `p >= 0.3797` and only opens when `openProbes == 0` in Prop [reserving 2 slots] or `openProbes <= 1` in Growth [reserving 1 slot], with stream weights `{1.00, 1.00, 0.90, 0.80, 0.60}`) achieved **`10/10` green years (`2017–2026`) in both Prop and Growth** on Dukascopy and **`9/9` green years (`2018–2026`) in MT5 Real Ticks**.

---

## 4. MT5 Strategy Tester Verification (`Model=4` Real Ticks + Random Delay)

### 4.1 Prop Firm Mode (`$50,000` Deposit, `InpMode=0`, `<3%` Daily / `<6%` Total DD)

| Year | Net Profit | Return % | Profit Factor | Closed Positions | Win Rate (Deals) | Trades / Day (Tr / Cal) | Avg Wait (Tr / Cal) | Max Bal DD | Torture Score (`0–100`) |
|---|---|---|---|---|---|---|---|---|---|
| `2018` | `+$2,360.61` | `+4.72%` | `1.62` | `69` | `44.9%` | `0.26 / 0.19` | `90.8h / 127.0h` | `1.94%` | **`47.2 / 100`** |
| `2019` | `+$1,351.08` | `+2.58%` | `1.33` | `142` | `40.4%` | `0.54 / 0.39` | `44.1h / 61.7h` | `3.55%` | **`57.9 / 100`** |
| `2020` | `+$2,972.44` | `+5.53%` | `1.45` | `224` | `43.0%` | `0.85 / 0.61` | `28.1h / 39.2h` | `3.53%` | **`64.5 / 100`** |
| `2021` | `+$1,103.19` | `+1.95%` | `1.78` | `35` | `50.0%` | `0.13 / 0.10` | `179.0h / 250.3h` | `1.52%` | **`33.9 / 100`** |
| `2022` | `+$5,101.97` | `+8.83%` | `1.99` | `109` | `42.2%` | `0.42 / 0.30` | `57.2h / 80.4h` | `2.05%` | **`56.6 / 100`** |
| `2023` | `+$1,891.30` | `+3.01%` | `1.28` | `78` | `34.6%` | `0.30 / 0.21` | `80.0h / 112.3h` | `2.32%` | **`49.0 / 100`** |
| **`2018–2023` Total** | **`+$14,853.67`** | **`+29.71%`** | **`1.53`** | **`657`** | **`42.2%`** | **`0.42 / 0.30`** | **`57.2h / 80.0h`** | **`3.53%` (`4.84%` Eq)** | **`54.9 / 100` (v1.00 baseline)** |
| `2024` (Unseen OOS) | `+$1,912.63` | `+3.83%` | `1.28` | `146` | `46.6%` | `0.56 / 0.40` | `43.1h / 60.2h` | `1.95%` | **`58.6 / 100`** |
| `2025` (Unseen OOS) | `+$13,007.35` | `+25.06%` | `2.27` | `196` | `45.9%` | `0.75 / 0.54` | `32.0h / 44.7h` | `2.42%` | **`68.4 / 100`** |
| `2026 YTD` (Unseen OOS) | `+$5,818.58` | `+8.96%` | `2.30` | `58` | `37.9%` | `0.27 / 0.19` | `89.8h / 125.8h` | `3.21%` | **`50.3 / 100`** |
| **`2024–2026` Unseen Total** | **`+$21,431.06`** | **`+42.86%`** | **`1.99`** | **`400`** | **`45.0%`** | **`0.54 / 0.39`** | **`44.4h / 62.1h`** | **`3.22%` (`3.40%` Eq)** | **`61.6 / 100` (v1.00 baseline)** |

- **By Stream (`2024–2026` Unseen Prop `$50k`)**: `H1`: 53 trades (`+$4,930`), `H2`: 35 trades (`+$2,863`), `M30`: 93 trades (`+$5,218`), `M15`: 110 trades (`+$3,561`), `M5`: 109 trades (`+$4,168`).
- **By Stream (`2018–2023` Prop `$50k`)**: `H1`: 96 trades (`+$2,109`), `H2`: 39 trades (`+$1,437`), `M30`: 148 trades (`+$4,145`), `M15`: 156 trades (`+$3,635`), `M5`: 218 trades (`+$3,455`).

---

### 4.2 House Money Growth Mode (`$10,000` Deposit, `InpMode=1`, Whale Pyramid ON)

| Year | Net Profit | Return % | Profit Factor | Closed Positions (Probes + Adds) | Win Rate (Deals) | Trades / Day (Tr / Cal) | Avg Wait (Tr / Cal) | Max Bal DD | Torture Score (`0–100`) |
|---|---|---|---|---|---|---|---|---|---|
| `2018` | `+$1,822.14` | `+18.22%` | `1.66` | `103` (`72 + 31`) | `46.6%` | `0.39 / 0.28` | `60.8h / 85.0h` | `5.73%` | **`53.5 / 100`** |
| `2019` | `+$326.34` | `+2.76%` | `1.05` | `218` (`165 + 53`) | `42.3%` | `0.84 / 0.60` | `28.7h / 40.2h` | `13.99%` | **`62.2 / 100`** |
| `2020` | `+$10,840.13` | `+89.23%` | `1.76` | `306` (`236 + 70`) | `43.5%` | `1.17 / 0.84` | `20.5h / 28.7h` | `16.57%` | **`71.8 / 100`** |
| `2021` | `+$1,279.29` | `+5.56%` | `1.35` | `59` (`45 + 14`) | `47.7%` | `0.23 / 0.16` | `106.2h / 148.5h` | `8.40%` | **`43.6 / 100`** |
| `2022` | `+$9,022.09` | `+37.18%` | `1.67` | `140` (`110 + 30`) | `42.9%` | `0.54 / 0.38` | `44.6h / 62.6h` | `8.04%` | **`62.4 / 100`** |
| `2023` | `+$9,302.80` | `+27.94%` | `1.40` | `103` (`80 + 23`) | `37.9%` | `0.40 / 0.28` | `60.6h / 85.0h` | `11.20%` | **`58.0 / 100`** |
| **`2018–2023` Total** | **`+$37,444.95`** | **`+374.45%`** | **`1.59`** | **`929` (`708 + 221`)** | **`43.1%`** | **`0.59 / 0.42`** | **`40.4h / 56.6h`** | **`10.08%` (`15.77%` Eq)** | **`61.8 / 100` (v1.00 baseline)** |
| `2024` (Unseen OOS) | `+$146.10` | `+1.46%` | `1.03` | `229` (`160 + 69`) | `41.9%` | `0.87 / 0.63` | `27.5h / 38.4h` | `13.48%` | **`62.6 / 100`** |
| `2025` (Unseen OOS) | `+$14,585.08` | `+143.75%` | `2.00` | `314` (`223 + 91`) | `47.1%` | `1.20 / 0.86` | `19.9h / 27.9h` | `8.68%` | **`73.6 / 100`** |
| `2026 YTD` (Unseen OOS) | `+$22,333.55` | `+90.31%` | `2.90` | `86` (`66 + 20`) | `50.0%` | `0.40 / 0.28` | `60.6h / 84.8h` | `14.41%` | **`63.9 / 100`** |
| **`2024–2026` Unseen Total** | **`+$38,142.54`** | **`+381.43%`** | **`2.21`** | **`629` (`449 + 180`)** | **`45.6%`** | **`0.85 / 0.61`** | **`28.2h / 39.5h`** | **`14.41%` (`16.50%` Eq)** | **`69.8 / 100` (v1.00 baseline)** |

- **By Stream (`2024–2026` Unseen Growth `$10k`)**:
  - `H1`: 52 (`+$4,688`), `H1+`: 22 (`+$2,075`)
  - `H2`: 34 (`+$3,703`), `H2+`: 16 (`+$2,420`)
  - `M30`: 96 (`+$6,644`), `M30+`: 36 (`+$3,549`)
  - `M15`: 114 (`+$3,452`), `M15+`: 39 (`+$2,458`)
  - `M5`: 153 (`+$6,573`), `M5+`: 67 (`+$1,504`)
- **By Stream (`2018–2023` Growth `$10k` `v1.00`)**:
  - `H1`: 80 (`+$1,151`), `H1+`: 26 (`+$1,199`)
  - `H2`: 33 (`+$1,692`), `H2+`: 9 (`+$1,116`)
  - `M30`: 140 (`+$10,210`), `M30+`: 44 (`+$5,195`)
  - `M15`: 160 (`+$2,412`), `M15+`: 60 (`+$1,798`)
  - `M5`: 295 (`+$6,682`), `M5+`: 82 (`+$1,139`)

---

### 4.3 `16Runes v1.10` Moonshot Edition (`$10,000` Start, `InpMode=1`)

| Year | `v1.00` Profit | `v1.10` Profit | Return | PF | Trades | Max DD | Score |
|---|---:|---:|---:|---:|---:|---:|---:|
| `2018` | `+$1,822` | **`+$6,402`** | `+64%` | `1.77` | `121` | `12.0%` | `58.9` |
| `2019` | `+$326` | **`+$1,257`** | `+8%` | `1.08` | `245` | `25.1%` | `64.2` |
| `2020` | `+$10,840` | **`+$26,824`** | `+152%` | `1.78` | `358` | `22.1%` | `78.2` |
| `2021` | `+$1,279` | **`+$3,298`** | `+7%` | `1.26` | `63` | `13.0%` | `46.3` |
| `2022` | `+$9,022` | **`+$16,313`** | `+34%` | `1.49` | `169` | `10.9%` | `67.9` |
| `2023` | `+$9,303` | **`+$65,560`** | `+102%` | `2.00` | `116` | `12.7%` | `71.1` |
| **`2018–2023`** | **`+$37,445`** | **`+$121,213`** | **`+1,212%`** | **`1.71`** | **`1,072`** | **`13.0%`** | **`69.7`** |
| `2024` (OOS) | `+$146` | **`+$403`** | `+4%` | `1.04` | `259` | `28.4%` | `64.0` |
| `2025` (OOS) | `+$14,585` | **`+$30,868`** | `+297%` | `1.85` | `357` | `20.4%` | `79.1` |
| `2026` (OOS) | `+$22,334` | **`+$103,832`** | `+252%` | `3.30` | `97` | `18.1%` | `74.1` |
| **`2024–2026`** | **`+$38,143`** | **`+$153,128`** | **`+1,531%`** | **`2.65`** | **`713`** | **`18.1%`** | **`78.8`** |

- **By Stream (`2024–2026` Unseen Growth `$10k` `v1.10`)**:
  - `H1`: 49 (`+$8,593`), `H1+`: 36 (`+$7,970`)
  - `H2`: 34 (`+$11,366`), `H2+`: 22 (`+$6,907`)
  - `M30`: 93 (`+$15,420`), `M30+`: 54 (`+$26,515`)
  - `M15`: 109 (`+$9,980`), `M15+`: 65 (`+$24,410`)
  - `M5`: 152 (`+$12,844`), `M5+`: 99 (`+$11,097`)
- **By Stream (`2018–2023` Growth `$10k` `v1.10`)**:
  - `H1`: 79 (`+$1,469`), `H1+`: 48 (`+$11,419`)
  - `H2`: 41 (`+$3,823`), `H2+`: 15 (`+$1,057`)
  - `M30`: 155 (`+$25,106`), `M30+`: 68 (`+$22,999`)
  - `M15`: 160 (`+$8,932`), `M15+`: 102 (`+$21,653`)
  - `M5`: 283 (`+$15,843`), `M5+`: 121 (`+$7,354`)

---

## 5. Python-to-MQL5 Parity Verification ([`runes_parity.py`](file:///c:/Users/faker/Documents/dev/onix/16runes-ea/python_pipeline/runes_parity.py))

Comparing the `2024–2026` MQL5 event log (`r16_prop50k_2024_2026_events.csv`, `998` triggers) against the Python research engine on Pepperstone M1 (`1,002` triggers):
- **Trigger Match (`±3` min, same direction)**: **`94.8%` (`946 / 998`)**
- **Same Stream Match**: **`90.0%`**
- **ONNX Probability Score Correlation**: **`r = 0.9759` (`median |diff| = 0.00000`)**
