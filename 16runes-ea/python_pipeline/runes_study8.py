"""16Runes Study 8: Stream Slot Allocation & LogReg Meta-Labeler ONNX Veto in Time-Ordered Portfolio (2017-2026).

Tests:
1. 4 Streams (H1, H2, M30, M15) vs 5 Streams (H1, H2, M30, M15 + top M5 Runes)
2. LogReg C=0.05 Meta-Labeler veto in both Prop (2 slots) and Growth (3 slots + Whale Pyramid)
3. Per-year R across all 10 years (2017-2026) on Dukascopy and 2023-2026 on Pepperstone.
"""
import os
import sys
import time
import numpy as np
import pandas as pd

sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
from runes_study4 import build_dataset
from runes_study7 import extract_features, portfolio_sim_nb, FEATS_16
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

if __name__ == "__main__":
    m1a_d, tfs_d, df_d = build_dataset("duka")
    X = extract_features(df_d)
    r = df_d["r"].values
    yr = df_d["year"].values
    ins = yr <= 2023
    oos = yr >= 2024
    y_bin = (r > 0.0).astype(int)

    clf = Pipeline([("sc", StandardScaler()), ("lr", LogisticRegression(C=0.05, max_iter=500))])
    oof_p = np.zeros(len(df_d))
    for y_val in range(2017, 2024):
        tr_m = ins & (yr != y_val)
        va_m = (yr == y_val)
        clf.fit(X[tr_m], y_bin[tr_m])
        oof_p[va_m] = clf.predict_proba(X[va_m])[:, 1]
    clf.fit(X[ins], y_bin[ins])
    oof_p[oos] = clf.predict_proba(X[oos])[:, 1]
    df_d["p"] = oof_p

    thr15 = float(np.quantile(oof_p[ins], 0.15))
    thr20 = float(np.quantile(oof_p[ins], 0.20))
    thr25 = float(np.quantile(oof_p[ins], 0.25))
    thr40 = float(np.quantile(oof_p[ins], 0.40))

    configs = [
        ("4 Streams (H1,H2,M30,M15) No Veto", df_d[df_d.stream < 4].reset_index(drop=True)),
        ("4 Streams + LogReg Veto q=0.15", df_d[(df_d.stream < 4) & (df_d.p >= thr15)].reset_index(drop=True)),
        ("4 Streams + LogReg Veto q=0.20", df_d[(df_d.stream < 4) & (df_d.p >= thr20)].reset_index(drop=True)),
        ("5 Streams + LogReg Veto (S0..3>=q15, M5>=q40)", df_d[((df_d.stream < 4) & (df_d.p >= thr15)) | ((df_d.stream == 4) & (df_d.p >= thr40))].reset_index(drop=True)),
        ("5 Streams + LogReg Veto q=0.25", df_d[df_d.p >= thr25].reset_index(drop=True)),
    ]

    for cname, sub in configs:
        print(f"\n=======================================================")
        print(f"CONFIG: {cname} (candidates={len(sub)})")
        for mode_nm, slots, pyr in [("Prop (2 slots)", 2, False), ("Growth (3 slots + Whale Pyramid)", 3, True)]:
            taken, pr_r, ad_r, xt, wh = portfolio_sim_nb(
                sub.j.values, sub.dir.values, sub.px.values, sub.R.values, sub.trail.values,
                sub.stream.values, sub.rune.values,
                m1a_d["t"], m1a_d["o"], m1a_d["h"], m1a_d["l"], m1a_d["c"], m1a_d["spr"], m1a_d["tday"], m1a_d["nydow"],
                slots, pyr, 1.5, 0.05, 1.0, 3.0, 5.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
            )
            m = taken == 1
            tot_r = pr_r[m] + ad_r[m]
            yrs = sub.year.values[m]
            mi = yrs <= 2023
            mo_mask = yrs >= 2024
            by_y = pd.Series(tot_r).groupby(yrs).sum()
            print(f"  [{mode_nm:32s}]: probes={m.sum():4d}  "
                  f"2017-23={tot_r[mi].sum():+6.1f}R (avg={tot_r[mi].mean():+.3f}R, n={mi.sum():3d})  "
                  f"2024-26={tot_r[mo_mask].sum():+6.1f}R (avg={tot_r[mo_mask].mean():+.3f}R, n={mo_mask.sum():3d})  "
                  f"green_yrs={int((by_y > 0).sum())}/{len(by_y)}")
            print("    Years:", "  ".join(f"{y}:{v:+.1f}R" for y, v in by_y.items()))
