"""Multi-timeframe market-structure hierarchy (broker-clock-free).

Timeframes: M5, M15, H1 (UTC-aligned: identical on every whole-hour-offset broker), H4 and D1 anchored to the gold
trading day (New York 17:00 close), i.e. exactly Pepperstone's server-midnight H4/D1 candles, rebuilt from M1 so
the EA can reproduce them on ANY broker from H1/M1 data with the DST-aware NY clock.

Per timeframe state (as of the last CLOSED bar):
  ribbon : +1 / -1 when the 7 EMAs are fully stacked with price beyond EMA-fast, else 0
  stack  : +1 / -1 when the 7 EMAs are fully stacked (price anywhere)
  bos    : direction of the last break of structure (close beyond the last confirmed swing high / low)
  hhhl   : +1 if last swing high > previous and last swing low > previous (HH+HL), -1 if LH+LL, else 0
"""
import numpy as np
import pandas as pd
from numba import njit
import sw_engine as E


def ny_local_minutes(t_utc: np.ndarray) -> np.ndarray:
    ny = pd.to_datetime(t_utc, unit="s").tz_localize("UTC").tz_convert("America/New_York")
    loc = ny.tz_localize(None).values.astype("datetime64[m]").astype(np.int64)
    return loc


def make_bars_ny(m1a: dict, hours: int, nyloc_min: np.ndarray):
    """NY-anchored bars: buckets of `hours` starting at NY 17:00 (H4: 17,21,01,05,09,13; D1: 17->17)."""
    key = (nyloc_min - 17 * 60) // (hours * 60)
    chg = np.flatnonzero(np.diff(key)) + 1
    start = np.concatenate([[0], chg]).astype(np.int64)
    end = np.concatenate([chg, [len(key)]]).astype(np.int64)
    b = dict(o=m1a["o"][start], c=m1a["c"][end - 1], h=np.maximum.reduceat(m1a["h"], start),
             l=np.minimum.reduceat(m1a["l"], start), m1s=start, m1e=end,
             spr=np.add.reduceat(m1a["spr"], start) / (end - start), minutes=hours * 60)
    b["t"] = m1a["t"][start]                 # UTC time of first minute
    b["t_close"] = m1a["t"][end - 1] + 60    # UTC time the bar is known closed (last minute + 60s)
    b["n"] = len(start)
    return b


@njit(cache=True)
def structure_nb(h, l, c, L, R):
    """Fractal swings (L bars left, R bars right; confirmed R bars later -> causal) and BOS / HHHL trend states."""
    n = len(c)
    bos = np.zeros(n, np.int64)
    hhhl = np.zeros(n, np.int64)
    sh_arr = np.full(n, np.nan)
    sl_arr = np.full(n, np.nan)
    last_sh = np.nan; prev_sh = np.nan
    last_sl = np.nan; prev_sl = np.nan
    state = 0
    for i in range(n):
        p = i - R  # candidate pivot confirmed at bar i
        if p - L >= 0:
            is_h = True
            is_l = True
            for q in range(p - L, p + R + 1):
                if q == p:
                    continue
                if h[q] >= h[p]:
                    is_h = False
                if l[q] <= l[p]:
                    is_l = False
            if is_h:
                prev_sh = last_sh; last_sh = h[p]
            if is_l:
                prev_sl = last_sl; last_sl = l[p]
        if not np.isnan(last_sh) and c[i] > last_sh:
            state = 1
        elif not np.isnan(last_sl) and c[i] < last_sl:
            state = -1
        bos[i] = state
        sh_arr[i] = last_sh
        sl_arr[i] = last_sl
        if not (np.isnan(prev_sh) or np.isnan(prev_sl)):
            if last_sh > prev_sh and last_sl > prev_sl:
                hhhl[i] = 1
            elif last_sh < prev_sh and last_sl < prev_sl:
                hhhl[i] = -1
    return bos, hhhl, sh_arr, sl_arr


def tf_states(b: dict, periods=E.DEFAULT_PERIODS, L=3, R=3):
    E.add_ribbon(b, periods)
    b["ribbon"] = np.where(b["bull"], 1, np.where(b["bear"], -1, 0)).astype(np.int64)
    b["stackd"] = np.where(b["stack_bull"], 1, np.where(b["stack_bear"], -1, 0)).astype(np.int64)
    b["bos"], b["hhhl"], b["swh"], b["swl"] = structure_nb(b["h"], b["l"], b["c"], L, R)
    st = b["stackd"]
    age = np.zeros(len(st), np.int64)
    for i in range(1, len(st)):
        age[i] = age[i - 1] + 1 if (st[i] != 0 and st[i] == st[i - 1]) else (1 if st[i] != 0 else 0)
    b["sage"] = age
    if "t_close" not in b:
        b["t_close"] = b["t"] + b["minutes"] * 60
    return b


def map_last_closed(src: dict, t_decision: np.ndarray) -> np.ndarray:
    """Index of the last src bar closed at or before each decision time (-1 if none)."""
    return np.searchsorted(src["t_close"], t_decision, side="right") - 1


def build_hierarchy(m1a: dict, periods=E.DEFAULT_PERIODS):
    nyl = ny_local_minutes(m1a["t"])
    tfs = {}
    for name, mins in (("M5", 5), ("M15", 15), ("H1", 60)):
        tfs[name] = tf_states(E.make_bars(m1a, mins), periods)
    tfs["H4"] = tf_states(make_bars_ny(m1a, 4, nyl), periods)
    tfs["D1"] = tf_states(make_bars_ny(m1a, 24, nyl), periods)
    return tfs
