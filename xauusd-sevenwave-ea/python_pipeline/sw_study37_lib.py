"""Study 37: does the web-found Turtle H4 stream (D) add to v1.20 in a REAL account, and how far does honest risk scaling go?

v1.20 = v1.10 streams A/B/G/P (trend-tail management) + the Growth whale pyramid (add 1 unit at +1.5R, stop at the entry).
D     = H4 close above the 20-bar high (fresh) with the H4+D1 7-EMA stacks bullish (mirror for shorts), market entry.
        management (a) SL 1.5 ATR(H4), TP 2R, 20-day cap (as researched), or (b) the v1.10 trend-tail management.
Account replay with real lots (0.01 step + the EA's min-lot rule and stop-slippage cushion), the v1.20 risk engine
(slots, never-breach room budget, Prop day lock), Dukascopy 2018-2026, hostile costs.  Two windows, each starting fresh.
"""
import sys
import numpy as np
import pandas as pd
from numba import njit
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_mtf as M
import sw_sim2 as S2
from sw_mt5report import score

m = V.m1a
tfs = V.tfs
J, D, PX, AT, SI = V.all_events(use=["A", "B", "G", "P"])
mg, slk, trk = V.MGMT["growth"]
Rv = slk * AT
probe = S2.run_fills(m, J, D, PX, Rv, trk * AT, mg, one_at_a_time=False).set_index("eidx")
W = {0: 1.0, 1: 1.0, 5: 0.6, 6: 0.8}


@njit(cache=False)
def first_touch(j, d, px, R, xt, mt, mh, ml, mspr, k):
    out = np.full(len(j), -1, np.int64)
    for e in range(len(j)):
        lvl = px[e] + d[e] * k * R[e]
        for q in range(j[e] + 1, len(mt)):
            if mt[q] >= xt[e]: break
            if d[e] > 0 and mh[q] + mspr[q] >= lvl: out[e] = q; break
            if d[e] < 0 and ml[q] <= lvl: out[e] = q; break
    return out


K = 1.5
xt = np.zeros(len(J), np.int64); xt[probe.index.values] = probe.exit_t.values
ja = first_touch(J.astype(np.int64), D.astype(np.int64), PX, Rv, xt, m["t"], m["h"], m["l"], m["spr"], K)
has = ja >= 0
addpx = np.where(D > 0, PX + K * Rv + 0.05, PX - K * Rv - 0.05)
mg_add = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=(3.0 - K) / K, max_min=1440)
add = S2.run_fills(m, ja[has], D[has].astype(np.int64), addpx[has], K * Rv[has], trk * AT[has], mg_add, one_at_a_time=False)
hidx = np.flatnonzero(has)
ADD = {int(hidx[e]): (int(a0), int(a1), float(r)) for e, a0, a1, r in zip(add.eidx.values, add.entry_t.values, add.exit_t.values, add.r.values)}

# ---------------------------------------------------------------- stream D (Turtle H4 + stacks)
H4 = tfs["H4"]
hh20 = pd.Series(H4["h"]).rolling(20).max().shift(1).values
ll20 = pd.Series(H4["l"]).rolling(20).min().shift(1).values
upb = (H4["c"] > hh20) & ~np.r_[False, H4["c"][:-1] > hh20[:-1]]
dnb = (H4["c"] < ll20) & ~np.r_[False, H4["c"][:-1] < ll20[:-1]]
st, _ = V.stacks()
kd = np.maximum(M.map_last_closed(tfs["D1"], H4["t_close"]), 0)
g2 = np.where(st["H4"] == st["D1"][kd], st["H4"], 0)
kh1 = np.maximum(M.map_last_closed(tfs["H1"], H4["t_close"]), 0)
atr_h1_at = tfs["H1"]["atr"][kh1]


def d_events(long_only):
    L = upb & (g2 == 1); S = (dnb & (g2 == -1)) if not long_only else np.zeros(H4["n"], bool)
    idx = np.flatnonzero(L | S); idx = idx[(idx > 300) & (idx < H4["n"] - 1)]
    d = np.where(L[idx], 1, -1).astype(np.int64)
    j = H4["m1e"][idx]
    ok = (m["t"][np.minimum(j, len(m["t"]) - 1)] - m["t"][j - 1]) <= 1800
    idx, d, j = idx[ok], d[ok], j[ok]
    px = np.where(d > 0, m["o"][j] + m["spr"][j] + 0.05, m["o"][j] - 0.05)
    return idx, d, j, px


def d_outcomes(long_only, mode):
    idx, d, j, px = d_events(long_only)
    if mode == "turtle":
        R = 1.5 * H4["atr"][idx]
        mgD = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=2.0, max_min=60 * 24 * 20)
        tr = S2.run_fills(m, j, d, px, R, 0 * R, mgD, one_at_a_time=False)
    else:
        a = atr_h1_at[idx]
        R = slk * a
        tr = S2.run_fills(m, j, d, px, R, trk * a, mg, one_at_a_time=False)
    out = []
    for e, t0, t1, r in zip(tr.eidx.values, tr.entry_t.values, tr.exit_t.values, tr.r.values):
        out.append((int(t0), int(t1), float(r), float(R[e])))
    return out


