"""Study 23: CADENCE engine.  Uniform 'harvest' targets + concurrency under a portfolio never-breach guard + daily
profit lock, scored on prop-firm consistency.

Per config, metrics on realised P/L by UTC day (selection years 2017-2022 | unseen 2023-2026):
  cagr, maxdd (balance), green days / weeks / months %, consistency pass rate = share of positive months whose best
  day is <= 30% (cons30) / <= 50% (cons50) of that month's profit, trades per weekday, position win rate.
Portfolio guard: per-position risk = base% x stream weight; TOTAL open risk (+25% cushion) <= 1/2 of the daily room and
1/2 of the trailing room (prop 3% / 6% floors), so no combination of stops can breach.
"""
import sys
import time
import itertools
import numpy as np
import pandas as pd
import sw_study22 as S22
import sw_sim2 as S2

t0 = time.time()
RIBBONS = {"v1.00": (20, 40, 60, 80, 100, 150, 200), "g5x1.8": (5, 9, 16, 29, 52, 94, 170),
           "g20x1.8": (20, 36, 65, 117, 210, 378, 680), "g30x1.8": (30, 54, 97, 175, 315, 567, 1020)}
# (label, mgmt, sl_k, trail_k): fixed harvest targets in units of ATR(H1) -> tp2_r = TP/SL
HARVEST = {
    "TP0.5/SL1.5": (dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=0.5 / 1.5, max_min=1440), 1.5, 0.0),
    "TP0.75/SL1.5": (dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=0.75 / 1.5, max_min=1440), 1.5, 0.0),
    "TP1.0/SL1.5": (dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=1.0 / 1.5, max_min=1440), 1.5, 0.0),
    "TP1.0/SL1.0": (dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=1.0, max_min=1440), 1.0, 0.0),
    "TP1.5/SL1.5": (dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=1.0, max_min=1440), 1.5, 0.0),
    "PROP v1.00": S22.MGMT["prop"],
    "GROWTH v1.00": S22.MGMT["growth"],
}


