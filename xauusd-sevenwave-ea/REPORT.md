# SevenWave v1.33: Backtest & Research Report (2026-11-04)

**v1.33** = v1.31 whale handling, with two changes:
- **No AI veto.** The rater had memorised 2017-2023, and on unseen years it vetoed better-than-average setups.
- **Kelly-safe Growth budget.** Growth bets at most 25% of the room above its trailing floor.

These are the most honest 2018-2023 numbers so far: no machine-learned part has seen the years it is scored on. Two caveats
remain. The strategy design was chosen on 2017-2022, and the few whale settings of v1.20-v1.31 (+1.5R, 5R, 72h, 3 ATR) were
kept because they helped both windows.

The deployed build was re-run on 2024-2026: Prop +$24,961 (+49.9%), Growth +$300,584 (+3,006%), with no vetoes. That matches
the test builds below within random-delay noise.

## v1.33 results (Pepperstone XAUUSD, Model 4 + random delay, 1:100, defaults, every input explicit; each window starts fresh)

**Prop Firm: $50,000 · 0.5% risk · daily 3% · trailing 6% · day banked at +2.4%**

| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |
|---|---|---|---|---|---|---|---|
| 2018 | +$465 (+0.9%) | 92 | 38.0% | 0.35 | 73 h | 2.53% | 25.7 |
| 2019 | +$2,471 (+4.9%) | 111 | 41.4% | 0.43 | 73 h | 3.42% | 27.4 |
| 2020 | +$5,838 (+11.0%) | 161 | 46.6% | 0.61 | 47 h | 2.57% | 38.5 |
| 2021 | +$510 (+0.9%) | 37 | 45.9% | 0.14 | 176 h | 1.88% | 25.9 |
| 2022 | +$2,325 (+3.9%) | 114 | 47.4% | 0.44 | 61 h | 2.50% | 31.0 |
| 2023 | +$2,859 (+4.6%) | 94 | 42.6% | 0.36 | 89 h | 2.72% | 26.8 |
| **2018-2023** | **+$14,467 (+28.9%)** | 609 | 43.8% | 0.39 | 86 h | 3.73% | 27.0 |
| 2024 | +$5,454 (+10.9%) | 157 | 43.9% | 0.60 | 48 h | 2.34% | 36.2 |
| 2025 | +$14,661 (+26.4%) | 217 | 46.5% | 0.83 | 39 h | 2.93% | 47.0 |
| 2026 YTD | +$3,968 (+5.7%) | 64 | 29.7% | 0.29 | 113 h | 3.26% | 29.5 |
| **2024-2026** | **+$24,082 (+48.2%)** | 438 | 43.2% | 0.61 | 55 h | 3.26% | 37.8 |

MT5 equity DD: 4.33% and 4.01%, PF 1.40 and 1.80. Challenge replay (+8%, best day ≤ 30%, 180 days): 3.1% pass in 2018-2023, 36.8% pass in
2024-2026, 0 breaches.

**House Money Growth: $10,000 · 1% risk · daily 10% · trailing 30% · whale pyramid · Kelly-safe 25% of the trailing room**

| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |
|---|---|---|---|---|---|---|---|
| 2018 | +$819 (+8.2%) | 169 (50 adds) | 39.1% | 0.65 | 39 h | 20.98% | 23.3 |
| 2019 | +$5,285 (+48.8%) | 194 (56 adds) | 44.8% | 0.74 | 42 h | 20.20% | 33.4 |
| 2020 | +$25,037 (+155.5%) | 286 (81 adds) | 47.9% | 1.09 | 26 h | 19.38% | 49.8 |
| 2021 | +$593 (+1.4%) | 69 (20 adds) | 42.0% | 0.26 | 93 h | 13.35% | 14.4 |
| 2022 | +$12,069 (+28.9%) | 210 (61 adds) | 42.9% | 0.81 | 33 h | 12.80% | 33.3 |
| 2023 | +$10,009 (+18.6%) | 171 (45 adds) | 42.1% | 0.66 | 49 h | 15.62% | 25.4 |
| **2018-2023** | **+$53,812 (+538.1%)** | 1,099 (313 adds) | 43.8% | 0.70 | 48 h | 22.95% | 30.2 |
| 2024 | +$9,981 (+99.8%) | 300 (86 adds) | 45.3% | 1.15 | 25 h | 14.71% | 48.7 |
| 2025 | +$140,380 (+702.6%) | 423 (127 adds) | 50.8% | 1.62 | 20 h | 14.92% | 59.9 |
| 2026 YTD | +$129,697 (+80.9%) | 110 (25 adds) | 40.9% | 0.51 | 65 h | 12.32% | 34.9 |
| **2024-2026** | **+$280,058 (+2,800.6%)** | 833 (238 adds) | 47.5% | 1.16 | 29 h | 14.92% | 53.0 |

MT5 equity DD: 25.1% and 13.4%, PF 1.39 and 2.27.

