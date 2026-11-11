"""SevenWave v1.10 research: geometric ribbon 10/16/26/41/66/105/168 + cadence streams.

Streams (gate = 7-EMA stacks of the listed higher timeframes, all with the SAME ribbon):
  A  H1 pools  | H4+D1   age 12-48   off 0.15     B  H2 pools | H4+D1  age 6-48  off 0.00
  C  H1 pools  | H4      age 12-120  off 0.15     E  H1 pools | H1     age 12-48 off 0.15
  F  M30 pools | H1+H4   age 12-96   off 0.15     G  H1 pools | H4+D1  age 3-12  off 0.15
  P  M15 pools | H1+H4+D1 age 12-96  off 0.15     W  M15 fresh wave (ribbon realign) | H1+H4+D1 (market entry)
  python sw_v110.py streams     # per-stream edge with the new ribbon
  python sw_v110.py grid        # portfolio + prop-challenge grid (selection 2017-2022, unseen 2023-2026)
"""
import sys
import time
import itertools
import numpy as np
import pandas as pd
_argv = list(sys.argv)
sys.argv = [sys.argv[0], (sys.argv[2] if len(sys.argv) > 2 else "duka")]
import sw_study22 as S22
sys.argv = _argv
import sw_engine as E
import sw_mtf as M
import sw_sim2 as S2
import sw_challenge as CH
from sw_study17 import pools_nb, pool_stop_events_nb

RIBBON = (10, 16, 26, 41, 66, 105, 168)
NAMES = ["A", "B", "C", "E", "F", "G", "P", "W"]
POOL_STREAMS = {"A": ("H1", ("H4", "D1"), 0.15, 12, 48), "B": ("H2", ("H4", "D1"), 0.0, 6, 48),
                "C": ("H1", ("H4",), 0.15, 12, 120), "E": ("H1", ("H1",), 0.15, 12, 48),
                "F": ("M30", ("H1", "H4"), 0.15, 12, 96), "G": ("H1", ("H4", "D1"), 0.15, 3, 12),
                "P": ("M15", ("H1", "H4", "D1"), 0.15, 12, 96)}
MGMT = {"growth": S22.MGMT["growth"], "prop": S22.MGMT["prop"],
        "mid": (dict(tp1_r=1.0, tp1_frac=0.3, be_r=0.05, act_r=1.5, tp2_r=3.0, max_min=2880), 1.5, 1.5)}
m1a, tfs = S22.m1a, S22.tfs
if "M15" not in tfs or "ribbon" not in tfs.get("M15", {}):
    tfs["M15"] = M.tf_states(E.make_bars(m1a, 15))
POOLS = dict(S22.POOLS)
POOLS["M15"] = pools_nb(tfs["M15"]["h"], tfs["M15"]["l"], 3, 3)


def stacks(per=RIBBON):
    st, rib = {}, {}
    for tf in ("M15", "M30", "H1", "H2", "H4", "D1"):
        T = tfs[tf]
        Em = np.vstack([E.ema_nb(T["c"], float(p)) for p in per])
        sc = np.sign(-np.diff(Em, axis=0)).sum(axis=0)
        st[tf] = np.where(sc >= 6, 1, np.where(sc <= -6, -1, 0)).astype(np.int64)
        rib[tf] = np.where((st[tf] == 1) & (T["c"] > Em[0]), 1, np.where((st[tf] == -1) & (T["c"] < Em[0]), -1, 0))
    return st, rib


def gate(st, T, names):
    o = None
    for h in names:
        k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
        sd = st[h][k]
        o = sd if o is None else np.where(o == sd, sd, 0)
    return o.astype(np.int64)