def portfolio(tr, K, base_pct, lock_pct, start=100_000.0, daily=3.0, maxdd=6.0):
    eq = start
    hwm = start
    open_pos = []
    day_pnl = {}
    taken = []
    cur_day = None
    day_ref = start
    for t in tr.itertuples():
        still = []
        for (xt, pnl, rk) in open_pos:
            if xt <= t.entry_t:
                eq += pnl
                hwm = max(hwm, eq)
                day_pnl[xt // 86400] = day_pnl.get(xt // 86400, 0.0) + pnl
            else:
                still.append((xt, pnl, rk))
        open_pos = still
        dkey = t.entry_t // 86400
        if dkey != cur_day:
            cur_day = dkey
            day_ref = eq
        if len(open_pos) >= K:
            continue
        if lock_pct > 0 and day_pnl.get(dkey, 0.0) >= eq * lock_pct / 100.0:
            continue
        room_day = eq - day_ref * (1 - daily / 100.0)
        room_tot = eq - hwm * (1 - maxdd / 100.0)
        open_risk = sum(p[2] for p in open_pos)
        budget = min(room_day, room_tot) * 0.5 / 1.25 - open_risk
        risk = min(eq * base_pct / 100.0 * S22.WEIGHT[int(t.stream)], budget)
        if risk <= eq * 1e-5:
            continue
        pnl = risk * t.r
        open_pos.append((t.exit_t, pnl, risk))
        taken.append((t.entry_t, t.exit_t, pnl, t.r))
    for (xt, pnl, rk) in open_pos:
        eq += pnl
        day_pnl[xt // 86400] = day_pnl.get(xt // 86400, 0.0) + pnl
    return pd.Series(day_pnl).sort_index(), pd.DataFrame(taken, columns=["entry_t", "exit_t", "pnl", "r"]), eq


def metrics(day, taken, start, y0, y1):
    lo = pd.Timestamp(f"{y0}-01-01").value // 10 ** 9 // 86400
    hi = pd.Timestamp(f"{y1 + 1}-01-01").value // 10 ** 9 // 86400
    d = day[(day.index >= lo) & (day.index < hi)]
    if len(d) < 20:
        return None
    s = pd.Series(d.values, index=pd.to_datetime(d.index * 86400, unit="s"))
    s = s[s != 0]
    start = start + float(day[day.index < lo].sum())          # real balance at the period start
    bal = start + s.cumsum()
    peak = np.maximum.accumulate(np.r_[start, bal.values])
    dd = float(((peak - np.r_[start, bal.values]) / peak).max() * 100)
    wk = s.resample("W").sum(); wk = wk[wk != 0]
    mo = s.resample("ME").sum(); mo = mo[mo != 0]
    c30 = []; c50 = []
    for m, g in s.groupby(s.index.to_period("M")):
        tot = g.sum()
        if tot > 0:
            c30.append(g.max() <= 0.30 * tot); c50.append(g.max() <= 0.50 * tot)
    tk = taken[(taken.entry_t // 86400 >= lo) & (taken.entry_t // 86400 < hi)]
    yrs = (s.index[-1] - s.index[0]).days / 365.0
    cagr = (bal.iloc[-1] / start) ** (1 / max(yrs, 0.5)) * 100 - 100
    wd = max(1, np.busday_count(s.index[0].date(), s.index[-1].date()))
    return dict(cagr=cagr, dd=dd, gd=(s > 0).mean() * 100, gw=(wk > 0).mean() * 100, gm=(mo > 0).mean() * 100,
                c30=np.mean(c30) * 100 if c30 else 0.0, c50=np.mean(c50) * 100 if c50 else 0.0,
                tpd=len(tk) / wd, wr=(tk.r > 0).mean() * 100)


rows = []
for rname, per in RIBBONS.items():
    ev = S22.events(per, 6)
    for hname, (mg, slk, trk) in HARVEST.items():
        ej, ed, ep, ea, es = ev
        tr = S2.run_fills(S22.m1a, ej, ed, ep, slk * ea, trk * ea, mg, one_at_a_time=False, meta={"stream": es})
        tr = tr.sort_values("entry_t").reset_index(drop=True)
        for K, lock, base in itertools.product((1, 2, 3, 4), (0.0, 0.5, 1.0), (0.5, 1.0)):
            day, taken, eqf = portfolio(tr, K, base, lock)
            mi = metrics(day, taken, 100_000.0, 2017, 2022)
            mo = metrics(day, taken, 100_000.0, 2023, 2026)
            if mi is None or mo is None:
                continue
            rows.append(dict(ribbon=rname, mgmt=hname, K=K, lock=lock, risk=base,
                             **{f"is_{k}": round(v, 1) for k, v in mi.items()}, **{f"oos_{k}": round(v, 1) for k, v in mo.items()}))
    print(f"{time.time() - t0:5.0f}s ribbon {rname} done")
R = pd.DataFrame(rows)
# in-sample cadence objective: consistency first, then return, penalise drawdown beyond 4%
R["is_obj"] = (R.is_c30 * 0.6 + R.is_c50 * 0.2 + R.is_gw * 0.6 + R.is_gm * 0.4 + R.is_gd * 0.3 + R.is_cagr * 1.5
               - np.maximum(R.is_dd - 4.0, 0) * 8 + R.is_tpd * 10)
R.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\cadence2_duka.csv", index=False)
pd.set_option("display.width", 320)
pd.set_option("display.max_columns", 40)
cols = ["ribbon", "mgmt", "K", "lock", "risk", "is_cagr", "is_dd", "is_gd", "is_gw", "is_gm", "is_c30", "is_c50", "is_tpd",
        "is_wr", "oos_cagr", "oos_dd", "oos_gd", "oos_gw", "oos_gm", "oos_c30", "oos_c50", "oos_tpd", "oos_wr"]
print("\n=== top 20 by IN-SAMPLE cadence objective (selection 2017-2022) with the unseen 2023-2026 check ===")
print(R.sort_values("is_obj", ascending=False)[cols].head(20).to_string(index=False))
print("\n=== v1.00 PROP baseline ===")
print(R[(R.ribbon == "v1.00") & (R.mgmt == "PROP v1.00") & (R.K == 1) & (R.lock == 0) & (R.risk == 0.5)][cols].to_string(index=False))
print("\n=== best in-sample per management (K/lock/risk free) ===")
print(R.sort_values("is_obj", ascending=False).groupby("mgmt").head(1)[cols].to_string(index=False))

