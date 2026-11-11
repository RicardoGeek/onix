"""7Wave rules 2-4 in Python, the same logic as MQL5/Indicators/7Wave/7Wave.mq5 (see RULES.md).

Shared by tools/wave_check.py (the chart checklist the user verified) and research/wave_scorecard.py, so both run
exactly the rules the user checked on the chart.

Rule 2, arrow : close > EMA20 > ... > EMA140 (UP) or the reverse (DOWN) on a closed bar, unless a wave in the same
                direction is still going; a wave ends when 3+ of the 7 lines are out of order
Rule 3, star  : EMA 20 closes beyond all 6 other lines after it was last beyond all of them on the other side,
                while at least 3 of those 6 lines still hold the old trend's order
Rule 4, candle: a signal is drawn only on a bar closing its color (UP bullish, DOWN bearish); otherwise it waits
                for the first such bar and is cancelled if EMA 20 stops being beyond all 6 lines on its side
(a line is out of order when it is on the wrong side of at least one other line of the set)
"""
import numpy as np
import pandas as pd

PERIODS = (20, 40, 60, 80, 100, 120, 140)
WAVE_END_LINES = 3
STAR_MIN_IN_ORDER = 3


def emas(close, periods=PERIODS):
    """Columns of EMAs seeded like the indicator: EMA[0] = close[0], EMA[i] = close[i]*k + EMA[i-1]*(1-k)."""
    s = pd.Series(np.asarray(close, dtype=float))
    return np.column_stack([s.ewm(span=p, adjust=False).mean().to_numpy() for p in periods])


def out_of_order(v, direction):
    """Lines of v (fastest first) on the wrong side of at least one other line, for `direction` (1 up, -1 down)."""
    wrong = [False] * len(v)
    for a in range(len(v) - 1):
        for b in range(a + 1, len(v)):
            in_order = v[a] > v[b] if direction > 0 else v[a] < v[b]
            if not in_order:
                wrong[a] = wrong[b] = True
    return sum(wrong)


def signals_for(open_, close, ema, settle=0, states=False):
    """Stars and arrows on closed bars.

    Returns (signals, stats), or (signals, stats, wave) with states=True. signals: list of (bar drawn on,
    "arrow"/"star", direction, bar it became due on). stats counts waits, cancellations and rejected crosses from bar
    `settle` on. wave[i]: the 7Wave wave still going after closed bar i (1 up, -1 down, 0 none), as the indicator's
    "Wave" Data Window line.
    """
    open_ = np.asarray(open_, dtype=float)
    close = np.asarray(close, dtype=float)
    n = len(close)
    fast, rest = ema[:, 0], ema[:, 1:]
    side_all = np.where(fast > rest.max(axis=1), 1, np.where(fast < rest.min(axis=1), -1, 0))
    up = (close > fast) & np.all(ema[:, :-1] > ema[:, 1:], axis=1)
    dn = (close < fast) & np.all(ema[:, :-1] < ema[:, 1:], axis=1)
    aligned_all = np.where(up, 1, np.where(dn, -1, 0))
    candle_all = np.sign(close - open_).astype(int)
    out, stats = [], dict(arrow_waited=0, arrow_cancelled=0, star_waited=0, star_cancelled=0, star_rejected=0)
    wave_after = np.zeros(n, dtype=np.int64)
    wave = waiting = waiting_since = 0
    last_side = star_waiting = star_since = 0
    for i in range(1, n - 1):  # closed bars only; bar n-1 is still forming
        side, candle = side_all[i], candle_all[i]
        counted = i >= settle
        # rules 2 + 4: arrows
        if wave != 0 and out_of_order(ema[i], wave) >= WAVE_END_LINES:
            wave = 0
        if waiting != 0:
            if side != waiting:
                waiting = 0
                stats["arrow_cancelled"] += counted
            elif candle == waiting:
                out.append((i, "arrow", waiting, waiting_since))
                stats["arrow_waited"] += counted
                wave, waiting = waiting, 0
        aligned = aligned_all[i]
        if aligned != 0 and aligned != wave and aligned != waiting:
            if candle == aligned:
                out.append((i, "arrow", aligned, i))
                wave = aligned
            else:
                waiting, waiting_since = aligned, i
        # rules 3 + 4: stars
        if star_waiting != 0:
            if side != star_waiting:
                star_waiting = 0
                stats["star_cancelled"] += counted
            elif candle == star_waiting:
                out.append((i, "star", star_waiting, star_since))
                stats["star_waited"] += counted
                star_waiting = 0
        if side != 0 and last_side == -side:
            in_order = (len(PERIODS) - 1) - out_of_order(ema[i][1:], -side)
            if in_order >= STAR_MIN_IN_ORDER:
                if candle == side:
                    out.append((i, "star", side, i))
                else:
                    star_waiting, star_since = side, i
            else:
                stats["star_rejected"] += counted
        if side != 0:
            last_side = side
        wave_after[i] = wave
    return (out, stats, wave_after) if states else (out, stats)