def all_events(per=RIBBON, use=NAMES):
    st, rib = stacks(per)
    a1 = tfs["H1"]["atr"]
    J, D, PX, AT, SI = [], [], [], [], []
    for si, nm in enumerate(NAMES):
        if nm not in use:
            continue
        if nm == "W":
            T = tfs["M15"]
            g = gate(st, T, ("H1", "H4", "D1"))
            rb = rib["M15"]
            r = np.zeros(T["n"], np.int64)
            r[1:] = np.where((rb[1:] == 1) & (rb[:-1] != 1) & (g[1:] == 1), 1,
                             np.where((rb[1:] == -1) & (rb[:-1] != -1) & (g[1:] == -1), -1, 0))
            idx = np.flatnonzero(r != 0)
            idx = idx[(idx > 2000) & (idx < T["n"] - 1)]
            j = T["m1e"][idx]
            ok = (m1a["t"][np.minimum(j, len(m1a["t"]) - 1)] - m1a["t"][j - 1]) <= 1800
            idx, j = idx[ok], j[ok]
            d = r[idx]
            px = np.where(d > 0, m1a["o"][j] + m1a["spr"][j] + 0.05, m1a["o"][j] - 0.05)
        else:
            S, filt, off, amin, amax = POOL_STREAMS[nm]
            T = tfs[S]
            ph, phi, pl, pli = POOLS[S]
            j, d, px, _ = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], gate(st, T, filt), T["m1s"], T["m1e"], m1a["o"],
                                             m1a["h"], m1a["l"], m1a["spr"], off, amin, amax, 0.05, 3.0)
        k = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][j]), 0)
        J.append(j); D.append(d); PX.append(px); AT.append(a1[k]); SI.append(np.full(len(j), si))
    J = np.concatenate(J); D = np.concatenate(D); PX = np.concatenate(PX); AT = np.concatenate(AT); SI = np.concatenate(SI)
    o = np.lexsort((SI, J))
    J, D, PX, AT, SI = J[o], D[o], PX[o], AT[o], SI[o]
    keep = np.r_[True, np.diff(J) > 0]
    return J[keep], D[keep], PX[keep], AT[keep], SI[keep]


def outcomes(ev, mode):
    mg, slk, trk = MGMT[mode]
    J, D, PX, AT, SI = ev
    return S2.run_fills(m1a, J, D, PX, slk * AT, trk * AT, mg, one_at_a_time=False, meta={"stream": SI})


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "streams"
    t0 = time.time()
    ev = all_events(use=["A", "B", "G", "P", "W"])
    if what == "streams":
        for mode in ("growth", "prop", "mid"):
            tr = outcomes(ev, mode)
            print(f"\n=== {mode} management, ribbon {RIBBON} ===")
            for si, nm in enumerate(NAMES):
                g = tr[tr.stream == si]
                if len(g) == 0:
                    continue
                yr = g.groupby("year").r.sum()
                days = (g.entry_t.max() - g.entry_t.min()) / 86400 * 5 / 7
                print(f"{nm}: n={len(g):5d} tpd={len(g) / days:.2f} wr={(g.r > 0).mean() * 100:4.1f} avgR={g.r.mean():+.3f} "
                      f"ins={yr[yr.index <= 2022].sum():+6.1f} ({int((yr[yr.index <= 2022] > 0).sum())}/6) "
                      f"oos={yr[yr.index >= 2023].sum():+6.1f} ({int((yr[yr.index >= 2023] > 0).sum())}/4)")
    else:
        WEIGHTS = {"edge": np.array([1.0, 1.0, 0.0, 0.0, 0.0, 0.6, 0.8, 0.6]),
                   "flat": np.ones(8)}
        rows = []
        for mode in ("growth", "mid", "prop"):
            tr = outcomes(ev, mode)
            for wname, w in WEIGHTS.items():
                CH.WEIGHT = w
                for risk, K, cap in itertools.product((0.5, 1.0, 1.5), (1, 2, 3), (0.0, 2.4)):
                    ch = CH.run_challenges(tr, risk, K=K, target=8.0, cons=0.30, daily=3.0, maxdd=6.0, max_days=180,
                                           step_days=7, day_cap_pct=cap)
                    a = CH.summarise(ch, 2017, 2022); b = CH.summarise(ch, 2023, 2026)
                    rows.append(dict(mode=mode, w=wname, risk=risk, K=K, cap=cap, **{f"is_{k}": v for k, v in a.items()},
                                     **{f"oos_{k}": v for k, v in b.items()}))
            print(f"{time.time() - t0:5.0f}s {mode}")
        R = pd.DataFrame(rows)
        R["is_obj"] = R.is_pass_ - R.is_breach * 3 - R.is_med_days.fillna(180) / 6
        R.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\v110_challenge.csv", index=False)
        pd.set_option("display.width", 260)
        cols = ["mode", "w", "risk", "K", "cap", "is_pass_", "is_breach", "is_timeout", "is_med_days", "is_p75_days",
                "oos_pass_", "oos_breach", "oos_timeout", "oos_med_days", "oos_p75_days"]
        print(R.sort_values("is_obj", ascending=False)[cols].head(25).to_string(index=False))


