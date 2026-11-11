# 7Wave ribbon as the trend filter for the swing breakout (2026-11-06)

The 7Wave signals time entries at coin-flip odds (`SCORECARD.md`, `TRAINER_RESULTS.md`). This test asks a different
question: does the user's ribbon work as the **trend filter** for the one entry that held up in 10 years of
SevenWave research?

## The test

Code: `research/gate_test.py`. It reuses the SevenWave research engine unchanged
(`xauusd-sevenwave-ea/python_pipeline`).

- **Entry**: a stop order 0.15 ATR(H1) before an unbroken H1 fractal swing high or low (3 bars on each side), aged
  12-48 H1 bars, and only in the trend filter's direction.
- **Management** ("growth"): stop 1.5 ATR(H1); trail 2 ATR once the trade is +1R; target 3R; at most 24 hours.
- **Costs and fills**: fill-accurate on M1 bars, with hostile costs (spread, commission, slippage, swap).
- **Trend filter**: the state of the last closed bar of each timeframe, with no look-ahead.
  - **7Wave ribbon on H4 + D1**: the user's 20/40/60/80/100/120/140 EMAs, all 7 lines stacked the same way on both
    H4 and D1. These periods were never tuned.
  - **Reference**: the SevenWave ribbon 10/16/26/41/66/105/168, which was selected on 2017-2022 data.
- **Data**: Dukascopy 2017-2026, judged on 2017-2022 (seen) and 2023-2026 (unseen). Checked again on Pepperstone's
  own M1 data with real spreads, 2023-2026.

## Results by trend filter (average R per trade, after costs)

| Trend filter | Trades | Trades/day | Win rate | Avg R | Seen 2017-22 (green years) | Unseen 2023-26 (green years) | Pepperstone 2023-26 |
|---|---|---|---|---|---|---|---|
| No filter | 1,956 | 0.78 | 39% | -0.006 | -0.012 (3 of 6) | +0.003 (3 of 4) | +0.028 |
| SevenWave ribbon on H4 + D1 (reference, tuned) | 277 | 0.11 | 48% | +0.328 | +0.253 (6 of 6) | +0.413 (4 of 4) | +0.442 |
| **7Wave ribbon on H4 + D1** | 367 | 0.15 | 45% | **+0.255** | +0.249 (5 of 6) | +0.262 (3 of 4) | **+0.315** |
| 7Wave ribbon on H4 | 604 | 0.24 | 43% | +0.147 | +0.145 (5 of 6) | +0.151 (3 of 4) | +0.218 |
| 7Wave wave (the indicator's arrows) on H4 | 643 | 0.26 | 42% | +0.122 | +0.114 (6 of 6) | +0.134 (3 of 4) | +0.187 |
| 7Wave wave on H1 | 656 | 0.26 | 43% | +0.129 | +0.074 (4 of 6) | +0.215 (4 of 4) | +0.223 |

- **The breakout alone is worth nothing**: -0.006R over 1,956 trades.
- **With the user's ribbon on H4 + D1** it makes +0.255R per trade, positive in both the seen and unseen years, and
  +0.315R on Pepperstone's own data.
- **A trade-off between edge and frequency**: the looser 7Wave filters (H4 only, or the live wave) trade about
  twice as often at about half the edge.
- **Whale management** (stop to +0.05R at +1.5R, trail 3 ATR, target 5R, 72 h) lifts the 7Wave ribbon on H4 + D1 to
  +0.410R per trade (+0.734R on Pepperstone 2023-26). Almost all of that extra comes from the big trend years
  2025-2026, and 2017-2019 are weaker.

## Account tables

Growth management, one position at a time, $10,000, 1% of the balance risked per trade, compounding.

**7Wave ribbon on H4 + D1, Dukascopy:**

| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |
|---|---|---|---|---|---|---|---|
| 2017 | $+1,214 (+12.1%) | 32 | 47% | 0.12 | 186 h | 5.1% | 24.4 |
| 2018 | $+950 (+8.5%) | 23 | 48% | 0.09 | 284 h | 3.4% | 26.6 |
| 2019 | $+1,906 (+15.7%) | 32 | 47% | 0.12 | 258 h | 3.3% | 24.8 |
| 2020 | $+693 (+4.9%) | 45 | 44% | 0.17 | 142 h | 4.1% | 24.3 |
| 2021 | $-266 (-1.8%) | 9 | 22% | 0.03 | 782 h | 5.8% | 10.1 |
| 2022 | $+444 (+3.1%) | 34 | 35% | 0.13 | 205 h | 8.7% | 12.5 |
| 2023 | $-597 (-4.0%) | 26 | 27% | 0.10 | 329 h | 11.1% | 8.7 |
| 2024 | $+1,156 (+8.1%) | 40 | 48% | 0.15 | 185 h | 7.8% | 17.1 |
| 2025 | $+6,141 (+39.6%) | 61 | 57% | 0.24 | 137 h | 5.5% | 37.8 |
| 2026 | $+295 (+1.4%) | 8 | 38% | 0.04 | 709 h | 1.9% | 18.4 |
| **All** | $+11,936 (+119%) | 310 | 45% | 0.12 | 271 h | 11.1% | |

**7Wave ribbon on H4 + D1, Pepperstone with real spreads:**

The EMAs start warming up in January 2023, so 2023 is partly a warm-up year.

| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |
|---|---|---|---|---|---|---|---|
| 2023 | $+30 (+0.3%) | 29 | 34% | 0.11 | 304 h | 6.8% | 15.9 |
| 2024 | $+1,191 (+11.9%) | 40 | 50% | 0.15 | 185 h | 3.3% | 24.6 |
| 2025 | $+4,460 (+39.7%) | 60 | 58% | 0.23 | 139 h | 5.5% | 37.1 |
| 2026 | $+157 (+1.0%) | 14 | 36% | 0.06 | 538 h | 3.5% | 15.1 |
| **All** | $+5,838 (+58%) | 143 | 49% | 0.14 | 235 h | 6.8% | |

**For comparison, the tuned SevenWave reference, Dukascopy:**
- All 10 years positive.
- 235 trades, +$11,344 (+113%), max DD 6.1%.
- One trade every 14 days (340 h average wait).

## What changed and what is still open

- **What changed**: the user's untuned ribbon, used as the trend context, does the job the tuned SevenWave ribbon
  did. It turns a coin-flip entry into a +0.25-0.32R per trade edge on both data feeds, and it trades 32% more often
  than the reference.
- **Open challenges**:
  - **Frequency.** About one trade every 11 days (0.12 a day) at the strict H4 + D1 filter. The looser filters
    double that, at half the edge.
  - **Losing years.** 2021 (-1.8%) and 2023 (-4.0%) lost money, and the worst drawdown was 11.1% at 1% risk.
  - **Parameters.** The entry's settings (age 12-48, offset 0.15) were chosen in the SevenWave research on
    2017-2022 data. The 2023-2026 results are unseen for them, and they hold.
  - **Still a research result.** It becomes trustworthy the same way the indicator did: drawn on the chart and
    checked by the user, then traded by the EA and confirmed in the MT5 tester on real ticks.
