"""Study 49: STRATEGY MOMENTUM (Gupta & Kelly 2019, "Factor Momentum Everywhere"): are SevenWave's own trade outcomes
persistent, so that risk should follow the strategy's recent results?  Only trades CLOSED before the new entry count.
(a) trailing mean R of the last N closed setups (N = 10 / 20 / 40) and the trailing 60-day sum of R, vs the next setup's R:
    tercile edges fixed on 2017-2021, pre-registered good side = high (hot regimes continue).
(b) account replay (study 44 engine): risk weight 0.5 / 1.0 / 1.5 by the trailing-20 tercile.
"""
import numpy as np
import pandas as pd
from sw_study37_lib import (m, J, D, PX, AT, SI, mg, trk, Rv, probe, W, K, ja, has, addpx, S2, acct, total_row)

hidx = np.flatnonzero(has)
ext = S2.run_fills(m, J[has], D[has].astype(np.int64), PX[has], Rv[has], trk * AT[has], dict(mg, tp2_r=5.0, max_min=4320), one_at_a_time=False)
ext.index = hidx[ext.eidx.values]
pr = probe.copy()
cm = pr.index.intersection(ext.index)
pr.loc[cm, ["entry_t", "exit_t", "r"]] = ext.loc[cm, ["entry_t", "exit_t", "r"]].values
pr = pr.sort_values("entry_t")
ent, exi, rr = pr.entry_t.values.astype(np.int64), pr.exit_t.values.astype(np.int64), pr.r.values.astype(float)
yr = pd.to_datetime(ent, unit="s").year.values
o = np.argsort(exi, kind="stable")
ex_s, r_s = exi[o], rr[o]
cs = np.r_[0.0, np.cumsum(r_s)]
nclosed = np.searchsorted(ex_s, ent, side="left")              # closed strictly before this entry


def trail_n(N):
    n = nclosed
    lo = np.maximum(n - N, 0)
    return np.where(n >= N, (cs[n] - cs[lo]) / np.maximum(n - lo, 1), np.nan)


def trail_days(days):
    lo = np.searchsorted(ex_s, ent - days * 86400, side="left")
    return np.where(ent - days * 86400 >= ex_s[0], cs[nclosed] - cs[lo], np.nan)


F = {"trailing mean R, last 10 closed": trail_n(10), "trailing mean R, last 20 closed": trail_n(20),
     "trailing mean R, last 40 closed": trail_n(40), "trailing 60-day sum of R": trail_days(60)}
print(f"{len(rr)} setups, base avgR {rr.mean():+.3f}; lag-1 autocorrelation of R in entry order {np.corrcoef(rr[:-1], rr[1:])[0, 1]:+.3f}")
print("| Feature (good = high) | n | bad tercile R | mid R | good tercile R | good-bad 2017-21 | good-bad 2022-26 | years good>bad |")
print("|---|---|---|---|---|---|---|---|")
TH = {}
for name, x in F.items():
    mk = np.isfinite(x)
    q1, q2 = np.nanquantile(x[mk & (yr <= 2021)], [1 / 3, 2 / 3])
    TH[name] = (q1, q2)
    lo, hi = mk & (x <= q1), mk & (x > q2)
    mid = mk & ~lo & ~hi
    e1 = rr[hi & (yr <= 2021)].mean() - rr[lo & (yr <= 2021)].mean()
    e2 = rr[hi & (yr >= 2022)].mean() - rr[lo & (yr >= 2022)].mean()
    ys = sorted(set(yr[mk]))
    wins = sum(1 for y in ys if (hi & (yr == y)).sum() >= 10 and (lo & (yr == y)).sum() >= 10 and rr[hi & (yr == y)].mean() > rr[lo & (yr == y)].mean())
    print(f"| {name} | {mk.sum()} | {rr[lo].mean():+.3f} | {rr[mid].mean():+.3f} | {rr[hi].mean():+.3f} | {e1:+.3f} | {e2:+.3f} | {wins}/{len(ys)} |")

# ---------------------------------------------------------------- (b) account replay with momentum risk weights
x20 = F["trailing mean R, last 20 closed"]
q1, q2 = TH["trailing mean R, last 20 closed"]
mult_by_idx = dict(zip(pr.index.values, np.where(~np.isfinite(x20), 1.0, np.where(x20 <= q1, 0.5, np.where(x20 > q2, 1.5, 1.0)))))
mga = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=(5.0 - K) / K, max_min=4320)
ad = S2.run_fills(m, ja[has], D[has].astype(np.int64), addpx[has], K * Rv[has], trk * AT[has], mga, one_at_a_time=False)
ADDS = {int(hidx[e]): (int(a0), int(a1), float(r)) for e, a0, a1, r in zip(ad.eidx.values, ad.entry_t.values, ad.exit_t.values, ad.r.values)}


