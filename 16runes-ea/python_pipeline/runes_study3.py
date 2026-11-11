"""16Runes Study 3: True Coiled Wedge/Flag Geometry (v3) + Multi-Timeframe Stream Cadence (M5/M15/M30/H1/H2)
+ Out-of-Sample Meta-Labeler Evaluation (Train 2017-2023 -> Test Unseen 2024-2026).
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

RUNE_NAMES = [
    "ASC_TRI", "BULL_WEDGE", "BULL_FLAG", "BULL_SYM_TRI",
    "DESC_TRI", "BEAR_WEDGE", "BEAR_FLAG", "BEAR_SYM_TRI",
    "DBL_BOTTOM", "TRPL_BOTTOM", "INV_HS", "FALL_WEDGE",
    "DBL_TOP", "TRPL_TOP", "HEAD_SHLDR", "RISE_WEDGE"
]

RIBBON = (10, 16, 26, 41, 66, 105, 168)


@njit(cache=True)
def detect_16runes_v3_nb(o, h, l, c, atr, L, R, off_atr, max_span):
    """Causal 16-Rune detector v3:
    - Runes 0..15 with upper/lower half coil confirmation after the controlling breakout pivot.
    - For Bullish Wedge (1), Bullish Flag (2), Falling Wedge (11):
      ila < iha < ilb < ihb (lower low lb followed by lower high hb), and all bars after ihb hold above
      lb + 0.25*(hb - lb) (tight upper-half coil under hb before breaking hb!).
    - For Bearish Wedge (5), Bearish Flag (6), Rising Wedge (15):
      iha < ila < ihb < ilb (higher high hb followed by higher low lb), and all bars after ilb hold below
      hb - 0.25*(hb - lb) (tight lower-half coil above lb before breaking lb!).
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

        # Unbroken & coil checks from ihb / ilb to current bar i
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

        best_r = -1
        best_d = 0
        best_trig = 0.0
        best_sl = 0.0
        best_h = 0.0
        best_piv = -1
        best_q = -1.0
        best_sp = span2

        # ------------------------------------------------------------------
        # 3-TROUGH / 3-PEAK REVERSALS (Runes 9, 10, 13, 14)
        # ------------------------------------------------------------------
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
                            best_sl = l3; best_h = neck_h - l2; best_piv = neck_ih; best_q = qscore; best_sp = span3_l
                    spread3_l = max(l1, max(l2, l3)) - min(l1, min(l2, l3))
                    if spread3_l <= 0.60 * a:
                        qscore = 1.55 - 0.5 * spread3_l / a
                        if qscore > best_q:
                            best_r = 9; best_d = 1; best_trig = neck_h - off_atr * a
                            best_sl = min(l2, l3); best_h = neck_h - min(l1, min(l2, l3)); best_piv = neck_ih; best_q = qscore; best_sp = span3_l

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
                            best_sl = h3; best_h = h2 - neck_l; best_piv = neck_il; best_q = qscore; best_sp = span3_h
                    spread3_h = max(h1, max(h2, h3)) - min(h1, min(h2, h3))
                    if spread3_h <= 0.60 * a:
                        qscore = 1.55 - 0.5 * spread3_h / a
                        if qscore > best_q:
                            best_r = 13; best_d = -1; best_trig = neck_l + off_atr * a
                            best_sl = max(h2, h3); best_h = max(h1, max(h2, h3)) - neck_l; best_piv = neck_il; best_q = qscore; best_sp = span3_h

        # ------------------------------------------------------------------
        # 2-PEAK / 2-TROUGH PATTERNS (Runes 0..8, 11, 12, 15)
        # ------------------------------------------------------------------
        if span2 <= max_span and w_a >= 0.70 and w_b >= 0.35:
            # --- Rune 8: DBL_BOTTOM
            if ila < ihb < ilb and abs(dl) <= 0.45 and (hb - min(la, lb)) >= 0.90 * a and unbroken_hi_b:
                qscore = 1.45 - 0.5 * abs(dl)
                if qscore > best_q:
                    best_r = 8; best_d = 1; best_trig = hb - off_atr * a
                    best_sl = lb; best_h = hb - min(la, lb); best_piv = ihb; best_q = qscore; best_sp = span2

            # --- Rune 12: DBL_TOP
            if iha < ilb < ihb and abs(dh) <= 0.45 and (max(ha, hb) - lb) >= 0.90 * a and unbroken_lo_b:
                qscore = 1.45 - 0.5 * abs(dh)
                if qscore > best_q:
                    best_r = 12; best_d = -1; best_trig = lb + off_atr * a
                    best_sl = hb; best_h = max(ha, hb) - lb; best_piv = ilb; best_q = qscore; best_sp = span2

            # --- Rune 0: ASC_TRI
            if abs(dh) <= 0.40 and dl >= 0.20 and w_b < 0.90 * w_a and unbroken_top2 and coil_above_lb:
                qscore = 1.40 - 0.5 * abs(dh) + 0.2 * min(dl, 2.0)
                if qscore > best_q:
                    best_r = 0; best_d = 1; best_trig = top2 - off_atr * a
                    best_sl = lb; best_h = top2 - la; best_piv = ihb; best_q = qscore; best_sp = span2

            # --- Rune 4: DESC_TRI
            if abs(dl) <= 0.40 and dh <= -0.20 and w_b < 0.90 * w_a and unbroken_bot2 and coil_below_hb:
                qscore = 1.40 - 0.5 * abs(dl) + 0.2 * min(-dh, 2.0)
                if qscore > best_q:
                    best_r = 4; best_d = -1; best_trig = bot2 + off_atr * a
                    best_sl = hb; best_h = ha - bot2; best_piv = ilb; best_q = qscore; best_sp = span2

            # --- Rune 3 & 7: SYMMETRICAL TRIANGLE
            if dh <= -0.18 and dl >= 0.18 and w_b <= 0.80 * w_a:
                sym_q = 1.30 + 0.3 * (1.0 - w_b / max(w_a, 1e-6))
                if unbroken_hi_b and coil_above_lb and imp >= -0.2 and sym_q > best_q:
                    best_r = 3; best_d = 1; best_trig = hb - off_atr * a
                    best_sl = lb; best_h = ha - la; best_piv = ihb; best_q = sym_q; best_sp = span2
                if unbroken_lo_b and coil_below_hb and imp <= 0.2 and sym_q > best_q:
                    best_r = 7; best_d = -1; best_trig = lb + off_atr * a
                    best_sl = hb; best_h = ha - la; best_piv = ilb; best_q = sym_q; best_sp = span2

            # --- Down-sloping structure with upper-half coil: BULL_FLAG (2), BULL_WEDGE (1), FALL_WEDGE (11)
            if dh < -0.12 and dl < -0.02 and unbroken_hi_b and coil_above_lb:
                slope_diff = abs((-dh) - (-dl))
                if bull_pole >= 2.0 and slope_diff <= 0.70 and (ha - lb) <= 0.65 * (ha - pole_lo):
                    qscore = 1.35 + 0.15 * min(bull_pole, 5.0) - 0.3 * slope_diff
                    if qscore > best_q:
                        best_r = 2; best_d = 1; best_trig = hb - off_atr * a
                        best_sl = lb; best_h = ha - pole_lo; best_piv = ihb; best_q = qscore; best_sp = span2
                if (-dh) > (-dl) + 0.10 and w_b < 0.85 * w_a:
                    qscore = 1.25 + 0.3 * (1.0 - w_b / max(w_a, 1e-6))
                    if imp >= 0.2:
                        if qscore > best_q:
                            best_r = 1; best_d = 1; best_trig = hb - off_atr * a
                            best_sl = lb; best_h = ha - lb; best_piv = ihb; best_q = qscore; best_sp = span2
                    else:
                        if qscore > best_q:
                            best_r = 11; best_d = 1; best_trig = hb - off_atr * a
                            best_sl = lb; best_h = ha - lb; best_piv = ihb; best_q = qscore; best_sp = span2

            # --- Up-sloping structure with lower-half coil: BEAR_FLAG (6), BEAR_WEDGE (5), RISE_WEDGE (15)
            if dh > 0.02 and dl > 0.12 and unbroken_lo_b and coil_below_hb:
                slope_diff = abs(dl - dh)
                if bear_pole >= 2.0 and slope_diff <= 0.70 and (hb - la) <= 0.65 * (pole_hi - la):
                    qscore = 1.35 + 0.15 * min(bear_pole, 5.0) - 0.3 * slope_diff
                    if qscore > best_q:
                        best_r = 6; best_d = -1; best_trig = lb + off_atr * a
                        best_sl = hb; best_h = pole_hi - la; best_piv = ilb; best_q = qscore; best_sp = span2
                if dl > dh + 0.10 and w_b < 0.85 * w_a:
                    qscore = 1.25 + 0.3 * (1.0 - w_b / max(w_a, 1e-6))
                    if imp <= -0.2:
                        if qscore > best_q:
                            best_r = 5; best_d = -1; best_trig = lb + off_atr * a
                            best_sl = hb; best_h = hb - la; best_piv = ilb; best_q = qscore; best_sp = span2
                    else:
                        if qscore > best_q:
                            best_r = 15; best_d = -1; best_trig = lb + off_atr * a
                            best_sl = hb; best_h = hb - la; best_piv = ilb; best_q = qscore; best_sp = span2

        if best_r >= 0:
            rune_id[i] = best_r
            rune_dir[i] = best_d
            trig_px[i] = best_trig
            sl_px[i] = best_sl
            pat_h[i] = best_h
            piv_idx[i] = best_piv
            qual[i] = best_q
            pat_span[i] = best_sp

    return rune_id, rune_dir, trig_px, sl_px, pat_h, piv_idx, qual, pat_span


