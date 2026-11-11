# XAUUSD SevenWave EA: CHANGELOG

## [v1.33] - 2026-11-04

The AI no longer vetoes trades. Every setup that passes the hierarchy, pool and risk rules is traded.

### Why
- **In-sample model**: the ONNX rater (v1.10) was trained on Dukascopy 2017-2023, so its veto in 2018-2023 MT5 runs was in-sample.
- **Method**: every v1.32 MT5 event was matched to its simulated outcome (`python_pipeline/sw_study52.py`, v1.30-like whale management).
- **Seen years 2018-2022**: vetoed setups made -0.05R to -0.58R against +0.39R to +1.17R for traded ones.
- **Unseen years 2024-2026**: the veto removed better-than-average setups, 133 of them at +0.43R against +0.29R for the traded ones.
  This is in every unseen year: 2024 +0.31R vs +0.16R, 2025 +0.50R vs +0.37R, 2026 +0.90R vs +0.39R.
- **Out-of-sample AUC 0.517** in v1.10's own walk-forward test: the rater has no skill on new data.
- **Disclosure**: v1.10-v1.32 2018-2023 MT5 results were flattered by this in-sample veto. The 2024-2026 results were out of sample for it.

### Strategy
- `SW_AI_VETO false`: the rater still scores every event for the log and HUD, but never blocks an entry.
- **Kelly-safe Growth budget**: Growth may now bet at most 25% of the trailing room above its floor (`SW_GROWTH_TOT_FRAC 0.25`,
  previously 0.5). Without the in-sample veto, the honest 2018-2023 Growth account froze at the 30% floor in Aug 2022 at
  0.5: each loss could take 40% of the remaining room, until even 0.01 lot no longer fitted. Prop already used 0.15.
- **No new inputs.**

### Verified (Pepperstone XAUUSD, Model 4 + random delay, 1:100, all inputs passed explicitly)
- **Growth $10k, defaults (1% / 10% / 30%), by room share**:

  | Room share | 2018-2023 | 2024-Oct 2026 |
  |---|---|---|
  | 0.5 | +$24,747, then froze | +$292,339 |
  | 0.15 | +$42,088 | +$193,887 |
  | **0.25 (shipped)** | **+$53,812, every year positive, max DD 23.0%** | **+$280,058 (PF 2.27, max DD 14.9%)** |

  v1.32 2024-2026: +$206,225.
- **Prop $50k, defaults**:
  - 2024-2026: +$24,082 (+48.2%, max DD 3.26%, equity DD 4.01%). Challenge pass 36.8% vs 35.0%, 0 breaches.
  - 2018-2023 (honest): +$14,467 (+28.9%). It showed +51.2% with the in-sample veto.
- **Risk frontier, Growth $10k, room share 0.5**:
  - 2% / 15% / 50%: +$444,009 (2018-23, max DD 39.9%) and +$3,273,039 (2024-26, max DD 29.4%).
  - 3% / 20% / 60%: +$424,779 (equity DD 59.4% of a 60% limit) and +$7,420,959 (max DD 43.1%).
  - So 2% is the sweet spot; 3% only adds drawdown in hard years. Pepperstone caps one order at 50 lots (binds near $5M).

## [v1.32] - 2026-11-04

An optional key-news-day filter. The default behaviour is unchanged from v1.31.

### Strategy
- **New input `InpSkipNewsDays`** (default `false`). When true, the EA opens no new first positions on the UTC day of a key US
  release: NFP, the CPI family, Core PCE, GDP q/q, Retail Sales, or the Fed rate decision. Open trades keep running.
- **Release days**: embedded for the Strategy Tester (`NewsDays.mqh`, 627 days 2016-12 .. 2026-12), because the tester has no
  calendar. Live, the terminal's MQL5 calendar is also asked by event id, so later releases are covered in any language.
- **`MQL5/Scripts/SW_CalendarExport.mq5`**: a read-only calendar export. `python_pipeline/sw_newsdays.py` regenerates the
  embedded tables from it.

