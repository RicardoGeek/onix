"""Study 45: NFP-day gold trades with real stops (M1 fills, Dukascopy, costs).  Entry 5 minutes after the release.
  FADE5    : against the first 5-minute reaction
  SURPRISE : with the macro surprise (NFP above forecast = USD-positive = gold down), forecast from the MQL5 calendar
Stop k x ATR(H1), target m x ATR(H1), time exit after `hold` minutes.  Split 2017-2021 / 2022-2026 and per year.
Caveat: news spreads/slippage are worse than the Duka spread model; entry at +5 min avoids the first spike.
"""
import sys
import itertools
import numpy as np
import pandas as pd
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_data as SD
import sw_sim2 as S2

m1a = V.m1a
cal = pd.read_csv(r"C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\Common\Files\sw_calendar_us.csv")
cal["t"] = cal.time_srv.values.astype(np.int64)   # calendar times are UTC
nfp = cal[(cal.event == "Nonfarm Payrolls") & (cal.importance == 3)].drop_duplicates("t").sort_values("t")
mt, mo, mh, ml, mc, sp = m1a["t"], m1a["o"], m1a["h"], m1a["l"], m1a["c"], m1a["spr"]
H1 = V.tfs["H1"]
print(f"NFP releases: {len(nfp)}, with forecast: {nfp.forecast.notna().sum()}")


def trade(j, d, atr, k, mtp, hold):
    ep = mo[j] + (sp[j] if d > 0 else 0.0) + 0.05 * d
    stop = ep - d * k * atr; tgt = ep + d * mtp * atr
    for q in range(j, min(j + hold, len(mt) - 1)):
        if d > 0 and ml[q] <= stop: return (min(mo[q], stop) - 0.10 - ep - S2.COMM) / (k * atr)
        if d < 0 and mh[q] + sp[q] >= stop: return (ep - max(mo[q] + sp[q], stop) - 0.10 - S2.COMM) / (k * atr)
        if d > 0 and mh[q] >= tgt: return (tgt - ep - S2.COMM) / (k * atr)
        if d < 0 and ml[q] + sp[q] <= tgt: return (ep - tgt - S2.COMM) / (k * atr)
    q = min(j + hold, len(mt) - 1)
    xp = mo[q] - 0.05 if d > 0 else mo[q] + sp[q] + 0.05
    return (d * (xp - ep) - S2.COMM) / (k * atr)


rows = []
for e in nfp.itertuples():
    j0 = np.searchsorted(mt, e.t)
    if j0 + 400 >= len(mt) or abs(mt[j0] - e.t) > 120:
        continue
    kk = np.searchsorted(H1["t_close"], e.t, side="right") - 1
    atr = H1["atr"][max(kk, 0)]
    m5 = mc[j0 + 4] - mo[j0]
    sur = e.actual - e.forecast if np.isfinite(e.actual) and np.isfinite(e.forecast) else np.nan
    for side, k, mtp, hold in itertools.product(("FADE5", "SURPRISE"), (1.0, 1.5, 2.0), (1.5, 3.0), (120, 240, 360)):
        d = -np.sign(m5) if side == "FADE5" else (-np.sign(sur) if np.isfinite(sur) else 0.0)
        if d == 0:
            continue
        rows.append(dict(side=side, k=k, m=mtp, hold=hold, year=pd.Timestamp(e.t, unit="s").year, r=trade(j0 + 5, int(d), atr, k, mtp, hold),
                         agree=np.sign(m5) == -np.sign(sur) if np.isfinite(sur) else False))
R = pd.DataFrame(rows)
out = []
for (side, k, mtp, hold), g in R.groupby(["side", "k", "m", "hold"]):
    py = g.groupby("year").r.mean()
    out.append(dict(side=side, stop=k, tp=mtp, hold=hold, n=len(g), wr=round((g.r > 0).mean() * 100, 1), avgR=round(g.r.mean(), 3),
                    r_17_21=round(g[g.year <= 2021].r.mean(), 3), r_22_26=round(g[g.year >= 2022].r.mean(), 3), yrs_pos=f"{int((py > 0).sum())}/{len(py)}"))
O = pd.DataFrame(out).sort_values("r_17_21", ascending=False)
pd.set_option("display.width", 200)
print(O.head(14).to_string(index=False))
sur_ok = R[(R.side == "SURPRISE")]
print(f"\nhow often the first 5-minute move agrees with the surprise sign: {sur_ok.drop_duplicates(['year', 'r']).agree.mean() * 100:.0f}%")
