# 7Wave wave scorecard (2026-11-06)

The question: at the moment a star or arrow is drawn, can anything visible on the chart, or an AI, tell the big waves
(the user's screenshots 1 and 2) from the fakes (screenshots 3 and 4)?

## What was measured

- **Signals**: every star and arrow of indicator v1.20 (`tools/wave_rules.py`, the rules the user checked on the chart),
  on H1 and M15.
- **Data**: Dukascopy XAUUSD M1, 2018 to 2026-09, on the Pepperstone chart clock (NY+7).
  - Feed check: Pepperstone M1 with its real spreads, 2024 to 2026-09.
- **Costs**: the hostile model of the SevenWave research.
  - Entry at the next M1 open after the signal bar closes; longs buy at the ask.
  - Spread $0.30 ($0.60 at the rollover), commission $0.08/oz, slippage $0.05 market / $0.10 stop, long swap.
  - If the stop and the target fall in the same M1 bar, the stop wins.
- **Trade**: R = 1.5 x ATR(14) of the signal timeframe.
  - **Good wave**: the +3R target is hit before the -1R stop. Time exit after 5 days (H1) or 2 days (M15).
  - **Fake**: stopped out before ever reaching +1R.
- **Seen / unseen**: every split was fixed on 2018-2021 and judged on 2022-2026, and year by year.
- **Code**: `research/wave_scorecard.py`. Raw output and per-signal CSVs are in `C:\Users\faker\Documents\goldie_research\7wave\`.

## 1. Taking every signal

**H1** (one signal every 2.9 trading days):

| Year | Signals | Signals/day | Avg wait | Good waves (+3R first) | Fakes | Avg R after costs | Total R |
|---|---|---|---|---|---|---|---|
| 2018 | 103 | 0.40 | 81 h | 15% | 59% | -0.519 | -53.4 |
| 2019 | 101 | 0.39 | 83 h | 21% | 50% | -0.302 | -30.5 |
| 2020 | 93 | 0.36 | 89 h | 18% | 56% | -0.320 | -29.8 |
| 2021 | 85 | 0.33 | 102 h | 21% | 53% | -0.241 | -20.5 |
| 2022 | 92 | 0.36 | 95 h | 27% | 48% | +0.033 | +3.0 |
| 2023 | 73 | 0.28 | 114 h | 25% | 55% | -0.083 | -6.0 |
| 2024 | 97 | 0.37 | 91 h | 24% | 55% | -0.091 | -8.8 |
| 2025 | 70 | 0.27 | 126 h | 30% | 47% | +0.188 | +13.2 |
| 2026 | 71 | 0.37 | 90 h | 18% | 45% | -0.303 | -21.5 |
| **All** | 785 | 0.35 | 97 h | 22% | 52% | -0.197 | -154.4 |

**M15** (1.3 signals per trading day):

| Year | Signals | Signals/day | Avg wait | Good waves (+3R first) | Fakes | Avg R after costs | Total R |
|---|---|---|---|---|---|---|---|
| 2018 | 376 | 1.46 | 23 h | 19% | 59% | -0.398 | -149.5 |
| 2019 | 355 | 1.38 | 25 h | 17% | 59% | -0.471 | -167.2 |
| 2020 | 328 | 1.27 | 27 h | 24% | 56% | -0.128 | -42.0 |
| 2021 | 357 | 1.38 | 24 h | 22% | 55% | -0.225 | -80.2 |
| 2022 | 341 | 1.32 | 25 h | 27% | 48% | -0.020 | -6.9 |
| 2023 | 332 | 1.29 | 26 h | 21% | 58% | -0.216 | -71.7 |
| 2024 | 360 | 1.39 | 24 h | 22% | 53% | -0.219 | -79.0 |
| 2025 | 316 | 1.22 | 28 h | 23% | 58% | -0.128 | -40.5 |
| 2026 | 242 | 1.25 | 27 h | 25% | 55% | -0.029 | -6.9 |
| **All** | 3007 | 1.33 | 25 h | 22% | 56% | -0.214 | -644.0 |

Stars and arrows score the same: H1 stars -0.170R and arrows -0.212R; M15 stars -0.230R and arrows -0.206R.

## 2. How far the waves run, compared with a coin flip

No target, -1R stop, up to 10 days (H1) or 4 days (M15). A random walk gives the "coin flip" column, without drift
or a time limit:

| Run before the -1R stop | H1 | M15 | Coin flip |
|---|---|---|---|
| 3R or more | 22% | 22% | 25% |
| 5R or more | 14% | 15% | 17% |
| 10R or more | 6% | 9% | 9% |

Waves like screenshots 1 and 2 happen after a star or arrow about as often as they would after a coin flip. This is
the root of everything below.

## 3. Context visible at the signal

Average R (good-wave bracket) for each bucket. The "years" column counts the years where the bucket that was best on
2018-2021 beat the worst one.

| Context | TF | Seen 2018-21 | Unseen 2022-26 | Years |
|---|---|---|---|---|
| H4 ribbon: all 7 in order vs 0-3 | H1 | -0.291 vs -0.385 | -0.089 vs **+0.056** (flipped) | 4 of 9 |
| H4 ribbon: all 7 in order vs 0-3 | M15 | -0.399 vs -0.284 | -0.046 vs -0.182 (flipped) | 6 of 9 (lost 2019-21, won 2022-26) |
| H1 ribbon: all 7 in order vs 0-3 | M15 | -0.420 vs -0.243 | -0.003 vs -0.203 (flipped) | 5 of 9 |
| Volatility expanding: ATR(14)/ATR(100) high vs mid | H1 | -0.198 vs -0.459 | +0.113 vs -0.166 | **8 of 9** |
| Session: London 06-12 vs Evening 17-22 UTC | M15 | -0.186 vs -0.514 | -0.190 vs -0.497 | **8 of 9** |
| EMA 140 slope, flat vs steep | H1 | -0.232 vs -0.547 | -0.080 vs -0.049 | 5 of 9 |
| Squeeze before the signal, low vs high | H1 | -0.118 vs -0.576 | -0.259 vs **+0.112** (flipped) | 4 of 9 |
| Signals in the last 100 bars (chop), high vs low | H1 | -0.207 vs -0.487 | -0.335 vs **+0.077** (flipped) | 4 of 9 |
| Star vs arrow | H1 | -0.320 vs -0.370 | -0.017 vs -0.067 | 4 of 9 |

- **No higher-timeframe gate holds.** Trading with the H4 or H1 ribbon helped in 2022-2026 and hurt in 2018-2021.
  It is a bet on trending years, not a separator.
  - The strongest case is M15 with the H4 ribbon in order. It did better in every year from 2022 to 2026, yet still
    averaged only about breakeven (-0.046R).
- **The tilt of the slow lines** that is visible in screenshots 1 and 2 shows up in the fakes just as often.
- **Two effects are consistent but small**:
  - On H1, signals while volatility is expanding (ATR(14)/ATR(100) above about 1.12) did better in 8 of 9 years.
  - On M15, signals in the 17:00-22:00 UTC evening did worst in 8 of 9 years: 16-19% good waves, -0.5R.
  - Neither makes the signals profitable on its own.

## 4. The AI

Walk-forward LightGBM on all 13-14 context features, trained on the years before each test year:

| TF | Pooled out-of-sample AUC | Top half beat bottom half |
|---|---|---|
| H1 | 0.503 | 5 of 7 years |
| M15 | 0.519 | 4 of 7 years |

That is a coin flip, the same as every earlier attempt on gold: 0.48 with 31 features, 0.50-0.545 on aligned M15 bars,
and Kronos at 49.5-50.3%.

## 5. Holding the waves

SevenWave whale handling: no target; at +1.5R the stop locks +0.05R, then it trails 3 ATR(H1).

| Year | H1: avg R | M15: avg R |
|---|---|---|
| 2018 | -0.439 | -0.426 |
| 2019 | -0.267 | -0.148 |
| 2020 | -0.297 | -0.012 |
| 2021 | +0.197 | -0.113 |
| 2022 | +0.070 | -0.047 |
| 2023 | -0.140 | -0.045 |
| 2024 | -0.165 | -0.013 |
| 2025 | +0.031 | -0.021 |
| 2026 | -0.316 | -0.170 |
| **All** | **-0.157** (32% winners, best +21.2R) | **-0.113** (22% winners, best +37.8R) |

Holding helps M15 (-0.214R becomes -0.113R) and catches the big waves (best trades +21R and +38R). It cannot fix entries
whose waves come at coin-flip odds.

## 6. Feed check

Pepperstone with its real spreads and Dukascopy agree.
- **H1:** the same 97 and 70 signals in 2024 and 2025, with -0.096R vs -0.091R in 2024 and +0.188R on both feeds in 2025.
- **M15:** 360 vs 360 signals in 2024 and 315 vs 316 in 2025.

The simulation matches the broker's own data.

## What it means

- **The problem:** the difference between screenshots 1-2 and 3-4 forms after the signal. At the signal, neither the
  14 measured contexts nor an AI trained on them can see it. A bigger GPU on the same inputs gives the same answer.
- **The way forward:** the information has to come from somewhere these features don't reach.
  1. **The user's eye, tested blind.** A replay that hides the future and asks Take or Skip at each signal.
     - If the user's picks beat "take everything" at decision time, the eye sees something real, and those labels
       are what an AI can learn.
     - If they don't, the edge in the user's manual trading came from how trades were managed, not from which
       waves were picked.
  2. **The two consistent effects** can go on the chart as candidate rules: H1 volatility expansion, and no M15
     signals in the 17-22 UTC evening.
  3. **The entry that did hold up**: in the SevenWave research, a stop entry at an old, untouched H1/H2 swing
     high/low, taken only with the bigger-timeframe ribbon. It made +0.14 to +0.39R per trade and was positive in 7-9
     of 10 years. The 7Wave ribbon could be that trend context, with the swing breakout as the trigger.