**Aggressive Growth preset (inputs 2% / 15% / 50%):**
- 2018-2023: +$156,656 (+1,567%), max DD 43.0%.
- 2024-2026: +$3,191,449 (+31,914%), max DD 34.0%.

See the risk frontier below. With v1.31's 0.5 share, the same preset made +$444,009 and +$3,273,039, but 0.5 lets a default
account freeze at its floor.

## v1.31 results (history: the 2018-2023 rows include the in-sample AI veto)

**Prop Firm: $50,000 · 0.5% risk · daily 3% · trailing 6% · day banked at +2.4%**

| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |
|---|---|---|---|---|---|---|---|
| 2018 | +$1,314 (+2.6%) | 62 | 43.5% | 0.24 | 108 h | 2.21% | 26.7 |
| 2019 | +$3,826 (+7.5%) | 80 | 51.2% | 0.31 | 102 h | 1.92% | 31.0 |
| 2020 | +$9,627 (+17.5%) | 121 | 52.9% | 0.46 | 62 h | 2.34% | 38.4 |
| 2021 | +$1,619 (+2.5%) | 25 | 56.0% | 0.10 | 261 h | 1.04% | 29.4 |
| 2022 | +$3,551 (+5.3%) | 97 | 49.5% | 0.37 | 72 h | 2.31% | 31.7 |
| 2023 | +$5,660 (+8.1%) | 76 | 50.0% | 0.29 | 110 h | 1.54% | 28.6 |
| **2018-2023** | **+$25,596 (+51.2%)** | 461 | 50.3% | 0.30 | 114 h | 2.34% | 29.2 |
| 2024 | +$4,681 (+9.4%) | 126 | 46.0% | 0.48 | 60 h | 1.75% | 35.7 |
| 2025 | +$15,695 (+28.7%) | 189 | 45.0% | 0.72 | 44 h | 2.68% | 44.1 |
| 2026 YTD | +$4,550 (+6.5%) | 55 | 30.9% | 0.25 | 132 h | 2.52% | 29.9 |
| **2024-2026** | **+$24,926 (+49.9%)** | 370 | 43.2% | 0.52 | 65 h | 2.68% | 36.6 |

**House Money Growth: $10,000 · 1% risk · daily 10% · trailing 30% · whale pyramid**

| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |
|---|---|---|---|---|---|---|---|
| 2018 | +$2,851 (+28.5%) | 111 (36 adds) | 43.2% | 0.43 | 60 h | 16.67% | 22.4 |
| 2019 | +$7,166 (+55.8%) | 152 (52 adds) | 52.6% | 0.58 | 53 h | 16.92% | 33.3 |
| 2020 | +$42,703 (+213.3%) | 223 (70 adds) | 55.2% | 0.85 | 34 h | 15.26% | 50.8 |
| 2021 | +$9,289 (+14.8%) | 46 (14 adds) | 52.2% | 0.18 | 139 h | 7.08% | 22.4 |
| 2022 | +$30,703 (+42.6%) | 176 (56 adds) | 45.5% | 0.68 | 39 h | 12.83% | 32.0 |
| 2023 | +$40,380 (+39.3%) | 142 (41 adds) | 43.7% | 0.55 | 59 h | 14.33% | 26.9 |
| **2018-2023** | **+$133,092 (+1,330.9%)** | 850 (269 adds) | 49.1% | 0.54 | 62 h | 21.32% | 29.7 |
| 2024 | +$4,830 (+48.3%) | 237 (70 adds) | 44.3% | 0.90 | 32 h | 16.65% | 39.2 |
| 2025 | +$94,112 (+634.6%) | 355 (104 adds) | 51.5% | 1.36 | 24 h | 13.16% | 58.9 |
| 2026 YTD | +$96,072 (+88.2%) | 95 (22 adds) | 44.2% | 0.44 | 76 h | 11.86% | 33.9 |
| **2024-2026** | **+$195,014 (+1,950.1%)** | 687 (196 adds) | 48.0% | 0.96 | 35 h | 16.65% | 48.7 |

- **$1k Growth**: 2018-2023 grew to $10,760 (+976%), 2024-2026 to $12,647 (+1,165%).
- **Max equity drawdown (MT5)**: Prop 3.11% / 3.78% against the 6% limit. Growth $10k 23.99% / 13.25% against the 30% limit.
- **Prop challenge replay** (8% target, best day <= 30%, 3%/6%, 180 days): 39.3% pass on 2024-2026 starts, 0 breaches.

## v1.20 (history)

**v1.20** is v1.10 plus the **whale pyramid**, in House Money Growth mode only. When a position first reaches +1.5R, the EA adds
one unit of the same size, with its stop at the first entry and the same 3R target. Prop Firm mode is unchanged.

**v1.10 strategy:**
- **Trend gate:** a geometric 7-EMA ribbon **10/16/26/41/66/105/168** stacked on H1/H4/D1.
- **Entries:** liquidity-pool breakouts (aged, unbroken H1/H2/M15 swing levels).
- **AI:** a quality veto (ONNX).
- **Positions:** up to 2 (Prop) / 3 (Growth) concurrent, under a portfolio never-breach budget, plus the Prop consistency lock.

