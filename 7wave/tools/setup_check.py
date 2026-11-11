"""Independent Python copy of 7Wave rules 5-6 (RULES.md): the H4+D1 trend filter and the H1 swing breakout.

Reads the broker's H1, H4 and D1 bars from the running Pepperstone terminal (read-only), runs the rules bar by bar
exactly as the indicator does, and lists the armed setups and entries to check on the H1 chart (server time).

    C:\\Users\\faker\\mlv\\Scripts\\python.exe 7wave\\tools\\setup_check.py [SYMBOL] [LAST_K]

Also importable: setup_signals(h1, h4, d1, point) returns one row per H1 bar with the filter, armed levels and entries.
"""
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wave_rules import PERIODS, emas  # noqa: E402

SWING, MIN_AGE, MAX_AGE, OFFSET, MAX_DIST, ATR_N = 3, 12, 48, 0.15, 3.0, 14


def stacks(close):
    e = emas(close, PERIODS)
    up = np.all(e[:, :-1] > e[:, 1:], axis=1)
    dn = np.all(e[:, :-1] < e[:, 1:], axis=1)
    return np.where(up, 1, np.where(dn, -1, 0))


def wilder_atr(h, l, c, n=ATR_N):
    out = np.empty(len(c))
    for i in range(len(c)):
        tr = h[i] - l[i] if i == 0 else max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1]))
        out[i] = (tr if i == 0 else (out[i - 1] * i + tr) / (i + 1)) if i < n else out[i - 1] + (tr - out[i - 1]) / n
    return out


def setup_signals(h1, h4, d1, point):
    """h1/h4/d1: DataFrames with time (server epoch seconds of the bar open), open, high, low, close, spread."""
    o, h, l, c = (h1[k].to_numpy(float) for k in ("open", "high", "low", "close"))
    spr = h1["spread"].to_numpy(float) * point
    n = len(c)
    atr = wilder_atr(h, l, c)
    # rule 5: the filter of each H1 bar from the H4 / D1 bars closed by its close
    close_t = h1["time"].to_numpy() + 3600
    k4 = np.searchsorted(h4["time"].to_numpy() + 4 * 3600, close_t, side="right") - 1
    kd = np.searchsorted(d1["time"].to_numpy() + 86400, close_t, side="right") - 1
    s4, sd = stacks(h4["close"].to_numpy(float)), stacks(d1["close"].to_numpy(float))
    f4 = np.where(k4 >= 0, s4[np.maximum(k4, 0)], 0)
    fd = np.where(kd >= 0, sd[np.maximum(kd, 0)], 0)
    filt = np.where(f4 == fd, f4, 0)
    # rule 6: untouched swing pools after each closed bar, then the armed level and entry of the next bar
    ph, phi, pl, pli = np.full(n, np.nan), np.full(n, -1), np.full(n, np.nan), np.full(n, -1)
    highs, lows = [], []  # [level, swing bar]
    for i in range(n - 1):  # closed bars only
        p = i - SWING
        if p - SWING >= 0:
            nb = [q for q in range(p - SWING, p + SWING + 1) if q != p]
            if all(h[q] < h[p] for q in nb):
                highs.append((h[p], p))
            if all(l[q] > l[p] for q in nb):
                lows.append((l[p], p))
        highs = [(v, k) for v, k in highs if h[i] <= v or k > i - 1]
        lows = [(v, k) for v, k in lows if l[i] >= v or k > i - 1]
        above = [(v, k) for v, k in highs if v > h[i]]
        below = [(v, k) for v, k in lows if v < l[i]]
        if above:  # nearest; on a tie the earlier swing, like the indicator
            ph[i], phi[i] = min(above)
        if below:
            pl[i], pli[i] = max(below, key=lambda x: (x[0], -x[1]))
    rows, used_h, used_l = [], -1, -1
    for i in range(1, n):
        p, a, closed = i - 1, atr[i - 1], i < n - 1
        row = dict(bar=i, filter_prev=int(filt[p]), long_level=np.nan, short_level=np.nan, pool=np.nan, age=np.nan,
                   entry=0, fill=np.nan, closed=closed)
        if filt[p] == 1 and not np.isnan(ph[p]) and phi[p] != used_h:
            age, lv = p - phi[p], ph[p] - OFFSET * a
            if MIN_AGE <= age <= MAX_AGE and lv - o[i] <= MAX_DIST * a:
                row.update(long_level=lv, pool=ph[p], age=age)
                if closed and h[i] + spr[i] >= lv:
                    row.update(entry=1, fill=max(lv, o[i] + spr[i]))
                    used_h = phi[p]
        if filt[p] == -1 and not np.isnan(pl[p]) and pli[p] != used_l:
            age, lv = p - pli[p], pl[p] + OFFSET * a
            if MIN_AGE <= age <= MAX_AGE and o[i] - lv <= MAX_DIST * a:
                row.update(short_level=lv, pool=pl[p], age=age)
                if closed and l[i] <= lv:
                    row.update(entry=-1, fill=min(lv, o[i]))
                    used_l = pli[p]
        rows.append(row)
    out = pd.DataFrame(rows)
    out["time"] = pd.to_datetime(h1["time"].to_numpy()[out.bar], unit="s")
    out["filter_bar"] = filt[out.bar]
    return out


def fetch(symbol):
    import MetaTrader5 as mt5
    if not mt5.initialize(path=r"C:\Program Files\Pepperstone MetaTrader 5\terminal64.exe"):
        raise SystemExit(f"initialize failed: {mt5.last_error()}")
    try:
        get = lambda tf: pd.DataFrame(mt5.copy_rates_from_pos(symbol, tf, 0, 200000))  # noqa: E731
        return get(mt5.TIMEFRAME_H1), get(mt5.TIMEFRAME_H4), get(mt5.TIMEFRAME_D1), mt5.symbol_info(symbol).point
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    symbol = sys.argv[1] if len(sys.argv) > 1 else "XAUUSD"
    last_k = int(sys.argv[2]) if len(sys.argv) > 2 else 12
    h1, h4, d1, point = fetch(symbol)
    sig = setup_signals(h1, h4, d1, point)
    ent = sig[sig.entry != 0]
    print(f"{symbol} H1: {len(h1)} bars from {pd.to_datetime(h1.time.iloc[0], unit='s'):%Y-%m-%d}; "
          f"H4 {len(h4)}, D1 {len(d1)} bars")
    per_year = ent.groupby(ent.time.dt.year).size()
    print("entries per year (2017+):", ", ".join(f"{y}: {v}" for y, v in per_year.items() if y >= 2017))
    now = sig.iloc[-1]
    state = "UP" if now.filter_prev == 1 else ("DOWN" if now.filter_prev == -1 else "OFF")
    armed = (f"buy stop {now.long_level:.2f}" if not np.isnan(now.long_level) else
             f"sell stop {now.short_level:.2f}" if not np.isnan(now.short_level) else "no order armed")
    print(f"forming bar {now.time:%a %Y-%m-%d %H:%M}: filter {state}, {armed}")
    print(f"last {last_k} entries (server time, the bar the entry traded in):")
    for r in ent.tail(last_k).itertuples():
        side = "BUY " if r.entry > 0 else "SELL"
        lv = r.long_level if r.entry > 0 else r.short_level
        print(f"  {r.time:%a %Y-%m-%d %H:%M}  {side} stop {lv:.2f}  fill {r.fill:.2f}  pool {r.pool:.2f}  age {int(r.age)}")