def events(use, with_adds):
    ev = []
    for e in pr.index.values:
        f = mult_by_idx[e] if use else 1.0
        q = pr.loc[e]
        ev.append((int(q.entry_t), "P", ("v", int(e)), int(q.exit_t), float(q.r), float(Rv[e]), W[int(SI[e])] * f))
        if with_adds and int(e) in ADDS:
            a0, a1, ar = ADDS[int(e)]
            ev.append((a0, "A", ("v", int(e)), a1, ar, K * float(Rv[e]) + 0.05, W[int(SI[e])] * K * f))
    ev.sort(key=lambda z: (z[0], z[1]))
    return ev


WIN = (("2018-01-01", "2024-01-01", "2018-2023"), ("2024-01-01", "2026-11-01", "2024-2026"))
print(f"\n(b) trailing-20 terciles {q1:+.3f} / {q2:+.3f} R -> risk weight 0.5 / 1.0 / 1.5")
print("| Run | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score | |")
print("|---|---|---|---|---|---|---|---|---|")
for use in (False, True):
    nm = "momentum weights" if use else "baseline"
    evg, evp = events(use, True), events(use, False)
    for (a, b, lab) in WIN:
        print(total_row(acct(evg, 0.5, 3, 1.0, 1e4, 10.0, 30.0, 0.0, a, b), 1e4, f"GROWTH $10k {lab} {nm}"))
    for (a, b, lab) in WIN:
        print(total_row(acct(evp, 0.15, 2, 0.5, 5e4, 3.0, 6.0, 2.4, a, b), 5e4, f"PROP $50k {lab} {nm}"))

# ---------------------------------------------------------------- (c) POST-HOC: the opposite side (cold streaks are better)
# Labelled post-hoc: the pre-registered side (hot = good) failed in 8-9 of 10 years, so the reverse is tested here and must
# survive both account windows with thresholds still fixed on 2017-2021.
print("\n(c) post-hoc contrarian variants (thresholds from 2017-2021)")
print("| Run | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score | |")
print("|---|---|---|---|---|---|---|---|---|")
for lab_v, (wc, wm, wh) in (("contrarian 1.5 / 1.0 / 0.5", (1.5, 1.0, 0.5)), ("skip hot tercile", (1.0, 1.0, 0.0)),
                            ("contrarian 1.3 / 1.0 / 0.7", (1.3, 1.0, 0.7))):
    mult_by_idx = dict(zip(pr.index.values, np.where(~np.isfinite(x20), 1.0, np.where(x20 <= q1, wc, np.where(x20 > q2, wh, wm)))))
    def events_c(with_adds):
        ev = []
        for e in pr.index.values:
            f = mult_by_idx[e]
            if f <= 0:
                continue
            q = pr.loc[e]
            ev.append((int(q.entry_t), "P", ("v", int(e)), int(q.exit_t), float(q.r), float(Rv[e]), W[int(SI[e])] * f))
            if with_adds and int(e) in ADDS:
                a0, a1, ar = ADDS[int(e)]
                ev.append((a0, "A", ("v", int(e)), a1, ar, K * float(Rv[e]) + 0.05, W[int(SI[e])] * K * f))
        ev.sort(key=lambda z: (z[0], z[1]))
        return ev
    evg, evp = events_c(True), events_c(False)
    for (a, b, lab) in WIN:
        print(total_row(acct(evg, 0.5, 3, 1.0, 1e4, 10.0, 30.0, 0.0, a, b), 1e4, f"GROWTH $10k {lab} {lab_v}"))
    for (a, b, lab) in WIN:
        print(total_row(acct(evp, 0.15, 2, 0.5, 5e4, 3.0, 6.0, 2.4, a, b), 5e4, f"PROP $50k {lab} {lab_v}"))

# per-year cold-vs-hot table (trailing 20)
lo, hi = np.isfinite(x20) & (x20 <= q1), np.isfinite(x20) & (x20 > q2)
print("\n| Year | cold n | cold R | hot n | hot R | cold - hot |")
print("|---|---|---|---|---|---|")
for y in sorted(set(yr)):
    a_, b_ = lo & (yr == y), hi & (yr == y)
    if a_.sum() and b_.sum():
        print(f"| {y} | {a_.sum()} | {rr[a_].mean():+.3f} | {b_.sum()} | {rr[b_].mean():+.3f} | {rr[a_].mean() - rr[b_].mean():+.3f} |")