**Test setup:**
- Broker: Pepperstone XAUUSD.
- Tester: Model 4. Real ticks from 2025-01; before that, ticks are generated from real Pepperstone M1 bars.
- Execution: random delay. Leverage 1:100. Every input is passed explicitly.
- AI trained on Dukascopy 2017-2023, so **2024-2026 is out of sample** for the model.

## v1.20 Prop Firm mode: $50,000 · 0.5% risk · daily 3% · trailing 6% · 2 slots · day banked at +2.4% · no pyramid

| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |
|---|---|---|---|---|---|---|---|
| 2018 | +$1,601 (+3.2%) | 62 | 45.2% | 0.24 | 108 h | 1.72% | 25.4 |
| 2019 | +$3,455 (+6.7%) | 88 | 53.4% | 0.34 | 93 h | 1.86% | 33.1 |
| 2020 | +$6,549 (+11.9%) | 137 | 54.7% | 0.52 | 55 h | 2.37% | 40.0 |
| 2021 | +$1,777 (+2.9%) | 25 | 60.0% | 0.10 | 261 h | 1.13% | 32.0 |
| 2022 | +$4,248 (+6.7%) | 102 | 52.0% | 0.39 | 68 h | 2.10% | 35.8 |
| 2023 | +$4,446 (+6.6%) | 83 | 48.2% | 0.32 | 101 h | 1.40% | 29.1 |
| **2018-2023** | **+$22,076 (+44.2%)** | 497 | 51.9% | 0.32 | 106 h | 2.37% | 30.5 |
| 2024 | +$4,418 (+8.8%) | 137 | 46.7% | 0.52 | 55 h | 2.11% | 36.0 |
| 2025 | +$9,818 (+18.0%) | 211 | 49.8% | 0.81 | 40 h | 2.92% | 43.9 |
| 2026 YTD | +$1,291 (+2.0%) | 61 | 37.7% | 0.28 | 119 h | 2.53% | 25.5 |
| **2024-2026** | **+$15,527 (+31.1%)** | 409 | 46.9% | 0.57 | 59 h | 2.92% | 35.8 |

- Positive in all 9 years. Max equity drawdown 2.82% (2018-2023) and 3.53% (2024-2026), against the 6% trailing limit.
  No breaker fired in either run.
- Each run starts fresh at $50k. The results match v1.10 at $100k, because Prop mode never pyramids.

## v1.20 House Money Growth mode: $1,000 · 1.0% risk · daily 10% · trailing 30% · 3 slots · whale pyramid

| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |
|---|---|---|---|---|---|---|---|
| 2018 | +$258 (+25.8%) | 110 (36 adds) | 50.0% | 0.42 | 61 h | 9.30% | 25.0 |
| 2019 | +$641 (+51.0%) | 163 (55 adds) | 58.3% | 0.62 | 50 h | 14.58% | 37.5 |
| 2020 | +$1,125 (+59.3%) | 250 (78 adds) | 56.0% | 0.95 | 30 h | 13.58% | 44.6 |
| 2021 | +$594 (+19.7%) | 49 (16 adds) | 59.2% | 0.19 | 131 h | 7.11% | 28.2 |
| 2022 | +$922 (+25.5%) | 184 (58 adds) | 51.1% | 0.71 | 38 h | 10.38% | 31.1 |
| 2023 | +$1,070 (+23.6%) | 148 (42 adds) | 48.6% | 0.57 | 56 h | 8.57% | 27.2 |
| **2018-2023** | **+$4,610 (+461.0%)** | 904 (285 adds) | 53.7% | 0.58 | 58 h | 15.17% | 30.1 |
| 2024 | +$269 (+26.9%) | 244 (69 adds) | 48.4% | 0.93 | 31 h | 11.58% | 33.7 |
| 2025 | +$3,114 (+245.5%) | 392 (121 adds) | 56.1% | 1.50 | 21 h | 11.59% | 59.3 |
| 2026 YTD | +$1,170 (+26.7%) | 108 (26 adds) | 49.1% | 0.50 | 67 h | 11.55% | 24.6 |
| **2024-2026** | **+$4,552 (+455.2%)** | 744 (216 adds) | 52.6% | 1.04 | 32 h | 11.59% | 45.3 |

v1.10 (no pyramid) on the same $1k: 2018-2023 +$3,351 (+335.1%, max DD 8.99%, score 27.3). 2024-2026 +$2,537 (+253.7%, max DD 12.53%, score 34.1).

- **The pyramid adds 38% more profit in 2018-2023 and 79% more in 2024-2026.** Max equity drawdown is 17.94% / 12.95%,
  against the 30% limit.
- **Parity with the research:** all 501 adds opened while their first position was still live. Their stops sat a median 1.50R
  from the add, exactly the research rule. The adds won 58.6% / 63.9% of the time.
