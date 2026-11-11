"""16Runes Study 1: 10-year (2017-2026) empirical discovery & edge analysis of all 16 chart patterns.

Tests the 16 Runes across M15, M30, H1, H2 structure timeframes on Dukascopy (2017-2026) and Pepperstone (2023-2026)
under hostile execution costs:
  0  ASC_TRI       Bullish Continuation : Ascending Triangle
  1  BULL_WEDGE    Bullish Continuation : Bullish Falling Wedge (in uptrend)
  2  BULL_FLAG     Bullish Continuation : Bullish Flag (parallel pullback after flagpole)
  3  BULL_SYM_TRI  Bullish Continuation : Bullish Symmetrical Triangle
  4  DESC_TRI      Bearish Continuation : Descending Triangle
  5  BEAR_WEDGE    Bearish Continuation : Bearish Rising Wedge (in downtrend)
  6  BEAR_FLAG     Bearish Continuation : Bearish Flag (parallel pullback after flagpole)
  7  BEAR_SYM_TRI  Bearish Continuation : Bearish Symmetrical Triangle
  8  DBL_BOTTOM    Bullish Reversal     : Double Bottom (W)
  9  TRPL_BOTTOM   Bullish Reversal     : Triple Bottom
  10 INV_HS        Bullish Reversal     : Inverted Head & Shoulders
  11 FALL_WEDGE    Bullish Reversal     : Falling Wedge (after down-move)
  12 DBL_TOP       Bearish Reversal     : Double Top (M)
  13 TRPL_TOP      Bearish Reversal     : Triple Top
  14 HEAD_SHLDR    Bearish Reversal     : Head & Shoulders
  15 RISE_WEDGE    Bearish Reversal     : Rising Wedge (after up-move)
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
import sw_sim2 as S2

RUNE_NAMES = [
    "ASC_TRI", "BULL_WEDGE", "BULL_FLAG", "BULL_SYM_TRI",
    "DESC_TRI", "BEAR_WEDGE", "BEAR_FLAG", "BEAR_SYM_TRI",
    "DBL_BOTTOM", "TRPL_BOTTOM", "INV_HS", "FALL_WEDGE",
    "DBL_TOP", "TRPL_TOP", "HEAD_SHLDR", "RISE_WEDGE"
]

RIBBON = (10, 16, 26, 41, 66, 105, 168)


@njit(cache=True)
def detect_16runes_nb(o, h, l, c, atr, ema_fast, ema_slow, L, R, off_atr, max_span):
    """Causal 16-Rune pattern detector on closed structure bars.

    At each closed bar i, updates confirmed (L, R) fractal swing highs and lows (confirmed at p = i - R).
    Then checks if the recent confirmed swing pivots form one of the 16 Runes whose breakout level has NOT
    yet been broken by any bar after the pattern's controlling pivot.

    Returns per bar i:
      rune_id[i]   : 0..15 (-1 if no rune armed on bar i)
      rune_dir[i]  : +1 or -1
      trig_px[i]   : breakout trigger price armed for bar i+1
      sl_px[i]     : structural stop anchor price
      pat_h[i]     : pattern height in price units
      piv_idx[i]   : index of the controlling pivot (to enforce one shot per pattern structure)
      qual[i]      : geometric compactness / symmetry score
    """
    n = len(c)
    rune_id = np.full(n, -1, np.int64)
    rune_dir = np.zeros(n, np.int64)
    trig_px = np.zeros(n, np.float64)
    sl_px = np.zeros(n, np.float64)
    pat_h = np.zeros(n, np.float64)
    piv_idx = np.full(n, -1, np.int64)
    qual = np.zeros(n, np.float64)

    # Ring buffer of last 6 confirmed swing highs and swing lows
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

        # 3 most recent swing highs (h1, h2, h3) and swing lows (l1, l2, l3)
        h1, h2, h3 = sh_v[3], sh_v[4], sh_v[5]
        ih1, ih2, ih3 = sh_i[3], sh_i[4], sh_i[5]
        l1, l2, l3 = sl_v[3], sl_v[4], sl_v[5]
        il1, il2, il3 = sl_i[3], sl_i[4], sl_i[5]

        # 2 most recent swing highs (ha, hb) and lows (la, lb)
        ha, hb = h2, h3
        iha, ihb = ih2, ih3
        la, lb = l2, l3
        ila, ilb = il2, il3

        # Prior impulse before pattern start
        start2 = min(iha, ila)
        end2 = max(ihb, ilb)
        span2 = end2 - start2
        if span2 < 4 or (i - end2) > 24:
            continue

        look_pre = max(0, start2 - 20)
        imp = (c[start2] - c[look_pre]) / a
        # Flagpole extremes in the 24 bars leading into the first pivot
        pole_lo = l[look_pre]
        pole_hi = h[look_pre]
        for q in range(look_pre, start2 + 1):
            if l[q] < pole_lo:
                pole_lo = l[q]
            if h[q] > pole_hi:
                pole_hi = h[q]
        bull_pole = (ha - pole_lo) / a
        bear_pole = (pole_hi - la) / a

        # Check if breakout above hb or max(ha,hb) is still unbroken since ihb
        unbroken_hi_b = True
        for q in range(ihb + 1, i + 1):
            if h[q] > hb:
                unbroken_hi_b = False
                break
        top2 = max(ha, hb)
        unbroken_top2 = True
        for q in range(ihb + 1, i + 1):
            if h[q] > top2:
                unbroken_top2 = False
                break

        unbroken_lo_b = True
        for q in range(ilb + 1, i + 1):
            if l[q] < lb:
                unbroken_lo_b = False
                break
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

        best_r = -1
        best_d = 0
        best_trig = 0.0
        best_sl = 0.0
        best_h = 0.0
        best_piv = -1
        best_q = -1.0

        # ------------------------------------------------------------------
        # 3-TROUGH / 3-PEAK REVERSALS (Runes 9, 10, 13, 14)
        # ------------------------------------------------------------------
        span3_l = il3 - il1
        if 6 <= span3_l <= max_span and (i - il3) <= 18:
            # Neckline high between il1 and il3
            neck_h = -1e18
            neck_ih = -1
            for k in range(3, 6):
                if il1 < sh_i[k] < il3 and sh_v[k] > neck_h:
                    neck_h = sh_v[k]
                    neck_ih = sh_i[k]
            if neck_ih >= 0:
                unbroken_nh = True
                for q in range(il3 + 1, i + 1):
                    if h[q] > neck_h:
                        unbroken_nh = False
                        break
                if unbroken_nh and (neck_h - min(l1, min(l2, l3))) >= 0.8 * a:
                    # Rune 10: INV_HS (l2 is Head < l1 and l3, shoulders balanced)
                    if l2 <= min(l1, l3) - 0.20 * a and abs(l3 - l1) <= 0.90 * a:
                        qscore = (min(l1, l3) - l2) / a - 0.5 * abs(l3 - l1) / a
                        if qscore > best_q:
                            best_r = 10; best_d = 1; best_trig = neck_h - off_atr * a
                            best_sl = l3; best_h = neck_h - l2; best_piv = il3; best_q = qscore
                    # Rune 9: TRPL_BOTTOM (l1, l2, l3 within 0.65 ATR)
                    spread3_l = max(l1, max(l2, l3)) - min(l1, min(l2, l3))
                    if spread3_l <= 0.65 * a:
                        qscore = 1.5 - spread3_l / a
                        if qscore > best_q:
                            best_r = 9; best_d = 1; best_trig = neck_h - off_atr * a
                            best_sl = min(l2, l3); best_h = neck_h - min(l1, min(l2, l3)); best_piv = il3; best_q = qscore

        span3_h = ih3 - ih1
        if 6 <= span3_h <= max_span and (i - ih3) <= 18:
            neck_l = 1e18
            neck_il = -1
            for k in range(3, 6):
                if ih1 < sl_i[k] < ih3 and sl_v[k] < neck_l:
                    neck_l = sl_v[k]
                    neck_il = sl_i[k]
            if neck_il >= 0:
                unbroken_nl = True
                for q in range(ih3 + 1, i + 1):
                    if l[q] < neck_l:
                        unbroken_nl = False
                        break
                if unbroken_nl and (max(h1, max(h2, h3)) - neck_l) >= 0.8 * a:
                    # Rune 14: HEAD_SHLDR (h2 is Head > h1 and h3, shoulders balanced)
                    if h2 >= max(h1, h3) + 0.20 * a and abs(h3 - h1) <= 0.90 * a:
                        qscore = (h2 - max(h1, h3)) / a - 0.5 * abs(h3 - h1) / a
                        if qscore > best_q:
                            best_r = 14; best_d = -1; best_trig = neck_l + off_atr * a
                            best_sl = h3; best_h = h2 - neck_l; best_piv = ih3; best_q = qscore
                    # Rune 13: TRPL_TOP (h1, h2, h3 within 0.65 ATR)
                    spread3_h = max(h1, max(h2, h3)) - min(h1, min(h2, h3))
                    if spread3_h <= 0.65 * a:
                        qscore = 1.5 - spread3_h / a
                        if qscore > best_q:
                            best_r = 13; best_d = -1; best_trig = neck_l + off_atr * a
                            best_sl = max(h2, h3); best_h = max(h1, max(h2, h3)) - neck_l; best_piv = ih3; best_q = qscore

        # ------------------------------------------------------------------
        # 2-PEAK / 2-TROUGH PATTERNS (Runes 0..8, 11, 12, 15)
        # ------------------------------------------------------------------
        if span2 <= max_span and w_a >= 0.6 and w_b >= 0.35:
            # --- Rune 8: DBL_BOTTOM (ila < ih_neck < ilb, |lb - la| <= 0.50 ATR)
            if ila < ihb < ilb and abs(dl) <= 0.50 and (hb - min(la, lb)) >= 0.85 * a and unbroken_hi_b:
                qscore = 1.4 - abs(dl)
                if qscore > best_q:
                    best_r = 8; best_d = 1; best_trig = hb - off_atr * a
                    best_sl = lb; best_h = hb - min(la, lb); best_piv = ilb; best_q = qscore

            # --- Rune 12: DBL_TOP (iha < il_neck < ihb, |hb - ha| <= 0.50 ATR)
            if iha < ilb < ihb and abs(dh) <= 0.50 and (max(ha, hb) - lb) >= 0.85 * a and unbroken_lo_b:
                qscore = 1.4 - abs(dh)
                if qscore > best_q:
                    best_r = 12; best_d = -1; best_trig = lb + off_atr * a
                    best_sl = hb; best_h = max(ha, hb) - lb; best_piv = ihb; best_q = qscore

            # --- Rune 0: ASC_TRI (flat top |dh| <= 0.45, rising bottom dl >= 0.20, unbroken top)
            if abs(dh) <= 0.45 and dl >= 0.20 and w_b < w_a and unbroken_top2 and imp >= -0.5:
                qscore = 1.3 - abs(dh) + 0.25 * min(dl, 2.0)
                if qscore > best_q:
                    best_r = 0; best_d = 1; best_trig = top2 - off_atr * a
                    best_sl = lb; best_h = top2 - la; best_piv = ihb; best_q = qscore

            # --- Rune 4: DESC_TRI (flat bottom |dl| <= 0.45, falling top dh <= -0.20, unbroken bottom)
            if abs(dl) <= 0.45 and dh <= -0.20 and w_b < w_a and unbroken_bot2 and imp <= 0.5:
                qscore = 1.3 - abs(dl) + 0.25 * min(-dh, 2.0)
                if qscore > best_q:
                    best_r = 4; best_d = -1; best_trig = bot2 + off_atr * a
                    best_sl = hb; best_h = ha - bot2; best_piv = ilb; best_q = qscore

            # --- Rune 3 & 7: SYMMETRICAL TRIANGLE (dh <= -0.18, dl >= 0.18, contracting)
            if dh <= -0.18 and dl >= 0.18 and w_b <= 0.82 * w_a:
                sym_q = 1.2 + 0.3 * (1.0 - w_b / max(w_a, 1e-6))
                # Rune 3: BULL_SYM_TRI
                if imp >= 0.0 and unbroken_hi_b and sym_q > best_q:
                    best_r = 3; best_d = 1; best_trig = hb - off_atr * a
                    best_sl = lb; best_h = ha - la; best_piv = ihb; best_q = sym_q
                # Rune 7: BEAR_SYM_TRI
                if imp < 0.0 and unbroken_lo_b and sym_q > best_q:
                    best_r = 7; best_d = -1; best_trig = lb + off_atr * a
                    best_sl = hb; best_h = ha - la; best_piv = ilb; best_q = sym_q

            # --- Down-sloping channel / wedge (dh < -0.12 and dl < -0.05) -> BULL_FLAG (2), BULL_WEDGE (1), FALL_WEDGE (11)
            if dh < -0.12 and dl < -0.05 and unbroken_hi_b:
                slope_diff = abs((-dh) - (-dl))
                # Rune 2: BULL_FLAG (strong flagpole >= 2.0 ATR, roughly parallel pullback)
                if bull_pole >= 2.0 and slope_diff <= 0.75 and (ha - lb) <= 0.70 * (ha - pole_lo):
                    qscore = 1.25 + 0.15 * min(bull_pole, 5.0) - 0.3 * slope_diff
                    if qscore > best_q:
                        best_r = 2; best_d = 1; best_trig = hb - off_atr * a
                        best_sl = lb; best_h = ha - pole_lo; best_piv = ihb; best_q = qscore
                # Contracting downward wedge: upper falls steeper than lower (-dh > -dl + 0.08, w_b < 0.88 * w_a)
                if (-dh) > (-dl) + 0.08 and w_b < 0.88 * w_a:
                    qscore = 1.15 + 0.3 * (1.0 - w_b / max(w_a, 1e-6))
                    if imp >= 0.2:
                        # Rune 1: BULL_WEDGE (continuation in uptrend)
                        if qscore > best_q:
                            best_r = 1; best_d = 1; best_trig = hb - off_atr * a
                            best_sl = lb; best_h = ha - lb; best_piv = ihb; best_q = qscore
                    else:
                        # Rune 11: FALL_WEDGE (bullish reversal after down-move)
                        if qscore > best_q:
                            best_r = 11; best_d = 1; best_trig = hb - off_atr * a
                            best_sl = lb; best_h = ha - lb; best_piv = ihb; best_q = qscore

            # --- Up-sloping channel / wedge (dh > 0.05 and dl > 0.12) -> BEAR_FLAG (6), BEAR_WEDGE (5), RISE_WEDGE (15)
            if dh > 0.05 and dl > 0.12 and unbroken_lo_b:
                slope_diff = abs(dl - dh)
                # Rune 6: BEAR_FLAG (strong bear flagpole >= 2.0 ATR, roughly parallel pullback)
                if bear_pole >= 2.0 and slope_diff <= 0.75 and (hb - la) <= 0.70 * (pole_hi - la):
                    qscore = 1.25 + 0.15 * min(bear_pole, 5.0) - 0.3 * slope_diff
                    if qscore > best_q:
                        best_r = 6; best_d = -1; best_trig = lb + off_atr * a
                        best_sl = hb; best_h = pole_hi - la; best_piv = ilb; best_q = qscore
                # Contracting upward wedge: lower rises steeper than upper (dl > dh + 0.08, w_b < 0.88 * w_a)
                if dl > dh + 0.08 and w_b < 0.88 * w_a:
                    qscore = 1.15 + 0.3 * (1.0 - w_b / max(w_a, 1e-6))
                    if imp <= -0.2:
                        # Rune 5: BEAR_WEDGE (continuation in downtrend)
                        if qscore > best_q:
                            best_r = 5; best_d = -1; best_trig = lb + off_atr * a
                            best_sl = hb; best_h = hb - la; best_piv = ilb; best_q = qscore
                    else:
                        # Rune 15: RISE_WEDGE (bearish reversal after up-move)
                        if qscore > best_q:
                            best_r = 15; best_d = -1; best_trig = lb + off_atr * a
                            best_sl = hb; best_h = hb - la; best_piv = ilb; best_q = qscore

        if best_r >= 0:
            rune_id[i] = best_r
            rune_dir[i] = best_d
            trig_px[i] = best_trig
            sl_px[i] = best_sl
            pat_h[i] = best_h
            piv_idx[i] = best_piv
            qual[i] = best_q

    return rune_id, rune_dir, trig_px, sl_px, pat_h, piv_idx, qual


@njit(cache=True)
def rune_stop_events_nb(rune_id, rune_dir, trig_px, sl_px, pat_h, piv_idx, qual,
                        atr, gate, m1s, m1e, mo, mh, ml, mspr, slip_in, max_dist_atr):
    """Simulate virtual stop-order triggers armed at structure bar p close, valid during bar p+1.

    gate[p]:
      0   -> no filter (allow all)
      +1  -> allow long runes (+1)
      -1  -> allow short runes (-1)
      99  -> allow both
    Enforces one shot per (rune_id, piv_idx) so the same pattern is never machine-gunned.
    """
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
                    out_sl[k] = sl_px[p]; out_ph[k] = pat_h[p]; out_q[k] = qual[p]
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
                    out_sl[k] = sl_px[p]; out_ph[k] = pat_h[p]; out_q[k] = qual[p]
                    k += 1
                    used_piv[rid] = piv
                    break
    return out_j[:k], out_d[:k], out_px[:k], out_r[:k], out_p[:k], out_sl[:k], out_ph[:k], out_q[:k]


def build_tfs(m1a):
    nyl = M.ny_local_minutes(m1a["t"])
    tfs = {}
    for name, mins in (("M15", 15), ("M30", 30), ("H1", 60), ("H2", 120)):
        tfs[name] = M.tf_states(E.make_bars(m1a, mins), RIBBON)
    tfs["H4"] = M.tf_states(M.make_bars_ny(m1a, 4, nyl), RIBBON)
    tfs["D1"] = M.tf_states(M.make_bars_ny(m1a, 24, nyl), RIBBON)
    return tfs


if __name__ == "__main__":
    t0 = time.time()
    src = sys.argv[1] if len(sys.argv) > 1 else "duka"
    m1 = D.load(f"{src}_m1")
    m1a = E.m1_arrays(m1, src)
    tfs = build_tfs(m1a)
    print(f"loaded {src} ({len(m1):,} M1 bars) in {time.time() - t0:.1f}s")

    # Compute HTF stack states
    st = {}
    for tf in ("M15", "M30", "H1", "H2", "H4", "D1"):
        T = tfs[tf]
        Em = T["E"]
        sc = np.sign(-np.diff(Em, axis=0)).sum(axis=0)
        st[tf] = np.where(sc >= 6, 1, np.where(sc <= -6, -1, 0)).astype(np.int64)

    mg = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=3.0, max_min=1440)
    a1 = tfs["H1"]["atr"]

    for tf_name in ("M15", "M30", "H1", "H2"):
        T = tfs[tf_name]
        rid, rdir, tpx, slpx, path, piv, qual = detect_16runes_nb(
            T["o"], T["h"], T["l"], T["c"], T["atr"], T["E"][0], T["E"][6], 3, 3, 0.10, 72
        )
        # Test 3 gating modes: raw (all), H4 stack, H4+D1 stack
        k_h4 = np.maximum(M.map_last_closed(tfs["H4"], T["t_close"]), 0)
        k_d1 = np.maximum(M.map_last_closed(tfs["D1"], T["t_close"]), 0)
        k_h1 = np.maximum(M.map_last_closed(tfs["H1"], T["t_close"]), 0)
        g_raw = np.full(T["n"], 99, np.int64)
        g_h4 = st["H4"][k_h4]
        g_h4d1 = np.where(st["H4"][k_h4] == st["D1"][k_d1], st["H4"][k_h4], 0).astype(np.int64)
        g_h1h4 = np.where(st["H1"][k_h1] == st["H4"][k_h4], st["H1"][k_h1], 0).astype(np.int64)

        print(f"\n==================== Timeframe {tf_name} ====================")
        for gname, g in (("RAW (no HTF gate)", g_raw), ("H4 7-EMA gate", g_h4),
                         ("H1+H4 7-EMA gate", g_h1h4), ("H4+D1 7-EMA gate", g_h4d1)):
            j, d, px, r_id, p_idx, sl_p, ph_p, q_p = rune_stop_events_nb(
                rid, rdir, tpx, slpx, path, piv, qual, T["atr"], g,
                T["m1s"], T["m1e"], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], 0.05, 3.0
            )
            if len(j) == 0:
                continue
            kh1 = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][j]), 0)
            at = a1[kh1]
            tr = S2.run_fills(m1a, j, d, px, 1.5 * at, 2.0 * at, mg, one_at_a_time=False,
                              meta={"rune": r_id, "qual": q_p, "pat_h": ph_p / at})
            tr = tr[tr.year >= 2017]
            ins = tr[tr.year <= 2023]
            oos = tr[tr.year >= 2024]
            yr_all = tr.groupby("year").r.sum()
            print(f"  {gname:20s}: n={len(tr):5d}  wr={(tr.r > 0).mean()*100:4.1f}%  avgR={tr.r.mean():+.3f}  "
                  f"2017-23={ins.r.sum():+6.1f}R ({ins.r.mean():+.3f}/tr)  "
                  f"2024-26={oos.r.sum():+6.1f}R ({oos.r.mean():+.3f}/tr)  "
                  f"green_yrs={int((yr_all > 0).sum())}/{len(yr_all)}")
            if gname in ("H4 7-EMA gate", "H4+D1 7-EMA gate"):
                for r_k in range(16):
                    sub = tr[tr.rune == r_k]
                    if len(sub) > 0:
                        s_in = sub[sub.year <= 2023]
                        s_oo = sub[sub.year >= 2024]
                        print(f"    [{r_k:2d}] {RUNE_NAMES[r_k]:14s}: n={len(sub):4d}  avgR={sub.r.mean():+.3f}  "
                              f"in={s_in.r.mean() if len(s_in) else 0:+.3f} ({len(s_in):3d})  "
                              f"oos={s_oo.r.mean() if len(s_oo) else 0:+.3f} ({len(s_oo):3d})")