### Research and verification (Pepperstone XAUUSD, Model 4 + random delay; filter ON vs v1.31)
- Setups on key-release days averaged -0.089R (35% WR) vs +0.368R on other days, Dukascopy 2017-2026.
- **MT5, filter on**: the profit factor rose and the drawdown fell in every run.
  - Growth $10k: 2018-2023 $143,092 → $205,113, but 2024-2026 $205,014 → $136,729.
  - Prop $50k: +51.2% → +56.9% and +49.9% → +47.0%; the 2024-2026 challenge pass rate fell from 39.3% to 30.1%.
  - Hence an option, not the default.
- **Rejected**:
  - Trading the NFP surprise or fading the first 5 minutes: ~0R with the true release times.
  - Dollar-index / USDJPY / silver / stock-index agreement as setup filters: no robust split.
- **Correction**: the MQL5 calendar stamps events in UTC, not server time. A first NFP test converted them and entered ~3h
  early, which looked like +0.40R per trade (look-ahead). Fixed everywhere; the day-level news filter was unaffected.

## [v1.31] - 2026-11-04

The wide whale trail; Prop now handles whales too (it still never adds a unit).

### Strategy
- **Wide whale trail (both modes)**: once a trade reaches +1.5R and is secured at break-even + 0.05R, it and its Growth add
  trail **3.0 x ATR(H1) instead of 2.0**.
- **Prop whale handling**: a Prop trade that reaches +1.5R is secured at break-even + 0.05R, then aims for 5R, may run 72h and
  trails 3 ATR. Prop still never adds a unit.
- **Restarts**: re-adopted whales keep the 72h stop and the wide trail.
- **No new inputs.**

### Verified (Pepperstone XAUUSD, Model 4 + random delay, 1:100, all inputs passed explicitly)
- **Growth $10k, 1%**:
  - 2018-2023: $10k grew to $143,092 (+1,331%), vs $136,219 for v1.30.
  - 2024-Oct 2026: $10k grew to **$205,014 (+1,950%)**, vs $74,369 for v1.30.
  - Max equity DD 23.99% / 13.25%; profit factor 1.72 / 2.53.
- **Growth $1k**:
  - 2018-2023: $10,760 (+976%).
  - 2024-2026: $12,647 (+1,165%), vs $6,394 for v1.30.
  - Max equity DD 22.91% / 10.35%.
- **Prop $50k**:
  - 2018-2023: $75,596 (+51.2%), vs +44.2% for v1.30. 2024-2026: $74,926 (+49.9%), vs +30.9%.
  - Every year positive. Max equity DD 3.11% / 3.78%; the worst day is about -1%.
  - Challenge replay pass rate: 33.3% → 39.3% (2024-2026) and 1.4% → 9.1% (2018-2023), with 0 breaches.
- **Trade-off**: the win rate is lower (Prop 43-50%, Growth 48-50%). Wider trails give up a few small wins for bigger runners.

## [v1.30] - 2026-11-04

The whale-extension release, House Money Growth only. Prop Firm behaviour is unchanged.

### Strategy
- **Whale extension**: when a position reaches +1.5R (the moment v1.20 adds a unit), both the position and its add now aim
  for **5R instead of 3R** and may run **72h instead of 24h**.
  - Time stops are now per position.
  - Whales re-adopted after a restart keep the 72h stop: adds are recognised by their `+` tag, first positions by a target
    beyond 4R.
- **Research** (Python, Dukascopy, real lots), Growth at 1% risk:
  - $1k: 2018-2023 +202% → +341%; 2024-2026 +557% → +746%.
  - $10k: +248% → +457%; +928% → +1,271%.
  - The neighbouring settings (TP 8R, 120h) also beat v1.20, so this is a plateau, not a lucky spike.

### Verified (Pepperstone XAUUSD, Model 4 + random delay, 1:100, all inputs passed explicitly)
- **Growth $1k**:
  - 2018-2023: $1k grew to **$10,248 (+925%)**, vs v1.20 +461%.
  - 2024-Oct 2026: $1k grew to **$6,394 (+539%)**, vs v1.20 +455%.
  - Max equity DD 20.75% / 11.56%.
