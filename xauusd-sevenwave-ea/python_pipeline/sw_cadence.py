"""Cadence & prop-consistency report from an MT5 tester report (positions rebuilt by sw_mt5report).

  python sw_cadence.py <report> <deposit> [target%]

Per year: green days / weeks / months, best-day share of the year's profit.
Challenge replay: from every Monday, a fresh $100k account replays the EA's own trades (each position's P/L as a
fraction of the balance at its entry, booked on its exit day) until +target with best day <= 30% of profit (PASS),
a 6% trailing / 3% daily floor touch (BREACH), or 180 days (TIMEOUT).
"""
import sys
import numpy as np
import pandas as pd
import sw_mt5report as R


def cadence(name, deposit, target=8.0):
    d, summ = R.read(name)
    P = R.positions(d)
    bal = d[d.type.isin(["buy", "sell", "balance"])].sort_values("time")
    # balance just before each position's entry
    bt = bal.time.values
    bv = bal.balance.values
    idx = np.searchsorted(bt, P.entry.values, side="left") - 1
    P["bal0"] = np.where(idx >= 0, bv[np.maximum(idx, 0)], deposit)
    P["ret"] = P.net / P.bal0
    P["xday"] = P.exit.dt.normalize()
    day = P.groupby("xday").net.sum()
    rows = []
    for y, g in day.groupby(day.index.year):
        wk = g.resample("W").sum(); wk = wk[wk != 0]
        mo = g.resample("ME").sum(); mo = mo[mo != 0]
        tot = g.sum()
        rows.append(dict(Year=y, GreenDays=f"{(g > 0).mean() * 100:.0f}%", GreenWeeks=f"{(wk > 0).mean() * 100:.0f}%",
                         GreenMonths=f"{int((mo > 0).sum())}/{len(mo)}",
                         BestDayShare=f"{g.max() / tot * 100:.0f}%" if tot > 0 else "n/a"))
    T = pd.DataFrame(rows)
    # challenge replay
    P = P.sort_values("exit").reset_index(drop=True)
    starts = pd.date_range(P.entry.min().normalize(), P.exit.max() - pd.Timedelta(days=180), freq="W-MON")
    res = []
    for s in starts:
        g = P[(P.entry >= s) & (P.exit < s + pd.Timedelta(days=180))]
        eq = 100_000.0; hwm = eq; dpnl = {}; status = "timeout"; days = 180.0
        for t in g.itertuples():
            pnl = eq * t.ret
            eq += pnl
            hwm = max(hwm, eq)
            dk = t.xday
            dpnl[dk] = dpnl.get(dk, 0.0) + pnl
            if eq <= hwm * 0.94 or dpnl[dk] <= -0.03 * 100_000.0:
                status = "breach"; days = (t.exit - s).total_seconds() / 86400; break
            prof = eq - 100_000.0
            if prof >= target * 1000.0 and max(dpnl.values()) <= 0.30 * prof:
                status = "pass"; days = (t.exit - s).total_seconds() / 86400; break
        res.append(dict(start=s, status=status, days=days))
    C = pd.DataFrame(res)
    C["year"] = C.start.dt.year
    by = C.groupby("year").agg(n=("status", "size"), pass_pct=("status", lambda x: (x == "pass").mean() * 100),
                               breach_pct=("status", lambda x: (x == "breach").mean() * 100))
    med = C[C.status == "pass"].groupby("year").days.median()
    by["median_days_to_pass"] = med
    return T, by.round(1), C, summ


if __name__ == "__main__":
    name, dep = sys.argv[1], float(sys.argv[2])
    tgt = float(sys.argv[3]) if len(sys.argv) > 3 else 8.0
    T, by, C, summ = cadence(name, dep, tgt)
    pd.set_option("display.width", 200)
    print(T.to_string(index=False))
    print(f"\nprop-challenge replay (+{tgt:.0f}% target, best day <= 30%, 3% daily / 6% trailing, 180 days), by start year:")
    print(by.to_string())
    a = C
    print(f"ALL: {len(a)} challenges, pass {(a.status == 'pass').mean() * 100:.1f}%, breach {(a.status == 'breach').mean() * 100:.1f}%, "
          f"median days to pass {a[a.status == 'pass'].days.median():.0f}")
