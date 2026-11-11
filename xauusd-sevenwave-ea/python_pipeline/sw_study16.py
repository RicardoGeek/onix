"""Study 16: hierarchy variants traded with the real management (one position at a time), frequency + idle gaps.
Setup streams: M15 realign (gated by higher-TF stacks) and H1 realign (gated by H4/D1).  Optional H1 stack-age window
(the 'fresh higher-TF wave').  Reports per-year sumR, WR, trades/day, max idle hours."""
import sys
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E
import sw_mtf as M

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
tfs = M.build_hierarchy(m1a)
MG = dict(tp1_r=0.25, tp1_frac=0.5, be_r=0.05, trail_mode=2, trail_k=3.0, trail_act_r=0.25, tp2_r=0.0, max_bars=96)


def realigns(T):
    rib = T["ribbon"]
    r = np.zeros(T["n"], np.int64)
    r[1:] = np.where((rib[1:] == 1) & (rib[:-1] != 1), 1, np.where((rib[1:] == -1) & (rib[:-1] != -1), -1, 0))
    return r


def stream(dec, gate, age_tf=None, age_lo=0, age_hi=10 ** 9):
    T = tfs[dec]
    r = realigns(T)
    idx = np.flatnonzero(r != 0)
    idx = idx[(idx > 400) & (idx < T["n"] - 1)]
    d = r[idx]
    ok = np.ones(len(idx), bool)
    for h in gate:
        k = np.maximum(M.map_last_closed(tfs[h], T["t_close"][idx]), 0)
        ok &= tfs[h]["stackd"][k] == d
        if h == age_tf:
            ag = tfs[h]["sage"][k]
            ok &= (ag >= age_lo) & (ag < age_hi)
    # express as M15-bar signals so all streams share one simulator/time axis
    t_sig = T["t_close"][idx[ok]]
    b = tfs["M15"]
    bi = np.searchsorted(b["t_close"], t_sig, side="right") - 1
    return bi, d[ok], (T["atr"][idx[ok]] if dec != "M15" else b["atr"][bi])


def run_streams(label, parts, sl_mult):
    b = tfs["M15"]
    bi = np.concatenate([p[0] for p in parts]); d = np.concatenate([p[1] for p in parts])
    sl = np.concatenate([p[2] * m for p, m in zip(parts, sl_mult)])
    o = np.argsort(bi, kind="stable")
    bi, d, sl = bi[o], d[o], sl[o]
    keep = np.r_[True, np.diff(bi) > 0]
    bi, d, sl = bi[keep], d[keep], sl[keep]
    tr = E.run(b, m1a, bi, d, sl, MG)
    st = E.year_stats(tr)
    a = st.iloc[-1]
    yrs = st.iloc[:-1]
    per = " ".join(f"{v:+5.1f}" for v in yrs.sum_r)
    print(f"{label:46s} n={a.n:5d} tpd={a.tpd:.2f} wr={a.wr:4.1f} avgR={a.avg_r:+.3f} sumR={a.sum_r:+6.1f} pf={a.pf:4.2f} "
          f"+yrs={int((yrs.sum_r > 0).sum())}/{len(yrs)} maxIdle={a.max_wait_h:6.0f}h green={a.green_m} | {per}")
    return tr


print(src)
run_streams("M15 | H1+H4+D1", [stream("M15", ("H1", "H4", "D1"))], [3.0])
run_streams("M15 | H1+H4", [stream("M15", ("H1", "H4"))], [3.0])
run_streams("M15 | H4+D1", [stream("M15", ("H4", "D1"))], [3.0])
run_streams("M15 | H4", [stream("M15", ("H4",))], [3.0])
for lo, hi in ((1, 12), (4, 24), (12, 48), (24, 96)):
    run_streams(f"M15 | H1+H4, H1 age {lo}-{hi}", [stream("M15", ("H1", "H4"), "H1", lo, hi)], [3.0])
    run_streams(f"M15 | H1+H4+D1, H1 age {lo}-{hi}", [stream("M15", ("H1", "H4", "D1"), "H1", lo, hi)], [3.0])
run_streams("H1 | H4+D1", [stream("H1", ("H4", "D1"))], [1.5])
run_streams("H1 | H4", [stream("H1", ("H4",))], [1.5])
for lo, hi in ((1, 12), (6, 30), (12, 60)):
    run_streams(f"H1 | H4, H4 age {lo}-{hi}", [stream("H1", ("H4",), "H4", lo, hi)], [1.5])
run_streams("M15|H1+H4 + H1|H4", [stream("M15", ("H1", "H4")), stream("H1", ("H4",))], [3.0, 1.5])
run_streams("M15|H1+H4(age12-48) + H1|H4+D1", [stream("M15", ("H1", "H4"), "H1", 12, 48), stream("H1", ("H4", "D1"))], [3.0, 1.5])
