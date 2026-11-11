"""Study 3: where is the persistent edge?  Year-by-year information coefficients of ribbon / time / volatility
features against forward M15 returns (ATR units).  A feature is only interesting if its sign holds in most years."""
import sys
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
b = E.add_ribbon(E.make_bars(m1a, 15))
c = b["c"]; a = b["atr"]; Em = b["E"]
n = b["n"]
df = pd.DataFrame({"t": b["t"], "c": c, "atr": a})
df["dt"] = pd.to_datetime(df.t, unit="s")
df["year"] = df.dt.dt.year
df["hour"] = df.dt.dt.hour
for h in (4, 16, 48, 96):
    f = np.full(n, np.nan)
    f[:-h] = (c[h:] - c[:-h]) / a[:-h]
    # drop if the window crosses a weekend gap (> 3h with no bar)
    gap = np.full(n, False)
    tt = b["t"]
    gap[:-h] = (tt[h:] - tt[:-h]) > (h * 900 + 3 * 3600)
    f[gap] = np.nan
    df[f"fwd{h}"] = f
order = np.sign(np.diff(Em, axis=0) * -1).sum(axis=0)  # +6 fully bull, -6 fully bear
df["order"] = order
for k, p in enumerate(b["periods"]):
    df[f"dist{p}"] = (c - Em[k]) / a
df["width"] = (Em[0] - Em[6]) / a
df["slope20"] = np.r_[np.full(4, np.nan), (Em[0][4:] - Em[0][:-4])] / a
df["slope200"] = np.r_[np.full(16, np.nan), (Em[6][16:] - Em[6][:-16])] / a
df["ret4"] = np.r_[np.full(4, np.nan), (c[4:] - c[:-4])] / a
df["ret16"] = np.r_[np.full(16, np.nan), (c[16:] - c[:-16])] / a
df["ret96"] = np.r_[np.full(96, np.nan), (c[96:] - c[:-96])] / a
atr_long = pd.Series(a).rolling(960).mean().values
df["volreg"] = a / atr_long
hi96 = pd.Series(b["h"]).rolling(96).max().values
lo96 = pd.Series(b["l"]).rolling(96).min().values
df["pos96"] = (c - lo96) / np.maximum(hi96 - lo96, 1e-9)
df = df.iloc[2000:].copy()
feats = ["order", "dist20", "dist60", "dist200", "width", "slope20", "slope200", "ret4", "ret16", "ret96", "volreg", "pos96"]
pd.set_option("display.width", 250)
for h in ("fwd4", "fwd16", "fwd96"):
    rows = {}
    for y, g in df.groupby("year"):
        g = g.dropna(subset=[h])
        rows[y] = {f: g[f].corr(g[h], method="spearman") for f in feats}
    t = pd.DataFrame(rows).T.round(3)
    t.loc["pos_yrs"] = (t > 0).sum()
    print(f"\n=== IC vs {h} ===")
    print(t)
# hour-of-day drift (mean fwd4 by UTC hour, per year sign consistency)
g = df.dropna(subset=["fwd4"]).groupby(["year", "hour"])["fwd4"].mean().unstack()
print("\n=== mean fwd4 (ATR) by UTC hour, per year ===")
print(g.round(3))
print("pos years per hour:", (g > 0).sum().to_dict())
