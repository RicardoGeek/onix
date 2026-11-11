"""16Runes Study 6: Deep Breakdown of the 2,556 H4+D1 Gated Rune Setups + Time-Ordered Portfolio & Meta-Labeler.
"""
import os
import sys
import time
import numpy as np
import pandas as pd

sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
from runes_study3 import RUNE_NAMES
from runes_study4 import build_dataset, FEATS, STREAMS

if __name__ == "__main__":
    m1a, tfs, df = build_dataset("duka")
    ins = df.year <= 2023
    oos = df.year >= 2024

    print("=== BY STREAM ===")
    for si, (nm, _, _) in enumerate(STREAMS):
        g = df[df.stream == si]
        gi = g[g.year <= 2023]
        go = g[g.year >= 2024]
        print(f"  S{si} ({nm:3s}): n={len(g):4d}  all={g.r.mean():+.3f}R  2017-23={gi.r.mean():+.3f}R ({len(gi):4d}, sum={gi.r.sum():+6.1f}R)  "
              f"2024-26={go.r.mean():+.3f}R ({len(go):4d}, sum={go.r.sum():+6.1f}R)")

    print("\n=== BY RUNE (ALL 5 STREAMS) ===")
    for rk in range(16):
        g = df[df.rune == rk]
        if len(g) == 0:
            continue
        gi = g[g.year <= 2023]
        go = g[g.year >= 2024]
        print(f"  [{rk:2d}] {RUNE_NAMES[rk]:14s}: n={len(g):4d}  all={g.r.mean():+.3f}R  "
              f"2017-23={gi.r.mean() if len(gi) else 0:+.3f}R ({len(gi):3d})  "
              f"2024-26={go.r.mean() if len(go) else 0:+.3f}R ({len(go):3d})")

    print("\n=== BY UTC SESSION (f15_liq_sess) ===")
    for v, lbl in [(1.0, "London/NY 06-16 UTC"), (0.0, "Asia 23-05 UTC"), (-1.0, "Evening 17-22 UTC")]:
        g = df[df.f15_liq_sess == v]
        gi = g[g.year <= 2023]
        go = g[g.year >= 2024]
        print(f"  {lbl:22s}: n={len(g):4d}  all={g.r.mean():+.3f}R  "
              f"2017-23={gi.r.mean():+.3f}R ({len(gi):4d})  2024-26={go.r.mean():+.3f}R ({len(go):4d})")

    print("\n=== BY VOLATILITY REGIME (f11_vol_reg) ===")
    for q0, q1 in [(0.0, 0.85), (0.85, 1.15), (1.15, 10.0)]:
        g = df[(df.f11_vol_reg >= q0) & (df.f11_vol_reg < q1)]
        gi = g[g.year <= 2023]
        go = g[g.year >= 2024]
        print(f"  vol_reg [{q0:.2f}, {q1:.2f}): n={len(g):4d}  all={g.r.mean():+.3f}R  "
              f"2017-23={gi.r.mean():+.3f}R ({len(gi):4d})  2024-26={go.r.mean():+.3f}R ({len(go):4d})")

    print("\n=== BY COST/ATR (f12_cost_atr) ===")
    for q0, q1 in [(0.0, 0.06), (0.06, 0.10), (0.10, 1.0)]:
        g = df[(df.f12_cost_atr >= q0) & (df.f12_cost_atr < q1)]
        gi = g[g.year <= 2023]
        go = g[g.year >= 2024]
        print(f"  cost_atr [{q0:.2f}, {q1:.2f}): n={len(g):4d}  all={g.r.mean():+.3f}R  "
              f"2017-23={gi.r.mean():+.3f}R ({len(gi):4d})  2024-26={go.r.mean():+.3f}R ({len(go):4d})")

    print("\n=== BY PATTERN HEIGHT / ATR (f7_pat_h_atr) ===")
    for q0, q1 in [(0.0, 1.5), (1.5, 3.0), (3.0, 20.0)]:
        g = df[(df.f7_pat_h_atr >= q0) & (df.f7_pat_h_atr < q1)]
        gi = g[g.year <= 2023]
        go = g[g.year >= 2024]
        print(f"  pat_h_atr [{q0:.1f}, {q1:.1f}): n={len(g):4d}  all={g.r.mean():+.3f}R  "
              f"2017-23={gi.r.mean():+.3f}R ({len(gi):4d})  2024-26={go.r.mean():+.3f}R ({len(go):4d})")
