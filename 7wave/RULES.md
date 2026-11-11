# 7Wave: the rules

7Wave is the user's own manual strategy, turned into code one step at a time:

1. **Indicator**: draws the rules on the chart, and the user checks them by eye.
2. **EA**: trades exactly what the indicator shows. No risk management yet; the user checks it by manual experiments.
3. **Risk engine**: kept small.

Rules 1-4 come from the user. Rules 5-6 come from the research in `research/GATE_TEST.md`, and the user approved
adding them on 2026-11-06. Each rule is written here as an exact definition before it is coded, and the code adds
nothing that was not agreed. Terminal: Pepperstone only.

## Rule 1: the ribbon (v1.00, checked by the user on the chart on 2026-11-06)

- Seven EMAs of the close: 20, 40, 60, 80, 100, 120, 140.
- EMA formula, the same one as MetaTrader's built-in Moving Average (Exponential, Close):
  - `k = 2 / (period + 1)`
  - on the oldest bar, the EMA starts at that bar's close
  - after that, `EMA[i] = close[i] * k + EMA[i-1] * (1 - k)`
- Colors only tell the lines apart. They have no meaning yet:
  - 20, 40, 60: red gradient
  - 80: yellow
  - 100, 120, 140: green gradient

## Rule 2: arrows, a new wave (v1.11, checked by the user on the chart on 2026-11-06; rule 4 added in v1.20)

- A bar is checked once, on the chart's timeframe, after it closes. The bar that is still forming is never checked, so
  an arrow never appears and then disappears. The user's reason: one aggressive move can misalign the lines inside a
  single bar.
- **Aligned UP** on a closed bar: close > EMA 20 > EMA 40 > EMA 60 > EMA 80 > EMA 100 > EMA 120 > EMA 140.
- **Aligned DOWN** on a closed bar: close < EMA 20 < EMA 40 < EMA 60 < EMA 80 < EMA 100 < EMA 120 < EMA 140.
- **A wave ends** when at least 3 of the 7 lines are out of order for its direction. A line is out of order when it is
  on the wrong side of at least one other line: in an UP wave every faster EMA must be above every slower one, and in a
  DOWN wave below it.
  - UP wave, EMA 20 dips under EMA 40: 2 lines are out of order (20 and 40), so the wave goes on.
  - UP wave, EMA 20 dips under EMA 40 and EMA 60: 3 lines are out of order (20, 40 and 60), so the wave ends.
  - Price does not end a wave. A close back across EMA 20 counts only for starting a wave, not for ending one.
- **New wave**: an aligned closed bar makes an arrow due, unless a wave in the same direction is still going or an
  arrow in that direction is already waiting for its candle.
  - After a wave ends, the next wave can go either way, including the same direction again.
  - A change of direction always makes an arrow due, because a fully reversed ribbon has all 7 lines out of order.
- The arrow is drawn following rule 4 (candle color). The wave starts when its arrow is drawn, so an arrow that is
  cancelled while waiting starts no wave.
- The arrow sits at the EMA 140 of the bar it is drawn on: UP arrows just below the line, DOWN arrows just above it.
- The whole chart history is checked the same way, oldest bar first, each bar using only data up to its own close.
  So the arrows on old bars are exactly what you would have seen live, however far back you scroll.
- The Data Window shows each closed bar's state. All three lines are blank on the bar that is still forming.
  - `Aligned now`: 1 up, -1 down, 0 no.
  - `Wave`: the wave still going after this bar (1 up, -1 down, 0 none).
  - `Lines out of order`: the count for the wave that was going into this bar, blank when none was.
- Cross-check: `tools/wave_check.py` is an independent Python copy of rules 2-4. It lists where the stars and arrows
  should be.
- History:
  - v1.10 drew arrows only on a change of direction. The user checked it against the chart.
  - The user then asked for two waves in a row in the same direction to both get an arrow, with a wave ending at 3
    lines out of order. That is v1.11, also checked against the chart.
  - v1.20 added rule 4 (candle color) to the arrows.

