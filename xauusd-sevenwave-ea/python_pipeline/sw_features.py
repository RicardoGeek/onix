"""SevenWave feature set (computed at an M15 bar close, no look-ahead, scale-free, broker-clock-free).

Every feature is expressed in ATR units / ratios / bar counts so 2017 gold ($1,200) and 2026 gold ($4,000+) look
alike to the model.  Direction-signed: for a long candidate the feature is taken as-is, for a short it is
multiplied by -1 (so "price far above EMA-fast" means "stretched in the trade direction" for both).

The SAME definitions are re-implemented 1:1 in MQL5 (SevenWave/Features.mqh).  Order matters: FEATURES.
"""
import numpy as np
import pandas as pd
from numba import njit
import sw_engine as E

FEATURES = [
    "g0", "g1", "g2", "g3", "g4", "g5",          # adjacent ribbon gaps (e_k - e_k+1)/ATR, signed
    "d0", "d2", "d4", "d6",                      # (close - e_k)/ATR, signed
    "s0", "s3", "s6",                            # 4-bar slope of e0/e3/e6 in ATR, signed
    "age", "fresh",                              # log1p bars since stack formed / since opposite stack
    "volreg", "atr_bp", "cost_atr",              # ATR14 / ATR(960 mean), ATR in bp of price, spread/ATR
    "hsin", "hcos",                              # UTC hour of the decision (cyclic)
    "h1_order", "h1_d0", "h1_d6",                # H1 ribbon: order score (-6..6) signed, distances in H1 ATR
    "pos96", "hi96", "lo96",                     # 24h range position, distance to 24h high/low in ATR (signed)
    "ret4", "ret16", "ret96",                    # past returns in ATR, signed
    "body", "clv",                               # last bar body/range signed, close location value signed
    "rsi", "er16", "er96", "tvr",                # RSI14-50 signed, efficiency ratios, tick-volume ratio
]


@njit(cache=True)
def rsi_nb(c, n):
    out = np.full(len(c), 50.0)
    up = 0.0
    dn = 0.0
    for i in range(1, len(c)):
        ch = c[i] - c[i - 1]
        u = ch if ch > 0 else 0.0
        d = -ch if ch < 0 else 0.0
        if i <= n:
            up += u / n
            dn += d / n
        else:
            up = (up * (n - 1) + u) / n
            dn = (dn * (n - 1) + d) / n
        if i >= n:
            out[i] = 100.0 if dn == 0 else 100.0 - 100.0 / (1.0 + up / dn)
    return out


@njit(cache=True)
def stack_age_nb(stack_bull, stack_bear):
    n = len(stack_bull)
    age = np.zeros(n)
    fresh_b = np.zeros(n)  # bars since last bear stack (for bull) and vice versa
    fresh_s = np.zeros(n)
    a = 0
    lb = -100000
    ls = -100000
    for i in range(n):
        if stack_bull[i]:
            a = a + 1 if (i > 0 and stack_bull[i - 1]) else 1
            lb = i
        elif stack_bear[i]:
            a = a + 1 if (i > 0 and stack_bear[i - 1]) else 1
            ls = i
        else:
            a = 0
        age[i] = a
        fresh_b[i] = i - ls
        fresh_s[i] = i - lb
    return age, fresh_b, fresh_s


def er_np(c, n):
    ch = np.abs(c[n:] - c[:-n])
    vol = pd.Series(np.abs(np.diff(c))).rolling(n).sum().values[n - 1:]
    out = np.full(len(c), np.nan)
    out[n:] = ch / np.maximum(vol, 1e-12)
    return out


