"""Prop-challenge simulator: what a prop trader actually experiences.

From every start week (2017-2026) a fresh $100k account trades the SevenWave event stream under the never-breach
risk engine until it PASSES (+target and best day <= cons x total profit), BREACHES (daily or trailing floor), or
times out.  Realised P/L is booked on the exit day (UTC).  Selection years = starts in 2017-2022; unseen = 2023-2026.

  rate_pass, median / p75 days to pass, rate_breach, rate_timeout, best-day share at pass.
"""
import numpy as np
import pandas as pd

WEIGHT = np.array([1.0, 1.0, 0.5, 0.5, 0.35, 0.35])


def challenge_one(entry_t, exit_t, r, stream, i0, start_t, risk_pct, K, target, cons, daily, maxdd, max_days,
                  start=100_000.0, lock_pct=0.0, day_cap_pct=0.0):
    """Run one challenge from event index i0.  Returns (status, days, best_share).
    day_cap_pct > 0: the day's realised profit can never exceed that % of the starting balance (the EA banks the day
    and flattens when the cap is touched) - a direct enforcement of the prop best-day consistency rule."""
    eq = start
    hwm = start
    open_pos = []            # [exit_t, pnl, risk]
    day_pnl = {}
    day_ref = start
    cur_day = start_t // 86400
    end_t = start_t + max_days * 86400
    n = len(entry_t)
    i = i0
    cap = start * day_cap_pct / 100.0

    def realise(upto):
        nonlocal eq, hwm, open_pos
        keep = []
        for p in sorted(open_pos, key=lambda q: q[0]):
            if p[0] <= upto:
                dk = p[0] // 86400
                pnl = p[1]
                if cap > 0 and pnl > 0:
                    pnl = min(pnl, max(0.0, cap - day_pnl.get(dk, 0.0)))
                eq += pnl
                hwm = max(hwm, eq)
                day_pnl[dk] = day_pnl.get(dk, 0.0) + pnl
            else:
                keep.append(p)
        open_pos = keep

    def check():
        prof = eq - start
        if eq <= hwm * (1 - maxdd / 100.0) + 1e-6:
            return "breach"
        # pass on realised balance reaching the target (the EA flattens at that moment); positions still open are
        # booked at their worst case (full stop) so a pass is never counted on profit that could still vanish
        worst_open = sum(p[2] for p in open_pos) * 1.1
        if prof - worst_open >= start * target / 100.0:
            best = max(day_pnl.values()) if day_pnl else 0.0
            if best <= cons * prof:
                return "pass"
        return None

    while i < n and entry_t[i] < end_t:
        t = entry_t[i]
        # realise everything that closed before this entry, day by day, checking status after each realisation
        if open_pos:
            for p in sorted(open_pos, key=lambda q: q[0]):
                if p[0] <= t:
                    realise(p[0])
                    st = check()
                    if st:
                        return st, (p[0] - start_t) / 86400.0, (max(day_pnl.values()) / max(eq - start, 1e-9))
        dk = t // 86400
        if dk != cur_day:
            cur_day = dk
            day_ref = eq
        if day_ref - eq >= day_ref * daily / 100.0 * 0.8:   # daily breaker
            i += 1
            continue
        if len(open_pos) >= K or (lock_pct > 0 and day_pnl.get(dk, 0.0) >= eq * lock_pct / 100.0) or \
                (cap > 0 and day_pnl.get(dk, 0.0) >= cap * 0.999):
            i += 1
            continue
        room_day = eq - day_ref * (1 - daily / 100.0)
        room_tot = eq - hwm * (1 - maxdd / 100.0)
        budget = min(room_day, room_tot) * 0.5 / 1.25 - sum(p[2] for p in open_pos)
        risk = min(eq * risk_pct / 100.0 * WEIGHT[stream[i]], budget)
        if risk > start * 1e-5:
            open_pos.append([exit_t[i], risk * r[i], risk])
        i += 1
    realise(end_t)
    st = check()
    if st:
        return st, max_days, max(day_pnl.values()) / max(eq - start, 1e-9)
    return "timeout", max_days, np.nan


def run_challenges(tr, risk_pct, K=1, target=8.0, cons=0.30, daily=3.0, maxdd=6.0, max_days=120, step_days=7,
                   lock_pct=0.0, day_cap_pct=0.0):
    tr = tr.sort_values("entry_t").reset_index(drop=True)
    et = tr.entry_t.values.astype(np.int64)
    xt = tr.exit_t.values.astype(np.int64)
    rr = tr.r.values.astype(float)
    ss = tr.stream.values.astype(int) if "stream" in tr else np.zeros(len(tr), int)
    t_first, t_last = et[0], et[-1] - max_days * 86400
    out = []
    for s in range(int(t_first), int(t_last), step_days * 86400):
        i0 = int(np.searchsorted(et, s))
        st, days, share = challenge_one(et, xt, rr, ss, i0, s, risk_pct, K, target, cons, daily, maxdd, max_days,
                                        lock_pct=lock_pct, day_cap_pct=day_cap_pct)
        out.append(dict(start=pd.Timestamp(s, unit="s"), status=st, days=days, share=share))
    return pd.DataFrame(out)


def summarise(ch, y0, y1):
    c = ch[(ch.start.dt.year >= y0) & (ch.start.dt.year <= y1)]
    if len(c) == 0:
        return {}
    p = c[c.status == "pass"]
    return dict(n=len(c), pass_=round((c.status == "pass").mean() * 100, 1), breach=round((c.status == "breach").mean() * 100, 1),
                timeout=round((c.status == "timeout").mean() * 100, 1), med_days=round(p.days.median(), 1) if len(p) else np.nan,
                p75_days=round(p.days.quantile(0.75), 1) if len(p) else np.nan)
