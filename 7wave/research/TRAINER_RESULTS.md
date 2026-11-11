# 7Wave blind replay and stop study (2026-11-06)

## 1. The user's eye, blind, at the signal

The user judged 400 random 7Wave signals (200 H1, 200 M15, 2018-2026) with the date, price and future hidden:
187 Take, 85 Strong take, 128 Skip. Median decision time 3.2 s.
Scored with `trainer/score_trainer.py`; the raw data is in `C:\Users\faker\Documents\goldie_research\7wave\`.

| Group | Signals | Good waves (+3R first) | Fakes | Avg R (bracket) | Avg R (holding) |
|---|---|---|---|---|---|
| Everything shown | 400 | 22% | 54% | -0.184 | -0.157 |
| Takes (Take + Strong) | 272 | 22% | 55% | -0.185 | -0.141 |
| Strong takes | 85 | 18% | 52% | -0.404 | -0.452 |
| Skips | 128 | 23% | 53% | -0.183 | -0.190 |

- **Ranking skill (AUC)**: 0.479, with a 95% interval of 0.418 to 0.540.
  - By timeframe: H1 0.476, M15 0.482. The scorecard's AI scored 0.503 / 0.519 on the same scale, so the eye and the
    AI are both at coin-flip level at the signal.
- **Strong takes were the weakest group**: 18% good waves and -0.40R. The setups that look most convincing tend to
  come late in the move.
- **Possible learning during the session**:
  - First 200 decisions: takes -0.327R vs skips +0.056R, AUC 0.437.
  - Last 200 decisions: takes -0.027R vs skips -0.375R, AUC 0.522. Takes beat everything by +0.124R, with a 95%
    interval of -0.051 to +0.291.
  - This could be learning from the reveals, or luck. Only a fresh batch of unseen signals can tell.

## 2. Stop study: is it the stop or the entry?

Code: `research/stop_study.py`.
- **Trade**: every signal is replayed with five stops. Each stop keeps a +3R target in its own R, with a time exit
  after 10 days (H1) or 4 days (M15).
- **Control group**: 4 random entries per signal (random bar, random direction) on the same data.
- **"Stopped, then +3R anyway"**: the share of stop-outs that later reached the original +3R target, the "killed
  right before the moonshot" case.

**H1** (781 signals, 3,124 random entries):

| Stop | Median stop | 7Wave: wins | 7Wave: avg R | 7Wave: stopped, then +3R | Random: wins | Random: avg R | Random: stopped, then +3R |
|---|---|---|---|---|---|---|---|
| 1.5 ATR (trainer) | 1.5 ATR | 22% | -0.200 | 55% | 24% | -0.134 | 58% |
| 2.5 ATR | 2.5 ATR | 23% | -0.153 | 34% | 23% | -0.134 | 35% |
| 4 ATR | 4.0 ATR | 19% | -0.144 | 14% | 19% | -0.146 | 16% |
| Beyond EMA 140 + 0.5 ATR | 3.1 ATR | 20% | -0.162 | 26% | 21% | -0.146 | 54% * |
| Beyond the 20-bar swing + 0.25 ATR | 4.7 ATR | 16% | -0.119 | 15% | 21% | -0.129 | 41% * |

**M15** (3,005 signals, 12,020 random entries):

| Stop | Median stop | 7Wave: wins | 7Wave: avg R | 7Wave: stopped, then +3R | Random: wins | Random: avg R | Random: stopped, then +3R |
|---|---|---|---|---|---|---|---|
| 1.5 ATR (trainer) | 1.5 ATR | 22% | -0.212 | 62% | 22% | -0.224 | 67% |
| 2.5 ATR | 2.5 ATR | 23% | -0.137 | 43% | 24% | -0.111 | 47% |
| 4 ATR | 4.0 ATR | 21% | -0.082 | 24% | 23% | -0.065 | 28% |
| Beyond EMA 140 + 0.5 ATR | 3.0 ATR | 21% | -0.136 | 37% | 21% | -0.192 | 59% * |
| Beyond the 20-bar swing + 0.25 ATR | 4.5 ATR | 19% | -0.088 | 22% | 22% | -0.126 | 50% * |

\* Random entries often sit on the wrong side of the ribbon, so their structural stops fall back to the 1 ATR minimum.
Compare 7Wave with random only on the fixed ATR rows.

**The user's 400 picks with the same stops:**

| Stop | All 400 | Takes | Strong takes | Skips |
|---|---|---|---|---|
| 1.5 ATR (trainer) | -0.184 | -0.185 | -0.404 | -0.183 |
| 2.5 ATR | -0.069 | -0.061 | -0.258 | -0.087 |
| 4 ATR | -0.090 | -0.040 | -0.086 | -0.195 |
| Beyond EMA 140 + 0.5 ATR | -0.099 | -0.035 | -0.127 | -0.234 |
| Beyond the 20-bar swing + 0.25 ATR | -0.074 | -0.019 | -0.203 | -0.192 |

## What it shows

- **"Stopped right before the moonshot" is real and frequent.** With the 1.5 ATR stop, 55-62% of stop-outs reach the
  +3R level afterwards anyway. Random entries show the same rate (58-67%), so this comes from gold's volatility, not
  from 7Wave.
- **Wider stops help, but the help comes from costs.** With a 4 ATR stop:
  - Wait-and-see drops: 14-24% of stop-outs then reach +3R.
  - Average R improves: H1 from -0.20 to -0.14, M15 from -0.21 to -0.08.
  - Random entries improve just as much, because fixed dollar costs are a smaller part of a bigger R. At equal
    stops, 7Wave entries and random entries end up level.
- **With room to breathe, the user's takes did better than their skips.** With wide or structural stops, takes were
  ahead by about 0.15-0.2R (for example -0.019R vs -0.192R beyond the 20-bar swing).
  - This matches the user's feeling that good picks were "killed too early".
  - It is about one standard error, and the best of five stop variants, so it is a lead to retest on fresh signals,
    not a finding.