def build(b: dict, h1: dict, m1a: dict, tick_vol=None):
    """Per-bar unsigned feature matrix pieces; sign is applied per candidate later via signed()."""
    n = b["n"]
    c, h, l, o = b["c"], b["h"], b["l"], b["o"]
    a = np.maximum(b["atr"], 1e-9)
    Em = b["E"]
    F = {}
    for k in range(6):
        F[f"g{k}"] = (Em[k] - Em[k + 1]) / a
    for k in (0, 2, 4, 6):
        F[f"d{k}"] = (c - Em[k]) / a
    for k in (0, 3, 6):
        s = np.full(n, np.nan)
        s[4:] = (Em[k][4:] - Em[k][:-4]) / a[4:]
        F[f"s{k}"] = s
    age, fb, fs = stack_age_nb(b["stack_bull"], b["stack_bear"])
    F["_age"] = age
    F["_fresh_b"] = fb
    F["_fresh_s"] = fs
    atr_long = pd.Series(a).rolling(960, min_periods=200).mean().values
    F["volreg"] = a / atr_long
    F["atr_bp"] = a / c * 1e4
    F["cost_atr"] = b["spr"] / a
    hr = ((b["t"] + b["minutes"] * 60) % 86400) / 3600.0  # decision time = bar close (UTC)
    F["hsin"] = np.sin(2 * np.pi * hr / 24)
    F["hcos"] = np.cos(2 * np.pi * hr / 24)
    # H1 ribbon as of the last closed H1 bar at the M15 close
    close_t = b["t"] + b["minutes"] * 60
    hidx = np.searchsorted(h1["t"] + 3600, close_t, side="right") - 1
    hidx = np.maximum(hidx, 0)
    order_h1 = np.sign(-np.diff(h1["E"], axis=0)).sum(axis=0)
    ah1 = np.maximum(h1["atr"], 1e-9)
    F["h1_order"] = order_h1[hidx]
    F["h1_d0"] = (c - h1["E"][0][hidx]) / ah1[hidx]
    F["h1_d6"] = (c - h1["E"][6][hidx]) / ah1[hidx]
    hi96 = pd.Series(h).rolling(96, min_periods=10).max().values
    lo96 = pd.Series(l).rolling(96, min_periods=10).min().values
    F["pos96"] = (c - lo96) / np.maximum(hi96 - lo96, 1e-9) - 0.5
    F["hi96"] = (hi96 - c) / a
    F["lo96"] = (c - lo96) / a
    for k in (4, 16, 96):
        r = np.full(n, np.nan)
        r[k:] = (c[k:] - c[:-k]) / a[k:]
        F[f"ret{k}"] = r
    rng = np.maximum(h - l, 1e-9)
    F["body"] = (c - o) / rng
    F["clv"] = ((c - l) - (h - c)) / rng
    F["rsi"] = rsi_nb(c, 14) - 50.0
    F["er16"] = er_np(c, 16)
    F["er96"] = er_np(c, 96)
    if tick_vol is not None:
        tv = tick_vol
        F["tvr"] = tv / np.maximum(pd.Series(tv).rolling(96, min_periods=10).mean().values, 1e-9)
    else:
        F["tvr"] = np.ones(n)
    return F


SIGNED = {"g0", "g1", "g2", "g3", "g4", "g5", "d0", "d2", "d4", "d6", "s0", "s3", "s6", "h1_order", "h1_d0", "h1_d6",
          "pos96", "ret4", "ret16", "ret96", "body", "clv", "rsi"}


def candidate_matrix(F: dict, idx: np.ndarray, dirs: np.ndarray) -> np.ndarray:
    X = np.empty((len(idx), len(FEATURES)), np.float32)
    d = dirs.astype(np.float64)
    for j, f in enumerate(FEATURES):
        if f == "age":
            v = np.log1p(F["_age"][idx])
        elif f == "fresh":
            v = np.log1p(np.where(d > 0, F["_fresh_b"][idx], F["_fresh_s"][idx]))
        elif f in ("hi96", "lo96"):
            # distance to the extreme in the trade direction / against it
            v = np.where(d > 0, F["hi96"][idx], F["lo96"][idx]) if f == "hi96" else np.where(d > 0, F["lo96"][idx], F["hi96"][idx])
        else:
            v = F[f][idx]
            if f in SIGNED:
                v = v * d
        X[:, j] = v
    return X


def tick_volume_bars(m1: pd.DataFrame, b: dict):
    v = m1["vol"].values.astype(np.float64)
    return np.add.reduceat(v, b["m1s"])
