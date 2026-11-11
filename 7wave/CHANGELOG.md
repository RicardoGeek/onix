# 7Wave: CHANGELOG

## [7Wave_EA v1.01] - 2026-11-06

**The fix.** In the user's tester run of v1.00 (XAUUSD H1, real ticks, 2025-01 to 2026-10), the broker rejected two
stop orders with error 10015 (invalid price): 2025-09-17 21:00, the Fed decision, and 2026-10-21 22:00. The price
went through both levels in those bars, so v1.00 missed two trades. From v1.01 a rejected entry stays wanted for its
bar: it is retried on the next ticks and turns into a market order once price reaches the level.

**The check** of the v1.00 run with `tools/ea_check.py`, plus a comparison of every order in the tester journal:

- **Exits**: all 71 trades exit for the same reason (26 stop, 20 trail, 15 target, 10 time) and in the same minute
  as a minute-by-minute replay of the rules. Prices are within 0.05R on 64; the other 7 are slippage in fast markets
  and Monday-open time exits.
- **Orders**: on 599 of 608 bars where the EA was flat, it placed the order the indicator copy armed, same side and
  level. The other 9 differ by cents, because the tester's year of warm-up gives a slightly different ATR.
  - 2025-04-03 01:00-02:00 (the Liberation Day spike) are armed only in the copy. Pepperstone's stored H1 bars there
    show zero spread and differ from its real ticks.
- **Entries**:
  - All 71 fills are inside their signal bar.
  - 69 match the indicator copy's bar-by-bar entries.
  - Two fills, and two copy entries the EA did not get, are touches of the level by 0-14 cents. Real ticks and whole
    bars disagree on those.
- **Results** (0.01 lot): 71 trades, 55% winners, +0.496R per trade, +35.2R in total.
  - The same trades at 1% risk: 2025 +38.1%, 2026 to October +2.1%, max drawdown 5.6%.
  - The research expected +39.7% for 2025 and +1.0% for 2026 to September (`research/GATE_TEST.md`, Pepperstone).
- Archived as `bin/7Wave/7Wave_EA_v1.01.ex5`. Installed in Pepperstone, where it replaces the v1.00 copy.

## [7Wave_EA v1.00] - 2026-11-06

Step 2: the EA that follows the indicator (`RULES.md`, "Step 2"). Rules 5 and 6 (indicator v1.30) were checked by the
user on the chart.

- It trades only the swing breakout. At each H1 bar open it reads the indicator's armed buy-stop or sell-stop level
  (iCustom buffers 19 and 21) and places a stop order valid for that bar only. If the bar opened past the level, it
  enters at market.
- Management is the research's growth profile:
  - stop 1.5 x the indicator's Wilder ATR (buffer 27, last closed bar) = 1R, and target +3R, both moved to the actual
    fill;
  - from +1R the stop trails 2 ATR behind the best price, on completed M1 bars;
  - exit at market after 24 hours.
- Fixed lot (input, 0.01), one trade at a time, no risk engine.
- It survives restarts: an open trade is picked up again, with its ATR stored in the order comment.
- Trade log in `Common\Files\7wave_ea_trades_tester.csv` (tester) or `7wave_ea_trades_live.csv` (live).
- Compiled with 0 errors and 0 warnings. Archived as `bin/7Wave/7Wave_EA_v1.00.ex5`.
- Installed in Pepperstone only, as `Experts\7Wave\7Wave_EA.ex5` plus `7Wave_EA_v1.00.ex5`.

## [v1.30] - 2026-11-06

The swing-breakout setup from `research/GATE_TEST.md`, drawn on H1 charts (`RULES.md`, rules 5 and 6). The user
approved adding it. Rules 3 and 4 (v1.20) were checked by the user on the chart.

- **Rule 5, trend filter**:
  - UP when the 7 lines (20-140) are stacked up on both the last closed H4 bar and the last closed D1 bar, DOWN when
    both are stacked down, OFF otherwise.
  - Shown in the Data Window (`Trend filter H4+D1`) and in a status line at the bottom-left of the chart. The status
    line also names the order armed for the forming bar.
- **Rule 6, swing breakout**:
  - With the filter UP, a buy stop sits 0.15 ATR under the nearest untouched H1 swing high (the high beats 3 bars on
    each side). The swing must be 12-48 bars old and the level within 3 ATR of the open. Shorts mirror this.
  - Each swing gives at most one entry.
  - Drawn as tiny dots (pool), small dots (entry level) and diamonds (entries), sky blue for longs and magenta for
    shorts.
  - Levels are armed at the bar's open and the entry is marked when the bar closes, so nothing repaints.
- Rules 5 and 6 run on H1 charts only. Other timeframes show a note in the status line.
- `tools/setup_check.py` is an independent Python copy of rules 5-6 on the broker's own H1/H4/D1 bars.
  - **Parity with the research engine** on Pepperstone 2024-2026: 137 vs 137 entries, 129 on the same bar and in
    the same direction (94%). Six of the eight differences are the same entry one hour later, because the research
    inflates spreads by 25% on purpose (`research/setup_parity.py`).
  - **Entries per year** on Pepperstone H1: 2017 15, 2018 28, 2019 30, 2020 48, 2021 9, 2022 37, 2023 34, 2024 49,
    2025 71, 2026 17.
