"""Oliver Kell Study 6: Broker-Invariant 16-Feature OHLC + 10/20 EMA Cycle Meta-Labeler
Tested on both Dukascopy (2017-2026) and Pepperstone (2023-2026).
"""
import os
import sys
import time
import numpy as np
import pandas as pd
from numba import njit
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\16runes-ea\python_pipeline")
import sw_data as D
import sw_engine as E
import sw_mtf as M
from kell_study1 import SETUP_NAMES, RIBBON_7, build_kell_tfs, kell_events_nb
from kell_study4 import detect_kell_v4_nb, STREAMS
from runes_study2 import simulate_whale_nb
from runes_study10_moonshot import portfolio_moonshot_nb

KELL_FEATS_16 = [
    "f0_stream",            # 0..4 normalized (/4)
    "f1_dir",               # +1 or -1
    "f2_is_3piv_rev",       # 1 if 3-pivot Reversal/Exhaustion Extension (span3)
    "f3_is_base_n_break",   # 1 if BASE_N_BREAK_BULL (0) or BASE_N_BREAK_BEAR (1)
    "f4_is_wedge_pop_drop", # 1 if WEDGE_POP_BULL (2) or WEDGE_DROP_BEAR (3)
    "f5_is_ema_crossback",  # 1 if EMA_CROSSBACK_BULL (4) or EMA_CROSSBACK_BEAR (5)
    "f6_is_bear_cont",      # 1 if BASE_N_BREAK_BEAR (1) or EMA_CROSSBACK_BEAR (5)
    "f7_qual",              # geometric quality score
    "f8_base_h_atr",        # base height in structure ATRs
    "f9_comp_ratio",        # base compression ratio w_b / w_a
    "f10_imp_align",        # prior impulse aligned with trade direction
    "f11_ema_ext",          # distance of close from EMA20 in structure ATRs aligned with dir
    "f12_vol_u",            # U-shaped H1 volatility squeeze/expansion |vol_reg - 1.0|
    "f13_vol_reg",          # H1 volatility regime ATR14 / mean480(ATR14)
    "f14_cost_atr",         # spread/cost / ATR14(H1)
    "f15_h4_rib_sp",        # H4 7-EMA ribbon spread in H4 ATRs aligned with dir
]


