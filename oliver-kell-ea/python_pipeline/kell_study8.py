"""Oliver Kell Study 8b: Final Verification of detect_kell_v4_nb (Rising/Flat Base 'n Break + EMA10 Reclaim)
and 16-Feature ONNX Meta-Labeler across Dukascopy (2017-2026) and Pepperstone (2023-2026).
"""
import os
import sys
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
from kell_study4 import STREAMS
from runes_study2 import simulate_whale_nb
from runes_study10_moonshot import portfolio_moonshot_nb

KELL_FEATS_16 = [
    "f0_stream",            # 0..4 normalized (/4)
    "f1_dir",               # +1 or -1
    "f2_is_3piv_rev",       # 1 if 3-pivot Reversal/Exhaustion Extension (Inv H&S, Triple Bot/Top, H&S)
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
    "f15_h4_rib_sp",        # H4 7-EMA ribbon spread in H4 ATRs aligned with dir (+ session liquidity)
]


@njit(cache=True)
def detect_kell_final_nb(o, h, l, c, v, ema10, ema20, vma20, atr, L, R, off_atr):
    """Causal Oliver Kell Cycle detector (exact MQL5 Series.mqh parity):
      0: BASE_N_BREAK_BULL  - Flat-top/ascending base (|dh|<=0.40, dl>=0.18, w_b<0.90*w_a) OR tight horizontal/rising
                              base above 10/20 EMAs (bull_ema, |dh|<=0.32, dl>=-0.05, w_b<=1.65, bull_pole>=1.8, lb>=e20-0.45*a)
                              with unbroken top2 & upper-80% coil confirmation.
      1: BASE_N_BREAK_BEAR  - Flat-bottom/descending base (|dl|<=0.40, dh<=-0.18, w_b<0.90*w_a) OR tight horizontal/falling
                              base below 10/20 EMAs (bear_ema, |dl|<=0.32, dh<=0.05, w_b<=1.65, bear_pole>=1.8, hb<=e20+0.45*a)
                              with unbroken bot2 & lower-80% coil confirmation.
      2: WEDGE_POP_BULL     - Contracting symmetrical or falling wedge (w_b <= 0.85*w_a) with upper-80% coil.
      3: WEDGE_DROP_BEAR    - Contracting symmetrical or rising wedge (w_b <= 0.85*w_a) with lower-80% coil.
      4: EMA_CROSSBACK_BULL - Bullish flag / channel pullback into 10/20 EMA zone after >=2.0 ATR bull pole, upper-80% coil.
      5: EMA_CROSSBACK_BEAR - Bearish flag / channel rally into 10/20 EMA zone after >=2.0 ATR bear pole, lower-80% coil.
      6: REV_EXT_POP_BULL   - Bullish Reversal Extension (3-trough Inv H&S / Triple Bottom, or 2-trough Double Bottom reclaiming EMA10).
      7: EXH_EXT_DROP_BEAR  - Bearish Exhaustion Extension (3-peak H&S / Triple Top, or 2-peak Double Top breaking below EMA10).
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

    for i in range(L + R + 30, n):
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
        bull_ema = (e10 >= e20 - 0.15 * a) and (e20 >= e20_prev - 0.08 * a)
        bear_ema = (e10 <= e20 + 0.15 * a) and (e20 <= e20_prev + 0.08 * a)

        h1, h2, h3 = sh_v[3], sh_v[4], sh_v[5]
        ih1, ih2, ih3 = sh_i[3], sh_i[4], sh_i[5]
        l1, l2, l3 = sl_v[3], sl_v[4], sl_v[5]
        il1, il2, il3 = sl_i[3], sl_i[4], sl_i[5]

        ha, hb = h2, h3
        iha, ihb = ih2, ih3
        la, lb = l2, l3
        ila, ilb = il2, il3

        start2 = min(iha, ila)
        end2 = max(ihb, ilb)
        span2 = end2 - start2
        if span2 < 5 or (i - end2) > 36:
            continue

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

        best_s = -1
        best_d = 0
        best_trig = 0.0
        best_sl = 0.0
        best_h = 0.0
        best_piv = -1
        best_q = -1.0
        best_sp = span2
        best_cr = cr2

        # 1. 3-PIVOT REVERSAL / EXHAUSTION EXTENSION (6: Bull Rev, 7: Bear Exh)
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
                    if l2 <= min(l1, l3) - 0.20 * a and abs(l3 - l1) <= 0.85 * a:
                        qscore = 1.60 + 0.25 * (min(l1, l3) - l2) / a - 0.3 * abs(l3 - l1) / a
                        if qscore > best_q:
                            best_s = 6; best_d = 1; best_trig = neck_h - off_atr * a
                            best_sl = l3; best_h = neck_h - l2; best_piv = neck_ih; best_q = qscore
                            best_sp = span3_l; best_cr = (neck_h - l3) / max(neck_h - l2, 1e-6)
                    spread3_l = max(l1, max(l2, l3)) - min_l3
                    if spread3_l <= 0.60 * a:
                        qscore = 1.55 - 0.5 * spread3_l / a
                        if qscore > best_q:
                            best_s = 6; best_d = 1; best_trig = neck_h - off_atr * a
                            best_sl = min(l2, l3); best_h = neck_h - min_l3; best_piv = neck_ih
                            best_q = qscore; best_sp = span3_l; best_cr = 0.85

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
                    if h2 >= max(h1, h3) + 0.20 * a and abs(h3 - h1) <= 0.85 * a:
                        qscore = 1.60 + 0.25 * (h2 - max(h1, h3)) / a - 0.3 * abs(h3 - h1) / a
                        if qscore > best_q:
                            best_s = 7; best_d = -1; best_trig = neck_l + off_atr * a
                            best_sl = h3; best_h = h2 - neck_l; best_piv = neck_il; best_q = qscore
                            best_sp = span3_h; best_cr = (h3 - neck_l) / max(h2 - neck_l, 1e-6)
                    spread3_h = max_h3 - min(h1, min(h2, h3))
                    if spread3_h <= 0.60 * a:
                        qscore = 1.55 - 0.5 * spread3_h / a
                        if qscore > best_q:
                            best_s = 7; best_d = -1; best_trig = neck_l + off_atr * a
                            best_sl = max(h2, h3); best_h = max_h3 - neck_l; best_piv = neck_il
                            best_q = qscore; best_sp = span3_h; best_cr = 0.85

        # 2. 2-PIVOT STRUCTURAL KELL CYCLE SETUPS (0..7)
        if span2 <= 72 and w_a >= 0.70 and w_b >= 0.35:
            # 6/7: Double Bottom / Double Top Reversal Extension reclaiming EMA10
            if ila < ihb < ilb and abs(dl) <= 0.45 and (hb - min(la, lb)) >= 0.90 * a and unbroken_hi_b:
                if c[i] >= e10 and c[i] >= lb + 0.55 * (hb - lb):
                    qscore = 1.45 - 0.5 * abs(dl)
                    if qscore > best_q:
                        best_s = 6; best_d = 1; best_trig = hb - off_atr * a
                        best_sl = lb; best_h = hb - min(la, lb); best_piv = ihb
                        best_q = qscore; best_sp = span2; best_cr = cr2

            if iha < ilb < ihb and abs(dh) <= 0.45 and (max(ha, hb) - lb) >= 0.90 * a and unbroken_lo_b:
                if c[i] <= e10 and c[i] <= hb - 0.55 * (hb - lb):
                    qscore = 1.45 - 0.5 * abs(dh)
                    if qscore > best_q:
                        best_s = 7; best_d = -1; best_trig = lb + off_atr * a
                        best_sl = hb; best_h = max(ha, hb) - lb; best_piv = ilb
                        best_q = qscore; best_sp = span2; best_cr = cr2

            # 0/1: Base 'n Break (Flat-top/Ascending Base OR Tight Horizontal/Rising Base above 10/20 EMAs)
            is_asc_base = (abs(dh) <= 0.40 and dl >= 0.18 and w_b < 0.90 * w_a)
            is_rect_base_bull = (bull_ema and abs(dh) <= 0.32 and dl >= -0.05 and w_b <= 1.65 and bull_pole >= 1.8 and lb >= e20 - 0.45 * a)
            if (is_asc_base or is_rect_base_bull) and unbroken_top2 and coil_above_lb:
                qscore = 1.44 - 0.5 * abs(dh) + 0.2 * min(max(dl, 0.0), 2.0) + (0.08 if bull_ema else 0.0)
                if qscore > best_q:
                    best_s = 0; best_d = 1; best_trig = top2 - off_atr * a
                    best_sl = lb; best_h = top2 - min(la, lb); best_piv = ihb
                    best_q = qscore; best_sp = span2; best_cr = cr2

            is_desc_base = (abs(dl) <= 0.40 and dh <= -0.18 and w_b < 0.90 * w_a)
            is_rect_base_bear = (bear_ema and abs(dl) <= 0.32 and dh <= 0.05 and w_b <= 1.65 and bear_pole >= 1.8 and hb <= e20 + 0.45 * a)
            if (is_desc_base or is_rect_base_bear) and unbroken_bot2 and coil_below_hb:
                qscore = 1.44 - 0.5 * abs(dl) + 0.2 * min(max(-dh, 0.0), 2.0) + (0.08 if bear_ema else 0.0)
                if qscore > best_q:
                    best_s = 1; best_d = -1; best_trig = bot2 + off_atr * a
                    best_sl = hb; best_h = max(ha, hb) - bot2; best_piv = ilb
                    best_q = qscore; best_sp = span2; best_cr = cr2

            # 2/3: Wedge Pop / Wedge Drop (Symmetrical or Contracting Wedge)
            if dh <= -0.18 and dl >= 0.18 and w_b <= 0.80 * w_a:
                sym_q = 1.32 + 0.3 * (1.0 - cr2)
                if unbroken_hi_b and coil_above_lb and imp >= -0.2 and sym_q > best_q:
                    best_s = 2; best_d = 1; best_trig = hb - off_atr * a
                    best_sl = lb; best_h = ha - la; best_piv = ihb
                    best_q = sym_q; best_sp = span2; best_cr = cr2
                if unbroken_lo_b and coil_below_hb and imp <= 0.2 and sym_q > best_q:
                    best_s = 3; best_d = -1; best_trig = lb + off_atr * a
                    best_sl = hb; best_h = ha - la; best_piv = ilb
                    best_q = sym_q; best_sp = span2; best_cr = cr2

            # 4/5: EMA Crossback Flag & Falling/Rising Wedge Continuation
            if dh < -0.12 and dl < -0.02 and unbroken_hi_b and coil_above_lb:
                slope_diff = abs((-dh) - (-dl))
                if bull_pole >= 2.0 and slope_diff <= 0.70 and (ha - lb) <= 0.65 * (ha - pole_lo):
                    qscore = 1.38 + 0.15 * min(bull_pole, 5.0) - 0.3 * slope_diff
                    if qscore > best_q:
                        best_s = 4; best_d = 1; best_trig = hb - off_atr * a
                        best_sl = lb; best_h = ha - pole_lo; best_piv = ihb
                        best_q = qscore; best_sp = span2; best_cr = cr2
                if (-dh) > (-dl) + 0.10 and w_b < 0.85 * w_a:
                    qscore = 1.28 + 0.3 * (1.0 - cr2)
                    if (imp >= 0.2 or w_b < 0.72 * w_a) and qscore > best_q:
                        best_s = 2; best_d = 1; best_trig = hb - off_atr * a
                        best_sl = lb; best_h = ha - lb; best_piv = ihb
                        best_q = qscore; best_sp = span2; best_cr = cr2

            if dh > 0.02 and dl > 0.12 and unbroken_lo_b and coil_below_hb:
                slope_diff = abs(dl - dh)
                if bear_pole >= 2.0 and slope_diff <= 0.70 and (hb - la) <= 0.65 * (pole_hi - la):
                    qscore = 1.38 + 0.15 * min(bear_pole, 5.0) - 0.3 * slope_diff
                    if qscore > best_q:
                        best_s = 5; best_d = -1; best_trig = lb + off_atr * a
                        best_sl = hb; best_h = pole_hi - la; best_piv = ilb
                        best_q = qscore; best_sp = span2; best_cr = cr2
                if dl > dh + 0.10 and w_b < 0.85 * w_a:
                    qscore = 1.28 + 0.3 * (1.0 - cr2)
                    if (imp <= -0.2 or w_b < 0.72 * w_a) and qscore > best_q:
                        best_s = 3; best_d = -1; best_trig = lb + off_atr * a
                        best_sl = hb; best_h = hb - la; best_piv = ilb
                        best_q = qscore; best_sp = span2; best_cr = cr2

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
            imp_val[i] = imp * best_d
            rel_vol[i] = 1.0
            ema_ext[i] = ((c[i] - e20) / a) * best_d

    return setup_id, s_dir, trig_px, sl_px, base_h, piv_idx, qual, span_arr, comp_rat, imp_val, rel_vol, ema_ext


def build_final_dataset(src="duka"):
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
    a1_mean480 = pd.Series(a1).rolling(480, min_periods=1).mean().values
    vol_reg_h1 = np.clip(a1 / np.maximum(a1_mean480, 1e-6), 0.3, 3.5)

    h4_e = tfs["H4"]["E"]
    h4_a = np.maximum(tfs["H4"]["atr"], 1e-6)
    h4_sp = (h4_e[0] - h4_e[-1]) / h4_a

    rows = []
    for s_id, (tf_name, gate_tfs, off) in enumerate(STREAMS):
        T = tfs[tf_name]
        sid, sdir, tpx, slpx, bh, piv, qual, sp, cr, im, rv, ex = detect_kell_final_nb(
            T["o"], T["h"], T["l"], T["c"], T["v"], T["ema10"], T["ema20"], T["vma20"], T["atr"], 3, 3, off
        )
        bad = ((sdir == -1) & (sid != 7)) | ((sid == 2) & (s_id == 4)) | ((sid == 4) & ((s_id == 2) | (s_id == 3)))
        sid = np.where(bad, -1, sid).astype(np.int64)
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


def extract_final_features(df: pd.DataFrame) -> np.ndarray:
    return df[KELL_FEATS_16].values.astype(np.float32)


if __name__ == "__main__":
    m1a_d, tfs_d, df_d = build_final_dataset("duka")
    X_d = extract_final_features(df_d)
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

    for q in (0.12, 0.15, 0.20, 0.25):
        thr = np.quantile(oof_p[ins], q)
        k_in = ins & (oof_p >= thr); v_in = ins & (oof_p < thr)
        k_oo = oos & (oof_p >= thr); v_oo = oos & (oof_p < thr)
        print(f"Veto q={q:.2f} (thr={thr:.4f}): "
              f"2017-23 CV kept={r_d[k_in].mean():+.3f}R ({k_in.sum()}) vs veto={r_d[v_in].mean():+.3f}R ({v_in.sum()}) | "
              f"2024-26 OOS kept={r_d[k_oo].mean():+.3f}R ({k_oo.sum()}) vs veto={r_d[v_oo].mean():+.3f}R ({v_oo.sum()})")

    p_all = clf.predict_proba(X_d)[:, 1]
    df_d["p"] = p_all
    w_arr = np.array([1.0, 1.0, 0.90, 0.80, 0.60])
    thr_htf = float(np.quantile(p_all[ins], 0.12))
    thr_m5 = float(np.quantile(p_all[ins], 0.35))
    thr_hi = float(np.quantile(p_all[ins], 0.65))

    sub_d = df_d[((df_d.stream < 4) & (df_d.p >= thr_htf)) | ((df_d.stream == 4) & (df_d.p >= thr_m5))].reset_index(drop=True)
    for mode_lbl, res_htf, two_st, wtp, hi_m in [
        ("Duka Prop (3 slots, reserve 2 HTF, 5R TP)", 2, False, 5.0, 1.15),
        ("Duka Growth Moonshot (3 slots, reserve 1 HTF, 2-Stage Scale-In, 7R TP)", 1, True, 7.0, 1.30),
    ]:
        tk, pr, a1, a2, _ = portfolio_moonshot_nb(
            sub_d.j.values, sub_d.dir.values, sub_d.px.values, sub_d.R.values, sub_d.trail.values, sub_d.stream.values,
            m1a_d["t"], m1a_d["o"], m1a_d["h"], m1a_d["l"], m1a_d["c"], m1a_d["spr"], m1a_d["tday"], m1a_d["nydow"],
            3, res_htf, two_st, 1.5, 0.05, 2.75, 1.60, 1.0, 3.0, wtp, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
        )
        m = tk == 1
        sw = w_arr[sub_d.stream.values[m]] * np.where(sub_d.p.values[m] >= thr_hi, hi_m, 1.0)
        tot_r = (pr[m] + (a1[m] + 0.5 * a2[m]) * (1.0 if two_st else 0.0)) * sw
        yrs = sub_d.year.values[m]
        by_y = pd.Series(tot_r).groupby(yrs).sum()
        print(f"\n[{mode_lbl}]")
        print(f"  Probes={m.sum()} | 2017-23={tot_r[yrs<=2023].sum():+6.1f}R | 2024-26 OOS={tot_r[yrs>=2024].sum():+6.1f}R | Total={tot_r.sum():+6.1f}R | Green={int((by_y>0).sum())}/10")
        print("  Years:", "  ".join(f"{y}:{v:+.1f}R" for y, v in by_y.items()))
