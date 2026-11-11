"""16Runes Study 7: Meta-Labeler with U-shaped Volatility Squeeze/Expansion + Rune Geometry Features
+ Full Time-Ordered Multi-Position Portfolio Replay (2017-2026 Dukascopy & 2023-2026 Pepperstone).
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
from runes_study4 import detect_16runes_v4_nb, rune_events_v4_nb, STREAMS
from runes_study2 import simulate_whale_nb

FEATS_16 = [
    "f0_stream",           # 0..4 normalized (/4)
    "f1_dir",              # +1 or -1
    "f2_is_3piv",          # 1 if TRPL_BOTTOM, INV_HS, TRPL_TOP, HEAD_SHLDR
    "f3_is_asc_desc_tri",  # 1 if ASC_TRI or DESC_TRI
    "f4_is_sym_tri",       # 1 if BULL_SYM_TRI or BEAR_SYM_TRI
    "f5_is_flag",          # 1 if BULL_FLAG or BEAR_FLAG
    "f6_is_counter_wedge", # 1 if FALL_WEDGE (11) or RISE_WEDGE (15) or BEAR_FLAG (6) or DESC_TRI (4)
    "f7_qual",             # geometric quality score
    "f8_pat_h_atr",        # pattern height in structure ATRs
    "f9_comp_ratio",       # apex compression w_b / w_a
    "f10_imp_align",       # prior impulse aligned with trade direction
    "f11_vol_u",           # U-shaped volatility regime: |vol_reg - 1.0| (squeeze <0.85 or expansion >1.15)
    "f12_vol_reg",         # raw H1 volatility regime ATR14 / mean480(ATR14)
    "f13_cost_atr",        # cost / ATR14(H1)
    "f14_h4_rib_sp",       # H4 ribbon spread in H4 ATRs aligned with dir
    "f15_liq_sess",        # +1 London/NY (06-16 UTC), -0.5 Evening (17-22 UTC), 0 Asia
]


def extract_features(df):
    r_id = df["rune"].values
    d = df["dir"].values.astype(float)
    vol_reg = df["f11_vol_reg"].values
    X = np.column_stack([
        df["f0_stream"].values,
        d,
        np.isin(r_id, [9, 10, 13, 14]).astype(float),
        np.isin(r_id, [0, 4]).astype(float),
        np.isin(r_id, [3, 7]).astype(float),
        np.isin(r_id, [2, 6]).astype(float),
        np.isin(r_id, [4, 6, 11]).astype(float),
        df["f6_qual"].values,
        df["f7_pat_h_atr"].values,
        df["f8_comp_ratio"].values,
        df["f9_imp_align"].values,
        np.abs(vol_reg - 1.0),
        vol_reg,
        df["f12_cost_atr"].values,
        df["f14_h4_rib_sp"].values,
        df["f15_liq_sess"].values,
    ]).astype(np.float32)
    return X


@njit(cache=True)
def portfolio_sim_nb(ej, ed, ep, eR, etrail, estream, erune,
                     mt, mo, mh, ml, mc, mspr, mtday, mdow,
                     max_slots, pyramid, be_at_r, be_r, act_r, tp2_r, whale_tp_r, whale_trail_mult,
                     max_min, whale_min, comm, slip_stop, slip_mkt, swap_l, swap_s):
    """Time-ordered multi-position portfolio simulator (matches MQL5 Trader.mqh):
    - Up to max_slots concurrent probe positions (one per stream at a time).
    - Optional Whale Pyramid (in Growth mode): when a probe first reaches +be_at_r (1.5R), opens 1 add of same size
      with SL at probe's entry and TP at whale_tp_r (5.0R).
    - Returns taken mask, net R (including any pyramid add R on that probe), exit_t, is_whale, add_r.
    """
    ne = len(ej)
    nm = len(mc)
    taken = np.zeros(ne, np.int64)
    out_r = np.zeros(ne, np.float64)
    out_add_r = np.zeros(ne, np.float64)
    out_xt = np.zeros(ne, np.int64)
    out_wh = np.zeros(ne, np.int64)

    # Active slots tracking: exit bar index, stream id
    slot_end = np.full(max_slots, -1, np.int64)
    slot_stm = np.full(max_slots, -1, np.int64)

    for e in range(ne):
        j = ej[e]
        if j >= nm:
            continue
        stm = estream[e]
        # Free expired slots and check if stream is already open
        free_s = -1
        stm_busy = False
        for s in range(max_slots):
            if slot_end[s] < j:
                slot_end[s] = -1
                slot_stm[s] = -1
            if slot_stm[s] == stm:
                stm_busy = True
            if slot_end[s] == -1 and free_s == -1:
                free_s = s
        if stm_busy or free_s == -1:
            continue

        # Simulate probe (+ optional whale add) on M1 bars
        d = ed[e]; px0 = ep[e]; R = eR[e]; tdist = etrail[e]
        sl = px0 - d * R
        tp2 = px0 + d * tp2_r * R
        cur_max_min = max_min
        is_whale = False
        ext = px0; swap = 0.0; last_day = mtday[j]

        # Add state
        has_add = False
        add_open = False
        add_px0 = 0.0
        add_sl = 0.0
        add_tp = 0.0
        add_ext = 0.0
        add_tdist = 0.0
        add_realized = 0.0
        add_swap = 0.0

        realized = 0.0
        pos = 1.0
        k = j
        while k < nm:
            if mtday[k] != last_day:
                mult = 3.0 if mdow[k] == 2 else 1.0
                swap += pos * (swap_l if d == 1 else swap_s) * mult
                if add_open:
                    add_swap += 1.0 * (swap_l if d == 1 else swap_s) * mult
                last_day = mtday[k]
            sp = mspr[k]
            if d == 1:
                o_ = mo[k]; h_ = mh[k]; l_ = ml[k]; c_ = mc[k]
            else:
                o_ = mo[k] + sp; h_ = mh[k] + sp; l_ = ml[k] + sp; c_ = mc[k] + sp
            adverse = l_ if d == 1 else h_
            favor = h_ if d == 1 else l_

            # Check add stop/target if add_open
            if add_open:
                if d * (o_ - add_sl) <= 0:
                    px = o_ - d * slip_stop
                    add_realized += d * (px - add_px0); add_open = False
                elif d * (adverse - add_sl) <= 0:
                    px = add_sl - d * slip_stop
                    add_realized += d * (px - add_px0); add_open = False
                elif d * (favor - add_tp) >= 0:
                    add_realized += d * (add_tp - add_px0); add_open = False
                else:
                    if d * (favor - add_ext) > 0:
                        add_ext = favor
                    if d * (add_ext - add_px0) >= act_r * R and add_tdist > 0:
                        alvl = add_ext - d * add_tdist
                        if d * (alvl - add_sl) > 0 and d * (c_ - alvl) > 0:
                            add_sl = alvl

            # Check probe stop
            if k > j and d * (o_ - sl) <= 0:
                px = o_ - d * slip_stop
                realized += pos * d * (px - px0); pos = 0.0
                break
            if d * (adverse - sl) <= 0:
                px = sl - d * slip_stop
                realized += pos * d * (px - px0); pos = 0.0
                break
            if k > j:
                if (not is_whale) and d * (favor - px0) >= be_at_r * R:
                    is_whale = True
                    nsl = px0 + d * be_r * R
                    if d * (nsl - sl) > 0:
                        sl = nsl
                    tp2 = px0 + d * whale_tp_r * R
                    tdist = tdist * whale_trail_mult
                    cur_max_min = whale_min
                    if pyramid and (not has_add):
                        has_add = True
                        add_open = True
                        add_px0 = (px0 + d * be_at_r * R) + d * slip_mkt
                        add_sl = px0
                        add_tp = tp2
                        add_ext = add_px0
                        add_tdist = tdist
                if tp2_r > 0 and d * (favor - tp2) >= 0:
                    realized += pos * d * (tp2 - px0); pos = 0.0
                    break
                if d * (favor - ext) > 0:
                    ext = favor
            if d * (ext - px0) >= act_r * R and tdist > 0:
                lvl = ext - d * tdist
                if d * (lvl - sl) > 0 and d * (c_ - lvl) > 0:
                    sl = lvl
            if cur_max_min > 0 and (mt[k] - mt[j]) >= cur_max_min * 60:
                if k + 1 < nm:
                    k += 1
                    px = (mo[k] - slip_mkt) if d == 1 else (mo[k] + mspr[k] + slip_mkt)
                    realized += pos * d * (px - px0); pos = 0.0
                    if add_open:
                        add_realized += d * (px - add_px0); add_open = False
                break
            k += 1
        if pos > 0:
            k = min(k, nm - 1)
            realized += pos * d * (mc[k] - px0)
        if add_open:
            k2 = min(k, nm - 1)
            add_realized += d * (mc[k2] - add_px0)
            add_open = False

        taken[e] = 1
        out_r[e] = (realized - comm + swap) / R
        if has_add:
            out_add_r[e] = (add_realized - comm + add_swap) / R
        out_xt[e] = mt[min(k, nm - 1)]
        out_wh[e] = 1 if is_whale else 0
        slot_end[free_s] = k
        slot_stm[free_s] = stm

    return taken, out_r, out_add_r, out_xt, out_wh


from runes_study4 import build_dataset

if __name__ == "__main__":
    m1a_d, tfs_d, df_d = build_dataset("duka")
    X = extract_features(df_d)
    r = df_d["r"].values
    yr = df_d["year"].values
    ins = yr <= 2023
    oos = yr >= 2024

    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
    from sklearn.pipeline import Pipeline
    import lightgbm as lgb

    y_bin = (r > 0.0).astype(int)
    for name, clf in [
        ("LogReg C=0.05 (16 feats)", Pipeline([("sc", StandardScaler()), ("lr", LogisticRegression(C=0.05, max_iter=500))])),
        ("LGBM leaves=5 min_leaf=70 reg=30", lgb.LGBMClassifier(
            n_estimators=55, learning_rate=0.03, num_leaves=5, min_child_samples=70,
            subsample=0.8, colsample_bytree=0.75, reg_lambda=30.0, random_state=42, verbose=-1
        )),
        ("LGBM leaves=6 min_leaf=60 reg=25", lgb.LGBMClassifier(
            n_estimators=60, learning_rate=0.03, num_leaves=6, min_child_samples=60,
            subsample=0.8, colsample_bytree=0.75, reg_lambda=25.0, random_state=42, verbose=-1
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
        for q in (0.15, 0.20, 0.25, 0.30):
            thr = np.quantile(oof_p[ins], q)
            keep_in = ins & (oof_p >= thr)
            veto_in = ins & (oof_p < thr)
            keep_oo = oos & (oof_p >= thr)
            veto_oo = oos & (oof_p < thr)
            print(f"  veto q={q:.2f} (thr={thr:.4f}): "
                  f"2017-23 CV kept={r[keep_in].mean():+.3f}R ({keep_in.sum()}, sum={r[keep_in].sum():+.1f}R) "
                  f"vs vetoed={r[veto_in].mean():+.3f}R ({veto_in.sum()}) | "
                  f"2024-26 OOS kept={r[keep_oo].mean():+.3f}R ({keep_oo.sum()}, sum={r[keep_oo].sum():+.1f}R) "
                  f"vs vetoed={r[veto_oo].mean():+.3f}R ({veto_oo.sum()})")

    # Now test the best LGBM Meta-Labeler at q=0.20 in a Time-Ordered Portfolio Replay (Prop 2 slots vs Growth 3 slots + Pyramid)
    clf = lgb.LGBMClassifier(
        n_estimators=55, learning_rate=0.03, num_leaves=5, min_child_samples=70,
        subsample=0.8, colsample_bytree=0.75, reg_lambda=30.0, random_state=42, verbose=-1
    )
    oof_p = np.zeros(len(df_d))
    for y_val in range(2017, 2024):
        tr_m = ins & (yr != y_val)
        va_m = (yr == y_val)
        clf.fit(X[tr_m], y_bin[tr_m])
        oof_p[va_m] = clf.predict_proba(X[va_m])[:, 1]
    clf.fit(X[ins], y_bin[ins])
    oof_p[oos] = clf.predict_proba(X[oos])[:, 1]
    thr = np.quantile(oof_p[ins], 0.20)

    for label, sub in [("ALL (No Veto)", df_d), ("AI Veto q=0.20", df_d[oof_p >= thr].reset_index(drop=True))]:
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
            print(f"\nPortfolio [{label} | {mode_nm}]:")
            print(f"  Total probes={m.sum()}  2017-23 sumR={tot_r[mi].sum():+6.1f}R (avg={tot_r[mi].mean():+.3f}R, n={mi.sum()})  "
                  f"2024-26 sumR={tot_r[mo_mask].sum():+6.1f}R (avg={tot_r[mo_mask].mean():+.3f}R, n={mo_mask.sum()})  "
                  f"green_yrs={int((by_y > 0).sum())}/{len(by_y)}")
            print("  Per-year R:", "  ".join(f"{y}:{v:+.1f}R" for y, v in by_y.items()))
