"""Study 7: structural intraday effects anchored to the gold trading day (NY 17:00 close / 18:00 reopen).

  * hour-of-trading-day drift (NY local hours, DST-proof) net of a realistic round-trip cost;
  * intraday momentum: return of the first part of the trading day vs the rest of the day;
  * day-of-week drift.
Prices: bid M1; long entry at ask (bid+spread), exit at bid.  Values in $/oz and in M15-ATR units per year.
"""
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
t = pd.to_datetime(m1a["t"], unit="s").tz_localize("UTC").tz_convert("America/New_York")
df = pd.DataFrame({"o": m1a["o"], "c": m1a["c"], "spr": m1a["spr"], "tday": m1a["tday"]}, index=t)
df["nyh"] = t.hour
df["year"] = t.year
# M15 ATR mapped to minutes
atr_m1 = np.repeat(b["atr"], b["m1e"] - b["m1s"])
df["atr"] = atr_m1
pd.set_option("display.width", 260)
pd.set_option("display.max_columns", 30)
# hourly open->close (next hour open) returns by NY hour
g = df.groupby(["tday", "nyh"]).agg(o=("o", "first"), c=("c", "last"), spr=("spr", "first"), atr=("atr", "first"),
                                     year=("year", "first"))
g["ret_atr"] = (g["c"] - g["o"] - g["spr"] - 0.13) / g["atr"]   # long round trip net (spread + comm + slip)
g["gross_atr"] = (g["c"] - g["o"]) / g["atr"]
tab = g.reset_index().groupby(["year", "nyh"])["gross_atr"].mean().unstack()
print("=== gross hourly drift (M15-ATR) by NY hour ===")
print(tab.round(2).to_string())
print("pos years:", (tab > 0).sum().to_dict())
net = g.reset_index().groupby(["year", "nyh"])["ret_atr"].mean().unstack()
print("=== NET long hourly (ATR) by NY hour ===")
print(net.round(2).to_string())
# intraday momentum: first segment 18:00-03:00 NY (Asia) and 03:00-09:00 (London) vs rest 09:00-16:00
day = df.groupby("tday").agg(year=("year", "last"))
def seg(h0, h1):
    m = (df.nyh >= h0) & (df.nyh < h1) if h0 < h1 else ((df.nyh >= h0) | (df.nyh < h1))
    s = df[m].groupby("tday").agg(o=("o", "first"), c=("c", "last"), atr=("atr", "first"))
    return (s["c"] - s["o"]) / s["atr"]
day["asia"] = seg(18, 3)
day["london"] = seg(3, 9)
day["ny"] = seg(9, 16)
day["last"] = seg(15, 17)
day["first_half"] = seg(18, 9)
day = day.dropna()
rows = {}
for y, gg in day.groupby("year"):
    rows[y] = {"asia->london": gg.asia.corr(gg.london, method="spearman"),
               "asia+lon->ny": gg.first_half.corr(gg.ny, method="spearman"),
               "london->ny": gg.london.corr(gg.ny, method="spearman"),
               "day->last2h": (gg.first_half + gg.ny - gg["last"]).corr(gg["last"], method="spearman")}
print("=== intraday momentum IC per year ===")
r = pd.DataFrame(rows).T.round(3)
r.loc["pos"] = (r > 0).sum()
print(r.to_string())
