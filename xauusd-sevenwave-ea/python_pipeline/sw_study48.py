"""Study 48: NEWS SENTIMENT.  GDELT DOC 2.0 daily timelines for worldwide "gold price" coverage, 2017-2026:
average tone (positive = upbeat wording) and raw article volume (attention).  Day d is complete at 00:15 UTC on d+1;
we use it from d+1 01:00 UTC (no look-ahead).
(a) as filters on the v1.30 setups (study 46 outcomes), pre-registered good side, thresholds from 2017-2021 only;
(b) as standalone weekly rules on gold (Monday to Monday, 0.04% cost).
"""
import glob
import numpy as np
import pandas as pd

RAW = r"C:\Users\faker\Documents\goldie_research\sevenwave\data\outside\gdelt"


def load(mode):
    fr = []
    for f in sorted(glob.glob(rf"{RAW}\{mode}_*.csv")):
        try:
            x = pd.read_csv(f)
        except Exception:
            continue
        if "Date" in x.columns:
            fr.append(x[["Date", "Value"]])
    x = pd.concat(fr)
    x["d"] = pd.to_datetime(x.Date)
    return x.drop_duplicates("d").set_index("d").Value.astype(float).sort_index()


tone, vol = load("timelinetone"), load("timelinevolraw")
idx = pd.date_range(min(tone.index.min(), vol.index.min()), max(tone.index.max(), vol.index.max()), freq="D")
tone = tone.reindex(idx); vol = vol.reindex(idx)
print(f"GDELT tone days {tone.notna().sum()}, volume days {vol.notna().sum()}, {idx[0].date()} .. {idx[-1].date()}")
day = idx.values.astype("datetime64[s]").astype(np.int64)
avail = day + 86400 + 3600
t7 = tone.rolling(7, min_periods=4).mean(); t30 = tone.rolling(30, min_periods=15).mean(); s30 = tone.rolling(90, min_periods=30).std()
v7 = vol.rolling(7, min_periods=4).mean(); v30 = vol.rolling(60, min_periods=20).mean()
SER = {"tone_z": ((tone - t30) / s30).values, "tone_7v30": ((t7 - t30) / s30).values, "att": (v7 / v30).values}

Z = np.load(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\study46_feats.npz", allow_pickle=True)
r, t, d = Z["r"], Z["t"].astype(np.int64), Z["d"]
yr = pd.to_datetime(t, unit="s").year.values
ok = np.isfinite(r)
k = np.searchsorted(avail, t, side="right") - 1
val = lambda s: np.where(k >= 0, s[np.maximum(k, 0)], np.nan)
F = {
    "News tone yesterday z (x trade dir)": (d * val(SER["tone_z"]), "high"),
    "News tone 7d vs 30d (x trade dir)": (d * val(SER["tone_7v30"]), "high"),
    "News attention 7d/60d volume": (val(SER["att"]), "high"),
}
print(f"\n(a) {ok.sum()} setups, base avgR {r[ok].mean():+.3f}")
print("| Feature (good side) | n | bad tercile R | mid R | good tercile R | good-bad 2017-21 | good-bad 2022-26 | years good>bad |")
print("|---|---|---|---|---|---|---|---|")
for name, (x, good) in F.items():
    mk = ok & np.isfinite(x)
    tr = mk & (yr <= 2021)
    q1, q2 = np.nanquantile(x[tr], [1 / 3, 2 / 3])
    lo, hi = mk & (x <= q1), mk & (x > q2)
    mid = mk & ~lo & ~hi
    gd, bd = (hi, lo) if good == "high" else (lo, hi)
    e1 = r[gd & (yr <= 2021)].mean() - r[bd & (yr <= 2021)].mean()
    e2 = r[gd & (yr >= 2022)].mean() - r[bd & (yr >= 2022)].mean()
    yrs = sorted(set(yr[mk]))
    wins = sum(1 for y in yrs if (gd & (yr == y)).sum() >= 10 and (bd & (yr == y)).sum() >= 10
               and r[gd & (yr == y)].mean() > r[bd & (yr == y)].mean())
    print(f"| {name} ({good}) | {mk.sum()} | {r[bd].mean():+.3f} | {r[mid].mean():+.3f} | {r[gd].mean():+.3f} | {e1:+.3f} | {e2:+.3f} | {wins}/{len(yrs)} |")

# ---------------------------------------------------------------- (b) standalone weekly rules
import sys
_argv = list(sys.argv); sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
m1 = V.m1a
mt, mo = m1["t"].astype(np.int64), m1["o"]
mon = pd.date_range("2017-03-06", "2026-09-21", freq="W-MON")
ts = mon.values.astype("datetime64[s]").astype(np.int64)
j0 = np.searchsorted(mt, ts)
p0 = mo[np.minimum(j0, len(mt) - 1)]
wret = (p0[1:] / p0[:-1] - 1) * 100
ts0 = ts[:-1]
wy = pd.to_datetime(ts0, unit="s").year.values
kw = np.searchsorted(avail, ts0, side="right") - 1
wv = lambda s: np.where(kw >= 0, s[np.maximum(kw, 0)], np.nan)
RULES = {
    "tone 7d above 30d -> long, below -> short": np.sign(wv(SER["tone_7v30"])),
    "tone 7d z > +1 long / < -1 short": np.where(wv(SER["tone_7v30"]) > 1, 1, np.where(wv(SER["tone_7v30"]) < -1, -1, 0)),
    "contrarian: tone z < -1 long / > +1 short": np.where(wv(SER["tone_7v30"]) < -1, 1, np.where(wv(SER["tone_7v30"]) > 1, -1, 0)),
    "attention spike (7d/60d > 1.3) long": np.where(wv(SER["att"]) > 1.3, 1, 0),
    "benchmark: always long": np.ones(len(ts0)),
}
print("\n(b) standalone weekly rules (Monday to Monday, 0.04% cost per trade)")
print("| Rule | weeks in market | avg % per trade | hit rate | t-stat | years positive | 2017-21 | 2022-26 |")
print("|---|---|---|---|---|---|---|---|")
for name, sig in RULES.items():
    s = np.nan_to_num(sig).astype(int)
    mk = (s != 0) & np.isfinite(wret)
    pnl = s[mk] * wret[mk] - 0.04
    py = pd.Series(pnl).groupby(wy[mk]).sum()
    tst = pnl.mean() / (pnl.std(ddof=1) / np.sqrt(len(pnl)))
    print(f"| {name} | {mk.sum()} | {pnl.mean():+.3f}% | {(pnl > 0).mean() * 100:.0f}% | {tst:+.2f} | {int((py > 0).sum())}/{len(py)} | "
          f"{pnl[wy[mk] <= 2021].mean():+.3f}% | {pnl[wy[mk] >= 2022].mean():+.3f}% |")
