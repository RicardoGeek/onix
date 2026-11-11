"""16Runes Study 4: Multi-Stream Portfolio + Out-of-Sample Meta-Labeler (Train 2017-2023, Test Unseen 2024-2026).

Tests:
1. 16-feature vector combining Rune geometry (type, quality, height/ATR, compression ratio, prior impulse, span)
   and market regime (H1 volatility expansion, cost/ATR, H1/H4 ribbon spread, UTC session liquidity).
2. Compares shallow regularized LightGBM vs L2-regularized LogisticRegression (both exportable to native MT5 ONNX)
   trained strictly on 2017-2023.
3. Verifies whether VETOED setups have strictly LOWER avgR than KEPT setups in BOTH walk-forward 2017-2023 AND
   unseen 2024-2026 (Dukascopy & Pepperstone).
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
from runes_study2 import simulate_whale_nb


@njit(cache=True)
def detect_16runes_v4_nb(o, h, l, c, atr, L, R, off_atr, max_span):
    """Causal 16-Rune detector v4 returning full geometric telemetry for the Meta-Labeler:
      rune_id, rune_dir, trig_px, sl_px, pat_h, piv_idx, qual, pat_span, comp_ratio, imp_dir
    """
    n = len(c)
    rune_id = np.full(n, -1, np.int64)
    rune_dir = np.zeros(n, np.int64)
    trig_px = np.zeros(n, np.float64)
    sl_px = np.zeros(n, np.float64)
    pat_h = np.zeros(n, np.float64)
    piv_idx = np.full(n, -1, np.int64)
    qual = np.zeros(n, np.float64)
    pat_span = np.zeros(n, np.int64)
    comp_rat = np.ones(n, np.float64)
    imp_val = np.zeros(n, np.float64)

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

        best_r = -1
        best_d = 0
        best_trig = 0.0
        best_sl = 0.0
        best_h = 0.0
        best_piv = -1
        best_q = -1.0
        best_sp = span2
        best_cr = cr2

        # 3-TROUGH / 3-PEAK REVERSALS (Runes 9, 10, 13, 14)
        span3_l = il3 - il1
        if 8 <= span3_l <= max_span and (i - il3) <= 24:
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
                if unbroken_nh and (neck_h - min(l1, min(l2, l3))) >= 0.85 * a:
                    if l2 <= min(l1, l3) - 0.20 * a and abs(l3 - l1) <= 0.85 * a:
                        qscore = 1.60 + 0.25 * (min(l1, l3) - l2) / a - 0.3 * abs(l3 - l1) / a
                        if qscore > best_q:
                            best_r = 10; best_d = 1; best_trig = neck_h - off_atr * a
                            best_sl = l3; best_h = neck_h - l2; best_piv = neck_ih; best_q = qscore
                            best_sp = span3_l; best_cr = (neck_h - l3) / max(neck_h - l2, 1e-6)
                    spread3_l = max(l1, max(l2, l3)) - min(l1, min(l2, l3))
                    if spread3_l <= 0.60 * a:
                        qscore = 1.55 - 0.5 * spread3_l / a
                        if qscore > best_q:
                            best_r = 9; best_d = 1; best_trig = neck_h - off_atr * a
                            best_sl = min(l2, l3); best_h = neck_h - min(l1, min(l2, l3)); best_piv = neck_ih
                            best_q = qscore; best_sp = span3_l; best_cr = 0.85

        span3_h = ih3 - ih1
        if 8 <= span3_h <= max_span and (i - ih3) <= 24:
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
                if unbroken_nl and (max(h1, max(h2, h3)) - neck_l) >= 0.85 * a:
                    if h2 >= max(h1, h3) + 0.20 * a and abs(h3 - h1) <= 0.85 * a:
                        qscore = 1.60 + 0.25 * (h2 - max(h1, h3)) / a - 0.3 * abs(h3 - h1) / a
                        if qscore > best_q:
                            best_r = 14; best_d = -1; best_trig = neck_l + off_atr * a
                            best_sl = h3; best_h = h2 - neck_l; best_piv = neck_il; best_q = qscore
                            best_sp = span3_h; best_cr = (h3 - neck_l) / max(h2 - neck_l, 1e-6)
                    spread3_h = max(h1, max(h2, h3)) - min(h1, min(h2, h3))
                    if spread3_h <= 0.60 * a:
                        qscore = 1.55 - 0.5 * spread3_h / a
                        if qscore > best_q:
                            best_r = 13; best_d = -1; best_trig = neck_l + off_atr * a
                            best_sl = max(h2, h3); best_h = max(h1, max(h2, h3)) - neck_l; best_piv = neck_il
                            best_q = qscore; best_sp = span3_h; best_cr = 0.85

        # 2-PEAK / 2-TROUGH PATTERNS (Runes 0..8, 11, 12, 15)
        if span2 <= max_span and w_a >= 0.70 and w_b >= 0.35:
            if ila < ihb < ilb and abs(dl) <= 0.45 and (hb - min(la, lb)) >= 0.90 * a and unbroken_hi_b:
                qscore = 1.45 - 0.5 * abs(dl)
                if qscore > best_q:
                    best_r = 8; best_d = 1; best_trig = hb - off_atr * a
                    best_sl = lb; best_h = hb - min(la, lb); best_piv = ihb; best_q = qscore; best_sp = span2; best_cr = cr2

            if iha < ilb < ihb and abs(dh) <= 0.45 and (max(ha, hb) - lb) >= 0.90 * a and unbroken_lo_b:
                qscore = 1.45 - 0.5 * abs(dh)
                if qscore > best_q:
                    best_r = 12; best_d = -1; best_trig = lb + off_atr * a
                    best_sl = hb; best_h = max(ha, hb) - lb; best_piv = ilb; best_q = qscore; best_sp = span2; best_cr = cr2

            if abs(dh) <= 0.40 and dl >= 0.20 and w_b < 0.90 * w_a and unbroken_top2 and coil_above_lb:
                qscore = 1.40 - 0.5 * abs(dh) + 0.2 * min(dl, 2.0)
                if qscore > best_q:
                    best_r = 0; best_d = 1; best_trig = top2 - off_atr * a
                    best_sl = lb; best_h = top2 - la; best_piv = ihb; best_q = qscore; best_sp = span2; best_cr = cr2

            if abs(dl) <= 0.40 and dh <= -0.20 and w_b < 0.90 * w_a and unbroken_bot2 and coil_below_hb:
                qscore = 1.40 - 0.5 * abs(dl) + 0.2 * min(-dh, 2.0)
                if qscore > best_q:
                    best_r = 4; best_d = -1; best_trig = bot2 + off_atr * a
                    best_sl = hb; best_h = ha - bot2; best_piv = ilb; best_q = qscore; best_sp = span2; best_cr = cr2

            if dh <= -0.18 and dl >= 0.18 and w_b <= 0.80 * w_a:
                sym_q = 1.30 + 0.3 * (1.0 - cr2)
                if unbroken_hi_b and coil_above_lb and imp >= -0.2 and sym_q > best_q:
                    best_r = 3; best_d = 1; best_trig = hb - off_atr * a
                    best_sl = lb; best_h = ha - la; best_piv = ihb; best_q = sym_q; best_sp = span2; best_cr = cr2
                if unbroken_lo_b and coil_below_hb and imp <= 0.2 and sym_q > best_q:
                    best_r = 7; best_d = -1; best_trig = lb + off_atr * a
                    best_sl = hb; best_h = ha - la; best_piv = ilb; best_q = sym_q; best_sp = span2; best_cr = cr2

            if dh < -0.12 and dl < -0.02 and unbroken_hi_b and coil_above_lb:
                slope_diff = abs((-dh) - (-dl))
                if bull_pole >= 2.0 and slope_diff <= 0.70 and (ha - lb) <= 0.65 * (ha - pole_lo):
                    qscore = 1.35 + 0.15 * min(bull_pole, 5.0) - 0.3 * slope_diff
                    if qscore > best_q:
                        best_r = 2; best_d = 1; best_trig = hb - off_atr * a
                        best_sl = lb; best_h = ha - pole_lo; best_piv = ihb; best_q = qscore; best_sp = span2; best_cr = cr2
                if (-dh) > (-dl) + 0.10 and w_b < 0.85 * w_a:
                    qscore = 1.25 + 0.3 * (1.0 - cr2)
                    if imp >= 0.2:
                        if qscore > best_q:
                            best_r = 1; best_d = 1; best_trig = hb - off_atr * a
                            best_sl = lb; best_h = ha - lb; best_piv = ihb; best_q = qscore; best_sp = span2; best_cr = cr2
                    elif w_b < 0.72 * w_a:
                        if qscore > best_q:
                            best_r = 11; best_d = 1; best_trig = hb - off_atr * a
                            best_sl = lb; best_h = ha - lb; best_piv = ihb; best_q = qscore; best_sp = span2; best_cr = cr2

            if dh > 0.02 and dl > 0.12 and unbroken_lo_b and coil_below_hb:
                slope_diff = abs(dl - dh)
                if bear_pole >= 2.0 and slope_diff <= 0.70 and (hb - la) <= 0.65 * (pole_hi - la):
                    qscore = 1.35 + 0.15 * min(bear_pole, 5.0) - 0.3 * slope_diff
                    if qscore > best_q:
                        best_r = 6; best_d = -1; best_trig = lb + off_atr * a
                        best_sl = hb; best_h = pole_hi - la; best_piv = ilb; best_q = qscore; best_sp = span2; best_cr = cr2
                if dl > dh + 0.10 and w_b < 0.85 * w_a:
                    qscore = 1.25 + 0.3 * (1.0 - cr2)
                    if imp <= -0.2:
                        if qscore > best_q:
                            best_r = 5; best_d = -1; best_trig = lb + off_atr * a
                            best_sl = hb; best_h = hb - la; best_piv = ilb; best_q = qscore; best_sp = span2; best_cr = cr2
                    elif w_b < 0.72 * w_a:
                        if qscore > best_q:
                            best_r = 15; best_d = -1; best_trig = lb + off_atr * a
                            best_sl = hb; best_h = hb - la; best_piv = ilb; best_q = qscore; best_sp = span2; best_cr = cr2

        if best_r >= 0:
            rune_id[i] = best_r
            rune_dir[i] = best_d
            trig_px[i] = best_trig
            sl_px[i] = best_sl
            pat_h[i] = best_h
            piv_idx[i] = best_piv
            qual[i] = best_q
            pat_span[i] = best_sp
            comp_rat[i] = best_cr
            imp_val[i] = imp * best_d

    return rune_id, rune_dir, trig_px, sl_px, pat_h, piv_idx, qual, pat_span, comp_rat, imp_val


@njit(cache=True)
def rune_events_v4_nb(rune_id, rune_dir, trig_px, sl_px, pat_h, piv_idx, qual, pat_span, comp_rat, imp_val,
                      atr, gate, m1s, m1e, mo, mh, ml, mspr, slip_in, max_dist_atr):
    nb = len(atr)
    nm = len(mo)
    out_j = np.empty(nb, np.int64)
    out_d = np.empty(nb, np.int64)
    out_px = np.empty(nb, np.float64)
    out_r = np.empty(nb, np.int64)
    out_p = np.empty(nb, np.int64)
    out_sl = np.empty(nb, np.float64)
    out_ph = np.empty(nb, np.float64)
    out_q = np.empty(nb, np.float64)
    out_sp = np.empty(nb, np.int64)
    out_cr = np.empty(nb, np.float64)
    out_im = np.empty(nb, np.float64)
    used_piv = np.full(16, -1, np.int64)
    k = 0
    for p in range(50, nb - 1):
        rid = rune_id[p]
        if rid < 0:
            continue
        d = rune_dir[p]
        g = gate[p]
        if g != 99 and g != d:
            continue
        piv = piv_idx[p]
        if piv == used_piv[rid]:
            continue
        j0 = m1s[p + 1]
        j1 = m1e[p + 1]
        if j0 >= nm:
            continue
        L = trig_px[p]
        a = atr[p]
        if d == 1:
            if (L - mo[j0]) > max_dist_atr * a or (mo[j0] - L) > 0.5 * a:
                continue
            for j in range(j0, min(j1, nm)):
                if mh[j] + mspr[j] >= L:
                    op = mo[j] + mspr[j]
                    fill = (op if op > L else L) + slip_in
                    out_j[k] = j; out_d[k] = 1; out_px[k] = fill; out_r[k] = rid; out_p[k] = p
                    out_sl[k] = sl_px[p]; out_ph[k] = pat_h[p] / a; out_q[k] = qual[p]
                    out_sp[k] = pat_span[p]; out_cr[k] = comp_rat[p]; out_im[k] = imp_val[p]
                    k += 1
                    used_piv[rid] = piv
                    break
        else:
            if (mo[j0] - L) > max_dist_atr * a or (L - mo[j0]) > 0.5 * a:
                continue
            for j in range(j0, min(j1, nm)):
                if ml[j] <= L:
                    op = mo[j]
                    fill = (op if op < L else L) - slip_in
                    out_j[k] = j; out_d[k] = -1; out_px[k] = fill; out_r[k] = rid; out_p[k] = p
                    out_sl[k] = sl_px[p]; out_ph[k] = pat_h[p] / a; out_q[k] = qual[p]
                    out_sp[k] = pat_span[p]; out_cr[k] = comp_rat[p]; out_im[k] = imp_val[p]
                    k += 1
                    used_piv[rid] = piv
                    break
    return (out_j[:k], out_d[:k], out_px[:k], out_r[:k], out_p[:k],
            out_sl[:k], out_ph[:k], out_q[:k], out_sp[:k], out_cr[:k], out_im[:k])


STREAMS = [
    ("H1",  ("H4", "D1"),       0.12),   # Stream 0: H1 Runes gated by H4+D1
    ("H2",  ("H4", "D1"),       0.08),   # Stream 1: H2 Runes gated by H4+D1
    ("M30", ("H4", "D1"),       0.12),   # Stream 2: M30 Runes gated by H4+D1
    ("M15", ("H1", "H4", "D1"), 0.12),   # Stream 3: M15 Runes gated by H1+H4+D1
    ("M5",  ("H1", "H4", "D1"), 0.12),   # Stream 4: M5 Runes gated by H1+H4+D1
]

FEATS = [
    "f0_stream", "f1_dir", "f2_is_cont", "f3_is_3piv", "f4_is_tri", "f5_is_wedge_flag",
    "f6_qual", "f7_pat_h_atr", "f8_comp_ratio", "f9_imp_align", "f10_span_norm",
    "f11_vol_reg", "f12_cost_atr", "f13_h1_rib_sp", "f14_h4_rib_sp", "f15_liq_sess"
]


def build_dataset(src="duka"):
    m1 = D.load(f"{src}_m1")
    m1a = E.m1_arrays(m1, src)
    tfs = build_all_tfs(m1a)

    st = {}
    for tf in ("M5", "M15", "M30", "H1", "H2", "H4", "D1"):
        T = tfs[tf]
        Em = T["E"]
        sc = np.sign(-np.diff(Em, axis=0)).sum(axis=0)
        st[tf] = np.where(sc >= 6, 1, np.where(sc <= -6, -1, 0)).astype(np.int64)

    a1 = tfs["H1"]["atr"]
    # Rolling 480-bar mean of H1 ATR
    cs = np.cumsum(np.r_[0.0, a1])
    idx = np.arange(len(a1))
    lo_i = np.maximum(0, idx - 479)
    mean_a1 = (cs[idx + 1] - cs[lo_i]) / (idx - lo_i + 1)
    vol_reg_h1 = a1 / np.maximum(mean_a1, 1e-9)

    rows = []
    for si, (tf_name, gate_tfs, off_atr) in enumerate(STREAMS):
        T = tfs[tf_name]
        rid, rdir, tpx, slpx, path, piv, qual, pspan, crat, impv = detect_16runes_v4_nb(
            T["o"], T["h"], T["l"], T["c"], T["atr"], 3, 3, off_atr, 72
        )
        g = None
        for gt in gate_tfs:
            kg = np.maximum(M.map_last_closed(tfs[gt], T["t_close"]), 0)
            sg = st[gt][kg]
            g = sg if g is None else np.where(g == sg, sg, 0)
        g = g.astype(np.int64)

        j, d, px, r_id, p_idx, sl_p, ph_p, q_p, sp_p, cr_p, im_p = rune_events_v4_nb(
            rid, rdir, tpx, slpx, path, piv, qual, pspan, crat, impv,
            T["atr"], g, T["m1s"], T["m1e"], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], 0.05, 3.0
        )
        if len(j) == 0:
            continue
        kh1 = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][j]), 0)
        kh4 = np.maximum(M.map_last_closed(tfs["H4"], m1a["t"][j]), 0)
        ok = (kh1 >= 480) & (kh4 >= 10)
        j, d, px, r_id, ph_p, q_p, sp_p, cr_p, im_p, kh1, kh4 = (
            j[ok], d[ok], px[ok], r_id[ok], ph_p[ok], q_p[ok], sp_p[ok], cr_p[ok], im_p[ok], kh1[ok], kh4[ok]
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

        h1_rib_sp = (tfs["H1"]["E"][0, kh1] - tfs["H1"]["E"][6, kh1]) / np.maximum(a1[kh1], 1e-9) * d
        h4_rib_sp = (tfs["H4"]["E"][0, kh4] - tfs["H4"]["E"][6, kh4]) / np.maximum(tfs["H4"]["atr"][kh4], 1e-9) * d

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
            "f10_span_norm": sp_p.astype(float) / 36.0,
            "f11_vol_reg": np.clip(vol_reg_h1[kh1], 0.3, 3.5),
            "f12_cost_atr": np.clip(cost / np.maximum(a1[kh1], 1e-9), 0.0, 0.5),
            "f13_h1_rib_sp": np.clip(h1_rib_sp, -6.0, 6.0),
            "f14_h4_rib_sp": np.clip(h4_rib_sp, -6.0, 6.0),
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
    m1a_d, tfs_d, df_d = build_dataset("duka")
    print(f"Built Dukascopy 5-stream dataset: {len(df_d):,} setups in {time.time() - t0:.1f}s")

    X = df_d[FEATS].values.astype(np.float32)
    r = df_d["r"].values
    yr = df_d["year"].values
    ins = yr <= 2023
    oos = yr >= 2024

    print(f"Baseline ALL 5 streams: n={len(df_d)}  2017-23 avgR={r[ins].mean():+.3f} (sum={r[ins].sum():+.1f}R, n={ins.sum()})  "
          f"2024-26 avgR={r[oos].mean():+.3f} (sum={r[oos].sum():+.1f}R, n={oos.sum()})")

    # Test 1: L2-regularized LogisticRegression / Ridge on 2017-2023
    from sklearn.linear_model import LogisticRegression, Ridge
    from sklearn.preprocessing import StandardScaler
    from sklearn.pipeline import Pipeline
    import lightgbm as lgb

    y_bin = (r > 0.0).astype(int)
    for name, clf in [
        ("LogReg C=0.05", Pipeline([("sc", StandardScaler()), ("lr", LogisticRegression(C=0.05, max_iter=500))])),
        ("LogReg C=0.01", Pipeline([("sc", StandardScaler()), ("lr", LogisticRegression(C=0.01, max_iter=500))])),
        ("LGBM leaves=5 min_leaf=80", lgb.LGBMClassifier(
            n_estimators=60, learning_rate=0.03, num_leaves=5, min_child_samples=80,
            subsample=0.8, colsample_bytree=0.7, reg_lambda=30.0, random_state=42, verbose=-1
        )),
        ("LGBM leaves=4 min_leaf=120", lgb.LGBMClassifier(
            n_estimators=45, learning_rate=0.03, num_leaves=4, min_child_samples=120,
            subsample=0.8, colsample_bytree=0.7, reg_lambda=50.0, random_state=42, verbose=-1
        )),
    ]:
        # Leave-one-year-out CV on 2017-2023
        oof_p = np.zeros(len(df_d))
        for y_val in range(2017, 2024):
            tr_m = ins & (yr != y_val)
            va_m = (yr == y_val)
            clf.fit(X[tr_m], y_bin[tr_m])
            oof_p[va_m] = clf.predict_proba(X[va_m])[:, 1]
        # Fit on all 2017-2023 and predict on unseen 2024-2026
        clf.fit(X[ins], y_bin[ins])
        oof_p[oos] = clf.predict_proba(X[oos])[:, 1]

        print(f"\n--- Meta-Labeler: {name} ---")
        for q in (0.15, 0.20, 0.25, 0.30, 0.35):
            thr = np.quantile(oof_p[ins], q)
            keep_in = ins & (oof_p >= thr)
            veto_in = ins & (oof_p < thr)
            keep_oo = oos & (oof_p >= thr)
            veto_oo = oos & (oof_p < thr)
            print(f"  veto q={q:.2f} (thr={thr:.4f}): "
                  f"2017-23 CV kept={r[keep_in].mean():+.3f}R ({keep_in.sum()}) vs vetoed={r[veto_in].mean():+.3f}R ({veto_in.sum()}) | "
                  f"2024-26 OOS kept={r[keep_oo].mean():+.3f}R ({keep_oo.sum()}, sum={r[keep_oo].sum():+.1f}R) "
                  f"vs vetoed={r[veto_oo].mean():+.3f}R ({veto_oo.sum()})")
