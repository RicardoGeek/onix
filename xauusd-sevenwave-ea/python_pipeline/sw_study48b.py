"""Study 48b (POST-HOC): contrarian news tone at the ACCOUNT level.  Study 48 found that setups whose direction AGREES with the
last week's GDELT tone trend (7d vs 30d, z) earn +0.10R vs +0.41R when it disagrees (8/10 years, both halves) - the
pre-registered side was the opposite.  Thresholds from 2017-2021; setups without tone data (2026) keep weight 1.
Variants: skip the agreeing third; risk weights 0.6 (agree) / 1.0 / 1.3 (disagree).  Engine as study 44."""
import glob
import numpy as np
import pandas as pd
from sw_study37_lib import (m, J, D, PX, AT, SI, mg, trk, Rv, probe, W, K, ja, has, addpx, S2, acct, total_row)

RAW = r"C:\Users\faker\Documents\goldie_research\sevenwave\data\outside\gdelt"
fr = []
for f in sorted(glob.glob(rf"{RAW}\timelinetone_*.csv")):
    try:
        x = pd.read_csv(f)
        if "Date" in x.columns:
            fr.append(x[["Date", "Value"]])
    except Exception:
        pass
tone = pd.concat(fr); tone["d"] = pd.to_datetime(tone.Date)
tone = tone.drop_duplicates("d").set_index("d").Value.astype(float).sort_index()
tone = tone.reindex(pd.date_range(tone.index.min(), tone.index.max(), freq="D"))
z = ((tone.rolling(7, min_periods=4).mean() - tone.rolling(30, min_periods=15).mean()) / tone.rolling(90, min_periods=30).std()).values
avail = tone.index.values.astype("datetime64[s]").astype(np.int64) + 86400 + 3600
t = m["t"][J].astype(np.int64)
k = np.searchsorted(avail, t, side="right") - 1
x = np.where((k >= 0) & (k < len(z)) & (t < avail[-1] + 86400), D * z[np.clip(k, 0, len(z) - 1)], np.nan)
yr = pd.to_datetime(t, unit="s").year.values
q1, q2 = np.nanquantile(x[np.isfinite(x) & (yr <= 2021)], [1 / 3, 2 / 3])
print(f"tone-agreement terciles (2017-21): {q1:+.3f} / {q2:+.3f}; setups with tone {np.isfinite(x).sum()} of {len(x)}")

hidx = np.flatnonzero(has)
ext = S2.run_fills(m, J[has], D[has].astype(np.int64), PX[has], Rv[has], trk * AT[has], dict(mg, tp2_r=5.0, max_min=4320), one_at_a_time=False)
ext.index = hidx[ext.eidx.values]
pr = probe.copy(); cm = pr.index.intersection(ext.index)
pr.loc[cm, ["entry_t", "exit_t", "r"]] = ext.loc[cm, ["entry_t", "exit_t", "r"]].values
mga = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=(5.0 - K) / K, max_min=4320)
ad = S2.run_fills(m, ja[has], D[has].astype(np.int64), addpx[has], K * Rv[has], trk * AT[has], mga, one_at_a_time=False)
ADDS = {int(hidx[e]): (int(a0), int(a1), float(r)) for e, a0, a1, r in zip(ad.eidx.values, ad.entry_t.values, ad.exit_t.values, ad.r.values)}


def events(mult, with_adds):
    ev = []
    for e in pr.index.values:
        f = mult[int(e)]
        if f <= 0:
            continue
        q = pr.loc[e]
        ev.append((int(q.entry_t), "P", ("v", int(e)), int(q.exit_t), float(q.r), float(Rv[e]), W[int(SI[e])] * f))
        if with_adds and int(e) in ADDS:
            a0, a1, ar = ADDS[int(e)]
            ev.append((a0, "A", ("v", int(e)), a1, ar, K * float(Rv[e]) + 0.05, W[int(SI[e])] * K * f))
    ev.sort(key=lambda z_: (z_[0], z_[1]))
    return ev


nan = ~np.isfinite(x)
VAR = {"baseline": np.ones(len(J)),
       "skip tone-agreeing third": np.where(nan, 1.0, np.where(x > q2, 0.0, 1.0)),
       "weights 1.3 / 1.0 / 0.6": np.where(nan, 1.0, np.where(x <= q1, 1.3, np.where(x > q2, 0.6, 1.0)))}
WIN = (("2018-01-01", "2024-01-01", "2018-2023"), ("2024-01-01", "2026-01-01", "2024-2025"))
print("| Run | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score | |")
print("|---|---|---|---|---|---|---|---|---|")
for nm, mu in VAR.items():
    evg, evp = events(mu, True), events(mu, False)
    for (a, b, lab) in WIN:
        print(total_row(acct(evg, 0.5, 3, 1.0, 1e4, 10.0, 30.0, 0.0, a, b), 1e4, f"GROWTH $10k {lab} {nm}"))
    for (a, b, lab) in WIN:
        print(total_row(acct(evp, 0.15, 2, 0.5, 5e4, 3.0, 6.0, 2.4, a, b), 5e4, f"PROP $50k {lab} {nm}"))