def build_kell_dataset_v6(src="duka"):
    m1 = D.load(f"{src}_m1")
    m1a = E.m1_arrays(m1, src)
    tfs = build_kell_tfs(m1, m1a, RIBBON_7)

    st = {}
    for tf in ("M5", "M15", "M30", "H1", "H2", "H4", "D1"):
        T = tfs[tf]
        Em = T["E"]
        sc = np.sign(-np.diff(Em, axis=0)).sum(axis=0)
        st[tf] = np.where(sc >= 6, 1, np.where(sc <= -6, -1, 0)).astype(np.int64)

    a1 = tfs["H1"]["atr"]
    a1_mean480 = pd.Series(a1).rolling(480, min_periods=50).mean().values
    vol_reg_h1 = np.clip(a1 / np.maximum(a1_mean480, 1e-6), 0.3, 3.5)

    h4_e = tfs["H4"]["E"]
    h4_a = np.maximum(tfs["H4"]["atr"], 1e-6)
    h4_sp = (h4_e[0] - h4_e[-1]) / h4_a

    rows = []
    for s_id, (tf_name, gate_tfs, off) in enumerate(STREAMS):
        T = tfs[tf_name]
        sid, sdir, tpx, slpx, bh, piv, qual, sp, cr, im, rv, ex = detect_kell_v4_nb(
            T["o"], T["h"], T["l"], T["c"], T["v"], T["ema10"], T["ema20"], T["vma20"], T["atr"], 3, 3, off
        )
        g = np.full(T["n"], 99, np.int64)
        for gtf in gate_tfs:
            kg = np.maximum(M.map_last_closed(tfs[gtf], T["t_close"]), 0)
            sg = st[gtf][kg]
            g = np.where(g == 99, sg, np.where(g == sg, g, 0)).astype(np.int64)

        j, d, px, setup_k, p_idx, sl_p, bh_p, q_p, sp_p, cr_p, im_p, rv_p, ex_p = kell_events_nb(
            sid, sdir, tpx, slpx, bh, piv, qual, sp, cr, im, rv, ex,
            T["atr"], g, T["m1s"], T["m1e"], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], 0.05, 3.0
        )
        if len(j) == 0:
            continue

        t_trig = m1a["t"][j]
        kh1 = np.maximum(M.map_last_closed(tfs["H1"], t_trig), 0)
        kh4 = np.maximum(M.map_last_closed(tfs["H4"], t_trig), 0)
        at = a1[kh1]

        r_out, xt_out, mfe_out, wh_out = simulate_whale_nb(
            j, d, px, 1.5 * at, 2.0 * at,
            m1a["t"], m1a["o"], m1a["h"], m1a["l"], m1a["c"], m1a["spr"], m1a["tday"], m1a["nydow"],
            1.5, 0.05, 1.0, 3.0, 5.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
        )

        hr_utc = (t_trig // 3600) % 24
        cost_est = np.where((hr_utc >= 21) & (hr_utc <= 22), 0.60, 0.30)
        liq_sess = np.where((hr_utc >= 6) & (hr_utc <= 16), 1.0, np.where((hr_utc >= 17) & (hr_utc <= 22), -1.0, 0.0))

        # Note: in detect_kell_v4_nb, 3-pivot Rev/Exh setups have qual >= 1.50
        is_3piv = ((setup_k >= 6) & (q_p >= 1.50)).astype(float)

        df_s = pd.DataFrame({
            "j": j,
            "t": t_trig,
            "exit_t": xt_out,
            "stream": s_id,
            "setup": setup_k,
            "dir": d,
            "px": px,
            "R": 1.5 * at,
            "trail": 2.0 * at,
            "r": r_out,
            "whale": wh_out,
            "f0_stream": s_id / 4.0,
            "f1_dir": d.astype(float),
            "f2_is_3piv_rev": is_3piv,
            "f3_is_base_n_break": np.isin(setup_k, [0, 1]).astype(float),
            "f4_is_wedge_pop_drop": np.isin(setup_k, [2, 3]).astype(float),
            "f5_is_ema_crossback": np.isin(setup_k, [4, 5]).astype(float),
            "f6_is_bear_cont": np.isin(setup_k, [1, 5]).astype(float),
            "f7_qual": q_p,
            "f8_base_h_atr": np.clip(bh_p, 0.5, 10.0),
            "f9_comp_ratio": np.clip(cr_p, 0.2, 1.2),
            "f10_imp_align": np.clip(im_p, -6.0, 6.0),
            "f11_ema_ext": np.clip(ex_p, -4.0, 4.0) + 0.25 * liq_sess,
            "f12_vol_u": np.abs(vol_reg_h1[kh1] - 1.0),
            "f13_vol_reg": vol_reg_h1[kh1],
            "f14_cost_atr": np.clip(cost_est / np.maximum(at, 1e-6), 0.0, 0.5),
            "f15_h4_rib_sp": np.clip(h4_sp[kh4] * d, -6.0, 6.0),
        })
        rows.append(df_s)

    df = pd.concat(rows, ignore_index=True)
    df = df.sort_values(["j", "stream"]).drop_duplicates(subset=["j"], keep="first").reset_index(drop=True)
    df["year"] = pd.to_datetime(df["t"], unit="s").dt.year
    df = df[df["year"] >= 2017].reset_index(drop=True)
    return m1a, tfs, df


def extract_kell_features_v6(df: pd.DataFrame) -> np.ndarray:
    return df[KELL_FEATS_16].values.astype(np.float32)


if __name__ == "__main__":
    m1a_d, tfs_d, df_d = build_kell_dataset_v6("duka")
    X_d = extract_kell_features_v6(df_d)
    r_d = df_d["r"].values
    yr_d = df_d["year"].values
    ins = yr_d <= 2023
    oos = yr_d >= 2024
    y_bin = (r_d > 0.0).astype(int)

    clf = Pipeline([("sc", StandardScaler()), ("lr", LogisticRegression(C=0.05, max_iter=500, random_state=42))])
    oof_p = np.zeros(len(df_d))
    for y_val in range(2017, 2024):
        tr_m = ins & (yr_d != y_val)
        va_m = (yr_d == y_val)
        clf.fit(X_d[tr_m], y_bin[tr_m])
        oof_p[va_m] = clf.predict_proba(X_d[va_m])[:, 1]
    clf.fit(X_d[ins], y_bin[ins])
    oof_p[oos] = clf.predict_proba(X_d[oos])[:, 1]

    for q in (0.12, 0.15, 0.18, 0.20, 0.25):
        thr = np.quantile(oof_p[ins], q)
        k_in = ins & (oof_p >= thr); v_in = ins & (oof_p < thr)
        k_oo = oos & (oof_p >= thr); v_oo = oos & (oof_p < thr)
        print(f"Veto q={q:.2f} (thr={thr:.4f}): "
              f"2017-23 CV kept={r_d[k_in].mean():+.3f}R ({k_in.sum()}) vs veto={r_d[v_in].mean():+.3f}R ({v_in.sum()}) | "
              f"2024-26 OOS kept={r_d[k_oo].mean():+.3f}R ({k_oo.sum()}) vs veto={r_d[v_oo].mean():+.3f}R ({v_oo.sum()})")

    p_all = clf.predict_proba(X_d)[:, 1]
    df_d["p"] = p_all
    w_arr = np.array([1.0, 1.0, 0.90, 0.80, 0.60])
    thr_hi = float(np.quantile(p_all[ins], 0.65))

    m1a_p, tfs_p, df_p = build_kell_dataset_v6("pep")
    X_p = extract_kell_features_v6(df_p)
    df_p["p"] = clf.predict_proba(X_p)[:, 1]

    print("\n=== Joint Dukascopy (2017-2026) & Pepperstone (2023-2026) Threshold Verification ===")
    for q_htf in (0.12, 0.15, 0.18, 0.20):
        for q_m5 in (0.35, 0.38, 0.42):
            thr_htf = float(np.quantile(p_all[ins], q_htf))
            thr_m5 = float(np.quantile(p_all[ins], q_m5))

            sub_d = df_d[((df_d.stream < 4) & (df_d.p >= thr_htf)) | ((df_d.stream == 4) & (df_d.p >= thr_m5))].reset_index(drop=True)
            tk_gd, pr_gd, a1_gd, a2_gd, _ = portfolio_moonshot_nb(
                sub_d.j.values, sub_d.dir.values, sub_d.px.values, sub_d.R.values, sub_d.trail.values, sub_d.stream.values,
                m1a_d["t"], m1a_d["o"], m1a_d["h"], m1a_d["l"], m1a_d["c"], m1a_d["spr"], m1a_d["tday"], m1a_d["nydow"],
                3, 1, True, 1.5, 0.05, 2.75, 1.60, 1.0, 3.0, 7.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
            )
            mgd = tk_gd == 1
            sw_gd = w_arr[sub_d.stream.values[mgd]] * np.where(sub_d.p.values[mgd] >= thr_hi, 1.30, 1.0)
            tot_gd = (pr_gd[mgd] + a1_gd[mgd] + 0.5 * a2_gd[mgd]) * sw_gd
            by_ygd = pd.Series(tot_gd).groupby(sub_d.year.values[mgd]).sum()

            sub_p = df_p[((df_p.stream < 4) & (df_p.p >= thr_htf)) | ((df_p.stream == 4) & (df_p.p >= thr_m5))].reset_index(drop=True)
            tk_gp, pr_gp, a1_gp, a2_gp, _ = portfolio_moonshot_nb(
                sub_p.j.values, sub_p.dir.values, sub_p.px.values, sub_p.R.values, sub_p.trail.values, sub_p.stream.values,
                m1a_p["t"], m1a_p["o"], m1a_p["h"], m1a_p["l"], m1a_p["c"], m1a_p["spr"], m1a_p["tday"], m1a_p["nydow"],
                3, 1, True, 1.5, 0.05, 2.75, 1.60, 1.0, 3.0, 7.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
            )
            mgp = tk_gp == 1
            sw_gp = w_arr[sub_p.stream.values[mgp]] * np.where(sub_p.p.values[mgp] >= thr_hi, 1.30, 1.0)
            tot_gp = (pr_gp[mgp] + a1_gp[mgp] + 0.5 * a2_gp[mgp]) * sw_gp
            by_ygp = pd.Series(tot_gp).groupby(sub_p.year.values[mgp]).sum()

            print(f"q_htf={q_htf:.2f} q_m5={q_m5:.2f} | "
                  f"Duka Growth={tot_gd.sum():+5.1f}R ({int((by_ygd>0).sum())}/10) | "
                  f"Pep Growth={tot_gp.sum():+5.1f}R ({int((by_ygp>0).sum())}/4) [2024={by_ygp.get(2024,0):+.1f}R]")