- Binary archived as `bin/7Wave/7Wave_v1.30.ex5`. Installed in the Pepperstone terminal only.

## [v1.20] - 2026-11-06

Two changes the user asked for to when signals are drawn (`RULES.md`, rules 3 and 4). Rule 2 v1.11 was checked by the user on
the chart.

- **Stars (rule 3)**: a star when EMA 20 finishes crossing all 6 other lines while at least 3 of them still hold the
  old trend's order. They are drawn in the same colors as the arrows, a little farther from the EMA 140 line. The
  in-order count is an input (`InpStarMinInOrder`, default 3).
- **Arrows (rule 2)**: kept as they were, so stars and arrows can be compared. A wave now starts when its arrow is
  drawn.
- **Candle color (rule 4)**: stars and arrows are drawn only on a bar closing their color (UP bullish, DOWN bearish).
  Otherwise they wait for the first such bar, and are cancelled if EMA 20 stops being beyond all 6 other lines on their
  side first.
- New Data Window lines: `Arrow waiting for its candle`, `EMA 20 vs other 6`, `Star check`, `Star waiting for its candle`.
- `tools/wave_check.py` follows rules 2-4. On Pepperstone XAUUSD (data to 2026-11-06 18:00):

  | Timeframe | Arrows: one every | Arrows that waited for their candle | Stars: one every | Stars that waited | Stars cancelled while waiting |
  |---|---|---|---|---|---|
  | H1 | 6.5 days | 48 | 12.9 days | 24 | 3 |
  | M15 | 1.6 days | 49 | 2.9 days | 34 | 1 |
  | M5 | 0.5 days | 51 | 1.0 day | 32 | 2 |
- Binary archived as `bin/7Wave/7Wave_v1.20.ex5`. Installed in the Pepperstone terminal only.

## [v1.11] - 2026-11-06

Rule 2 change, asked for by the user after checking v1.10 on the chart: two waves in a row in the same direction now
both get an arrow.

- A wave ends when at least 3 of the 7 lines are out of order for its direction. A line is out of order when it is on
  the wrong side of at least one other line. The count is an input (`InpWaveEndLines`, default 3).
- An aligned bar gets an arrow unless a wave in the same direction is still going, so the next wave can go either way.
- New Data Window line `Lines out of order`. `Wave` now shows the wave still going, and drops to 0 once it has ended.
- `tools/wave_check.py` follows the new rule. On Pepperstone XAUUSD (data to 2026-11-06):

  | Timeframe | v1.10: one arrow every | v1.11: one arrow every |
  |---|---|---|
  | H1 | 13.0 calendar days | 6.5 calendar days |
  | M15 | 3.4 days | 1.6 days |
  | M5 | 1.0 day | 0.5 days |
- Binary archived as `bin/7Wave/7Wave_v1.11.ex5`. Installed in the Pepperstone terminal only.

## [v1.10] - 2026-11-06

Second step of the indicator: new-wave arrows (`RULES.md`, rule 2). Rule 1 (v1.00) was checked by the user on the chart.

- A closed bar is aligned UP when close > EMA 20 > 40 > 60 > 80 > 100 > 120 > 140, and aligned DOWN when it is the
  exact reverse.
- The first aligned bar whose direction differs from the last arrow gets an arrow at its EMA 140, so arrows alternate.
  UP arrows are sky blue, just below the line. DOWN arrows are magenta, just above it.
- Only closed bars are checked, oldest first, so arrows never repaint. The whole history is checked, which takes
  milliseconds, so the arrows are there however far back you scroll.
- New Data Window lines: `Aligned now` and `Wave`.
- `tools/wave_check.py` is an independent Python copy of rule 2 that lists where the arrows should be. On Pepperstone
  XAUUSD (data to 2026-11-06) it gives one arrow every 13.0 calendar days on H1, every 3.4 days on M15 and every 1.0 day on M5.
- Binary archived as `bin/7Wave/7Wave_v1.10.ex5`. Installed in the Pepperstone terminal only.

## [v1.00] - 2026-11-06

First step of the indicator: the ribbon (`RULES.md`, rule 1).

- Seven EMAs of the close: 20, 40, 60, 80, 100, 120, 140. The periods are inputs and these are their defaults.
- Colors only tell the lines apart: 20-60 red gradient, 80 yellow, 100-140 green gradient. They were picked to show up on
  the black chart background and can be changed in the indicator's Colors tab.
- The Data Window lists each line as `EMA <period>`. The indicator name carries the version: `7Wave v1.00 (20/40/60/80/100/120/140)`.
- Source: `MQL5/Indicators/7Wave/7Wave.mq5`. The binary is archived as `bin/7Wave/7Wave_v1.00.ex5`.
- Installed in the Pepperstone terminal only, as `MQL5\Indicators\7Wave\7Wave.ex5`.
