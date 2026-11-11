"""Study 1: which ribbon event has directional edge?  Prints best fixed TP/SL pairs (in ATR) per event family."""
import sys
import time
import numpy as np
import pandas as pd
from numba import njit
from sw_data import load
import sw_engine as E
import sw_events as V

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
tf = int(sys.argv[2]) if len(sys.argv) > 2 else 15
t0 = time.time()
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
b = E.add_ribbon(E.make_bars(m1a, tf))
h1 = E.add_ribbon(E.make_bars(m1a, 60))
# last CLOSED H1 bar at each tf-bar close: H1 bar k closes at t_h1[k] + 3600 <= t_b + tf*60
close_t = b["t"] + tf * 60
hidx = np.searchsorted(h1["t"] + 3600, close_t, side="right") - 1
h1_bull = np.where(hidx >= 0, h1["stack_bull"][np.maximum(hidx, 0)], False)
h1_bear = np.where(hidx >= 0, h1["stack_bear"][np.maximum(hidx, 0)], False)
E7 = b["E"]
atr = b["atr"]
width = (E7[0] - E7[6]) / atr
n = b["n"]
print(f"{src} tf={tf}: {n:,} bars, {time.time() - t0:.1f}s")


@njit(cache=True)
def pullback_events(stack_bull, stack_bear, bull, bear, lo, hi, cl, e0, e1, e2, flipbar_window, regap):
    """First pullback into EMA-fast/EMA-2 zone after a fresh full alignment, entry at the close of the first bar that
    closes back beyond EMA-fast while the 7-EMA stack is intact."""
    n = len(cl)
    sig = np.zeros(n, np.int64)
    last_bull = -10 ** 9
    last_bear = -10 ** 9
    wave_dir = 0
    wave_start = -1
    touched = False
    used = False
    for i in range(1, n):
        # fresh flip detection
        if bull[i] and not bull[i - 1] and (last_bear > last_bull or i - last_bull >= regap):
            wave_dir = 1; wave_start = i; touched = False; used = False
        if bear[i] and not bear[i - 1] and (last_bull > last_bear or i - last_bear >= regap):
            wave_dir = -1; wave_start = i; touched = False; used = False
        if bull[i]:
            last_bull = i
        if bear[i]:
            last_bear = i
        if wave_dir == 0 or used:
            continue
        if i - wave_start > flipbar_window:
            wave_dir = 0
            continue
        if wave_dir == 1:
            if not stack_bull[i]:
                wave_dir = 0
                continue
            if lo[i] <= e1[i]:
                touched = True
            if touched and i > wave_start and cl[i] > e0[i] and lo[i - 1] <= e1[i - 1] + 0.0 or (touched and cl[i] > e0[i] and lo[i] <= e1[i]):
                if i > wave_start:
                    sig[i] = 1
                    used = True
        else:
            if not stack_bear[i]:
                wave_dir = 0
                continue
            if hi[i] >= e1[i]:
                touched = True
            if touched and i > wave_start and cl[i] < e0[i] and hi[i - 1] >= e1[i - 1] or (touched and cl[i] < e0[i] and hi[i] >= e1[i]):
                if i > wave_start:
                    sig[i] = -1
                    used = True
    return sig


events = {}
fresh = E.fresh_signals_nb(b["bull"], b["bear"], 32)
events["E1 fresh flip"] = fresh
f2 = fresh.copy(); f2[(fresh == 1) & ~h1_bull] = 0; f2[(fresh == -1) & ~h1_bear] = 0
events["E4 fresh flip + H1 stack"] = f2
realign = np.zeros(n, np.int64)
realign[1:][b["bull"][1:] & ~b["bull"][:-1]] = 1
realign[1:][b["bear"][1:] & ~b["bear"][:-1]] = -1
r3 = realign.copy(); r3[(realign == 1) & ~h1_bull] = 0; r3[(realign == -1) & ~h1_bear] = 0
events["E3 any realign + H1 stack"] = r3
events["E3b any realign"] = realign
pb = pullback_events(b["stack_bull"], b["stack_bear"], b["bull"], b["bear"], b["l"], b["h"], b["c"],
                     E7[0], E7[1], E7[2], 48, 32)
events["E2 first pullback (EMA40 touch)"] = pb
pb2 = pb.copy(); pb2[(pb == 1) & ~h1_bull] = 0; pb2[(pb == -1) & ~h1_bear] = 0
events["E2b first pullback + H1 stack"] = pb2
# compression breakout: ribbon width small over the last 16 bars before the alignment
wmax16 = pd.Series(np.abs(width)).rolling(16).max().shift(1).values
for wthr in (1.0, 2.0):
    c5 = realign.copy(); c5[~(wmax16 < wthr)] = 0
    events[f"E5 squeeze<{wthr} breakout"] = c5
# counter: fade the fresh flip
events["E1 FADE"] = -fresh

cost_usd = 0.30 + 0.08 + 0.05 + 0.10
for name, sig in events.items():
    idx = np.flatnonzero(sig != 0)
    idx = idx[(idx > 1500) & (idx < n - 1)]
    if len(idx) < 50:
        print(name, "too few", len(idx)); continue
    d = sig[idx]
    m1j = b["m1e"][idx]
    mfe, cens = V.excursions_nb(m1j, d, atr[idx], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], V.YS, 4320)
    cost_atr = cost_usd / atr[idx]
    s, rows = V.table(mfe, cost_atr, name)
    days = (b["t"][idx[-1]] - b["t"][idx[0]]) / 86400 * 5 / 7
    print(f"{s}   [{len(idx) / days:.2f}/day]")
print(f"{time.time() - t0:.1f}s")