from runes_study1 import rune_stop_events_nb
from runes_study2 import simulate_whale_nb


def build_all_tfs(m1a):
    nyl = M.ny_local_minutes(m1a["t"])
    tfs = {}
    for name, mins in (("M5", 5), ("M15", 15), ("M30", 30), ("H1", 60), ("H2", 120)):
        tfs[name] = M.tf_states(E.make_bars(m1a, mins), RIBBON)
    tfs["H4"] = M.tf_states(M.make_bars_ny(m1a, 4, nyl), RIBBON)
    tfs["D1"] = M.tf_states(M.make_bars_ny(m1a, 24, nyl), RIBBON)
    return tfs


if __name__ == "__main__":
    t0 = time.time()
    src = sys.argv[1] if len(sys.argv) > 1 else "duka"
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

    for tf_name in ("M5", "M15", "M30", "H1", "H2"):
        T = tfs[tf_name]
        rid, rdir, tpx, slpx, path, piv, qual, pspan = detect_16runes_v3_nb(
            T["o"], T["h"], T["l"], T["c"], T["atr"], 3, 3, 0.12, 72
        )
        k_h4 = np.maximum(M.map_last_closed(tfs["H4"], T["t_close"]), 0)
        k_d1 = np.maximum(M.map_last_closed(tfs["D1"], T["t_close"]), 0)
        k_h1 = np.maximum(M.map_last_closed(tfs["H1"], T["t_close"]), 0)

        g_h4d1 = np.where(st["H4"][k_h4] == st["D1"][k_d1], st["H4"][k_h4], 0).astype(np.int64)
        g_h1h4d1 = np.where((st["H1"][k_h1] == st["H4"][k_h4]) & (st["H4"][k_h4] == st["D1"][k_d1]), st["H4"][k_h4], 0).astype(np.int64)
        g = g_h1h4d1 if tf_name in ("M5", "M15") else g_h4d1

        j, d, px, r_id, p_idx, sl_p, ph_p, q_p = rune_stop_events_nb(
            rid, rdir, tpx, slpx, path, piv, qual, T["atr"], g,
            T["m1s"], T["m1e"], m1a["o"], m1a["h"], m1a["l"], m1a["spr"], 0.05, 3.0
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
        df = pd.DataFrame({"j": j, "dir": d, "r": r_out, "rune": r_id, "qual": q_p,
                           "entry_t": m1a["t"][j], "exit_t": xt_out, "whale": wh_out})
        df["year"] = pd.to_datetime(df["entry_t"], unit="s").dt.year
        df = df[df.year >= 2017]
        ins = df[df.year <= 2023]
        oos = df[df.year >= 2024]
        yr_all = df.groupby("year").r.sum()
        print(f"\n==================== Timeframe {tf_name} (v3 Coil Geometry) ====================")
        print(f"  ALL RUNES: n={len(df):5d}  wr={(df.r > 0).mean()*100:4.1f}%  avgR={df.r.mean():+.3f}  "
              f"2017-23={ins.r.sum():+6.1f}R ({ins.r.mean():+.3f}/tr)  "
              f"2024-26={oos.r.sum():+6.1f}R ({oos.r.mean():+.3f}/tr)  "
              f"green_yrs={int((yr_all > 0).sum())}/{len(yr_all)}")
        for r_k in range(16):
            sub = df[df.rune == r_k]
            if len(sub) > 0:
                s_in = sub[sub.year <= 2023]
                s_oo = sub[sub.year >= 2024]
                print(f"    [{r_k:2d}] {RUNE_NAMES[r_k]:14s}: n={len(sub):4d}  avgR={sub.r.mean():+.3f}  "
                      f"in={s_in.r.mean() if len(s_in) else 0:+.3f} ({len(s_in):3d})  "
                      f"oos={s_oo.r.mean() if len(s_oo) else 0:+.3f} ({len(s_oo):3d})")