## Rule 3: stars, EMA 20 crosses the ribbon (v1.20, checked by the user on the chart on 2026-11-06)

- Checked once per closed bar, like rule 2.
- **EMA 20's side** on a closed bar: above all 6 other lines, below all 6, or inside the ribbon.
- **Full cross UP**: the first closed bar where EMA 20 is above all 6 other lines, when the last time it was beyond all
  of them it was below. So it has crossed all 6 lines from below. **Full cross DOWN** is the mirror.
- **Old order**: on that bar, at least 3 of the 6 slower lines (EMA 40 to EMA 140) still hold the old trend's order.
  That is DOWN order for an UP cross, and UP order for a DOWN cross.
  - Lines are counted like the wave end: a line is out of the old order when it is on the wrong side of at least one
    other of the 6.
  - A full cross with fewer than 3 lines in the old order gets no star.
- A full cross that passes makes a star due, and it is drawn following rule 4 (candle color).
- The star sits at the EMA 140 of the bar it is drawn on, like the arrows but a little farther from the line (UP below,
  DOWN above). Colors match the arrows: sky blue UP, magenta DOWN.
- Stars and arrows are independent: drawing one never changes the other.
- The Data Window shows, for each closed bar:
  - `EMA 20 vs other 6`: 1 above all, -1 below all, 0 inside.
  - `Star check`: on a full-cross bar, how many of the 6 slower lines still hold the old order.
  - `Star waiting for its candle`: 1 up, -1 down, 0 no.

## Rule 4: candle color, for stars and arrows (v1.20, checked by the user on the chart on 2026-11-06)

- An UP star or arrow is drawn only on a bar that closes bullish (close > open). A DOWN one is drawn only on a bar that
  closes bearish (close < open). A doji (close = open) is neither.
- If the bar where a signal becomes due closes the other color, the signal waits. It is drawn on the first later bar
  that closes its color.
- A waiting signal is cancelled when, at a bar's close, EMA 20 is no longer beyond all 6 other lines on its side (above
  all for UP, below all for DOWN). This also covers a signal in the opposite direction, which needs EMA 20 on the other
  side.
- The Data Window shows `Arrow waiting for its candle` and `Star waiting for its candle` (1 up, -1 down, 0 no).

## Rule 5: the trend filter, H4 + D1 (v1.30, checked by the user on the chart on 2026-11-06)

- Rules 5 and 6 work on H1 charts, because the setup is defined on H1. Other timeframes show a note instead.
- The filter uses the broker's H4 and D1 bars. On Pepperstone they start at server midnight, which is 17:00 New York.
- On each of them, take the 7 EMAs of the close (20 ... 140, same formula as rule 1).
  - **Stacked UP**: EMA 20 > EMA 40 > EMA 60 > EMA 80 > EMA 100 > EMA 120 > EMA 140. Only the lines count, not price.
  - **Stacked DOWN**: the reverse.
- **Filter of a closed H1 bar**: look at the H4 bar and the D1 bar that had both closed by the time that H1 bar closed.
  - **UP** when both are stacked UP.
  - **DOWN** when both are stacked DOWN.
  - **OFF** otherwise.
- Shown as the Data Window line `Trend filter H4+D1` (1 up, -1 down, 0 off) and as a status line in the chart corner.

## Rule 6: the swing breakout entry (v1.30, checked by the user on the chart on 2026-11-06)

- **Swing high on H1**: a bar whose high is above the highs of the 3 bars before it and the 3 bars after it. It is only
  known 3 bars later. A **swing low** is the mirror image.
- **Untouched**: a swing high stays untouched until a later bar's high goes above it. A swing low stays untouched
  until a later bar's low goes below it.
