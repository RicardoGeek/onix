"""sw_sim3: sw_sim2 plus two FAILED-BREAKOUT exits (study 50).
  nf_min / nf_r: at nf_min minutes after the fill, if the best excursion is still below nf_r R, exit at the next open.
  bi_tf / bi_r: at every close of a bi_tf-second bar, if the close is more than bi_r R beyond the entry against the trade, exit at the next open.

Fill-accurate SevenWave trade simulator for STOP-order entries (one position at a time).

Each entry: M1 fill index j, direction, fill price (already includes slippage), stop distance R ($), trail distance
($).  Management (all in R of the initial stop):
  TP1 partial (tp1_r, tp1_frac) -> stop to break-even + be_r;  ratchet: when MFE >= act_r, stop trails
  at (best price - trail_dist) evaluated on COMPLETED M1 bars;  optional TP2 (tp2_r);  time stop max_min.
Pessimism: in the fill minute no favourable excursion is credited but the adverse extreme counts; stop before
target inside any minute; gaps through the stop fill at the open minus slippage; long swap charged per rollover.
"""
import numpy as np
import pandas as pd
from numba import njit

COMM = 0.07        # $/oz round trip (Pepperstone Razor $7/lot)
SLIP_STOP = 0.10   # $/oz on every stop exit
SLIP_MKT = 0.05    # $/oz on market (time-stop) exits
SWAP_LONG = -0.80  # $/oz per rollover, x3 Wednesday
SWAP_SHORT = 0.0


@njit(cache=False)
def simulate_fills_nb(ej, ed, ep, eR, etrail, mt, mo, mh, ml, mc, mspr, mtday, mdow,
                      tp1_r, tp1_frac, be_r, act_r, tp2_r, max_min, comm, slip_stop, slip_mkt, swap_l, swap_s,
                      one_at_a_time, nf_min, nf_r, bi_tf, bi_r):
    ne = len(ej)
    taken = np.zeros(ne, np.int64)
    out_r = np.zeros(ne); out_xt = np.zeros(ne, np.int64); out_tp1 = np.zeros(ne, np.int64)
    out_mfe = np.zeros(ne); out_why = np.zeros(ne, np.int64)
    nm = len(mc)
    busy = -1
    for e in range(ne):
        j = ej[e]
        if j >= nm or (one_at_a_time and j <= busy):
            continue
        d = ed[e]; px0 = ep[e]; R = eR[e]; tdist = etrail[e]
        sl = px0 - d * R
        tp1 = px0 + d * tp1_r * R
        tp2 = px0 + d * tp2_r * R
        pos = 1.0; realized = 0.0; done1 = False
        ext = px0; swap = 0.0; last_day = mtday[j]; why = 5; nf_done = False
        k = j
        while k < nm:
            if mtday[k] != last_day:
                mult = 3.0 if mdow[k] == 2 else 1.0
                swap += pos * (swap_l if d == 1 else swap_s) * mult
                last_day = mtday[k]
            sp = mspr[k]
            if d == 1:
                o_ = mo[k]; h_ = mh[k]; l_ = ml[k]; c_ = mc[k]
            else:
                o_ = mo[k] + sp; h_ = mh[k] + sp; l_ = ml[k] + sp; c_ = mc[k] + sp
            adverse = l_ if d == 1 else h_
            favor = h_ if d == 1 else l_
            if k > j and d * (o_ - sl) <= 0:
                px = o_ - d * slip_stop
                realized += pos * d * (px - px0); pos = 0.0; why = 1
                break
            if d * (adverse - sl) <= 0:
                px = sl - d * slip_stop
                realized += pos * d * (px - px0); pos = 0.0; why = 1
                break
            if k > j:
                if (not done1) and tp1_frac > 0 and d * (favor - tp1) >= 0:
                    realized += tp1_frac * d * (tp1 - px0)
                    pos -= tp1_frac
                    done1 = True
                    nsl = px0 + d * be_r * R
                    if d * (nsl - sl) > 0:
                        sl = nsl
                if tp2_r > 0 and d * (favor - tp2) >= 0:
                    realized += pos * d * (tp2 - px0); pos = 0.0; why = 2
                    break
                if d * (favor - ext) > 0:
                    ext = favor
            if nf_min > 0 and (not nf_done) and (mt[k] - mt[j]) >= nf_min * 60:
                nf_done = True
                if d * (ext - px0) < nf_r * R:
                    if k + 1 < nm:
                        k += 1
                        px = (mo[k] - slip_mkt) if d == 1 else (mo[k] + mspr[k] + slip_mkt)
                        realized += pos * d * (px - px0); pos = 0.0; why = 4
                    break
            if bi_tf > 0 and k > j and (mt[k] + 60) % bi_tf == 0 and d * (c_ - px0) < -bi_r * R:
                if k + 1 < nm:
                    k += 1
                    px = (mo[k] - slip_mkt) if d == 1 else (mo[k] + mspr[k] + slip_mkt)
                    realized += pos * d * (px - px0); pos = 0.0; why = 6
                break
            # completed-M1-bar ratchet
            if d * (ext - px0) >= act_r * R and tdist > 0:
                lvl = ext - d * tdist
                if d * (lvl - sl) > 0 and d * (c_ - lvl) > 0:
                    sl = lvl
            if max_min > 0 and (mt[k] - mt[j]) >= max_min * 60:
                if k + 1 < nm:
                    k += 1
                    px = (mo[k] - slip_mkt) if d == 1 else (mo[k] + mspr[k] + slip_mkt)
                    realized += pos * d * (px - px0); pos = 0.0; why = 3
                break
            k += 1
        if pos > 0:
            k = min(k, nm - 1)
            realized += pos * d * (mc[k] - px0)
        taken[e] = 1
        out_r[e] = (realized - comm + swap) / R
        out_xt[e] = mt[min(k, nm - 1)]
        out_tp1[e] = 1 if done1 else 0
        out_mfe[e] = d * (ext - px0) / R
        out_why[e] = why
        busy = k
    return taken, out_r, out_xt, out_tp1, out_mfe, out_why