- **Growth $10k**:
  - 2018-2023: $10k grew to **$136,219 (+1,262%)**.
  - 2024-Oct 2026: $10k grew to **$74,369 (+644%)**.
  - Max equity DD 21.16% / 11.54%.
- **Growth $10k at 2% risk**: 2018-2023 grew to $336,424 (+3,264%, equity DD 29.46%). But 2024-2026 hit the 30% floor in early
  2025 and stalled at $13,427. **1% stays the default.**
- **Prop $50k**, 2024-Oct 2026: +$15,429 (+30.9%), the same as v1.20.

## [v1.20] - 2026-11-04

The whale-pyramid release ("wait for the whale and ride the wave"). Prop Firm behaviour is unchanged.

### Strategy
- **Whale pyramid (House Money Growth only)**:
  - Trigger: a position first reaches +1.5R, counted after its entry minute.
  - The EA then opens ONE add of the same size. Its stop sits at the first entry, its target is the first position's 3R target,
    and it has the same 24h time stop.
  - Before the add, the first position's stop moves to at least break-even + 0.05R, so it no longer carries risk.
  - Trades that never reach +1.5R never get the add. Each position gets one add decision; a position first seen beyond
    +2.0R (a gap or a restart) gets none.
- **Research** (Python, Dukascopy 2017-2026, hostile costs): +0.382R vs +0.258R per attempt, positive 10/10 years.
  Growth $10k grew to $385,123 vs $145,737 (max DD 25.4%). In Prop it froze the account against its 6% trailing floor,
  so Prop never pyramids.
- **Slots and budget**: an add rides inside its first position's slot (Growth still allows 3 first positions). It shares the
  portfolio never-breach budget: an add opens only if its full stop fits the remaining budget.
- **Restarts**: adds are tagged `<stream>+` in the order comment (e.g. `SW7 A+ R35.10 T31.27`). After a restart they are
  re-linked to their first position, so no position is ever pyramided twice.
- **No new inputs.** The HUD shows adds next to positions. The tester logs mark adds with a `+` stream and `pyramid` decisions.

### Verified (Pepperstone XAUUSD, Model 4 + random delay, 1:100, all inputs passed explicitly)
- **Prop $50k**, same behaviour as v1.10:
  - 2018-2023: $50k grew to $72,076 (+44.2%), positive every year, max equity DD 2.82%.
  - 2024-Oct 2026: $50k grew to $65,527 (+31.1%), positive every year, max equity DD 3.53%.
- **Growth $1k**:
  - 2018-2023: $1k grew to **$5,618 (+461%)**, vs $4,351 (+335%) for v1.10.
  - 2024-Oct 2026: $1k grew to **$5,552 (+455%)**, vs $3,537 (+254%) for v1.10.
  - Max equity DD 17.94% / 12.95%, against a 30% limit.
  - At $1k, lots round down to 0.01 steps, so the median real risk was 0.58-0.66% instead of 1%.
- **Parity**: all 285 + 216 adds opened while their first position was live, with the stop a median 1.50R from the add
  (exactly the research rule). Adds won 58.6% / 63.9% and made +$761 / +$1,940.
