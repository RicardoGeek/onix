"""Study 52: does the v1.10 AI veto still earn its keep?  Match every MT5 event (trade / veto) of the v1.32 default runs to
the Python setup (same stream, direction, trigger minute) and compare the simulated R of vetoed vs traded setups
(v1.30-like whale management, Dukascopy 2017-2026)."""
import numpy as np
import pandas as pd
from sw_study37_lib import (m, J, D, PX, AT, SI, mg, trk, Rv, probe, K, has, S2)

hidx = np.flatnonzero(has)
ext = S2.run_fills(m, J[has], D[has].astype(np.int64), PX[has], Rv[has], trk * AT[has], dict(mg, tp2_r=5.0, max_min=4320), one_at_a_time=False)
ext.index = hidx[ext.eidx.values]
pr = probe.copy()
cm = pr.index.intersection(ext.index)
pr.loc[cm, ["r"]] = ext.loc[cm, ["r"]].values
r = np.full(len(J), np.nan); r[pr.index.values] = pr.r.values
NAMES = {0: "A", 1: "B", 5: "G", 6: "P"}
st = np.array([NAMES.get(int(s), "?") for s in SI])
tmin = (m["t"][J].astype(np.int64) // 60) * 60
key = pd.Series(np.arange(len(J)), index=pd.MultiIndex.from_arrays([st, D.astype(int), tmin]))
key = key[~key.index.duplicated()]
MT = r"C:\Users\faker\Documents\goldie_research\sevenwave\mt5"
rows = []
for run in ("sw132_default_g10k_2024_2026", "sw132_default_prop50k_2024_2026", "sw132n_g10k_2018_2023", "sw132n_prop50k_2018_2023"):
    e = pd.read_csv(rf"{MT}\{run}_sevenwave_events.csv")
    e = e[e.decision.isin(["trade", "veto", "busy"])].copy()
    tu = pd.to_datetime(e.utc, format="%Y.%m.%d %H:%M:%S").values.astype("datetime64[s]").astype(np.int64)
    e["tmin"] = (tu // 60) * 60
    hit = []
    for s_, d_, t_ in zip(e.stream.values, e["dir"].values.astype(int), e.tmin.values):
        ix = np.nan
        for dt in (0, -60, 60):
            k = (s_, d_, t_ + dt)
            if k in key.index:
                ix = key[k]; break
        hit.append(ix)
    e["ix"] = hit
    e = e.dropna(subset=["ix"])
    e["r"] = r[e.ix.astype(int).values]
    e["run"] = run
    rows.append(e)
E = pd.concat(rows).dropna(subset=["r"])
E["year"] = pd.to_datetime(E.utc, format="%Y.%m.%d %H:%M:%S").dt.year
print("| Run | traded n | traded R | vetoed n | vetoed R | busy n | busy R |")
print("|---|---|---|---|---|---|---|")
for run, g in E.groupby("run"):
    c = {k: g[g.decision == k] for k in ("trade", "veto", "busy")}
    print(f"| {run} | {len(c['trade'])} | {c['trade'].r.mean():+.3f} | {len(c['veto'])} | {c['veto'].r.mean():+.3f} | {len(c['busy'])} | {c['busy'].r.mean():+.3f} |")
u = E.drop_duplicates(["ix"])
tv = u[u.decision.isin(["trade", "veto"])]
print("\nunique setups by year (trade vs veto):")
print("| Year | traded n | traded R | vetoed n | vetoed R |")
print("|---|---|---|---|---|")
for y, g in tv.groupby("year"):
    a, b = g[g.decision == "trade"], g[g.decision == "veto"]
    print(f"| {y} | {len(a)} | {a.r.mean():+.3f} | {len(b)} | {b.r.mean():+.3f} |")
a, b = tv[tv.decision == "trade"], tv[tv.decision == "veto"]
print(f"| all | {len(a)} | {a.r.mean():+.3f} | {len(b)} | {b.r.mean():+.3f} |  WR traded {(a.r > 0).mean() * 100:.1f}% vetoed {(b.r > 0).mean() * 100:.1f}%")
