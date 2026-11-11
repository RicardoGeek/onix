"""Oliver Kell Study 2: Refining the 8 Oliver Kell Cycle Setups (True Tight-Box Base 'n Break,
Wedge Pop/Drop, EMA Crossback, Reversal/Exhaustion Extension) + Testing Oliver Kell Exit Rules
(Exhaustion Extension Ratchet + EMA 10/20 Crossback Trail vs Whale Trail) across 2017-2026.
"""
import os
import sys
import time
import numpy as np
import pandas as pd
from numba import njit

sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\16runes-ea\python_pipeline")
import sw_data as D
import sw_engine as E
import sw_mtf as M
from kell_study1 import SETUP_NAMES, RIBBON_7, build_kell_tfs, kell_events_nb
from runes_study2 import simulate_whale_nb


@njit(cache=True)
def detect_kell_v2_nb(o, h, l, c, v, ema10, ema20, vma20, atr, L, R, off_atr):
    """Causal Oliver Kell Cycle detector v2:
      0: BASE_N_BREAK_BULL  - Tight consolidation base (either fractal flat-top/asc base OR 5..14-bar tight box
                              with range <= 1.75*ATR) riding above rising 10/20 EMAs after an impulse leg.
      1: BASE_N_BREAK_BEAR  - Bearish tight consolidation base below falling 10/20 EMAs after a bearish impulse.
      2: WEDGE_POP_BULL     - Contracting wedge (symmetrical or descending apex w_b <= 0.82*w_a) popping above 10/20 EMAs.
      3: WEDGE_DROP_BEAR    - Contracting wedge popping/dropping below 10/20 EMAs.
      4: EMA_CROSSBACK_BULL - Bullish pullback that kisses the 10/20 EMA band after an impulse pole and coils in upper 80%.
      5: EMA_CROSSBACK_BEAR - Bearish rally that kisses the 10/20 EMA band after a bear impulse pole and coils in lower 80%.
      6: REV_EXT_POP_BULL   - Reversal Extension V-bottom / double-bottom / inv-H&S after stretch below EMA20, reclaiming EMA10.
      7: EXH_EXT_DROP_BEAR  - Exhaustion Extension V-top / double-top / H&S after stretch above EMA20, breaking below EMA10.
    """
    n = len(c)
    setup_id = np.full(n, -1, np.int64)
    s_dir = np.zeros(n, np.int64)
    trig_px = np.zeros(n, np.float64)
    sl_px = np.zeros(n, np.float64)
    base_h = np.zeros(n, np.float64)
    piv_idx = np.full(n, -1, np.int64)
    qual = np.zeros(n, np.float64)
    span_arr = np.zeros(n, np.int64)
    comp_rat = np.ones(n, np.float64)
    imp_val = np.zeros(n, np.float64)
    rel_vol = np.ones(n, np.float64)
    ema_ext = np.zeros(n, np.float64)

    sh_v = np.zeros(6, np.float64)
    sh_i = np.full(6, -1, np.int64)
    n_sh = 0
    sl_v = np.zeros(6, np.float64)
    sl_i = np.full(6, -1, np.int64)
    n_sl = 0

    for i in range(L + R + 36, n):
        p = i - R
        is_h = True
        is_l = True
        hp = h[p]
        lp = l[p]
        for q in range(p - L, p + R + 1):
            if q == p:
                continue
            if h[q] >= hp:
                is_h = False
            if l[q] <= lp:
                is_l = False
        if is_h:
            for k in range(5):
                sh_v[k] = sh_v[k + 1]
                sh_i[k] = sh_i[k + 1]
            sh_v[5] = hp
            sh_i[5] = p
            if n_sh < 6:
                n_sh += 1
        if is_l:
            for k in range(5):
                sl_v[k] = sl_v[k + 1]
                sl_i[k] = sl_i[k + 1]
            sl_v[5] = lp
            sl_i[5] = p
            if n_sl < 6:
                n_sl += 1

        if n_sh < 3 or n_sl < 3:
            continue

        a = atr[i]
        if a <= 1e-9:
            continue

        e10 = ema10[i]
        e20 = ema20[i]
        e20_prev = ema20[i - 3]
        bull_ema = (e10 >= e20 - 0.12 * a) and (e20 >= e20_prev - 0.05 * a)
        bear_ema = (e10 <= e20 + 0.12 * a) and (e20 <= e20_prev + 0.05 * a)

        h1, h2, h3 = sh_v[3], sh_v[4], sh_v[5]
        ih1, ih2, ih3 = sh_i[3], sh_i[4], sh_i[5]
        l1, l2, l3 = sl_v[3], sl_v[4], sl_v[5]
        il1, il2, il3 = sl_i[3], sl_i[4], sl_i[5]

        ha, hb = h2, h3
        iha, ihb = ih2, ih3
        la, lb = l2, l3
        ila, ilb = il2, il3

        v_rec = max(v[i], max(v[i - 1], v[i - 2]))
        rvol = v_rec / max(vma20[i], 1.0)

        best_s = -1
        best_d = 0
        best_trig = 0.0
        best_sl = 0.0
        best_h = 0.0
        best_piv = -1
        best_q = -1.0
        best_sp = 0
        best_cr = 1.0
        best_imp = 0.0

        # ------------------------------------------------------------------
        # A. 3-PIVOT REVERSAL EXTENSION (6: Bull Rev Ext, 7: Bear Exh Ext)
        # ------------------------------------------------------------------
        span3_l = il3 - il1
        if 8 <= span3_l <= 72 and (i - il3) <= 24:
            neck_h = -1e18
            neck_ih = -1
            for k in range(3, 6):
                if il1 < sh_i[k] < il3 and sh_v[k] > neck_h:
                    neck_h = sh_v[k]
                    neck_ih = sh_i[k]
            if neck_ih >= 0:
                unbroken_nh = True
                for q in range(neck_ih + 1, i + 1):
                    if h[q] > neck_h:
                        unbroken_nh = False
                        break
                min_l3 = min(l1, min(l2, l3))
                if unbroken_nh and (neck_h - min_l3) >= 0.85 * a:
                    # Either Inv H&S or Triple Bottom out of Reversal Extension
                    if (l2 <= min(l1, l3) - 0.20 * a and abs(l3 - l1) <= 0.85 * a) or (max(l1, max(l2, l3)) - min_l3 <= 0.60 * a):
                        qscore = 1.58 + 0.15 * ((neck_h - min_l3) / a)
                        if qscore > best_q:
                            best_s = 6; best_d = 1; best_trig = neck_h - off_atr * a
                            best_sl = min(l2, l3); best_h = neck_h - min_l3; best_piv = neck_ih
                            best_q = qscore; best_sp = span3_l; best_cr = (neck_h - l3) / max(neck_h - min_l3, 1e-6)
                            best_imp = (c[i] - c[max(0, il1 - 12)]) / a

        span3_h = ih3 - ih1
        if 8 <= span3_h <= 72 and (i - ih3) <= 24:
            neck_l = 1e18
            neck_il = -1
            for k in range(3, 6):
                if ih1 < sl_i[k] < ih3 and sl_v[k] < neck_l:
                    neck_l = sl_v[k]
                    neck_il = sl_i[k]
            if neck_il >= 0:
                unbroken_nl = True
                for q in range(neck_il + 1, i + 1):
                    if l[q] < neck_l:
                        unbroken_nl = False
                        break
                max_h3 = max(h1, max(h2, h3))
                if unbroken_nl and (max_h3 - neck_l) >= 0.85 * a:
                    if (h2 >= max(h1, h3) + 0.20 * a and abs(h3 - h1) <= 0.85 * a) or (max_h3 - min(h1, min(h2, h3)) <= 0.60 * a):
                        qscore = 1.58 + 0.15 * ((max_h3 - neck_l) / a)
                        if qscore > best_q:
                            best_s = 7; best_d = -1; best_trig = neck_l + off_atr * a
                            best_sl = max(h2, h3); best_h = max_h3 - neck_l; best_piv = neck_il
                            best_q = qscore; best_sp = span3_h; best_cr = (h3 - neck_l) / max(max_h3 - neck_l, 1e-6)
                            best_imp = (c[max(0, ih1 - 12)] - c[i]) / a

        # ------------------------------------------------------------------
        # B. 2-PIVOT STRUCTURAL KELL CYCLE SETUPS (0..7)
        # ------------------------------------------------------------------
        start2 = min(iha, ila)
        end2 = max(ihb, ilb)
        span2 = end2 - start2
        if 5 <= span2 <= 72 and (i - end2) <= 36:
            look_pre = max(0, start2 - 24)
            imp = (c[start2] - c[look_pre]) / a
            pole_lo = l[look_pre]
            pole_hi = h[look_pre]
            for q in range(look_pre, start2 + 1):
                if l[q] < pole_lo:
                    pole_lo = l[q]
                if h[q] > pole_hi:
                    pole_hi = h[q]
            bull_pole = (ha - pole_lo) / a
            bear_pole = (pole_hi - la) / a

            unbroken_hi_b = True
            coil_above_lb = True
            floor_coil = lb + 0.20 * (hb - lb)
            for q in range(ihb + 1, i + 1):
                if h[q] > hb:
                    unbroken_hi_b = False
                    break
                if l[q] < floor_coil:
                    coil_above_lb = False
            top2 = max(ha, hb)
            unbroken_top2 = True
            for q in range(ihb + 1, i + 1):
                if h[q] > top2:
                    unbroken_top2 = False
                    break

            unbroken_lo_b = True
            coil_below_hb = True
            ceil_coil = hb - 0.20 * (hb - lb)
            for q in range(ilb + 1, i + 1):
                if l[q] < lb:
                    unbroken_lo_b = False
                    break
                if h[q] > ceil_coil:
                    coil_below_hb = False
            bot2 = min(la, lb)
            unbroken_bot2 = True
            for q in range(ilb + 1, i + 1):
                if l[q] < bot2:
                    unbroken_bot2 = False
                    break

            dh = (hb - ha) / a
            dl = (lb - la) / a
            w_a = (ha - la) / a
            w_b = (hb - lb) / a
            cr2 = w_b / max(w_a, 1e-6)

            if w_a >= 0.70 and w_b >= 0.35:
                # 6/7: Double Bottom / Double Top Reversal Extension
                if ila < ihb < ilb and abs(dl) <= 0.45 and (hb - min(la, lb)) >= 0.90 * a and unbroken_hi_b:
                    qscore = 1.45 - 0.5 * abs(dl)
                    if qscore > best_q:
                        best_s = 6; best_d = 1; best_trig = hb - off_atr * a
                        best_sl = lb; best_h = hb - min(la, lb); best_piv = ihb
                        best_q = qscore; best_sp = span2; best_cr = cr2; best_imp = imp

                if iha < ilb < ihb and abs(dh) <= 0.45 and (max(ha, hb) - lb) >= 0.90 * a and unbroken_lo_b:
                    qscore = 1.45 - 0.5 * abs(dh)
                    if qscore > best_q:
                        best_s = 7; best_d = -1; best_trig = lb + off_atr * a
                        best_sl = hb; best_h = max(ha, hb) - lb; best_piv = ilb
                        best_q = qscore; best_sp = span2; best_cr = cr2; best_imp = -imp

                # 0/1: Base 'n Break (Horizontal / Ascending Triangle Base above 10/20 EMAs)
                if abs(dh) <= 0.40 and dl >= 0.20 and w_b < 0.90 * w_a and unbroken_top2 and coil_above_lb:
                    qscore = 1.42 - 0.5 * abs(dh) + 0.2 * min(dl, 2.0) + (0.08 if bull_ema else 0.0)
                    if qscore > best_q:
                        best_s = 0; best_d = 1; best_trig = top2 - off_atr * a
                        best_sl = lb; best_h = top2 - la; best_piv = ihb
                        best_q = qscore; best_sp = span2; best_cr = cr2; best_imp = imp

                if abs(dl) <= 0.40 and dh <= -0.20 and w_b < 0.90 * w_a and unbroken_bot2 and coil_below_hb:
                    qscore = 1.42 - 0.5 * abs(dl) + 0.2 * min(-dh, 2.0) + (0.08 if bear_ema else 0.0)
                    if qscore > best_q:
                        best_s = 1; best_d = -1; best_trig = bot2 + off_atr * a
                        best_sl = hb; best_h = ha - bot2; best_piv = ilb
                        best_q = qscore; best_sp = span2; best_cr = cr2; best_imp = -imp

                # 2/3: Wedge Pop / Wedge Drop (Symmetrical or Contracting Wedge)
                if dh <= -0.18 and dl >= 0.18 and w_b <= 0.80 * w_a:
                    sym_q = 1.32 + 0.3 * (1.0 - cr2)
                    if unbroken_hi_b and coil_above_lb and imp >= -0.2 and sym_q > best_q:
                        best_s = 2; best_d = 1; best_trig = hb - off_atr * a
                        best_sl = lb; best_h = ha - la; best_piv = ihb
                        best_q = sym_q; best_sp = span2; best_cr = cr2; best_imp = imp
                    if unbroken_lo_b and coil_below_hb and imp <= 0.2 and sym_q > best_q:
                        best_s = 3; best_d = -1; best_trig = lb + off_atr * a
                        best_sl = hb; best_h = ha - la; best_piv = ilb
                        best_q = sym_q; best_sp = span2; best_cr = cr2; best_imp = -imp

                # 4/5: EMA Crossback Flag & Falling/Rising Wedge Continuation
                if dh < -0.12 and dl < -0.02 and unbroken_hi_b and coil_above_lb:
                    slope_diff = abs((-dh) - (-dl))
                    if bull_pole >= 2.0 and slope_diff <= 0.70 and (ha - lb) <= 0.65 * (ha - pole_lo):
                        qscore = 1.38 + 0.15 * min(bull_pole, 5.0) - 0.3 * slope_diff
                        if qscore > best_q:
                            best_s = 4; best_d = 1; best_trig = hb - off_atr * a
                            best_sl = lb; best_h = ha - pole_lo; best_piv = ihb
                            best_q = qscore; best_sp = span2; best_cr = cr2; best_imp = imp
                    if (-dh) > (-dl) + 0.10 and w_b < 0.85 * w_a:
                        qscore = 1.28 + 0.3 * (1.0 - cr2)
                        if (imp >= 0.2 or w_b < 0.72 * w_a) and qscore > best_q:
                            best_s = 2; best_d = 1; best_trig = hb - off_atr * a
                            best_sl = lb; best_h = ha - lb; best_piv = ihb
                            best_q = qscore; best_sp = span2; best_cr = cr2; best_imp = imp

                if dh > 0.02 and dl > 0.12 and unbroken_lo_b and coil_below_hb:
                    slope_diff = abs(dl - dh)
                    if bear_pole >= 2.0 and slope_diff <= 0.70 and (hb - la) <= 0.65 * (pole_hi - la):
                        qscore = 1.38 + 0.15 * min(bear_pole, 5.0) - 0.3 * slope_diff
                        if qscore > best_q:
                            best_s = 5; best_d = -1; best_trig = lb + off_atr * a
                            best_sl = hb; best_h = pole_hi - la; best_piv = ilb
                            best_q = qscore; best_sp = span2; best_cr = cr2; best_imp = -imp
                    if dl > dh + 0.10 and w_b < 0.85 * w_a:
                        qscore = 1.28 + 0.3 * (1.0 - cr2)
                        if (imp <= -0.2 or w_b < 0.72 * w_a) and qscore > best_q:
                            best_s = 3; best_d = -1; best_trig = lb + off_atr * a
                            best_sl = hb; best_h = hb - la; best_piv = ilb
                            best_q = qscore; best_sp = span2; best_cr = cr2; best_imp = -imp

        # ------------------------------------------------------------------
        # C. COMPACT 6..12 BAR "BASE 'N BREAK" BOX ABOVE/BELOW 10 & 20 EMAS
        # (Matches the inset candlestick diagram on Oliver Kell's whiteboard!)
        # ------------------------------------------------------------------
        if best_s < 0:
            # Check compact 8-bar consolidation base after a strong 12-bar impulse above 10/20 EMAs
            box_len = 8
            b_start = i - box_len + 1
            box_hi = h[b_start]
            box_lo = l[b_start]
            hi_idx = b_start
            lo_idx = b_start
            for q in range(b_start + 1, i + 1):
                if h[q] > box_hi:
                    box_hi = h[q]
                    hi_idx = q
                if l[q] < box_lo:
                    box_lo = l[q]
                    lo_idx = q
            box_w = (box_hi - box_lo) / a
            # Must be a tight box (0.55 .. 1.65 ATR) where high was NOT made on current bar i
            if 0.55 <= box_w <= 1.65:
                pre_start = max(0, b_start - 14)
                pre_lo = l[pre_start]
                pre_hi = h[pre_start]
                for q in range(pre_start, b_start + 1):
                    if l[q] < pre_lo:
                        pre_lo = l[q]
                    if h[q] > pre_hi:
                        pre_hi = h[q]
                imp_up = (box_hi - pre_lo) / a
                imp_dn = (pre_hi - box_lo) / a
                # Bullish compact Base 'n Break: EMA10 > EMA20, box_lo holds near/above EMA20, current close in upper half of box
                if bull_ema and hi_idx < i and imp_up >= 2.2 and box_lo >= e20 - 0.35 * a and c[i] >= box_lo + 0.55 * (box_hi - box_lo):
                    best_s = 0; best_d = 1; best_trig = box_hi - off_atr * a
                    best_sl = box_lo; best_h = box_hi - box_lo; best_piv = hi_idx
                    best_q = 1.36 + 0.10 * min(imp_up, 4.0) - 0.20 * box_w
                    best_sp = box_len; best_cr = box_w / max(imp_up, 1.0); best_imp = imp_up
                elif bear_ema and lo_idx < i and imp_dn >= 2.2 and box_hi <= e20 + 0.35 * a and c[i] <= box_hi - 0.55 * (box_hi - box_lo):
                    best_s = 1; best_d = -1; best_trig = box_lo + off_atr * a
                    best_sl = box_hi; best_h = box_hi - box_lo; best_piv = lo_idx
                    best_q = 1.36 + 0.10 * min(imp_dn, 4.0) - 0.20 * box_w
                    best_sp = box_len; best_cr = box_w / max(imp_dn, 1.0); best_imp = imp_dn

        if best_s >= 0:
            setup_id[i] = best_s
            s_dir[i] = best_d
            trig_px[i] = best_trig
            sl_px[i] = best_sl
            base_h[i] = best_h
            piv_idx[i] = best_piv
            qual[i] = best_q
            span_arr[i] = best_sp
            comp_rat[i] = best_cr
            imp_val[i] = best_imp
            rel_vol[i] = min(max(rvol, 0.2), 5.0)
            ema_ext[i] = ((c[i] - e20) / a) * best_d

    return setup_id, s_dir, trig_px, sl_px, base_h, piv_idx, qual, span_arr, comp_rat, imp_val, rel_vol, ema_ext


