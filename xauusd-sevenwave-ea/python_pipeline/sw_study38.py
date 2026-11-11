"""Study 38: "market intraday momentum" (Gao, Han, Li & Zhou 2018, JFE; Elaut et al. 2016 for FX; global evidence 2021)
applied to gold: does an early-day return predict the return of a later window of the same NY trading day?

Signal windows (New York time, the gold day runs 18:00 -> 17:00):  S1 18:00(prev)->08:30 (Asia+London), S2 08:20->08:50 (COMEX open),
S3 18:00(prev)->12:00.   Trade windows: T1 13:00->13:30 (pre-settlement), T2 15:00->16:55 (day end), T3 09:00->13:30 (NY morning).
Trade = sign(signal return) [or the opposite], entry at the window start (M1 open), exit at the window end, costs included.
Also gated: only when |signal| > its 60-day median (strong-signal days).
Selection 2017-2022 (Dukascopy), unseen 2023-2026.
"""
import sys
import itertools
import numpy as np
import pandas as pd
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_sim2 as S2

m1a = V.m1a
t, o, c, spr = m1a["t"], m1a["o"], m1a["c"], m1a["spr"]
ny = pd.to_datetime(t, unit="s", utc=True).tz_convert("America/New_York")
nymin = (ny.hour * 60 + ny.minute).values
day = m1a["tday"].astype(np.int64)
COST = S2.COMM + 2 * S2.SLIP_MKT

df = pd.DataFrame({"day": day, "min": nymin, "o": o, "c": c, "spr": spr, "t": t})
# minute -> index lookup per day: first M1 bar at or after a given NY minute (within the same trading day)
df["i"] = np.arange(len(df))


def at_or_after(target_min):
    """per day: index of the first bar whose NY minute >= target (respecting the 18:00 day start)."""
    mm = np.where(df["min"].values >= 18 * 60, df["min"].values - 24 * 60, df["min"].values)   # -360..1019
    tm = target_min - 24 * 60 if target_min >= 18 * 60 else target_min
    sel = mm >= tm
    s = pd.Series(np.where(sel, df.i.values, np.iinfo(np.int64).max), index=df.day.values)
    return s.groupby(level=0).min()


marks = {k: at_or_after(v) for k, v in {"1800": 18 * 60, "0820": 8 * 60 + 20, "0830": 8 * 60 + 30, "0850": 8 * 60 + 50,
                                         "0900": 9 * 60, "1200": 12 * 60, "1300": 13 * 60, "1330": 13 * 60 + 30,
                                         "1500": 15 * 60, "1655": 16 * 60 + 55}.items()}
days = marks["1800"].index.values
BIG = np.iinfo(np.int64).max


def px(idx, field):
    return np.where(idx < BIG, df[field].values[np.minimum(idx, len(df) - 1)], np.nan)


def win_ret(a, b):
    ia, ib = marks[a].reindex(days).values, marks[b].reindex(days).values
    ok = (ia < BIG) & (ib < BIG) & (ib > ia)
    return np.where(ok, px(ib, "o") - px(ia, "o"), np.nan), ia, ib, ok


yrs = pd.to_datetime(df.t.values[np.minimum(marks["1800"].reindex(days).values, len(df) - 1)], unit="s").year.values
SIG = {"S1 18:00->08:30": ("1800", "0830"), "S2 08:20->08:50": ("0820", "0850"), "S3 18:00->12:00": ("1800", "1200")}
TRD = {"T1 13:00->13:30": ("1300", "1330"), "T2 15:00->16:55": ("1500", "1655"), "T3 09:00->13:30": ("0900", "1330")}
rows = []
for (sn, (sa, sb)), (tn, (ta, tb)), side, strong in itertools.product(SIG.items(), TRD.items(), (1, -1), (False, True)):
    if marks[tb].empty:
        continue
    s, _, _, okS = win_ret(sa, sb)
    _, ia, ib, okT = win_ret(ta, tb)
    # trade window must start after the signal window ends
    if pd.Timestamp("2000-01-01 " + f"{ta[:2]}:{ta[2:]}") < pd.Timestamp("2000-01-01 " + f"{sb[:2]}:{sb[2:]}") and sb != "0830":
        continue
    ok = okS & okT & np.isfinite(s) & (s != 0)
    if strong:
        med = pd.Series(np.abs(s)).rolling(60, min_periods=30).median().shift(1).values
        ok &= np.abs(s) > med
    d = np.sign(s) * side
    entry = px(ia, "o") + np.where(d > 0, px(ia, "spr"), 0.0)
    exit_ = px(ib, "o") + np.where(d < 0, px(ib, "spr"), 0.0)
    pnl = d * (exit_ - entry) - COST
    # normalise by the 20-day average daily range so years are comparable
    rngd = df.groupby("day").c.agg(lambda x: x.max() - x.min()).reindex(days).rolling(20, min_periods=20).mean().shift(1).values
    r = pnl / np.maximum(rngd, 1e-9)
    ok &= np.isfinite(r)
    rr, yy = r[ok], yrs[ok]
    if len(rr) < 200:
        continue
    py = pd.Series(rr).groupby(yy).mean()
    rows.append(dict(signal=sn, trade=tn, side="follow" if side > 0 else "fade", strong=strong, n=len(rr),
                     wr=round((rr > 0).mean() * 100, 1), avg_2017_22=round(rr[yy <= 2022].mean() * 100, 2),
                     avg_2023_26=round(rr[yy >= 2023].mean() * 100, 2), yrs_pos=f"{int((py > 0).sum())}/{len(py)}"))
R = pd.DataFrame(rows).sort_values("avg_2017_22", ascending=False)
pd.set_option("display.width", 220)
print("avg_* = mean P/L per trade in % of the 20-day average daily range, after costs")
print(R.head(20).to_string(index=False))
R.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\study38_intraday_momentum.csv", index=False)
