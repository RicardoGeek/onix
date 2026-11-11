"""Oliver Kell Study 1: Empirical 10-Year Evaluation of Oliver Kell's Cycle of Price Action
on XAUUSD (2017-2023 Seen/Train vs 2024-2026 Unseen Out-of-Sample, Hostile Execution Costs).

Tests the core concepts from the Oliver Kell diagram ("983% in 1 year"):
  1. 10 EMA & 20 EMA Cycle + HTF Trend Hierarchy Gate
  2. Setups (Long & Short):
     - 0/1: BASE_N_BREAK (Tight multi-bar consolidation base above/below 10/20 EMAs, breakout on volume)
     - 2/3: WEDGE_POP / WEDGE_DROP (Contracting wedge/flag continuation popping above / dropping below 10/20 EMAs)
     - 4/5: EMA_CROSSBACK (Pullback into the 10/20 EMA zone followed by structural reclaim breakout)
     - 6/7: REV_EXT_POP / EXH_EXT_DROP (Reversal Extension / Exhaustion Extension turn into 10/20 EMA reclaim)
  3. Exit rules:
     - Standard Whale Trailing vs Exhaustion Extension Target/Ratchet vs EMA Crossback (close below 10 & 20 EMAs)
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

SETUP_NAMES = [
    "BASE_N_BREAK_BULL",  # 0
    "BASE_N_BREAK_BEAR",  # 1
    "WEDGE_POP_BULL",     # 2
    "WEDGE_DROP_BEAR",    # 3
    "EMA_CROSSBACK_BULL", # 4
    "EMA_CROSSBACK_BEAR", # 5
    "REV_EXT_POP_BULL",   # 6
    "EXH_EXT_DROP_BEAR",  # 7
]

# Include 10 and 20 EMA first, plus the geometric macro hierarchy (10, 20, 34, 55, 89, 144, 200)
KELL_PERIODS = (10, 20, 34, 55, 89, 144, 200)
RIBBON_7 = (10, 16, 26, 41, 66, 105, 168)


def make_bars_with_vol(m1a: dict, minutes: int, vol_arr: np.ndarray):
    b = E.make_bars(m1a, minutes)
    b["v"] = np.add.reduceat(vol_arr, b["m1s"]).astype(np.float64)
    return b


def make_bars_ny_with_vol(m1a: dict, hours: int, nyloc_min: np.ndarray, vol_arr: np.ndarray):
    b = M.make_bars_ny(m1a, hours, nyloc_min)
    b["v"] = np.add.reduceat(vol_arr, b["m1s"]).astype(np.float64)
    return b


def build_kell_tfs(m1: pd.DataFrame, m1a: dict, periods=RIBBON_7):
    vol_arr = m1["vol"].values.astype(np.float64)
    nyl = M.ny_local_minutes(m1a["t"])
    tfs = {}
    for name, mins in (("M5", 5), ("M15", 15), ("M30", 30), ("H1", 60), ("H2", 120)):
        b = make_bars_with_vol(m1a, mins, vol_arr)
        b["ema10"] = E.ema_nb(b["c"], 10.0)
        b["ema20"] = E.ema_nb(b["c"], 20.0)
        b["vma20"] = E.ema_nb(b["v"], 20.0)
        tfs[name] = M.tf_states(b, periods)
    for name, hrs in (("H4", 4), ("D1", 24)):
        b = make_bars_ny_with_vol(m1a, hrs, nyl, vol_arr)
        b["ema10"] = E.ema_nb(b["c"], 10.0)
        b["ema20"] = E.ema_nb(b["c"], 20.0)
        b["vma20"] = E.ema_nb(b["v"], 20.0)
        tfs[name] = M.tf_states(b, periods)
    return tfs


@njit(cache=True)
def detect_kell_cycle_nb(o, h, l, c, v, ema10, ema20, vma20, atr, L, R, off_atr):
    """Causal Oliver Kell Cycle detector on closed structure bars:
    Uses confirmed (L, R) fractal swings AND rolling tight-base / crossback geometry around EMA10 & EMA20.
    Returns:
      setup_id (0..7 or -1), dir (+1/-1), trig_px, sl_px, base_h, piv_idx, qual, span, comp_rat, imp_val, rel_vol, ema_ext
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
        e10_prev = ema10[i - 3]
        e20_prev = ema20[i - 3]
        bull_ema = (e10 >= e20 - 0.10 * a) and (e20 >= e20_prev - 0.05 * a)
        bear_ema = (e10 <= e20 + 0.10 * a) and (e20 <= e20_prev + 0.05 * a)

        ha, hb = sh_v[4], sh_v[5]
        iha, ihb = sh_i[4], sh_i[5]
        la, lb = sl_v[4], sl_v[5]
        ila, ilb = sl_i[4], sl_i[5]

        start2 = min(iha, ila)
        end2 = max(ihb, ilb)
        span2 = end2 - start2
        if span2 < 4 or span2 > 72 or (i - end2) > 36:
            continue

        look_pre = max(0, start2 - 24)
        imp = (c[start2] - c[look_pre]) / a
        pole_lo = l[look_pre]
        pole_hi = h[look_pre]
        max_ext_lo = 0.0
        max_ext_hi = 0.0
        for q in range(look_pre, start2 + 1):
            if l[q] < pole_lo:
                pole_lo = l[q]
            if h[q] > pole_hi:
                pole_hi = h[q]
            ext_l = (ema20[q] - l[q]) / max(atr[q], 1e-6)
            ext_h = (h[q] - ema20[q]) / max(atr[q], 1e-6)
            if ext_l > max_ext_lo:
                max_ext_lo = ext_l
            if ext_h > max_ext_hi:
                max_ext_hi = ext_h

        bull_pole = (ha - pole_lo) / a
        bear_pole = (pole_hi - la) / a

        # Unbroken pivot & tight coil checks
        unbroken_hi_b = True
        coil_above_lb = True
        floor_coil = lb + 0.22 * (hb - lb)
        touched_ema_bull = False
        for q in range(ihb + 1, i + 1):
            if h[q] > hb:
                unbroken_hi_b = False
                break
            if l[q] < floor_coil:
                coil_above_lb = False
        for q in range(min(ilb, ihb), i + 1):
            if l[q] <= max(ema10[q], ema20[q]) + 0.35 * atr[q]:
                touched_ema_bull = True

        top2 = max(ha, hb)
        unbroken_top2 = True
        for q in range(ihb + 1, i + 1):
            if h[q] > top2:
                unbroken_top2 = False
                break

        unbroken_lo_b = True
        coil_below_hb = True
        ceil_coil = hb - 0.22 * (hb - lb)
        touched_ema_bear = False
        for q in range(ilb + 1, i + 1):
            if l[q] < lb:
                unbroken_lo_b = False
                break
            if h[q] > ceil_coil:
                coil_below_hb = False
        for q in range(min(ilb, ihb), i + 1):
            if h[q] >= min(ema10[q], ema20[q]) - 0.35 * atr[q]:
                touched_ema_bear = True

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
        if w_a < 0.60 or w_b < 0.30:
            continue
        cr2 = w_b / max(w_a, 1e-6)

        # Volume ratio (recent 3 bars max volume vs 20-bar EMA volume)
        v_rec = max(v[i], max(v[i - 1], v[i - 2]))
        rvol = v_rec / max(vma20[i], 1.0)

        best_s = -1
        best_d = 0
        best_trig = 0.0
        best_sl = 0.0
        best_h = 0.0
        best_piv = -1
        best_q = -1.0
        best_sp = span2
        best_cr = cr2

        # ------------------------------------------------------------------
        # 1. BASE 'N BREAK (Bullish 0 / Bearish 1)
        # Tight horizontal/ascending base above rising 10/20 EMAs (or below falling 10/20 EMAs)
        # ------------------------------------------------------------------
        if bull_ema and abs(dh) <= 0.45 and dl >= -0.10 and w_b <= 0.90 * w_a and unbroken_top2 and coil_above_lb:
            if lb >= e20 - 0.60 * a and c[i] >= e20:
                qscore = 1.50 - 0.4 * abs(dh) + 0.25 * (1.0 - min(cr2, 1.0)) + 0.10 * min(bull_pole, 4.0)
                if qscore > best_q:
                    best_s = 0; best_d = 1; best_trig = top2 - off_atr * a
                    best_sl = lb; best_h = top2 - min(la, lb); best_piv = ihb
                    best_q = qscore; best_sp = span2; best_cr = cr2

        if bear_ema and abs(dl) <= 0.45 and dh <= 0.10 and w_b <= 0.90 * w_a and unbroken_bot2 and coil_below_hb:
            if hb <= e20 + 0.60 * a and c[i] <= e20:
                qscore = 1.50 - 0.4 * abs(dl) + 0.25 * (1.0 - min(cr2, 1.0)) + 0.10 * min(bear_pole, 4.0)
                if qscore > best_q:
                    best_s = 1; best_d = -1; best_trig = bot2 + off_atr * a
                    best_sl = hb; best_h = max(ha, hb) - bot2; best_piv = ilb
                    best_q = qscore; best_sp = span2; best_cr = cr2

        # ------------------------------------------------------------------
        # 2. WEDGE POP (2) / WEDGE DROP (3)
        # Contracting wedge / flag continuation popping through 10/20 EMAs
        # ------------------------------------------------------------------
        if unbroken_hi_b and coil_above_lb and w_b <= 0.85 * w_a:
            # Either contracting symmetrical/descending wedge or flag with prior bull impulse
            is_wedge_pop = (dh <= -0.12 and (dl >= 0.12 or (dl < -0.02 and (-dh) > (-dl) + 0.08)))
            if is_wedge_pop and imp >= -0.25 and hb >= e20 - 0.25 * a:
                qscore = 1.40 + 0.30 * (1.0 - min(cr2, 1.0)) + 0.10 * min(max(bull_pole, 0.0), 4.0)
                if qscore > best_q:
                    best_s = 2; best_d = 1; best_trig = hb - off_atr * a
                    best_sl = lb; best_h = ha - min(la, lb); best_piv = ihb
                    best_q = qscore; best_sp = span2; best_cr = cr2

        if unbroken_lo_b and coil_below_hb and w_b <= 0.85 * w_a:
            is_wedge_drop = (dl >= 0.12 and (dh <= -0.12 or (dh > 0.02 and dl > dh + 0.08)))
            if is_wedge_drop and imp <= 0.25 and lb <= e20 + 0.25 * a:
                qscore = 1.40 + 0.30 * (1.0 - min(cr2, 1.0)) + 0.10 * min(max(bear_pole, 0.0), 4.0)
                if qscore > best_q:
                    best_s = 3; best_d = -1; best_trig = lb + off_atr * a
                    best_sl = hb; best_h = max(ha, hb) - la; best_piv = ilb
                    best_q = qscore; best_sp = span2; best_cr = cr2

        # ------------------------------------------------------------------
        # 3. EMA CROSSBACK (Bullish 4 / Bearish 5)
        # Controlled pullback to 10/20 EMA band after an impulse leg, reclaiming structure
        # ------------------------------------------------------------------
        if bull_ema and touched_ema_bull and unbroken_hi_b and coil_above_lb:
            if bull_pole >= 1.8 and dh < -0.08 and dl > -0.60 and (ha - lb) <= 0.68 * (ha - pole_lo):
                qscore = 1.45 + 0.15 * min(bull_pole, 5.0) - 0.20 * abs(dh - dl)
                if qscore > best_q:
                    best_s = 4; best_d = 1; best_trig = hb - off_atr * a
                    best_sl = lb; best_h = ha - pole_lo; best_piv = ihb
                    best_q = qscore; best_sp = span2; best_cr = cr2

        if bear_ema and touched_ema_bear and unbroken_lo_b and coil_below_hb:
            if bear_pole >= 1.8 and dl > 0.08 and dh < 0.60 and (hb - la) <= 0.68 * (pole_hi - la):
                qscore = 1.45 + 0.15 * min(bear_pole, 5.0) - 0.20 * abs(dl - dh)
                if qscore > best_q:
                    best_s = 5; best_d = -1; best_trig = lb + off_atr * a
                    best_sl = hb; best_h = pole_hi - la; best_piv = ilb
                    best_q = qscore; best_sp = span2; best_cr = cr2

        # ------------------------------------------------------------------
        # 4. REVERSAL EXTENSION POP (6) / EXHAUSTION EXTENSION DROP (7)
        # V-bottom/top extension >= 2.0 ATR beyond EMA20 followed by higher-low / lower-high break
        # ------------------------------------------------------------------
        if max_ext_lo >= 2.0 and ila < ihb < ilb and dl >= -0.25 and unbroken_hi_b and coil_above_lb:
            if (hb - min(la, lb)) >= 0.90 * a and hb >= e10:
                qscore = 1.42 + 0.12 * min(max_ext_lo, 5.0) - 0.3 * abs( min(dl, 0.0) )
                if qscore > best_q:
                    best_s = 6; best_d = 1; best_trig = hb - off_atr * a
                    best_sl = lb; best_h = hb - min(la, lb); best_piv = ihb
                    best_q = qscore; best_sp = span2; best_cr = cr2

        if max_ext_hi >= 2.0 and iha < ilb < ihb and dh <= 0.25 and unbroken_lo_b and coil_below_hb:
            if (max(ha, hb) - lb) >= 0.90 * a and lb <= e10:
                qscore = 1.42 + 0.12 * min(max_ext_hi, 5.0) - 0.3 * abs( max(dh, 0.0) )
                if qscore > best_q:
                    best_s = 7; best_d = -1; best_trig = lb + off_atr * a
                    best_sl = hb; best_h = max(ha, hb) - lb; best_piv = ilb
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
            rel_vol[i] = min(max(rvol, 0.2), 5.0)
            ema_ext[i] = ((c[i] - e20) / a) * best_d

    return setup_id, s_dir, trig_px, sl_px, base_h, piv_idx, qual, span_arr, comp_rat, imp_val, rel_vol, ema_ext