if __name__ == "__main__":
    t0 = time.time()
    src = sys.argv[1] if len(sys.argv) > 1 else "duka"
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

    for tf_name, off in (("H1", 0.12), ("H2", 0.08), ("M30", 0.12), ("M15", 0.12), ("M5", 0.12)):
        T = tfs[tf_name]
        sid, sdir, tpx, slpx, bh, piv, qual, sp, cr, im, rv, ex = detect_kell_v2_nb(
            T["o"], T["h"], T["l"], T["c"], T["v"], T["ema10"], T["ema20"], T["vma20"], T["atr"], 3, 3, off
        )
        k_h4 = np.maximum(M.map_last_closed(tfs["H4"], T["t_close"]), 0)
        k_d1 = np.maximum(M.map_last_closed(tfs["D1"], T["t_close"]), 0)
        k_h1 = np.maximum(M.map_last_closed(tfs["H1"], T["t_close"]), 0)

        g_h4d1 = np.where(st["H4"][k_h4] == st["D1"][k_d1], st["H4"][k_h4], 0).astype(np.int64)
        g_h1h4d1 = np.where((st["H1"][k_h1] == st["H4"][k_h4]) & (st["H4"][k_h4] == st["D1"][k_d1]), st["H4"][k_h4], 0).astype(np.int64)
        g = g_h1h4d1 if tf_name in ("M5", "M15") else g_h4d1

        j, d, px, s_id, p_idx, sl_p, bh_p, q_p, sp_p, cr_p, im_p, rv_p, ex_p = kell_events_nb(
            sid, sdir, tpx, slpx, bh, piv, qual, sp, cr, im, rv, ex,
            T["atr"], g, T["m1s"], T["m1e"], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], 0.05, 3.0
        )
        if len(j) == 0:
            continue
        kh1 = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][j]), 0)
        at = a1[kh1]
        r_out, xt_out, mfe_out, wh_out = simulate_whale_nb(
            j, d, px, 1.5 * at, 2.0 * at,
            m1a["t"], m1a["o"], m1a["h"], m1a["l"], m1a["c"], m1a["spr"], m1a["tday"], m1a["nydow"],
            1.5, 0.05, 1.0, 3.0, 5.0, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
        )
        df = pd.DataFrame({"j": j, "dir": d, "r": r_out, "setup": s_id, "qual": q_p, "rvol": rv_p,
                           "entry_t": m1a["t"][j], "exit_t": xt_out, "whale": wh_out})
        df["year"] = pd.to_datetime(df["entry_t"], unit="s").dt.year
        df = df[df.year >= 2017]
        ins = df[df.year <= 2023]
        oos = df[df.year >= 2024]
        yr_all = df.groupby("year").r.sum()
        print(f"\n==================== Timeframe {tf_name} (Oliver Kell Cycle v2) ====================")
        print(f"  ALL SETUPS: n={len(df):5d}  wr={(df.r > 0).mean()*100:4.1f}%  avgR={df.r.mean():+.3f}  "
              f"2017-23={ins.r.sum():+6.1f}R ({ins.r.mean():+.3f}/tr)  "
              f"2024-26={oos.r.sum():+6.1f}R ({oos.r.mean():+.3f}/tr)  "
              f"green_yrs={int((yr_all > 0).sum())}/{len(yr_all)}")
        for s_k in range(8):
            sub = df[df.setup == s_k]
            if len(sub) > 0:
                s_in = sub[sub.year <= 2023]
                s_oo = sub[sub.year >= 2024]
                print(f"    [{s_k:2d}] {SETUP_NAMES[s_k]:20s}: n={len(sub):4d}  avgR={sub.r.mean():+.3f}  "
                      f"in={s_in.r.mean() if len(s_in) else 0:+.3f} ({len(s_in):3d})  "
                      f"oos={s_oo.r.mean() if len(s_oo) else 0:+.3f} ({len(s_oo):3d})")
    print(f"\nDone in {time.time() - t0:.1f}s")
