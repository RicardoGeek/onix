"""16Runes Study 9: Reserved-Slot Multi-Timeframe Hierarchy (M5 never blocks H1/H2/M30/M15) + Pepperstone Verification.

Rule:
- Streams 0..3 (H1, H2, M30, M15) can use any free slot up to max_slots, gated by ONNX Meta-Labeler p >= thr_main.
- Stream 4 (M5) can ONLY open when at least 1 slot remains free for H1/H2/M30/M15 (used_slots < max_slots - 1)
  AND its ONNX Meta-Labeler score p >= thr_m5.
"""
import os
import sys
import time
import numpy as np
import pandas as pd
from numba import njit

sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
from runes_study4 import build_dataset
from runes_study7 import extract_features, FEATS_16
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline


@njit(cache=True)
def portfolio_sim_reserved_nb(ej, ed, ep, eR, etrail, estream, erune,
                              mt, mo, mh, ml, mc, mspr, mtday, mdow,
                              max_slots, reserve_htf, pyramid, be_at_r, be_r, act_r, tp2_r,
                              whale_tp_r, whale_trail_mult, max_min, whale_min,
                              comm, slip_stop, slip_mkt, swap_l, swap_s):
    ne = len(ej)
    nm = len(mc)
    taken = np.zeros(ne, np.int64)
    out_r = np.zeros(ne, np.float64)
    out_add_r = np.zeros(ne, np.float64)
    out_xt = np.zeros(ne, np.int64)
    out_wh = np.zeros(ne, np.int64)

    slot_end = np.full(max_slots, -1, np.int64)
    slot_stm = np.full(max_slots, -1, np.int64)

    for e in range(ne):
        j = ej[e]
        if j >= nm:
            continue
        stm = estream[e]
        free_s = -1
        stm_busy = False
        used_cnt = 0
        for s in range(max_slots):
            if slot_end[s] < j:
                slot_end[s] = -1
                slot_stm[s] = -1
            if slot_stm[s] != -1:
                used_cnt += 1
            if slot_stm[s] == stm:
                stm_busy = True
            if slot_end[s] == -1 and free_s == -1:
                free_s = s
        if stm_busy or free_s == -1:
            continue
        # Reserved slot check: Stream 4 (M5) requires at least `reserve_htf` free slots left for H1/H2/M30/M15
        if stm == 4 and used_cnt >= (max_slots - reserve_htf):
            continue

        d = ed[e]; px0 = ep[e]; R = eR[e]; tdist = etrail[e]
        sl = px0 - d * R
        tp2 = px0 + d * tp2_r * R
        cur_max_min = max_min
        is_whale = False
        ext = px0; swap = 0.0; last_day = mtday[j]

        has_add = False
        add_open = False
        add_px0 = 0.0; add_sl = 0.0; add_tp = 0.0; add_ext = 0.0; add_tdist = 0.0
        add_realized = 0.0; add_swap = 0.0

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
                        add_sl = px0; add_tp = tp2; add_ext = add_px0; add_tdist = tdist
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