@njit(cache=True)
def kell_events_nb(setup_id, s_dir, trig_px, sl_px, base_h, piv_idx, qual, span_arr, comp_rat, imp_val, rel_vol, ema_ext,
                   atr, gate, m1s, m1e, mo, mh, ml, mspr, slip_in, max_dist_atr):
    nb = len(atr)
    nm = len(mo)
    out_j = np.empty(nb, np.int64)
    out_d = np.empty(nb, np.int64)
    out_px = np.empty(nb, np.float64)
    out_s = np.empty(nb, np.int64)
    out_p = np.empty(nb, np.int64)
    out_sl = np.empty(nb, np.float64)
    out_bh = np.empty(nb, np.float64)
    out_q = np.empty(nb, np.float64)
    out_sp = np.empty(nb, np.int64)
    out_cr = np.empty(nb, np.float64)
    out_im = np.empty(nb, np.float64)
    out_rv = np.empty(nb, np.float64)
    out_ex = np.empty(nb, np.float64)
    used_piv = np.full(8, -1, np.int64)
    k = 0
    for p in range(50, nb - 1):
        sid = setup_id[p]
        if sid < 0:
            continue
        d = s_dir[p]
        g = gate[p]
        if g != 99 and g != d:
            continue
        piv = piv_idx[p]
        if piv == used_piv[sid]:
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
                    out_j[k] = j; out_d[k] = 1; out_px[k] = fill; out_s[k] = sid; out_p[k] = p
                    out_sl[k] = sl_px[p]; out_bh[k] = base_h[p] / a; out_q[k] = qual[p]
                    out_sp[k] = span_arr[p]; out_cr[k] = comp_rat[p]; out_im[k] = imp_val[p]
                    out_rv[k] = rel_vol[p]; out_ex[k] = ema_ext[p]
                    k += 1
                    used_piv[sid] = piv
                    break
        else:
            if (mo[j0] - L) > max_dist_atr * a or (L - mo[j0]) > 0.5 * a:
                continue
            for j in range(j0, min(j1, nm)):
                if ml[j] <= L:
                    op = mo[j]
                    fill = (op if op < L else L) - slip_in
                    out_j[k] = j; out_d[k] = -1; out_px[k] = fill; out_s[k] = sid; out_p[k] = p
                    out_sl[k] = sl_px[p]; out_bh[k] = base_h[p] / a; out_q[k] = qual[p]
                    out_sp[k] = span_arr[p]; out_cr[k] = comp_rat[p]; out_im[k] = imp_val[p]
                    out_rv[k] = rel_vol[p]; out_ex[k] = ema_ext[p]
                    k += 1
                    used_piv[sid] = piv
                    break
    return (out_j[:k], out_d[:k], out_px[:k], out_s[:k], out_p[:k],
            out_sl[:k], out_bh[:k], out_q[:k], out_sp[:k], out_cr[:k], out_im[:k], out_rv[:k], out_ex[:k])


from runes_study2 import simulate_whale_nb

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
        sid, sdir, tpx, slpx, bh, piv, qual, sp, cr, im, rv, ex = detect_kell_cycle_nb(
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
        print(f"\n==================== Timeframe {tf_name} (Oliver Kell Cycle) ====================")
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
