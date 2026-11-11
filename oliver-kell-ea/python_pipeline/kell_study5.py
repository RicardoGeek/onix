"""Oliver Kell Study 5: Clean 16-Feature Vector + Threshold & Exhaustion-Extension / Scale-In Optimization
across 10-Year Dukascopy (2017-2023 Train vs 2024-2026 Unseen OOS) and Pepperstone (2023-2026).
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
    "f2_is_base_n_break",   # 1 if BASE_N_BREAK_BULL (0) or BASE_N_BREAK_BEAR (1)
    "f3_is_wedge_pop_drop", # 1 if WEDGE_POP_BULL (2) or WEDGE_DROP_BEAR (3)
    "f4_is_ema_crossback",  # 1 if EMA_CROSSBACK_BULL (4) or EMA_CROSSBACK_BEAR (5)
    "f5_is_rev_exh_ext",    # 1 if REV_EXT_POP_BULL (6) or EXH_EXT_DROP_BEAR (7)
    "f6_is_bear_cont",      # 1 if BASE_N_BREAK_BEAR (1) or EMA_CROSSBACK_BEAR (5)
    "f7_qual",              # geometric quality score
    "f8_base_h_atr",        # base height in structure ATRs
    "f9_comp_ratio",        # base compression ratio w_b / w_a
    "f10_imp_align",        # prior impulse aligned with trade direction
    "f11_rel_vol_ema",      # breakout volume ratio + EMA20 extension composite
    "f12_vol_u",            # U-shaped H1 volatility squeeze/expansion |vol_reg - 1.0|
    "f13_vol_reg",          # H1 volatility regime ATR14 / mean480(ATR14)
    "f14_cost_atr",         # spread/cost / ATR14(H1)
    "f15_h4_rib_liq",       # H4 trend spread in H4 ATRs aligned with dir + session liquidity
]


def build_kell_dataset_v5(src="duka"):
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
            "f2_is_base_n_break": np.isin(setup_k, [0, 1]).astype(float),
            "f3_is_wedge_pop_drop": np.isin(setup_k, [2, 3]).astype(float),
            "f4_is_ema_crossback": np.isin(setup_k, [4, 5]).astype(float),
            "f5_is_rev_exh_ext": np.isin(setup_k, [6, 7]).astype(float),
            "f6_is_bear_cont": np.isin(setup_k, [1, 5]).astype(float),
            "f7_qual": q_p,
            "f8_base_h_atr": np.clip(bh_p, 0.5, 10.0),
            "f9_comp_ratio": np.clip(cr_p, 0.2, 1.2),
            "f10_imp_align": np.clip(im_p, -6.0, 6.0),
            "f11_rel_vol_ema": np.clip(rv_p, 0.2, 5.0),
            "f12_vol_u": np.abs(vol_reg_h1[kh1] - 1.0),
            "f13_vol_reg": vol_reg_h1[kh1],
            "f14_cost_atr": np.clip(cost_est / np.maximum(at, 1e-6), 0.0, 0.5),
            "f15_h4_rib_liq": liq_sess,
            "h4_rib_sp": np.clip(h4_sp[kh4] * d, -6.0, 6.0),
            "ema_ext": np.clip(ex_p, -4.0, 4.0),
        })
        rows.append(df_s)

    df = pd.concat(rows, ignore_index=True)
    df = df.sort_values(["j", "stream"]).drop_duplicates(subset=["j"], keep="first").reset_index(drop=True)
    df["year"] = pd.to_datetime(df["t"], unit="s").dt.year
    df = df[df["year"] >= 2017].reset_index(drop=True)
    return m1a, tfs, df


if __name__ == "__main__":
    from kell_study4 import build_kell_dataset, extract_kell_features

    m1a_d, tfs_d, df_d = build_kell_dataset("duka", use_v4=True)
    X_d = extract_kell_features(df_d)
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
    p_all = clf.predict_proba(X_d)[:, 1]
    df_d["p"] = p_all

    w_arr = np.array([1.0, 1.0, 0.90, 0.80, 0.60])
    thr_hi = float(np.quantile(p_all[ins], 0.65))

    print("=== Threshold Grid Search on 2017-2023 (Evaluated on 2017-23 & Unseen 2024-26) ===")
    for q_htf in (0.12, 0.15, 0.18, 0.20):
        for q_m5 in (0.32, 0.35, 0.38, 0.42):
            thr_htf = float(np.quantile(p_all[ins], q_htf))
            thr_m5 = float(np.quantile(p_all[ins], q_m5))
            sub = df_d[((df_d.stream < 4) & (df_d.p >= thr_htf)) | ((df_d.stream == 4) & (df_d.p >= thr_m5))].reset_index(drop=True)

            # Prop
            tk_p, pr_p, a1_p, a2_p, _ = portfolio_moonshot_nb(
                sub.j.values, sub.dir.values, sub.px.values, sub.R.values, sub.trail.values, sub.stream.values,
                m1a_d["t"], m1a_d["o"], m1a_d["h"], m1a_d["l"], m1a_d["c"], m1a_d["spr"], m1a_d["tday"], m1a_d["nydow"],
                3, 2, False, 1.5, 0.05, 2.75, 1.60, 1.0, 3.0, 5.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
            )
            mp = tk_p == 1
            sw_p = w_arr[sub.stream.values[mp]] * np.where(sub.p.values[mp] >= thr_hi, 1.15, 1.0)
            tot_p = pr_p[mp] * sw_p
            by_yp = pd.Series(tot_p).groupby(sub.year.values[mp]).sum()

            # Growth Moonshot
            tk_g, pr_g, a1_g, a2_g, _ = portfolio_moonshot_nb(
                sub.j.values, sub.dir.values, sub.px.values, sub.R.values, sub.trail.values, sub.stream.values,
                m1a_d["t"], m1a_d["o"], m1a_d["h"], m1a_d["l"], m1a_d["c"], m1a_d["spr"], m1a_d["tday"], m1a_d["nydow"],
                3, 1, True, 1.5, 0.05, 2.75, 1.60, 1.0, 3.0, 7.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
            )
            mg = tk_g == 1
            sw_g = w_arr[sub.stream.values[mg]] * np.where(sub.p.values[mg] >= thr_hi, 1.30, 1.0)
            tot_g = (pr_g[mg] + a1_g[mg] + 0.5 * a2_g[mg]) * sw_g
            by_yg = pd.Series(tot_g).groupby(sub.year.values[mg]).sum()

            yrs_g = sub.year.values[mg]
            print(f"q_htf={q_htf:.2f}({thr_htf:.4f}) q_m5={q_m5:.2f}({thr_m5:.4f}) | "
                  f"Prop: {tot_p.sum():+5.1f}R (green={int((by_yp>0).sum())}/10) | "
                  f"Growth: 17-23={tot_g[yrs_g<=2023].sum():+5.1f}R, 24-26={tot_g[yrs_g>=2024].sum():+5.1f}R, "
                  f"Tot={tot_g.sum():+5.1f}R (green={int((by_yg>0).sum())}/10)")

    # Also test on Pepperstone 2023-2026
    print("\n=== Pepperstone (2023-2026) Out-of-Sample Verification ===")
    m1a_p, tfs_p, df_p = build_kell_dataset("pep", use_v4=True)
    X_p = extract_kell_features(df_p)
    df_p["p"] = clf.predict_proba(X_p)[:, 1]
    thr_htf = float(np.quantile(p_all[ins], 0.12))
    thr_m5 = float(np.quantile(p_all[ins], 0.35))
    sub_p = df_p[((df_p.stream < 4) & (df_p.p >= thr_htf)) | ((df_p.stream == 4) & (df_p.p >= thr_m5))].reset_index(drop=True)
    tk_g, pr_g, a1_g, a2_g, _ = portfolio_moonshot_nb(
        sub_p.j.values, sub_p.dir.values, sub_p.px.values, sub_p.R.values, sub_p.trail.values, sub_p.stream.values,
        m1a_p["t"], m1a_p["o"], m1a_p["h"], m1a_p["l"], m1a_p["c"], m1a_p["spr"], m1a_p["tday"], m1a_p["nydow"],
        3, 1, True, 1.5, 0.05, 2.75, 1.60, 1.0, 3.0, 7.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
    )
    mg = tk_g == 1
    sw_g = w_arr[sub_p.stream.values[mg]] * np.where(sub_p.p.values[mg] >= thr_hi, 1.30, 1.0)
    tot_g = (pr_g[mg] + a1_g[mg] + 0.5 * a2_g[mg]) * sw_g
    by_yg = pd.Series(tot_g).groupby(sub_p.year.values[mg]).sum()
    print(f"Pepperstone Growth Moonshot (2023-2026): probes={mg.sum()} | Total={tot_g.sum():+.1f}R | Green={int((by_yg>0).sum())}/{len(by_yg)}")
    print("  Years:", "  ".join(f"{y}:{v:+.1f}R" for y, v in by_yg.items()))