- **$1k is close to the floor for gold.** In 2024-2026, 94% of the first positions used the 0.01-lot minimum (1 oz). While the
  balance was under $1.5k, 9% of them risked more than 1% (max 1.69%); the never-breach budget still caps every trade. Lots
  are rounded down, so the median real risk was 0.58-0.66% instead of 1%. That's why $1k compounds slower than $10k
  (v1.10 2018-2023: +335% at $1k vs +493% at $10k).

## v1.10 Prop Firm mode: $100,000 · 0.5% risk · daily 3% · trailing 6% · 2 slots · day banked at +2.4%

| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Green Weeks | Green Months | Best-Day Share | Score |
|---|---|---|---|---|---|---|---|---|---|---|
| 2018 | +$3,287 (+3.3%) | 62 | 46.8% | 0.24 | 108 h | 1.72% | 50% | 3/7 | 34% | 25.4 |
| 2019 | +$7,406 (+7.2%) | 88 | 54.5% | 0.34 | 93 h | 1.82% | 67% | 6/8 | 28% | 35.9 |
| 2020 | +$12,200 (+11.0%) | 137 | 54.0% | 0.52 | 55 h | 2.41% | 50% | 7/10 | 18% | 39.2 |
| 2021 | +$2,549 (+2.1%) | 26 | 53.8% | 0.10 | 251 h | 1.60% | 43% | 3/5 | 56% | 27.1 |
| 2022 | +$8,539 (+6.8%) | 103 | 52.4% | 0.40 | 68 h | 2.12% | 68% | 7/9 | 33% | 36.2 |
| 2023 | +$7,040 (+5.3%) | 85 | 47.1% | 0.33 | 99 h | 1.47% | 50% | 4/8 | 22% | 28.9 |
| **2024** | **+$10,440 (+10.4%)** | 139 | 47.5% | 0.53 | 55 h | 1.85% | 64% | 6/9 | 25% | 36.9 |
| **2025** | **+$19,288 (+17.5%)** | 217 | 48.4% | 0.83 | 39 h | 2.96% | 57% | 9/12 | **10%** | 44.2 |
| **2026 YTD** | **+$3,007 (+2.3%)** | 62 | 37.1% | 0.29 | 117 h | 2.54% | 33% | 2/4 | 65% | 25.7 |

- **Positive in all 9 years.** No year's drawdown exceeded 2.96%, against a 6% trailing limit.
- Run totals: 2018-2023 +$41,021; 2024-2026 +$32,735. The v1.00 comparison is +$19,126 and +$10,725.
- "Green Months x/y": y is the number of months that had trades. When the H4/D1 stacks disagree, the EA waits.

**Prop-challenge replay** uses the EA's own MT5 trades: a fresh $100k from every Monday, +8% target, best day ≤30%, 3%/6% trailing, 180 days.

| Start year | 2018-2023 | 2024 | 2025 | 2026 |
|---|---|---|---|---|
| Pass | 0.7% | 18.8% | **59.6%** | 0% |
| Breach | 0% | 0% | 0% | 0% |

The breach rate is zero everywhere: the account is never lost. In calm years an 8% target takes longer than 180 days at these returns (2-11%/yr), and with unlimited-time challenges the target is eventually reached.

## v1.10 House Money Growth mode: $10,000 · 1.0% risk · daily 10% · trailing 30% · 3 slots

| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Green Weeks | Green Months | Score |
|---|---|---|---|---|---|---|---|---|---|
| 2018 | +$3,107 (+31.1%) | 74 | 48.6% | 0.28 | 91 h | 5.59% | 43% | 5/7 | 30.2 |
| 2019 | +$6,458 (+49.3%) | 108 | 55.6% | 0.41 | 75 h | 10.04% | 61% | 7/8 | 34.5 |
| 2020 | +$13,325 (+68.1%) | 173 | 55.5% | 0.66 | 44 h | 7.18% | 54% | 7/10 | 43.9 |
| 2021 | +$5,214 (+15.9%) | 33 | 51.5% | 0.13 | 196 h | 4.43% | 57% | 3/5 | 24.9 |
| 2022 | +$11,688 (+30.7%) | 126 | 50.0% | 0.48 | 55 h | 7.36% | 58% | 7/9 | 33.1 |
| 2023 | +$9,490 (+19.1%) | 106 | 43.4% | 0.41 | 79 h | 7.69% | 44% | 4/8 | 24.2 |
| **2024** | **+$3,105 (+31.1%)** | 176 | 47.7% | 0.67 | 43 h | 11.42% | 43% | 6/9 | 31.6 |
| **2025** | **+$15,780 (+120.4%)** | 280 | 49.6% | 1.07 | 30 h | 11.24% | 60% | 8/12 | 46.7 |
| **2026 YTD** | **+$1,382 (+4.8%)** | 83 | 37.3% | 0.38 | 87 h | 11.71% | 33% | 2/4 | 17.4 |

- **Positive in all 9 years.**
- 2018-2023: $10k → **$59,283 (+493%)**. 2024-Oct 2026: $10k → **$30,267 (+203%)**.
- Max drawdown never exceeded 11.7%, against a 30% limit.

