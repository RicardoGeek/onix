"""Study 8: multi-day time-series momentum on gold (H1 closes, causal) vs forward 1/3/5-day returns, per year.
If a slow trend measure is consistently predictive it becomes the direction filter for intraday ribbon entries."""
import sys
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
h1 = E.add_ribbon(E.make_bars(m1a, 60), periods=(80, 160, 240, 320, 400, 600, 800))  # ~ M15 ribbon x4 on H1
c = h1["c"]
n = len(c)
a = h1["atr"]
df = pd.DataFrame({"t": h1["t"]})
df["year"] = pd.to_datetime(df.t, unit="s").dt.year
logc = np.log(c)
for d in (1, 5, 10, 20, 60):
    k = 23 * d
    r = np.full(n, np.nan); r[k:] = logc[k:] - logc[:-k]
    df[f"mom{d}d"] = r
for d in (1, 3, 5):
    k = 23 * d
    f = np.full(n, np.nan); f[:-k] = logc[k:] - logc[:-k]
    df[f"fwd{d}d"] = f
df["h1ribbon"] = np.sign(-np.diff(h1["E"], axis=0)).sum(axis=0)
ema = lambda x, p: pd.Series(x).ewm(span=p, adjust=False).mean().values
df["dist_ema480"] = (c - ema(c, 480)) / a
df = df.iloc[1500:].dropna()
# sample once per day to reduce overlap (at 13:00 UTC)
df = df[pd.to_datetime(df.t, unit="s").dt.hour == 13]
feats = ["mom1d", "mom5d", "mom10d", "mom20d", "mom60d", "h1ribbon", "dist_ema480"]
pd.set_option("display.width", 250)
for fw in ("fwd1d", "fwd3d", "fwd5d"):
    rows = {}
    for y, g in df.groupby("year"):
        rows[y] = {f: g[f].corr(g[fw], method="spearman") for f in feats}
    t = pd.DataFrame(rows).T.round(3)
    t.loc["pos"] = (t > 0).sum()
    t.loc["mean"] = t.iloc[:-1].mean()
    print(f"\n=== IC vs {fw} (daily samples) ===")
    print(t.to_string())
# simple sign strategy: hold direction of mom20d for next day -> yearly mean daily return (bp)
for f in ("mom5d", "mom20d", "mom60d", "h1ribbon"):
    s = np.sign(df[f]) * df["fwd1d"] * 1e4
    print(f, "follow-sign mean fwd1d bp/day by year:", s.groupby(df.year).mean().round(1).to_dict())
print("buy&hold mean fwd1d bp/day:", (df["fwd1d"] * 1e4).groupby(df.year).mean().round(1).to_dict())
