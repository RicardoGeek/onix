"""16Runes Study 10: Moonshot Optimization (2-Stage Whale Pyramid + Extended Tail + ONNX Conviction Boost).

Tests across 10 years (2017-2023 Train/Seen vs 2024-2026 Unseen OOS on Dukascopy & Pepperstone):
1. Baseline v1.00 Growth (1 Add at +1.5R, 5.0R Whale TP).
2. 2-Stage Whale Pyramid:
   - Stage 1 (+1.5R): Probe SL -> BE+0.05R, open Add #1 (SL at Probe entry 0.0R).
   - Stage 2 (+2.75R): Probe SL & Add #1 SL -> +1.55R, open Add #2 (SL at +1.50R).
   - Extended Whale TP: 5.0R vs 6.0R vs 7.0R vs 8.0R.
3. ONNX Conviction Multiplier:
   - High-conviction setups (p >= q65 of 2017-2023 training distribution) boosted by 1.30x.
"""
import os
import sys
import numpy as np
import pandas as pd
import onnxruntime as ort
from numba import njit

sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
from runes_study4 import build_dataset
from runes_study7 import extract_features

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ONNX_PATH = os.path.join(ROOT, "MQL5", "Files", "models", "16runes_meta.onnx")


@njit(cache=True)
def portfolio_moonshot_nb(ej, ed, ep, eR, etrail, estream,
                          mt, mo, mh, ml, mc, mspr, mtday, mdow,
                          max_slots, reserve_htf, two_stage_pyr,
                          be_at_r, be_r, pyr2_at_r, pyr2_lock_r,
                          act_r, tp2_r, whale_tp_r, whale_trail_mult,
                          max_min, whale_min, comm, slip_stop, slip_mkt, swap_l, swap_s):
    ne = len(ej)
    nm = len(mc)
    taken = np.zeros(ne, np.int64)
    out_r = np.zeros(ne, np.float64)
    out_add1_r = np.zeros(ne, np.float64)
    out_add2_r = np.zeros(ne, np.float64)
    out_xt = np.zeros(ne, np.int64)

    slot_end = np.full(max_slots, -1, np.int64)
    slot_stm = np.full(max_slots, -1, np.int64)

    for e in range(ne):
        j = ej[e]
        if j >= nm:
            continue
        stm = estream[e]
        free_s = -1
        stm_busy = False
        open_cnt = 0
        for s in range(max_slots):
            if slot_end[s] < j:
                slot_end[s] = -1
                slot_stm[s] = -1
            else:
                open_cnt += 1
            if slot_stm[s] == stm:
                stm_busy = True
            if slot_end[s] == -1 and free_s == -1:
                free_s = s
        if stm_busy or free_s == -1:
            continue
        if stm == 4 and open_cnt >= (max_slots - reserve_htf):
            continue

        d = ed[e]; px0 = ep[e]; R = eR[e]; tdist = etrail[e]
        sl = px0 - d * R
        tp2 = px0 + d * tp2_r * R
        cur_max_min = max_min
        is_whale = False
        ext = px0; swap = 0.0; last_day = mtday[j]

        has_add1 = False; add1_open = False
        add1_px0 = 0.0; add1_sl = 0.0; add1_tp = 0.0; add1_ext = 0.0; add1_tdist = 0.0
        add1_realized = 0.0; add1_swap = 0.0

        has_add2 = False; add2_open = False
        add2_px0 = 0.0; add2_sl = 0.0; add2_tp = 0.0; add2_ext = 0.0; add2_tdist = 0.0
        add2_realized = 0.0; add2_swap = 0.0

        realized = 0.0
        pos = 1.0
        k = j
        while k < nm:
            if mtday[k] != last_day:
                mult = 3.0 if mdow[k] == 2 else 1.0
                swap += pos * (swap_l if d == 1 else swap_s) * mult
                if add1_open:
                    add1_swap += 1.0 * (swap_l if d == 1 else swap_s) * mult
                if add2_open:
                    add2_swap += 1.0 * (swap_l if d == 1 else swap_s) * mult
                last_day = mtday[k]
            sp = mspr[k]
            if d == 1:
                o_ = mo[k]; h_ = mh[k]; l_ = ml[k]; c_ = mc[k]
            else:
                o_ = mo[k] + sp; h_ = mh[k] + sp; l_ = ml[k] + sp; c_ = mc[k] + sp
            adverse = l_ if d == 1 else h_
            favor = h_ if d == 1 else l_

            if add2_open:
                if d * (o_ - add2_sl) <= 0:
                    px = o_ - d * slip_stop
                    add2_realized += d * (px - add2_px0); add2_open = False
                elif d * (adverse - add2_sl) <= 0:
                    px = add2_sl - d * slip_stop
                    add2_realized += d * (px - add2_px0); add2_open = False
                elif d * (favor - add2_tp) >= 0:
                    add2_realized += d * (add2_tp - add2_px0); add2_open = False
                else:
                    if d * (favor - add2_ext) > 0:
                        add2_ext = favor
                    if d * (add2_ext - add2_px0) >= act_r * R and add2_tdist > 0:
                        alvl2 = add2_ext - d * add2_tdist
                        if d * (alvl2 - add2_sl) > 0 and d * (c_ - alvl2) > 0:
                            add2_sl = alvl2

            if add1_open:
                if d * (o_ - add1_sl) <= 0:
                    px = o_ - d * slip_stop
                    add1_realized += d * (px - add1_px0); add1_open = False
                elif d * (adverse - add1_sl) <= 0:
                    px = add1_sl - d * slip_stop
                    add1_realized += d * (px - add1_px0); add1_open = False
                elif d * (favor - add1_tp) >= 0:
                    add1_realized += d * (add1_tp - add1_px0); add1_open = False
                else:
                    if d * (favor - add1_ext) > 0:
                        add1_ext = favor
                    if d * (add1_ext - add1_px0) >= act_r * R and add1_tdist > 0:
                        alvl1 = add1_ext - d * add1_tdist
                        if d * (alvl1 - add1_sl) > 0 and d * (c_ - alvl1) > 0:
                            add1_sl = alvl1

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
                    if not has_add1:
                        has_add1 = True
                        add1_open = True
                        add1_px0 = (px0 + d * be_at_r * R) + d * slip_mkt
                        add1_sl = px0
                        add1_tp = tp2
                        add1_ext = add1_px0
                        add1_tdist = tdist
                if two_stage_pyr and is_whale and (not has_add2) and d * (favor - px0) >= pyr2_at_r * R:
                    has_add2 = True
                    lock_px = px0 + d * pyr2_lock_r * R
                    if d * (lock_px - sl) > 0:
                        sl = lock_px
                    if add1_open and d * (lock_px - add1_sl) > 0:
                        add1_sl = lock_px
                    add2_open = True
                    add2_px0 = (px0 + d * pyr2_at_r * R) + d * slip_mkt
                    add2_sl = px0 + d * be_at_r * R
                    add2_tp = tp2
                    add2_ext = add2_px0
                    add2_tdist = tdist
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
                    if add1_open:
                        add1_realized += d * (px - add1_px0); add1_open = False
                    if add2_open:
                        add2_realized += d * (px - add2_px0); add2_open = False
                break
            k += 1
        if pos > 0:
            k = min(k, nm - 1)
            realized += pos * d * (mc[k] - px0)
        if add1_open:
            k2 = min(k, nm - 1)
            add1_realized += d * (mc[k2] - add1_px0)
        if add2_open:
            k2 = min(k, nm - 1)
            add2_realized += d * (mc[k2] - add2_px0)

        taken[e] = 1
        out_r[e] = (realized - comm + swap) / R
        if has_add1:
            out_add1_r[e] = (add1_realized - comm + add1_swap) / R
        if has_add2:
            out_add2_r[e] = (add2_realized - comm + add2_swap) / R
        out_xt[e] = mt[min(k, nm - 1)]
        slot_end[free_s] = k
        slot_stm[free_s] = stm

    return taken, out_r, out_add1_r, out_add2_r, out_xt


