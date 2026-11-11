"""16Runes Study 5: Broad Candidate Rune Stream + ONNX Meta-Labeler Veto & Daily Milking Portfolio Optimization.

Candidate Runes:
  - Streams: H1, H2, M30, M15, M5
  - Candidate Pre-Filter: H4 ribbon order aligned with Rune direction (order * dir >= 4 out of 6)
    AND for M15/M5 also H1 ribbon order aligned (order * dir >= 4 out of 6).
  - This produces ~2x more candidate setups per day across all 16 Runes, including days when D1 EMA-168 is still
    catching up to a new H1+H4 trend wave.
  - The 16-feature Meta-Labeler (trained strictly on 2017-2023) scores every candidate Rune and discards fake entries!
"""
import os
import sys
import time
import numpy as np
import pandas as pd
from numba import njit

sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
import sw_data as D
import sw_engine as E
import sw_mtf as M

from runes_study3 import RUNE_NAMES, RIBBON, build_all_tfs
from runes_study4 import detect_16runes_v4_nb, rune_events_v4_nb
from runes_study2 import simulate_whale_nb

STREAMS = [
    ("H1",  0.12),   # Stream 0: H1
    ("H2",  0.08),   # Stream 1: H2
    ("M30", 0.12),   # Stream 2: M30
    ("M15", 0.12),   # Stream 3: M15
    ("M5",  0.12),   # Stream 4: M5
]

FEATS = [
    "f0_stream", "f1_dir", "f2_is_cont", "f3_is_3piv", "f4_is_tri", "f5_is_wedge_flag",
    "f6_qual", "f7_pat_h_atr", "f8_comp_ratio", "f9_imp_align",
    "f10_h1_ord", "f11_h4_ord", "f12_d1_ord",
    "f13_vol_reg", "f14_cost_atr", "f15_liq_sess"
]


