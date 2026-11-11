"""Study 18: robustness map of the liquidity-pool breakout (fixed TP/SL, no per-config best picking).
Varies structure TF (M30/H1/H2), pivot width, pool age window, entry offset and trend filter.  Reports EV at
SL1.5/TP3 and SL1.0/TP1.0 (structure-TF ATR) with per-year signs."""
import sys
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E
import sw_events as V
import sw_mtf as M
from sw_study4 import excursions_from_fill_nb
from sw_study17 import pools_nb, pool_stop_events_nb

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
tfs = M.build_hierarchy(m1a)
tfs["M30"] = M.tf_states(E.make_bars(m1a, 30))
tfs["H2"] = M.tf_states(E.make_bars(m1a, 120))
years = pd.to_datetime(m1a["t"], unit="s").year.values
cost_usd = 0.07 + 0.05 * 0.5
YS = V.YS
FIX = ((1.5, 3.0), (1.0, 1.0), (1.0, 2.0))


def trend_of(T, names, kind="stackd"):
    out = None
    for h in names:
        k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
        sd = tfs[h][kind][k]
        out = sd if out is None else np.where(out == sd, sd, 0)
    return out.astype(np.int64)


rows = []
for S in ("M30", "H1", "H2"):
    T = tfs[S]
    for LR in (2, 3, 5):
        ph, phi, pl, pli = pools_nb(T["h"], T["l"], LR, LR)
        for filt in (("H4",), ("H4", "D1"), ("H1", "H4") if S != "H1" else ("H2", "H4")):
            if S == "H2" and filt == ("H2", "H4"):
                continue
            tr = trend_of(T, filt)
            for off in (0.0, 0.15, 0.3):
                for amin, amax in ((3, 12), (6, 24), (12, 48), (24, 120)):
                    em, ed, ep, ea = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], tr, T["m1s"], T["m1e"], m1a["o"],
                                                         m1a["h"], m1a["l"], m1a["spr"], off, amin, amax, 0.05, 3.0)
                    if len(em) < 60:
                        continue
                    mfe = excursions_from_fill_nb(em, ed, ep, ea, m1a["h"], m1a["l"], m1a["spr"], YS, 2880)
                    rec = dict(S=S, LR=LR, filt="+".join(filt), off=off, age=f"{amin}-{amax}", n=len(em),
                               tpd=len(em) / ((m1a["t"][em[-1]] - m1a["t"][em[0]]) / 86400 * 5 / 7))
                    for y_, x_ in FIX:
                        yi = list(YS).index(y_)
                        w = mfe[:, yi] >= x_
                        ev = (w * x_ - (~w) * y_ - cost_usd / ea) / y_
                        per = np.array([ev[years[em] == yy].mean() if (years[em] == yy).sum() >= 4 else np.nan
                                        for yy in range(2017, 2027)])
                        rec[f"ev{y_}/{x_}"] = round(float(ev.mean()), 3)
                        rec[f"py{y_}/{x_}"] = int(np.nansum(per > 0))
                        if (y_, x_) == (1.5, 3.0):
                            rec["years"] = " ".join("  .  " if not np.isfinite(p) else f"{p:+.2f}" for p in per)
                    rows.append(rec)
R = pd.DataFrame(rows)
pd.set_option("display.width", 260)
pd.set_option("display.max_rows", 400)
R = R.sort_values("ev1.5/3.0", ascending=False)
print(R.head(40).to_string(index=False))
print("\nmedian EV by factor (SL1.5/TP3):")
for f in ("S", "LR", "filt", "off", "age"):
    print(R.groupby(f)["ev1.5/3.0"].median().round(3).to_dict(), "| pos-years median:", R.groupby(f)["py1.5/3.0"].median().to_dict())
R.to_csv(rf"C:\Users\faker\Documents\goldie_research\sevenwave\data\pools_map_{src}.csv", index=False)