if __name__ == "__main__":
    m1a_d, tfs_d, df_d = build_dataset("duka")
    X = extract_features(df_d)
    sess = ort.InferenceSession(ONNX_PATH)
    p = np.array([sess.run(None, {"input": X[i:i + 1].astype(np.float32)})[1][0, 1] for i in range(len(X))])
    df_d["p"] = p

    ins = df_d.year.values <= 2023
    thr_htf = float(np.quantile(p[ins], 0.12))
    thr_m5 = float(np.quantile(p[ins], 0.35))
    thr_hi = float(np.quantile(p[ins], 0.65))
    print(f"Thresholds (from 2017-2023): thr_htf={thr_htf:.6f}, thr_m5={thr_m5:.6f}, thr_hi(q65)={thr_hi:.6f}")

    sub = df_d[((df_d.stream < 4) & (df_d.p >= thr_htf)) | ((df_d.stream == 4) & (df_d.p >= thr_m5))].reset_index(drop=True)
    w_arr = np.array([1.0, 1.0, 0.90, 0.80, 0.60])

    for label, two_st, wtp, hi_mult in [
        ("v1.00 Baseline (1-Add, 5R TP, flat weight)", False, 5.0, 1.00),
        ("1-Add, 6R Whale TP, flat weight",            False, 6.0, 1.00),
        ("1-Add, 7R Whale TP, flat weight",            False, 7.0, 1.00),
        ("2-Stage Pyramid (+1.5R & +2.75R), 6R TP",    True,  6.0, 1.00),
        ("2-Stage Pyramid (+1.5R & +2.75R), 7R TP",    True,  7.0, 1.00),
        ("2-Stage Pyramid (+1.5R & +2.75R), 8R TP",    True,  8.0, 1.00),
        ("2-Stage Pyramid, 7R TP + AI Tier Boost 1.3x", True, 7.0, 1.30),
    ]:
        taken, pr_r, a1_r, a2_r, xt = portfolio_moonshot_nb(
            sub.j.values, sub.dir.values, sub.px.values, sub.R.values, sub.trail.values, sub.stream.values,
            m1a_d["t"], m1a_d["o"], m1a_d["h"], m1a_d["l"], m1a_d["c"], m1a_d["spr"], m1a_d["tday"], m1a_d["nydow"],
            3, 1, two_st, 1.5, 0.05, 2.75, 1.55, 1.0, 3.0, wtp, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
        )
        m = taken == 1
        sw = w_arr[sub.stream.values[m]]
        if hi_mult != 1.0:
            conv = np.where(sub.p.values[m] >= thr_hi, hi_mult, 1.0)
            sw = sw * conv
        # Note: in v1.00, Add1 was accidentally 0.67x; in Moonshot, Add1 and Add2 are full 1.0x!
        tot_r = (pr_r[m] + a1_r[m] + a2_r[m]) * sw
        yrs = sub.year.values[m]
        mi = yrs <= 2023
        mo = yrs >= 2024
        by_y = pd.Series(tot_r).groupby(yrs).sum()
        print(f"\n[{label}]")
        print(f"  2017-23: {tot_r[mi].sum():+6.1f}R  |  2024-26 OOS: {tot_r[mo].sum():+6.1f}R  |  Total: {tot_r.sum():+6.1f}R  |  Green yrs: {int((by_y>0).sum())}/10")
        print("  Years:", "  ".join(f"{y}:{v:+.1f}R" for y, v in by_y.items()))