def build_candidates(src="duka"):
    m1 = D.load(f"{src}_m1")
    m1a = E.m1_arrays(m1, src)
    tfs = build_all_tfs(m1a)

    ord_tf = {}
    st_tf = {}
    for tf in ("M5", "M15", "M30", "H1", "H2", "H4", "D1"):
        T = tfs[tf]
        Em = T["E"]
        sc = np.sign(-np.diff(Em, axis=0)).sum(axis=0).astype(np.int64)
        ord_tf[tf] = sc
        st_tf[tf] = np.where(sc >= 6, 1, np.where(sc <= -6, -1, 0)).astype(np.int64)

    a1 = tfs["H1"]["atr"]
    cs = np.cumsum(np.r_[0.0, a1])
    idx = np.arange(len(a1))
    lo_i = np.maximum(0, idx - 479)
    mean_a1 = (cs[idx + 1] - cs[lo_i]) / (idx - lo_i + 1)
    vol_reg_h1 = a1 / np.maximum(mean_a1, 1e-9)

    rows = []
    for si, (tf_name, off_atr) in enumerate(STREAMS):
        T = tfs[tf_name]
        rid, rdir, tpx, slpx, path, piv, qual, pspan, crat, impv = detect_16runes_v4_nb(
            T["o"], T["h"], T["l"], T["c"], T["atr"], 3, 3, off_atr, 72
        )
        kh1_bar = np.maximum(M.map_last_closed(tfs["H1"], T["t_close"]), 0)
        kh4_bar = np.maximum(M.map_last_closed(tfs["H4"], T["t_close"]), 0)
        kd1_bar = np.maximum(M.map_last_closed(tfs["D1"], T["t_close"]), 0)

        # Candidate gate: H4 order >= 4 in direction, and for M15/M5 also H1 order >= 4 in direction,
        # and D1 order >= 0 (not strongly counter-macro D1 trend)
        o_h1 = ord_tf["H1"][kh1_bar]
        o_h4 = ord_tf["H4"][kh4_bar]
        o_d1 = ord_tf["D1"][kd1_bar]
        if tf_name in ("M15", "M5"):
            bull_ok = (o_h4 >= 4) & (o_h1 >= 4) & (o_d1 >= 0)
            bear_ok = (o_h4 <= -4) & (o_h1 <= -4) & (o_d1 <= 0)
        else:
            bull_ok = (o_h4 >= 4) & (o_d1 >= 0)
            bear_ok = (o_h4 <= -4) & (o_d1 <= 0)
        g = np.where(bull_ok, 1, np.where(bear_ok, -1, 0)).astype(np.int64)

        j, d, px, r_id, p_idx, sl_p, ph_p, q_p, sp_p, cr_p, im_p = rune_events_v4_nb(
            rid, rdir, tpx, slpx, path, piv, qual, pspan, crat, impv,
            T["atr"], g, T["m1s"], T["m1e"], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], 0.05, 3.0
        )
        if len(j) == 0:
            continue
        kh1 = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][j]), 0)
        kh4 = np.maximum(M.map_last_closed(tfs["H4"], m1a["t"][j]), 0)
        kd1 = np.maximum(M.map_last_closed(tfs["D1"], m1a["t"][j]), 0)
        ok = (kh1 >= 480) & (kh4 >= 10) & (kd1 >= 10)
        j, d, px, r_id, ph_p, q_p, sp_p, cr_p, im_p, kh1, kh4, kd1 = (
            j[ok], d[ok], px[ok], r_id[ok], ph_p[ok], q_p[ok], sp_p[ok], cr_p[ok], im_p[ok], kh1[ok], kh4[ok], kd1[ok]
        )
        at = a1[kh1]
        r_out, xt_out, mfe_out, wh_out = simulate_whale_nb(
            j, d, px, 1.5 * at, 2.0 * at,
            m1a["t"], m1a["o"], m1a["h"], m1a["l"], m1a["c"], m1a["spr"], m1a["tday"], m1a["nydow"],
            1.5, 0.05, 1.0, 3.0, 5.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
        )
        t_utc = m1a["t"][j]
        hr_utc = ((t_utc - (t_utc % 60)) // 3600) % 24
        cost = np.where((hr_utc == 21) | (hr_utc == 22), 0.60, 0.30)
        liq_sess = np.where((hr_utc >= 6) & (hr_utc <= 16), 1.0, np.where((hr_utc >= 17) & (hr_utc <= 22), -1.0, 0.0))

        is_cont = np.where(r_id <= 7, 1.0, -1.0)
        is_3piv = np.where(np.isin(r_id, [9, 10, 13, 14]), 1.0, 0.0)
        is_tri = np.where(np.isin(r_id, [0, 3, 4, 7]), 1.0, 0.0)
        is_wf = np.where(np.isin(r_id, [1, 2, 5, 6, 11, 15]), 1.0, 0.0)

        df_s = pd.DataFrame({
            "j": j, "entry_t": t_utc, "exit_t": xt_out, "stream": si, "dir": d, "rune": r_id,
            "px": px, "R": 1.5 * at, "trail": 2.0 * at, "r": r_out, "mfe": mfe_out, "whale": wh_out,
            "f0_stream": float(si) / 4.0,
            "f1_dir": d.astype(float),
            "f2_is_cont": is_cont,
            "f3_is_3piv": is_3piv,
            "f4_is_tri": is_tri,
            "f5_is_wedge_flag": is_wf,
            "f6_qual": q_p,
            "f7_pat_h_atr": np.clip(ph_p, 0.5, 10.0),
            "f8_comp_ratio": np.clip(cr_p, 0.2, 1.2),
            "f9_imp_align": np.clip(im_p, -6.0, 6.0),
            "f10_h1_ord": (ord_tf["H1"][kh1] * d).astype(float) / 6.0,
            "f11_h4_ord": (ord_tf["H4"][kh4] * d).astype(float) / 6.0,
            "f12_d1_ord": (ord_tf["D1"][kd1] * d).astype(float) / 6.0,
            "f13_vol_reg": np.clip(vol_reg_h1[kh1], 0.3, 3.5),
            "f14_cost_atr": np.clip(cost / np.maximum(a1[kh1], 1e-9), 0.0, 0.5),
            "f15_liq_sess": liq_sess,
        })
        rows.append(df_s)

    df = pd.concat(rows, ignore_index=True)
    df = df.sort_values(["j", "stream"]).drop_duplicates("j", keep="first").reset_index(drop=True)
    df["year"] = pd.to_datetime(df["entry_t"], unit="s").dt.year
    df = df[df.year >= 2017].reset_index(drop=True)
    return m1a, tfs, df


if __name__ == "__main__":
    t0 = time.time()
    m1a_d, tfs_d, df_d = build_candidates("duka")
    print(f"Built Dukascopy candidate dataset: {len(df_d):,} setups in {time.time() - t0:.1f}s")

    X = df_d[FEATS].values.astype(np.float32)
    r = df_d["r"].values
    yr = df_d["year"].values
    ins = yr <= 2023
    oos = yr >= 2024

    print(f"Baseline Candidates: n={len(df_d)}  2017-23 avgR={r[ins].mean():+.3f} (sum={r[ins].sum():+.1f}R, n={ins.sum()})  "
          f"2024-26 avgR={r[oos].mean():+.3f} (sum={r[oos].sum():+.1f}R, n={oos.sum()})")

    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
    from sklearn.pipeline import Pipeline
    import lightgbm as lgb

    y_bin = (r > 0.0).astype(int)
    for name, clf in [
        ("LogReg C=0.05", Pipeline([("sc", StandardScaler()), ("lr", LogisticRegression(C=0.05, max_iter=500))])),
        ("LGBM leaves=5 min_leaf=100", lgb.LGBMClassifier(
            n_estimators=55, learning_rate=0.03, num_leaves=5, min_child_samples=100,
            subsample=0.8, colsample_bytree=0.7, reg_lambda=40.0, random_state=42, verbose=-1
        )),
        ("LGBM leaves=6 min_leaf=120", lgb.LGBMClassifier(
            n_estimators=65, learning_rate=0.03, num_leaves=6, min_child_samples=120,
            subsample=0.8, colsample_bytree=0.7, reg_lambda=40.0, random_state=42, verbose=-1
        )),
    ]:
        oof_p = np.zeros(len(df_d))
        for y_val in range(2017, 2024):
            tr_m = ins & (yr != y_val)
            va_m = (yr == y_val)
            clf.fit(X[tr_m], y_bin[tr_m])
            oof_p[va_m] = clf.predict_proba(X[va_m])[:, 1]
        clf.fit(X[ins], y_bin[ins])
        oof_p[oos] = clf.predict_proba(X[oos])[:, 1]

        print(f"\n--- Meta-Labeler: {name} ---")
        for q in (0.20, 0.25, 0.30, 0.35, 0.40, 0.45):
            thr = np.quantile(oof_p[ins], q)
            keep_in = ins & (oof_p >= thr)
            veto_in = ins & (oof_p < thr)
            keep_oo = oos & (oof_p >= thr)
            veto_oo = oos & (oof_p < thr)
            print(f"  veto q={q:.2f} (thr={thr:.4f}): "
                  f"2017-23 CV kept={r[keep_in].mean():+.3f}R ({keep_in.sum()}) vs vetoed={r[veto_in].mean():+.3f}R ({veto_in.sum()}) | "
                  f"2024-26 OOS kept={r[keep_oo].mean():+.3f}R ({keep_oo.sum()}, sum={r[keep_oo].sum():+.1f}R) "
                  f"vs vetoed={r[veto_oo].mean():+.3f}R ({veto_oo.sum()})")