**Score (0-100)** covers each acceptance criterion: profit 25, win rate 20 (50% = 0, 80%+ = 20), frequency 15, wait 10, drawdown 15, green months 15. A losing period is scaled down: -25%/yr halves its score and -50%/yr or worse scores 0. Before this rule, a system that lost 80% could still score 44.7 just from a high win rate and frequency. Positive periods are unchanged.

## What changed from v1.00 and why (each change validated on 2017-2022, judged on unseen 2023-2026)

| Lever | Finding |
|---|---|
| EMA periods (your idea) | Geometric spacing beats linear 20-200 for every fast period tried. 10/16/26/41/66/105/168 was the best on the selection years and positive 9/10 years unseen |
| M15 pools (new stream P) | +0.25R per trade, survives the time-ordered portfolio replay |
| M15 fresh-wave stream | Looked like +0.18R at 1.2/day, but is ~0R in a real portfolio (signals cluster in trends). **Rejected** |
| Concurrency (2/3 slots) | More of the best trend days captured; Growth CAGR roughly doubled vs one position |
| Room fraction 15% (Prop) | Keeps the expected growth of the room positive near the trailing floor: the account recovers instead of freezing |
| Daily consistency lock | No day can exceed 2.4%, so prop best-day rules are always satisfied |
| Relaxed 5/6 trend gate | Doubles activity in slow years but halves the edge. **Rejected** |

## Ideas tested after v1.10 (Python replays, Dukascopy 2017-2026, hostile costs, chosen on 2017-2022, judged on 2023-2026)

| Idea | Finding |
|---|---|
| Scalp every M15 ribbon retest in a trend (H1/H4/D1 gates) | About -0.17R per trade in a time-ordered replay. **Rejected** |
| Early entry: EMA10 halfway through the ribbon (crosses EMA41), price confirmed | -0.07R to -0.35R per trade. **Rejected** |
| Anatomy of 9,096 "rainbow slide" retests | 7.5% become whales (+3.73R) and 65.2% are fakes (-1.11R), for a net -0.29R per attempt. The whales are real but can't be picked in advance |
| Prop exit: scalp-style (20% at +0.3R, then BE, 2R cap) vs ride | $100k ended at $119,292 with a 74.0% win rate (scalp-style) vs $140,777 with 43.7% (ride). Ride stays the default |
| Whale pyramid on v1.10 entries (add 1 unit at +1.5R, stop at the first entry) | +0.382R vs +0.258R per attempt, positive 10/10 years. Growth $10k ended at $385,123 vs $145,737 (max DD 25.4%). It froze the Prop account. **Candidate for v1.20, Growth mode only** |
| "EMA ribbon calculus" whale trigger: std of the 7 EMAs, its velocity, z > 2.5 (`sw_study33.py`) | The spike fires on the bar that has already moved +2.0 ATR (a normal bar moves +0.1 ATR). At that bar the ribbon is already fully fanned 75-80% of the time. Over the next 16 bars, M5/M15 drift -0.05 ATR, against costs of 0.27-0.53 ATR. Following and fading both lose on M5/M15 (0-1 of 10 years positive). H1 made +0.01 to +0.025R in 2017-2022 and -0.045R in 2023-2026. Used as a filter on v1.10 entries, the result flips sign between periods. **Rejected** |
| The "fixed" calculus trigger: + ATR floor (thickness > 0.5 ATR) + EMA200 trend filter (`sw_study34.py`) | The filters remove about half the signals, but the rest still enter after the move. Best of 3 variants x 36 exits per timeframe, picked on 2017-2022, $100k at 0.5%: M5 ended at $3,762. M15 ended at $109,341 (+9.3% in 10 years, max DD 16.1%, 5/10 years positive). H1 ended at $98,240. The pasted buy rule never checks the flare direction, so about 1 in 7 of its buys follow a sharp drop. **Rejected** |

## Research round 2 (2026-11-04): web sources + experiments toward the "overfit" numbers

**Where the target numbers came from.** The $6.46M / 88.1% win-rate table (2024-2026, $50k Prop) is
`XAUUSD_Sniper_ONNX` v4.31 (xauusd-quant-ea/CHANGELOG.md).
- **How it was built:** its ONNX filter was trained on 1,434 MT5 outcomes from the same 2024-2026 runs it was scored on.
- **The tell:** a profit factor of 6.77 at 86.6% win rate means the average win was as large as the average loss (W/L ≈ 1.05),
  about +0.73R per trade. No out-of-sample test in this repo comes close.
- **The honest rebuild:** v4.40 kept the 83-86% win rate on unseen 2017-2026 data, but earned only +0.064R per trade
  (+92.8R over 1,447 trades), about +9% a year at 1% risk.