- **Python real-lot replay** (0.01-lot minimum, the EA's sizing rules) agrees in direction and size. Growth $1k: +121% → +202%
  (2018-2023) and +346% → +557% (2024-2026).

## [v1.10] - 2026-11-04

Cadence and consistency release. It optimises for prop-firm consistency rules and steady own-money growth instead of raw scale.

### Strategy
- **Geometric 7-EMA ribbon 10/16/26/41/66/105/168** (ratio 1.6) replaces the linear 20-200 ribbon on H1/H4/D1. It was selected on
  2017-2022 only, out of a grid of 27 ribbons. Every geometric neighbour was positive on both Dukascopy and Pepperstone, and the
  wider-spaced ribbons gave a clearer edge.
- **Streams A, B, G, P**: H1 / H2 / young-H1 pools gated by H4+D1, plus a new **M15 pool stream (P)** gated by H1+H4+D1.
  Streams C, E and F were dropped: their edge was ~0 with the new ribbon. Risk weights are 1.0 / 1.0 / 0.6 / 0.8.
- An M15 "fresh-wave" ribbon-realign stream was tested and **rejected**. Its independent stats looked strong (+0.18R/trade,
  1.2/day), but in a time-ordered portfolio replay it was ~0R, because its signals cluster in trends.
- **Management (both modes)**: trend-tail exits. SL 1.5x ATR(H1), no partial, ratchet 2.0x ATR(H1) after +1R, TP 3R, 24h
  time stop. (The v1.00 win-rate exit removed most of the edge of the new streams.)
- **AI veto retrained** on the v1.10 setups (Dukascopy 2017-2023, 1,329 setups, 17 trees, threshold 0.4396). Walk-forward on
  2023-2026 it raised the edge of the trades actually taken from +0.287R to +0.324R.

### Risk engine
- **Concurrent positions**: Prop 2, Growth 3, one per pool trigger, with per-position management state that survives restarts
  (R and the trail distance are stored in the order comment).
- **Portfolio never-breach budget**: the CURRENT risk of all open positions plus the new one may use at most 15% (Prop) / 50%
  (Growth) of the smaller of the daily and trailing rooms. Below about 15%, the expected growth of the room stays positive near a trailing floor
  (Kelly). At 40-50% a continuous 6%-trailing account froze at the floor in 2017; at 15% it survived all of 2017-2026.
- **Prop consistency lock**: once today's gain reaches 80% of the daily loss limit (2.4% by default), the EA banks the day,
  flattens and stands down. With an 8% target, the best day is then always below 30% of the profit.
- The total breaker only fires on a FRESH intraday slide. A day that opens near the trailing floor is handled by the
  shrinking position size instead of freezing the account (v1.10 pre-release bug, found in MT5).
- Defaults: Prop 0.5% per trade, daily 3%, trailing 6%. Growth 1.0% per trade, daily 10%, trailing 30%.
- Tester-only per-position trade log (`sevenwave_trades.csv`), giving exact statistics with concurrent positions.

### Verified (Pepperstone XAUUSD, Model 4 + random delay, 1:100, all inputs passed explicitly)
- Prop $100k: 2018-2023 **+41.0%, positive in every year**, max DD <= 2.41% per year. 2024 +10.4%, 2025 +17.5%, 2026 YTD +2.3%
  (+$32,735, max DD 2.96%). Prop-challenge replay (8% target, 30% best-day rule, 6% trailing, 180 days): 34.2% pass on
  2024-2026 starts (v1.00: 2.5%) and **0 breaches**.
- Growth $10k: 2018-2023 **$10k to $59,283 (+493%), positive in every year**, max DD <= 10%. 2024 +31.1%, 2025 +120.4%,
  2026 YTD +4.8% ($10k to $30,267, max DD 11.7%).
- Known limit: when the H4/D1 stacks disagree for months (2021, Apr-Sep 2026) the EA idles. A relaxed 5-of-6 gate doubles
  activity but cuts the edge in half (tested and rejected).
- Binary: `bin/XAUUSD_SevenWave/XAUUSD_SevenWave_v1.10.ex5` (SHA-256 DEEDDD5C...C1074A).

### Correction to v1.00 results
- The v1.00 2018-2023 MT5 rows first reported here ran with a leftover 5% risk input (the tester keeps unlisted inputs from the
  previous run). Re-run at the real defaults: Prop 0.75% gave +19.1% (positive every year, max DD 2.86%); Growth 3% gave +274%
  (positive every year, max DD 16.0%). The 2024-2026 v1.00 rows were correct.

## [v1.00] - 2026-11-03

First release of the SevenWave EA: a new design that does not reuse any previous EA's strategy.

### Strategy
- **Trend hierarchy**: a 7-EMA ribbon (20/40/60/80/100/150/200) on H1, H4 and D1. H4 is rebuilt from H1 and anchored to the
  17:00 New York close; D1 uses broker daily bars. The stack state is +1 when all EMAs are ordered fast > slow, -1 when they are reversed, and 0 when mixed.
- **Liquidity-Wave entries**: virtual stop orders just inside aged, unbroken 3/3-fractal swing highs/lows on M30/H1/H2,
  armed only when the hierarchy agrees. Six streams (A/B core, C/E/F/G frequency):
  A H1|H4+D1 age 12-48, B H2|H4+D1 age 6-48, C H1|H4 age 12-120, E H1|H1 age 12-48, F M30|H1+H4 age 12-96,
  G H1|H4+D1 age 3-12. Risk weights per stream: 1.0 / 1.0 / 0.5 / 0.5 / 0.35 / 0.35.
- **AI veto**: LightGBM to ONNX (17 features, `float32[1,17]` to `label int64[1]` + `probabilities float32[1,2]`), trained on
  Dukascopy 2017-2023 (1,898 setups, 19 trees). It vetoes setups below the 25th percentile of its training validation scores
  (threshold 0.40477). 2024-2026 is fully out of sample for the model.
- **Management by mode**:
  - Prop Firm (win-rate style): SL 2.0x ATR(H1), 20% partial at +0.3R, then break-even +0.05R, ratchet trail 1.0x ATR(H1)
    after +1.5R on completed M1 bars, TP 2R, 48h time stop.
  - House Money Growth (profit style): SL 1.5x ATR(H1), no partial, ratchet trail 2.0x ATR(H1) after +1R, TP 3R, 24h time stop.

### Risk engine
- Daily floor from max(day-start balance, equity) on the broker server day. Trailing total floor from the high-water mark of
  max(balance, equity).
- Never-breach sizing: a full stop plus a 25% cushion uses at most 1/2 of the daily room and 1/4 of the total room. Breakers
  flatten the account and stand down for the day at 80% of the daily budget or 90% of the total budget.
- Growth mode: house-money boost (up to 2x once the account has doubled) and a linear drawdown governor (x0.25..1).
- Lot sizing takes the largest of OrderCalcProfit, the tick formula and the contract floor. Margin is checked with the market order type and capped at 85% of free margin.

### Robustness
- Broker clock learned from the daily 17:00-NY break in H1 history (NY-locked, EU-DST or fixed-offset models, real US/EU
  DST calendars), and cross-checked against TimeTradeServer()-TimeGMT() on live terminals.
- Prices are quantised to the tick size. Stop and freeze levels are respected, the filling mode is auto-detected, and open positions are re-adopted after a restart.
- Latency/gap-safe entries: on 10016/10015/requote the EA re-enters without stops, then immediately attaches re-anchored SL/TP.
  It closes at once if price is already beyond the intended stop or no stop can be attached.

### Verified (Pepperstone XAUUSD, Model 4 + random delay, 1:100) - details in REPORT.md
- Prop $100k: 2024 +2.5%, 2025 +5.4%, 2026 YTD +2.5% (PF 1.34, max equity DD 4.08%, MT5 win rate 84.9%); 2018-2023 +17.6%
  (max equity DD 5.19%). The 6% trailing limit was never breached.
- Growth $10k: 2024 +18.4%, 2025 +95.5%, 2026 YTD +41.6% ($10k to $32,745, PF 1.52, max equity DD 14.5%); 2018-2023 $10k to $50,469.
  Positive in every year 2018-2026.
- Parity: 97.2% of EA triggers matched the Python research replay, AI score correlation 0.988, 94.5% of trades matched one-to-one.
- Binary: `bin/XAUUSD_SevenWave/XAUUSD_SevenWave_v1.00.ex5` (SHA-256 AD5FEA41...C95B2), deployed to Pepperstone, Upcomers,
  GetLeveraged and BreakFree (the MT5 Tests data folder has no MQL5 tree yet).
