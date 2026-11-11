"""Study 5: is ribbon momentum regime-dependent in a way a CAUSAL regime measure can detect?

Regime candidates (all from closed H1 bars, broker-clock-free):
  er20d  : efficiency ratio of H1 closes over 480 bars (~20 trading days)
  er5d   : efficiency ratio over 120 H1 bars (~5 days)
  trend20: |close - EMA(480 H1)| / ATR(H1) * sign agreement
IC of the M15 ribbon order score vs forward returns, split by regime tercile (terciles fixed from 2017-2019 only).
"""
import sys
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E
import sw_features as SF

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
b = E.add_ribbon(E.make_bars(m1a, 15))
h1 = E.add_ribbon(E.make_bars(m1a, 60))
n = b["n"]
c, a = b["c"], b["atr"]
close_t = b["t"] + 900
hidx = np.maximum(np.searchsorted(h1["t"] + 3600, close_t, side="right") - 1, 0)
reg = {}
for name, L in (("er20d", 480), ("er5d", 120), ("er2d", 48)):
    reg[name] = SF.er_np(h1["c"], L)[hidx]
order = np.sign(-np.diff(b["E"], axis=0)).sum(axis=0)
df = pd.DataFrame({"t": b["t"], "order": order, **reg})
df["year"] = pd.to_datetime(df.t, unit="s").dt.year
for hz in (16, 48, 96, 192):
    f = np.full(n, np.nan)
    f[:-hz] = (c[hz:] - c[:-hz]) / a[:-hz]
    df[f"fwd{hz}"] = f
df = df.iloc[3000:].dropna()
for rname in reg:
    q = df.loc[df.year <= 2019, rname].quantile([1 / 3, 2 / 3]).values
    df["tert"] = np.digitize(df[rname], q)
    print(f"\n=== regime {rname} terciles (fixed on 2017-19: {q.round(3)}) : IC(order, fwd) per year ===")
    for hz in (16, 96, 192):
        rows = {}
        for (y, tt), g in df.groupby(["year", "tert"]):
            rows.setdefault(y, {})[f"T{tt}"] = g["order"].corr(g[f"fwd{hz}"], method="spearman")
        t = pd.DataFrame(rows).T.round(3)
        t.loc["pos"] = (t > 0).sum()
        print(f"-- fwd{hz}\n" + t.T.to_string())