| Source | Idea tested (Dukascopy 2017-2026, hostile costs, chosen on 2017-2022) | Result | Verdict |
|---|---|---|---|
| Connors-style high-win-rate rules | RSI(2), IBS, double 7s, Bollinger fade in an uptrend; H1/H4/D1 | 60-65% WR, ~0R after costs, one-position replay ~0R | Rejected |
| Caporale & Plastun (2021, FMPM) | Follow an abnormal day's move until the close | +0.02R (2017-22), +0.13R (2023-26), 7/10 years | Too weak |
| Same paper | Fade the day after an abnormal day | -0.04R / -0.05R, 1/10 years | Rejected |
| MQL5 CodeBase: CME gap tracker | Fade the weekend gap toward Friday's close | +0.13R on 43 trades in-sample, negative from 2023 | Rejected |
| MQL5 CodeBase: Gold Breakout EA (Turtle) | H4 20-bar breakout, here gated by our H4+D1 stacks | +0.24R / +0.50R per trade, 7/10 years; in the account it helps 2024-26 and hurts 2018-23 | Regime bet, not added |
| Gao, Han, Li & Zhou (2018, JFE) | Intraday momentum: an early-day return predicts a later window | Best: +1% of the daily range per trade, 5/10 years | Rejected |
| Walk-forward AI rater, 31 causal features | Pick the winners in advance | OOS AUC 0.479 (the v1.10 17-feature rater: 0.517); win rate ~47% in every score bucket | Rejected |
| Kronos (AAAI 2026, Hugging Face, Kronos-small) | Zero-shot candlestick foundation model: 12h direction, and as a filter | Direction hit 49.5% on 2018-24 (years it may have seen) and 50.3% on unseen 2025-09+ (n=300); as a filter on 278 unseen setups, +0.606R when it agrees vs +0.587R when it disagrees | Rejected |
| Own: whale extension (v1.30) | Trades at +1.5R and their add aim for 5R and may run 72h | MT5 Growth $10k 1%: +1,262% (2018-23) / +644% (2024-26) | **Adopted** |
| Own: wide whale trail (v1.31) | Whales trail 3 ATR(H1) instead of 2 once secured at break-even | MT5 Growth $10k 1%: +1,331% / **+1,950%** | **Adopted** |
| Own: risk frontier and house-money boost | 1.5-3% risk, or extra risk on profits only | 2024-26 roughly triples, but 2018-23 hits the 30% floor (the EA would freeze) | 1% stays the default |
| MQL5 economic calendar (export script `MQL5/Scripts/SW_CalendarExport.mq5`) | Skip new trades on key US release days (NFP, CPI family, Core PCE, GDP, Retail Sales, Fed decision) | Setups on those days: -0.089R (35% WR) vs +0.368R otherwise. MT5: profit factor up and drawdown down in every run. Growth $10k +1,331% → +1,951% (2018-23) but +1,950% → +1,267% (2024-26); Prop +51% → +57% / +50% → +47%; challenge pass 39% → 30% | **Option (v1.32 `InpSkipNewsDays`, default off)**: smoother, but gives up the 2025 news-day whales |
| Same calendar | Trade the NFP surprise (or fade the first 5 minutes) from 5 min after the release | ~0R with the true release times: -0.10R (2017-21), +0.12R (2022-26), 5/10 years; the first 5-minute move already agrees with the surprise 66% of the time. *Correction:* a first run looked like +0.40R/trade because it shifted the UTC calendar times 2-3h early (look-ahead) | Rejected |
| Pepperstone USDX, USDJPY (yield proxy), XAGUSD, US500, NAS100 (H1) | Cross-asset agreement as a setup filter | Differences small and of mixed sign (e.g., USDJPY "agreeing" was worse) | Rejected |
| Own: Turtle-style second add at +3R (stop at the first add's entry, all units to 8R / 120h) | Pyramid more in strong trends | MT5 $10k: $89,460 / $156,985 vs v1.31 $143,092 / $205,014; $1k 2024-26 froze at the 30% floor | Rejected |
| Own: Kelly-safe Growth budget (share 0.15 of the trailing room) | Stops the freeze so 1.5-2% risk can survive | No freeze at 2%, but the budget binds: 2% made $123,902 / $189,579 vs v1.31 at 1%: $143,092 / $205,014 (MT5, $10k) | Rejected |

## Research round 4 (2026-11-04): data that is not in any MT5 price bar

**Method.**
- **Sources:** official public sources, parsed by `python_pipeline/sw_outside.py`. Each value is used only after it was actually published.
- **COT timing:** COT is used only from the Monday 21:00 UTC after its Friday release. The 2018-19 and 2025 shutdown backlogs are used only after
  the CFTC caught up.
- **Daily series:** used from the next day.
- **Pre-registered good side:** every hypothesis has its "good" side written down before the run.
- **Thresholds:** fixed on 2017-2021.
- **Pass bar:** good beats bad in both halves (2017-21, 2022-26) and in at least 7 of 10 years.
- **Outcomes:** v1.30-like whale management, Dukascopy 2017-2026.
- **Account replays:** comparisons only, as their absolute numbers sit below MT5 (the replay has no 3-ATR whale trail).

| Source | Idea tested | Result | Verdict |
|---|---|---|---|
| CFTC Commitments of Traders, COMEX gold (`sw_study46.py`) | Managed-money crowding and 4-week flow, hedger positioning, small-spec crowding, open-interest change | No feature passes. Hedgers: +0.010R (2017-21) / +0.455R (2022-26) but 4/10 years | Rejected |
| Same, as a weekly signal (`sw_study47.py`) | Williams COT index (hedgers > 80% long / < 20% short); contrarian managed money | -0.16% / -0.25% per week vs always-long +0.25% | Rejected |
| Geopolitical Risk daily index (Caldara & Iacoviello) | Rising GPR favours gold longs; GPR spike = long gold for a week | 6/10 and 4/10 years; weekly rule -0.15% | Rejected |
| US daily Economic Policy Uncertainty (Baker, Bloom & Davis) | Rising uncertainty favours longs | 4/10 years, sign flips between halves | Rejected |
| CBOE GVZ (gold implied vol) and VIX | Vol level, 5-day change, implied / realized | Only implied / realized passed (+0.275R / +0.055R, 7/10 years). In the account: skipping its bad third cut Growth $45.7k → $20.2k and $127k → $59k; risk weights 0.6/1.0/1.3 also worse in both windows | Rejected (chance survivor: 1 of 16) |
| US Treasury 10Y real yield (TIPS) | Falling real yields favour longs (5 / 20 days); weekly rule | 2-4/10 years; weekly -0.21% | Rejected |
| All 16 outside features in a walk-forward LightGBM | Rank the setups | AUC 0.516; top half +0.357R vs bottom half +0.309R; 2026 inverted | Rejected |
| SPDR GLD holdings (ETF flows) | Daily gold-ETF flows | The SPDR link now serves today's bar list, and no free history is reachable | Not testable |
| Gupta & Kelly (2019) strategy momentum (`sw_study49.py`) | Risk follows SevenWave's own last 10/20/40 closed trades | **Reversed**: after hot streaks the next setups earn +0.09 to +0.21R, after cold streaks +0.40 to +0.43R, in 8/10 years (winners close late, at the end of a trend). But neither direction helps the account: momentum weights $127k → $84k (Growth 2024-26); contrarian 1.5/1.0/0.5 $45.7k → $31.9k (2018-23), because cold streaks are exactly when the account is in drawdown | Rejected |
| Failed-breakout exits (`sw_study50.py`, `sw_sim3.py`) | Close a breakout that has not reached +0.25/0.5R after 1-8 h, or whose M15/H1 close is back beyond the entry | All 14 variants lower avg R in both halves; the losses shrink (-0.87R → -0.21R at the tightest) but too many late winners are cut | Rejected |
| Night effect: "gold rises in Asia, falls in New York" (`sw_study51.py`) | Session-only longs | Bid data: Asia +10%/yr (9/10 years). With mid prices it lives in the reopen hour: from 23:00 UTC +2.6%/yr, from 01:00 +0.6%/yr, negative after costs | Rejected (reopen artifact) |
| Baur (2013) autumn effect | September and November are strong | Sep/Nov -0.42% vs +1.36% for the other months; 2/10 years; Sep/Nov longs +0.25R vs +0.32R | Rejected |
| GDELT news sentiment (`sw_study48.py`): average tone and article volume of worldwide "gold price" news, daily, 2017-2025 | Upbeat news supports longs; attention spikes; weekly tone rules | Pre-registered side wrong: setups that agree with the last week's tone trend earn +0.10R vs +0.41R when they disagree (8/10 years). Post-hoc contrarian version (`sw_study48b.py`): skipping the agreeing third is worse in all 4 account runs; weights 1.3/1.0/0.6 give Growth +3% / +12% with deeper drawdowns and Prop -4% / +1% | Rejected (sentiment follows price; too weak for a live news feed) |

## v1.33: the AI veto was overfit (MT5, Pepperstone XAUUSD, Model 4 + random delay, defaults, every input explicit)

**What was wrong.** The ONNX rater shipped in v1.10 was trained on Dukascopy 2017-2023 (`AiModelMeta.mqh`: "v1.10 Duka 2017-2023").
Every v1.32 MT5 event was matched to its simulated outcome (`sw_study52.py`):
- **Seen years 2018-2022:** vetoed setups -0.05 to -0.58R vs traded +0.39 to +1.17R. The veto had memorised them.
- **Unseen 2024-2026:** vetoed setups did better than the ones it kept: 2024 +0.31R vs +0.16R, 2025 +0.50R vs +0.37R,
  2026 +0.90R vs +0.39R.

So **every 2018-2023 MT5 result from v1.10 to v1.32 was partly in-sample.** The 2024-2026 results were out of sample for it.

| Run (v1.33 = no veto) | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score | vs v1.32 |
|---|---|---|---|---|---|---|---|---|
| Prop $50k 2024-2026 | +$24,082 (+48.2%) | 438 | 43.2% | 0.61 | 55 h | 3.26% | 37.8 | +$25,067; challenge pass 36.8% vs 35.0%, 0 breaches |
| Growth $10k 2024-2026 | **+$292,339 (+2,923%)** | 840 (241 adds) | 48.2% | 1.17 | 29 h | 14.74% | 53.2 | +$206,225 (PF 2.28, equity DD 13.9%) |
| Prop $50k 2018-2023 (honest) | +$14,467 (+28.9%) | 609 | 43.8% | 0.39 | 86 h | 3.73% | 27.0 | +$25,596 with the in-sample veto; pass 3.1% |
| Growth $10k 2018-2023 (honest) | +$24,747 (+247.5%) | 833 (237 adds) | 43.0% | 0.69 | 49 h | 26.57% | 28.0 | **froze at the 30% floor in Aug 2022** |

**The Growth freeze.**
- **What happened:** without the memorised veto, 2022 ran at a 33.6% win rate. The Growth budget then let each loss take up to 40% of the
  remaining room above the 30% floor (share 0.5 / 1.25 cushion).
- **Result:** by August 2022 the account sat about $8 above its floor. Even 0.01 lot no longer fitted, and every later signal was refused.
- **Contrast:** Prop never freezes because it bets 15% of the room.
- **Fix (shipped in v1.33):** a Kelly-safe Growth share. MT5 Growth $10k at the defaults:
  - share 0.15: +$42,088 (2018-23) / +$193,887 (2024-26);
  - **share 0.25: +$53,812 / +$280,058, every year positive, no freeze;**
  - share 0.5: +$24,747 and frozen / +$292,339.

## v1.33 risk frontier (House Money Growth $10k, MT5, honest: no in-sample AI anywhere)

The same trades sized harder, with deeper drawdown limits. This buys profit with drawdown; it is not a new edge. The rows above the shipped ones use v1.31's 0.5 room share. Compounded results at 2-3% risk are very path-dependent (one MT5 run each, random delay). At 2% the 0.25 share gives up 2018-2023 compounding ($157k vs $444k) in exchange for never freezing at the floor.

| Growth $10k | 2018-2023 | Max DD | PF | 2024-Oct 2026 | Max DD | PF |
|---|---|---|---|---|---|---|
| 1% / daily 10% / trailing 30% (defaults) | +$24,747 (+247%), **froze Aug 2022** | 26.6% | 1.33 | +$292,339 (+2,923%) | 14.7% | 2.28 |
| **2% / daily 15% / trailing 50%** | **+$444,009 (+4,440%)**, every year positive | 39.9% | 1.40 | **+$3,273,039 (+32,730%)** | 29.4% | 2.07 |
| 3% / daily 20% / trailing 60% | +$424,779 (+4,248%); equity DD 59.4% (limit 60%) | 54.0% | 1.21 | +$7,420,959 (+74,210%) | 43.1% | 1.90 |
| **Shipped share 0.25:** 1% / 10% / 30% | +$53,812 (+538%) | 23.0% | 1.39 | +$280,058 (+2,801%) | 14.9% | 2.27 |
| **Shipped share 0.25:** 2% / 15% / 50% | +$156,656 (+1,567%) | 43.0% | 1.26 | +$3,191,449 (+31,914%) | 34.0% | 2.08 |
| Share 0.15: 2% / 15% / 50% | +$132,380 (+1,324%) | 35.3% | 1.31 | +$1,870,438 (+18,704%) | 27.9% | 2.03 |

- **2% risk is the sweet spot:** it is strong in both windows and does not freeze.
- **3% risk is past it:** it earns no more than 2% in 2018-2023, and nearly trips its own floor.
- **The 50-lot cap:** near $5M, Pepperstone's 50-lot maximum per order flattens further growth.
- **Each year at 2% / 15% / 50%:**
  - 2018-2023: 2018 +19.8%, 2019 +92.2%, 2020 +533%, 2021 +7.5%, 2022 +69.8%, 2023 +70.6%.
  - 2024-2026: 2024 +182.7%, 2025 +3,753%, 2026 YTD +201%.

## Correction to the v1.00 report

The v1.00 2018-2023 MT5 rows I first published ran with a leftover 5% risk input. At the real defaults, v1.00 Prop (0.75%) made +$19,126 (+19.1%, positive every year, max DD 2.86%) and v1.00 Growth (3%) made +$27,413 (+274%, max DD 16%). Its 2024-2026 rows were correct.

## Open items

- **Upcomers and GetLeveraged backtests.** v1.33 is deployed to both. Running the identical batch there needs those terminals closed.
- **Growth risk preset.** 1% / 10% / 30% stays the default. 2% / 15% / 50% is the verified aggressive preset (inputs only, no code).
- **Small-account sizing.** At $1k, lots round down to 0.01 steps, so the real risk is ~0.6% instead of 1%. Next lever: round to
  the nearest step when the rounded-up lot still fits the never-breach budget.
- **Entries refused at the 01:00 reopen.** About 8 triggers per run are refused with retcode 10018 (market closed), and the
  trigger is consumed. Next lever: keep the trigger armed and retry on the next tick.
- **Idle stretches.** The EA waits when the H4/D1 stacks disagree (2021, and Apr-Sep 2026). The next lever is new edge that works *in* those regimes (for example, H4-structure pools or a range engine), validated with the same portfolio-replay discipline.