- **Pool for a long**, at a closed bar: the lowest untouched swing high above that bar's high.
  **Pool for a short**: the highest untouched swing low below that bar's low.
- **ATR**: the 14-bar Wilder ATR of H1. The first 14 bars use the average of their true ranges; after that,
  ATR = previous ATR + (true range - previous ATR) / 14.
- **Armed buy stop** for the next bar, when the filter of the closed bar is UP: the pool level minus 0.15 ATR.
  It is armed only if all three of these hold:
  - the pool's swing bar is 12 to 48 bars older than the closed bar;
  - the level is no more than 3 ATR above the next bar's open;
  - this swing high has not already given an entry.
- **Armed sell stop**: the mirror image. It needs the filter DOWN and sits at the pool level plus 0.15 ATR, no more
  than 3 ATR below the open.
- **Entry**:
  - A buy triggers when the bar's high plus its spread reaches the armed level. A sell triggers when the bar's low
    reaches it.
  - The fill is the level itself, or the bar's open if the bar opened beyond the level.
  - Each swing high or low gives at most one entry.
- **No repaint**: the armed levels of the forming bar are known at its open and do not change during the bar. The
  entry marker appears when the bar closes.
- **On the chart**:
  - The pool is drawn as tiny dots and the entry level as small dots, sky blue for longs and magenta for shorts.
  - A diamond marks each entry.
  - The Data Window adds `Armed pool age (H1 bars)`.
- **Trade management is the EA's job (step 2).** The research used: stop 1.5 ATR, trail 2 ATR once the trade is +1R,
  target 3R, and at most 24 hours in the trade.

## Step 2: the EA follows the indicator (7Wave_EA v1.00)

The EA trades only the swing breakout of rules 5-6, exactly as the indicator draws it. The user approved these rules
on 2026-11-06. It does not trade the stars or arrows, which the scorecard showed to be coin flips as entries.

- **Chart**: XAUUSD H1. The EA reads the 7Wave indicator itself (iCustom), so both always agree, and in the visual
  tester the indicator is drawn on the same chart as the EA's trades.
- **Entry**: at the open of every H1 bar, while no trade of the EA is open:
  - If the indicator shows an armed buy-stop level for that bar, place a buy stop at that level. A sell-stop level
    gets a sell stop.
  - The order is valid for that bar only. It expires at the bar's end, and is also deleted at the next bar's open
    if still there.
  - If the bar opened already past the level, enter at market instead, as the research fills at the open.
  - If the broker rejects the order, the entry stays wanted for that bar (v1.01). It is retried on the next ticks,
    up to 30 times, and becomes a market order once price reaches the level.
  - The EA acts only at bar opens. When it is attached or restarted mid-bar, it waits for the next bar.
- **Management** (the research's "growth" profile, copied from its simulator):
  - **Stop**: 1.5 ATR from the fill. The ATR is the indicator's Wilder ATR(14) of the last closed bar, and this
    distance is 1R.
  - **Target**: +3R from the fill. The stop and target are first placed from the order level, then moved to the
    actual fill.
  - **Trail**: once the best price since the fill reaches +1R, the stop moves to 2 ATR behind the best price.
    - It is checked at the close of every completed M1 bar after the fill minute.
    - It only ever tightens, and only to a level the M1 close is already beyond.
    - Longs use bid prices. Shorts use ask prices (bid plus the bar's spread).
  - **No break-even step**. The research's growth profile has none.
  - **Time exit**: at market 24 hours after the fill.
- **Size**: a fixed lot (input, 0.01). One trade at a time. No risk engine yet; that is step 3.
- **Log**: every closed trade goes to `Common\Files\7wave_ea_trades_tester.csv` (rewritten at the start of each
  tester run) or `7wave_ea_trades_live.csv` (appended).
  - Each row has: signal bar, side, level, fill time and price, ATR, R distance, stop, target, exit time and price,
    exit reason (stop, trail, target, time), R, profit in $, and best R reached.
