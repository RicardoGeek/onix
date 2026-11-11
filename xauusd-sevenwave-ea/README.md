# XAUUSD SevenWave EA

A new XAUUSD Expert Advisor, built from scratch on the 7-EMA ribbon idea and tested on 10 years of real gold data.

> **v1.33** (current): the AI rater no longer vetoes trades. Its model was trained on 2017-2023, and on unseen 2024-2026 the setups
> it vetoed did better than the ones it kept (+0.43R vs +0.29R). It still scores every event for the log and HUD. Growth now bets at most
> 25% of the room above its trailing floor; at 50% the honest 2018-2023 account froze at the floor. MT5 Growth $10k: +$53,812 (2018-23)
> and +$280,058 (2024-26); Prop $50k: +28.9% and +48.2%. See REPORT.md and CHANGELOG.md.
>
> **v1.32**: v1.31, plus an optional `InpSkipNewsDays` (default off). When on, the EA opens no new trades on key US
> release days. That gives smoother results with lower drawdown, but gave up return in 2024-26.
>
> **v1.31**: a trade that first reaches +1.5R is secured at break-even, aims for 5R, may run 72h and trails 3 ATR(H1),
> in both modes. MT5 2024-2026: Growth $10k grew to $205k, Prop $50k to $74.9k. See REPORT.md.
>
> **v1.20** added the **whale pyramid** in House Money Growth mode. When a position first reaches +1.5R, the EA adds
> one unit of the same size, with its stop at the first entry and the same 3R target. Prop Firm mode never pyramids.
>
> **v1.10** changed the strategy described below. The ribbon is now geometric (**10/16/26/41/66/105/168**). The streams are
> **A, B, G and P** (P = M15 pools gated by H1+H4+D1). Both modes use trend-tail exits. Prop allows 2 concurrent positions and
> Growth allows 3, under a portfolio never-breach budget. Prop also has a consistency lock that banks the day at +2.4%.
> Defaults: Prop 0.5%, Growth 1.0% risk. See CHANGELOG.md and REPORT.md.

## The strategy in one paragraph

Seven EMAs (20/40/60/80/100/150/200) are computed on **H1, H4 and D1**. When they are stacked in perfect order
on the higher timeframes (fast above slow means up, the reverse means down), the trend hierarchy is aligned. The EA
then waits for price to reach a **liquidity pool**: a swing high or low on M30/H1/H2 that has held for hours or days,
and the place where resting stop orders cluster. When price breaks that level in the trend direction, the
stop orders fire, and the EA enters with them on the fresh wave. Six setup streams cover different structure
timeframes and pool ages. An **AI rater** (LightGBM converted to ONNX) scores each setup. Up to v1.32 it vetoed the weakest quarter; since
v1.33 the score is only logged, because the veto had no skill on years the model had not seen.

## Why this design: what 10 years of data showed

| Hypothesis tested (Dukascopy 2017-2026 + Pepperstone 2023-2026, hostile costs) | Result |
|---|---|
| Enter when the 7 EMAs first align on M15 | No edge: price is already extended (-0.06 to -0.21R per trade) |
| Pullback or limit entries into an aligned M15 ribbon | Random-walk odds minus costs |
| AI on every aligned M15 bar | Out-of-sample AUC 0.50-0.545, not tradable |
| Ribbon alignment stacked across H1 + H4 + D1 | Edge rises with every extra timeframe that agrees |
| Breakouts of aged H1/H2 liquidity pools in the hierarchy direction | **+0.14 to +0.39R per trade, positive in 7-9 of 10 years** |
| The same pool breakouts with no trend filter | ~0R: the hierarchy is what creates the edge |

## Settings (6 inputs)

| Input | Default | Meaning |
|---|---|---|
| Mode | Prop Firm | **Prop Firm**: protects the account. 2 positions; the portfolio risks at most 15% of the remaining daily and trailing room; the day is banked at +2.4%; never adds. **House Money Growth**: compounds. 3 positions; whale pyramid (one add at +1.5R); risks at most 50% of today's room and 25% of the trailing room. Both modes: trend-tail exits, whales secured at +1.5R aim for 5R, run up to 72h and trail 3 ATR(H1) |
| Risk per trade % | 0 = auto | Prop 0.5%, Growth 1.0% per position (stream weights A/B 1.0, G 0.6, P 0.8). Aggressive Growth preset: **2** with daily **15** and trailing **50** (MT5 $10k: +$156,656 in 2018-23, +$3,191,449 in 2024-26, max DD 43% / 34%) |
| Daily drawdown limit % | 0 = auto | Prop 3%, Growth 10%; measured from max(day-start balance, day-start equity) |
| Trailing max drawdown limit % | 0 = auto | Prop 6%, Growth 30%; measured from the high-water mark of max(balance, equity) |
| Magic number | 7072026 | |
| Skip key US news days | false | v1.32: no new trades on NFP / CPI / PCE / GDP / Retail Sales / Fed-decision days. Higher profit factor and lower drawdown, but less return in news-driven trend years |

There are no timezone, DST, symbol, lot or session settings. They are handled like this:
- **Clock**: gold pauses every day at 17:00 New York. The EA finds that pause in the broker's H1 history and learns the server
  clock from it: NY+7 (Pepperstone, GetLeveraged), CET/CEST (Upcomers) or a fixed offset. US and EU DST are applied
  automatically, in the tester and live alike.
- **Lots**: the EA takes the largest of MT5's OrderCalcProfit, the tick formula and the contract-size floor. This makes it immune to the
  10x tick-value misreport seen on Upcomers XAUUSD (tick value 0.1). Margin is always checked with market order types.
- **Prices** are quantised to the tick size. Stop and freeze levels and the filling mode (FOK/IOC) are detected automatically.

## Risk engine (both modes)

- **Room**: the distance from equity to the daily floor and to the trailing floor.
- **Budget**: every trade is sized so that the open stop risk of the whole portfolio, plus a 25% slippage cushion, stays inside a
  share of that room. Prop uses 15% of both. Growth uses 50% of today's room and, since v1.33, 25% of the trailing room.
- **Near a floor**: risk shrinks with the room (Kelly-safe), so a damaged account keeps trading small and recovers instead of
  freezing. No single stop can breach either limit.
- Circuit breakers: if equity comes within 20% of the daily budget or 10% of the total budget, the EA closes everything and stands down for the day.
- **Minimum lot**: 0.01 is allowed only when its full risk still fits the budget. Prices and lots respect the broker's tick size,
  steps and the 50-lot (Pepperstone) maximum per order.

## Files

- `MQL5/Experts/XAUUSD_SevenWave.mq5`: the EA
- `MQL5/Include/SevenWave/*.mqh`: Clock, Series (ribbon/ATR/pools), Market (MTF hierarchy), Streams, AiRater, RiskEngine, Trader
- `MQL5/Files/models/sevenwave_rater.onnx`: the AI rater (embedded at compile time via `#resource`)
- `python_pipeline/`: data, research studies, simulator, walk-forward training, ONNX export, MT5 report and parity tools

## Rebuild

```powershell
C:\Users\faker\mlv\Scripts\python.exe python_pipeline\sw_data.py --live      # refresh M1 caches (Dukascopy + Pepperstone)
C:\Users\faker\mlv\Scripts\python.exe python_pipeline\sw_export.py           # retrain + export ONNX + AiModelMeta.mqh
# copy MQL5\Include\SevenWave, MQL5\Files\models\sevenwave_rater.onnx and the .mq5 into the terminal, then compile
```