def events(pyr, dlist):
    ev = []
    for e in probe.index.values:
        t = probe.loc[e]
        ev.append((int(t.entry_t), "P", ("v", int(e)), int(t.exit_t), float(t.r), float(Rv[e]), W[int(SI[e])]))
        if pyr and int(e) in ADD:
            a0, a1, ar = ADD[int(e)]
            ev.append((a0, "A", ("v", int(e)), a1, ar, K * float(Rv[e]) + 0.05, W[int(SI[e])] * K))
    for k, (t0, t1, r, dist) in enumerate(dlist):
        ev.append((t0, "P", ("d", k), t1, r, dist, 1.0))
    ev.sort(key=lambda z: (z[0], z[1]))
    return ev


def acct(ev, frac, K_slots, risk_in, start, daily, maxdd, cap, y0, y1):
    t0s, t1s = pd.Timestamp(y0).value // 10**9, pd.Timestamp(y1).value // 10**9
    eq = start; hwm = start; op = []; dp = {}; dref = start; cur = None; out = []; live = set()
    for (t0, kind, key, t1, r, dist, w) in ev:
        if t0 < t0s or t0 >= t1s:
            continue
        keep = []
        for q in sorted(op, key=lambda z: z[0]):
            if q[0] <= t0:
                k = q[0] // 86400; pnl = q[1]
                if cap > 0 and pnl > 0: pnl = min(pnl, max(0.0, eq * cap / 100 - dp.get(k, 0.0)))
                eq += pnl; hwm = max(hwm, eq); dp[k] = dp.get(k, 0.0) + pnl
                out.append((pd.Timestamp(q[3], unit="s"), pd.Timestamp(q[0], unit="s"), pnl, eq, q[4]))
                if q[4] == "P": live.discard(q[5])
            else: keep.append(q)
        op = keep
        k = t0 // 86400
        if k != cur: cur = k; dref = eq
        if dref - eq >= dref * daily / 100 * 0.8: continue
        if cap > 0 and dp.get(k, 0.0) >= eq * cap / 100 * 0.999: continue
        room = min(eq - dref * (1 - daily / 100), eq - hwm * (1 - maxdd / 100))
        if kind == "P":
            if sum(1 for z in op if z[4] == "P") >= K_slots: continue
        else:
            if key not in live: continue
            base = [z for z in op if z[4] == "P" and z[5] == key]
            if not base: continue
            base[0][2] = 0.0
        budget = room * frac / 1.25 - sum(z[2] for z in op)
        if budget <= 0: continue
        target = min(eq * risk_in / 100.0 * w, budget)
        lpl = 100.0 * (dist + 0.10)
        lots = np.floor(target / lpl / 0.01 + 1e-9) * 0.01
        if lots < 0.01:
            if 0.01 * lpl * 1.25 <= budget: lots = 0.01
            else: continue
        risk = lots * 100.0 * dist
        op.append([t1, risk * r, risk, t0, kind, key])
        if kind == "P": live.add(key)
    T = pd.DataFrame(out, columns=["entry", "exit", "net", "balance", "kind"]).sort_values("exit").reset_index(drop=True)
    return T


def total_row(T, start, label):
    y0 = T.entry.min().normalize(); y1 = T.exit.max().normalize() + pd.Timedelta(days=1)
    bal = T.balance.values; pk = np.maximum.accumulate(np.r_[start, bal]); mdd = ((pk - np.r_[start, bal]) / pk).max() * 100
    wd = max(1, np.busday_count(y0.date(), y1.date())); ent = np.sort(T.entry.values.astype("datetime64[s]").astype(np.int64))
    wait = np.diff(ent).mean() / 3600; net = T.net.sum(); wr = (T.net > 0).mean() * 100
    mo = T.groupby(T.exit.dt.to_period("M")).net.sum(); yrs = max((y1 - y0).days / 365.0, 0.25)
    ann = ((start + net) / start) ** (1 / yrs) * 100 - 100
    yr = T.groupby(T.exit.dt.year).net.sum()
    bal0 = start; neg = 0
    for y, v in yr.items():
        neg += v < 0; bal0 += v
    return (f"| {label} | {'+' if net >= 0 else '-'}${abs(net):,.0f} ({net / start * 100:+.1f}%) | {len(T):,} | {wr:.1f}% | {len(T) / wd:.2f} | "
            f"{wait:.0f} h | {mdd:.2f}% | {score(ann, wr, len(T) / wd, wait, mdd, float((mo > 0).mean()))} | losing years {neg} |")


