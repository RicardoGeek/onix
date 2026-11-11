"""Study 33: the 'EMA ribbon calculus' whale trigger, implemented EXACTLY as in the snippet the user received:

  ribbon_thickness   = std across the 7 EMAs (pandas .std(axis=1), ddof=1)
  expansion_velocity = ribbon_thickness.diff()
  z = (v - rolling_mean_20(v)) / rolling_std_20(v);  whale_breakout = z > 2.5
Direction = the side the ribbon flares to (sign of EMA_fast - EMA_slow at the trigger bar); also the centroid velocity.
Trades: market at the next M1 open after the trigger bar closes (spread/commission/slippage applied), FOLLOW the flare
and FADE it; fixed ATR targets/stops + a ride exit; per year; plus a one-position real-account replay.
Also: as a FILTER on the v1.10 liquidity-pool entries (is a recent z-spike good or bad for them?).
Selection 2017-2022, unseen 2023-2026.  Timeframes M5 / M15 / H1.
"""
import sys
import numpy as np
import pandas as pd
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_engine as E
import sw_mtf as M
import sw_events as EV
import sw_sim2 as S2

m1a, tfs = V.m1a, V.tfs
PERIODS = {"snippet 3/5/8/12/15/21/30": [3, 5, 8, 12, 15, 21, 30], "user 3/5/8/10/12/15/35": [3, 5, 8, 10, 12, 15, 35]}
cost_usd = 0.07 + 0.05 + 0.05
pd.set_option("display.width", 240)


def whale(b, periods):
    df = pd.DataFrame({"close": b["c"]})
    cols = []
    for p in periods:
        df[f"ema_{p}"] = df["close"].ewm(span=p, adjust=False).mean()
        cols.append(f"ema_{p}")
    df["thick"] = df[cols].std(axis=1)
    df["vel"] = df["thick"].diff()
    mu = df["vel"].rolling(20).mean()
    sd = df["vel"].rolling(20).std()
    df["z"] = (df["vel"] - mu) / sd
    df["trig"] = (df["z"] > 2.5).astype(int)
    df["dir"] = np.sign(df[cols[0]] - df[cols[-1]]).astype(int)
    cen = df[cols].mean(axis=1)
    df["cdir"] = np.sign(cen.diff()).fillna(0).astype(int)
    return df


rows = []
for tfname, mins in (("M5", 5), ("M15", 15), ("H1", 60)):
    b = tfs[tfname] if tfname in tfs else M.tf_states(E.make_bars(m1a, mins))
    a = np.maximum(b["atr"], 1e-9)
    years = pd.to_datetime(b["t"], unit="s").year.values
    for pname, per in PERIODS.items():
        df = whale(b, per)
        first = (df.trig.values == 1) & (np.r_[0, df.trig.values[:-1]] == 0)       # first bar of each spike cluster
        idx = np.flatnonzero(first & (df.dir.values != 0))
        idx = idx[(idx > 500) & (idx < b["n"] - 1)]
        j = b["m1e"][idx]
        ok = (m1a["t"][np.minimum(j, len(m1a["t"]) - 1)] - m1a["t"][j - 1]) <= 1800
        idx, j = idx[ok], j[ok]
        days = (b["t"][idx[-1]] - b["t"][idx[0]]) / 86400 * 5 / 7
        for side, sgn in (("FOLLOW", 1), ("FADE", -1)):
            d = (df.dir.values[idx] * sgn).astype(np.int64)
            mfe, _ = EV.excursions_nb(j, d, a[idx], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], EV.YS, mins * 96)
            c_atr = cost_usd / a[idx]
            best = None
            for yi, y_ in enumerate(EV.YS):
                for x_ in EV.XS:
                    w = mfe[:, yi] >= x_
                    ev = (w * x_ - (~w) * y_ - c_atr) / y_
                    ins = ev[years[idx] <= 2022].mean(); oos = ev[years[idx] >= 2023].mean()
                    if best is None or ins > best[2]:
                        best = (y_, x_, ins, oos, w.mean(), ev)
            y_, x_, ins, oos, wr, ev = best
            per_year = pd.Series(ev, index=years[idx]).groupby(level=0).mean()
            rows.append(dict(tf=tfname, ribbon=pname, side=side, n=len(idx), per_day=round(len(idx) / days, 2),
                             best_SL_TP=f"SL{y_}/TP{x_} ATR", win=round(wr * 100, 1), ev_2017_22=round(ins, 3), ev_2023_26=round(oos, 3),
                             yrs_pos=f"{int((per_year > 0).sum())}/{len(per_year)}"))
R = pd.DataFrame(rows)
print("=== whale trigger (z > 2.5 on ribbon-thickness velocity), best fixed SL/TP chosen on 2017-2022, EV in R net of costs ===")
print(R.to_string(index=False))
R.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\whale_calculus.csv", index=False)

# ------------------------------------------------------------- as a filter on v1.10 pool entries
J, D, PX, AT, SI = V.all_events(use=["A", "B", "G", "P"])
mg, slk, trk = V.MGMT["growth"]
tr = S2.run_fills(m1a, J, D, PX, slk * AT, trk * AT, mg, one_at_a_time=False)
b = tfs["M15"]
df = whale(b, PERIODS["snippet 3/5/8/12/15/21/30"])
k = np.maximum(np.searchsorted(b["t_close"], m1a["t"][J], side="right") - 1, 0)
zmax = pd.Series(df.z.values).rolling(4, min_periods=1).max().values[k]          # any spike in the last hour
same = (df.dir.values[k] == D)
r = np.full(len(J), np.nan); r[tr.eidx.values] = tr.r.values
yr = pd.to_datetime(m1a["t"][J], unit="s").year.values
print("\n=== v1.10 pool entries split by a recent whale spike (z>2.5 in the last 4 M15 bars) ===")
for nm, msk in (("all v1.10 entries", np.ones(len(J), bool)), ("spike, same direction", (zmax > 2.5) & same),
                ("spike, opposite direction", (zmax > 2.5) & ~same), ("no spike", zmax <= 2.5)):
    rr = pd.Series(r[msk], index=yr[msk])
    print(f"{nm:28s} n={msk.sum():5d} avgR={np.nanmean(r[msk]):+.3f} | 2017-22 {rr[rr.index <= 2022].mean():+.3f} | "
          f"2023-26 {rr[rr.index >= 2023].mean():+.3f} | years+ {int((rr.groupby(level=0).sum() > 0).sum())}/10")