if __name__ == "__main__":
    m1a_d, tfs_d, df_d = build_dataset("duka")
    X_d = extract_features(df_d)
    r_d = df_d["r"].values
    yr_d = df_d["year"].values
    ins = yr_d <= 2023
    oos = yr_d >= 2024
    y_bin = (r_d > 0.0).astype(int)

    clf = Pipeline([("sc", StandardScaler()), ("lr", LogisticRegression(C=0.05, max_iter=500))])
    oof_p = np.zeros(len(df_d))
    for y_val in range(2017, 2024):
        tr_m = ins & (yr_d != y_val)
        va_m = (yr_d == y_val)
        clf.fit(X_d[tr_m], y_bin[tr_m])
        oof_p[va_m] = clf.predict_proba(X_d[va_m])[:, 1]
    clf.fit(X_d[ins], y_bin[ins])
    oof_p[oos] = clf.predict_proba(X_d[oos])[:, 1]
    df_d["p"] = oof_p

    thr15 = float(np.quantile(oof_p[ins], 0.15))
    thr45 = float(np.quantile(oof_p[ins], 0.45))
    thr50 = float(np.quantile(oof_p[ins], 0.50))
    print(f"Thresholds (from 2017-2023): thr15={thr15:.6f}, thr45={thr45:.6f}, thr50={thr50:.6f}")

    for m5_lbl, thr_m5 in [("M5>=q45", thr45), ("M5>=q50", thr50)]:
        sub = df_d[((df_d.stream < 4) & (df_d.p >= thr15)) | ((df_d.stream == 4) & (df_d.p >= thr_m5))].reset_index(drop=True)
        print(f"\n=======================================================")
        print(f"DUKASCOPY 2017-2026: 5 Streams (S0..3 >= q15, {m5_lbl}) + Reserved HTF Slot")
        for mode_nm, slots, res_htf, pyr in [
            ("Prop (2 slots, M5 reserves 1)", 2, 1, False),
            ("Prop (3 slots, M5 reserves 2)", 3, 2, False),
            ("Growth (3 slots, M5 reserves 1 + Pyramid)", 3, 1, True),
            ("Growth (4 slots, M5 reserves 2 + Pyramid)", 4, 2, True),
        ]:
            taken, pr_r, ad_r, xt, wh = portfolio_sim_reserved_nb(
                sub.j.values, sub.dir.values, sub.px.values, sub.R.values, sub.trail.values,
                sub.stream.values, sub.rune.values,
                m1a_d["t"], m1a_d["o"], m1a_d["h"], m1a_d["l"], m1a_d["c"], m1a_d["spr"], m1a_d["tday"], m1a_d["nydow"],
                slots, res_htf, pyr, 1.5, 0.05, 1.0, 3.0, 5.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
            )
            m = taken == 1
            tot_r = pr_r[m] + ad_r[m]
            adds = (ad_r[m] != 0).sum()
            yrs = sub.year.values[m]
            mi = yrs <= 2023
            mo_mask = yrs >= 2024
            by_y = pd.Series(tot_r).groupby(yrs).sum()
            print(f"  [{mode_nm:41s}]: probes={m.sum():4d} (+{adds:3d} adds)  "
                  f"2017-23={tot_r[mi].sum():+6.1f}R (avg={tot_r[mi].mean():+.3f}R, n={mi.sum():3d})  "
                  f"2024-26={tot_r[mo_mask].sum():+6.1f}R (avg={tot_r[mo_mask].mean():+.3f}R, n={mo_mask.sum():3d})  "
                  f"green_yrs={int((by_y > 0).sum())}/{len(by_y)}")
            print("    Years:", "  ".join(f"{y}:{v:+.1f}R" for y, v in by_y.items()))

    # Also test on Pepperstone 2023-2026 using the EXACT model & thresholds trained on Dukascopy 2017-2023!
    m1a_p, tfs_p, df_p = build_dataset("pep")
    X_p = extract_features(df_p)
    df_p["p"] = clf.predict_proba(X_p)[:, 1]
    sub_p = df_p[((df_p.stream < 4) & (df_p.p >= thr15)) | ((df_p.stream == 4) & (df_p.p >= thr45))].reset_index(drop=True)
    print(f"\n=======================================================")
    print(f"PEPPERSTONE 2023-2026 (Out-of-Sample Broker Feed): candidates={len(sub_p)}")
    for mode_nm, slots, res_htf, pyr in [
        ("Prop (3 slots, M5 reserves 2)", 3, 2, False),
        ("Growth (3 slots, M5 reserves 1 + Pyramid)", 3, 1, True),
    ]:
        taken, pr_r, ad_r, xt, wh = portfolio_sim_reserved_nb(
            sub_p.j.values, sub_p.dir.values, sub_p.px.values, sub_p.R.values, sub_p.trail.values,
            sub_p.stream.values, sub_p.rune.values,
            m1a_p["t"], m1a_p["o"], m1a_p["h"], m1a_p["l"], m1a_p["c"], m1a_p["spr"], m1a_p["tday"], m1a_p["nydow"],
            slots, res_htf, pyr, 1.5, 0.05, 1.0, 3.0, 5.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
        )
        m = taken == 1
        tot_r = pr_r[m] + ad_r[m]
        adds = (ad_r[m] != 0).sum()
        yrs = sub_p.year.values[m]
        by_y = pd.Series(tot_r).groupby(yrs).sum()
        print(f"  [{mode_nm:41s}]: probes={m.sum():4d} (+{adds:3d} adds)  "
              f"total={tot_r.sum():+6.1f}R (avg={tot_r.mean():+.3f}R)  green_yrs={int((by_y > 0).sum())}/{len(by_y)}")
        print("    Years:", "  ".join(f"{y}:{v:+.1f}R" for y, v in by_y.items()))
