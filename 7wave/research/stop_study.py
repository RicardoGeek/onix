"""7Wave stop study: is it the stop or the entry?

Every 7Wave star and arrow (2018-2026, H1 and M15) and the same number of random entries x N_RANDOM on the same data
(random bar, random direction: the coin-flip control) are replayed with different stops. Every stop keeps a +3R
target in its own R and a time exit after 10 days (H1) / 4 days (M15). Costs as in wave_scorecard.py.
"Stopped, then +3R" counts trades that hit the stop and afterwards reached the original +3R target anyway: the
"killed right before the moonshot" case.
The user's blind-replay picks (7wave/trainer) are replayed with the same stops.

    C:\\Users\\faker\\mlv\\Scripts\\python.exe 7wave\\research\\stop_study.py
"""
import os
import sys

import numpy as np
import pandas as pd
from numba import njit

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
sys.path.insert(0, HERE)
import wave_rules as wr  # noqa: E402
import wave_scorecard as sc  # noqa: E402

PICKS = os.path.join(sc.OUT, "7wave_trainer_results_2026-11-06.csv")
VARIANTS = [("1.5 ATR (trainer)", "atr", 1.5), ("2.5 ATR", "atr", 2.5), ("4 ATR", "atr", 4.0),
            ("beyond EMA 140 + 0.5 ATR", "ema140", 0.5), ("beyond the 20-bar swing + 0.25 ATR", "swing", 0.25)]
MIN_STOP_ATR = 1.0
N_RANDOM = 4
SEED = 11


@njit(cache=False)
def reached_after(jx, j1, d, level, h, l, spr):
    """True if price reaches `level` in the trade's favour after M1 bar jx and before j1."""
    for j in range(jx + 1, j1):
        if d > 0:
            if h[j] >= level:
                return True
        else:
            if l[j] + spr[j] <= level:
                return True
    return False


def stop_distance(kind, k, i, d, entry, b, ema, a14):
    a = a14[i]
    if kind == "atr":
        dist = k * a
    elif kind == "ema140":
        dist = (entry - (ema[i, 6] - d * k * a)) * d
    else:  # swing: the extreme of the last 20 closed bars
        ext = b["l"][i - 19:i + 1].min() if d > 0 else b["h"][i - 19:i + 1].max()
        dist = (entry - (ext - d * k * a)) * d
    return max(dist, MIN_STOP_ATR * a)


def replay(m, b, ema, a14, entries, tf):
    """entries: list of (bar index, direction). Returns a DataFrame with one row per entry and variant."""
    n = len(b["c"])
    rows = []
    for i, d in entries:
        j0 = b["m1e"][i]
        j1 = b["m1e"][min(i + sc.HOLD[tf], n - 1)]
        if j0 >= len(m["o"]) or j1 <= j0:
            continue
        entry = m["o"][j0] + m["spr"][j0] + sc.SLIP_IN if d > 0 else m["o"][j0] - sc.SLIP_IN
        for name, kind, k in VARIANTS:
            rdist = stop_distance(kind, k, i, d, entry, b, ema, a14)
            r, mfe, reason, jx = sc.simulate(j0, j1, d, rdist, m["o"], m["h"], m["l"], m["c"], m["spr"], m["swapcnt"])
            moon = reason == -1 and reached_after(jx, j1, d, entry + d * 3 * rdist, m["h"], m["l"], m["spr"])
            rows.append(dict(bar=i, dir=d, variant=name, stop_atr=rdist / a14[i], R=r, win=int(reason == 1),
                             stopped=int(reason == -1), moon=int(moon)))
    return pd.DataFrame(rows)


def summary(df):
    g = df.groupby("variant", sort=False)
    return pd.DataFrame(dict(n=g.size(), stop_atr=g.stop_atr.median(), win=g.win.mean(), R=g.R.mean(),
                             moon=g.moon.sum() / g.stopped.sum()))


def main():
    m = sc.load_m1("duka")
    rng = np.random.default_rng(SEED)
    picks = pd.read_csv(PICKS)
    md = ["# 7Wave stop study (raw output)", ""]
    pick_rows = []
    for tf, (minutes, _) in sc.TFS.items():
        b = sc.make_bars(m, minutes)
        n = len(b["c"])
        ema = wr.emas(b["c"])
        a14 = sc.atr(b, 14)
        sig, _ = wr.signals_for(b["o"], b["c"], ema)
        year = pd.to_datetime(b["t"], unit="s").year.to_numpy()
        ok = lambda i: i >= 120 and i + sc.HOLD[tf] < n - 1 and year[i] >= sc.FIRST_YEAR  # noqa: E731
        signals = [(i, d) for i, _, d, _ in sig if ok(i)]
        pool = np.array([i for i in range(n) if ok(i)])
        randoms = [(int(i), int(d)) for i, d in zip(rng.choice(pool, N_RANDOM * len(signals)),
                                                     rng.choice([-1, 1], N_RANDOM * len(signals)))]
        s7, sr = summary(replay(m, b, ema, a14, signals, tf)), summary(replay(m, b, ema, a14, randoms, tf))
        md += [f"## {tf}: all {len(signals)} 7Wave signals vs {len(randoms)} random entries, 2018-2026", "",
               "| Stop | Median stop (ATR) | 7Wave: wins (+3R) | 7Wave: avg R | 7Wave: stopped, then +3R anyway "
               "| Random: wins | Random: avg R | Random: stopped, then +3R anyway |", "|---|---|---|---|---|---|---|---|"]
        for v in s7.index:
            a, r = s7.loc[v], sr.loc[v]
            md.append(f"| {v} | {a.stop_atr:.1f} | {a.win:.0%} | {a.R:+.3f} | {a.moon:.0%} | {r.win:.0%} | {r.R:+.3f} "
                      f"| {r.moon:.0%} |")
        md.append("")
        # the user's picks on this timeframe
        idx = {t: k for k, t in enumerate(pd.to_datetime(b["t"], unit="s").strftime("%Y-%m-%d %H:%M"))}
        p = picks[picks.tf == tf]
        ent = [(idx[t], int(d)) for t, d in zip(p.date, p.dir)]
        rp = replay(m, b, ema, a14, ent, tf)
        rp["decision"] = np.repeat(p.decision.to_numpy(), len(VARIANTS))
        pick_rows.append(rp)
    rp = pd.concat(pick_rows)
    md += ["## The user's 400 blind-replay picks, both timeframes", "",
           "| Stop | All 400: avg R | Takes: avg R | Strong takes: avg R | Skips: avg R | Takes: wins | Skips: wins |",
           "|---|---|---|---|---|---|---|"]
    for v, g in rp.groupby("variant", sort=False):
        t, st, sk = g[g.decision >= 1], g[g.decision == 2], g[g.decision == 0]
        md.append(f"| {v} | {g.R.mean():+.3f} | {t.R.mean():+.3f} | {st.R.mean():+.3f} | {sk.R.mean():+.3f} "
                  f"| {t.win.mean():.0%} | {sk.win.mean():.0%} |")
    path = os.path.join(sc.OUT, "stop_study_raw.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(md))
    print("\n".join(md))


if __name__ == "__main__":
    main()