def run_fills(m1a, ej, ed, ep, eR, etrail, mg, one_at_a_time=True, meta=None):
    o = np.argsort(ej, kind="stable")
    ej, ed, ep, eR, etrail = ej[o], ed[o], ep[o], eR[o], etrail[o]
    res = simulate_fills_nb(ej.astype(np.int64), ed.astype(np.int64), ep.astype(np.float64), eR.astype(np.float64),
                            etrail.astype(np.float64), m1a["t"], m1a["o"], m1a["h"], m1a["l"], m1a["c"], m1a["spr"],
                            m1a["tday"], m1a["nydow"], float(mg.get("tp1_r", 0.5)), float(mg.get("tp1_frac", 0.5)),
                            float(mg.get("be_r", 0.05)), float(mg.get("act_r", 1.0)), float(mg.get("tp2_r", 0.0)),
                            int(mg.get("max_min", 0)), COMM, SLIP_STOP, SLIP_MKT, SWAP_LONG, SWAP_SHORT,
                            bool(one_at_a_time), int(mg.get("nf_min", 0)), float(mg.get("nf_r", 0.0)),
                            int(mg.get("bi_tf", 0)), float(mg.get("bi_r", 0.0)))
    taken, r, xt, tp1, mfe, why = res
    m = taken == 1
    df = pd.DataFrame({"eidx": o[m], "j": ej[m], "dir": ed[m], "r": r[m], "entry_t": m1a["t"][ej[m]], "exit_t": xt[m],
                       "tp1": tp1[m], "mfe": mfe[m], "why": why[m], "R": eR[m], "entry_px": ep[m]})
    if meta is not None:
        for k, v in meta.items():
            df[k] = np.asarray(v)[o][m]
    df["entry_dt"] = pd.to_datetime(df["entry_t"], unit="s")
    df["year"] = df["entry_dt"].dt.year
    return df
