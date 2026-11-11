"""SevenWave report from the EA's own trade log (sevenwave_trades.csv, one row per CLOSED position, exact P/L).

  python sw_tradelog.py <trades.csv> <deposit> [target%]

Per year (by entry): Net Profit, Trades, Win Rate (positions), Win Rate MT5 (profitable exit deals), Avg Trades/Day,
Avg Wait (h), Max DD (closed balance), Green Days / Weeks / Months, Best-Day Share, Score.
Challenge replay: every Monday a fresh $100k replays the EA's trades in exit order (each trade's P/L as a fraction of
the balance before it) until +target with best day <= 30% of profit (PASS), 6% trailing / 3% daily (BREACH), or 180 days.
"""
import sys
import numpy as np
import pandas as pd
from sw_mt5report import score


def load(path):
    t = pd.read_csv(path)
    t["entry"] = pd.to_datetime(t.entry, format="%Y.%m.%d %H:%M:%S")
    t["exit"] = pd.to_datetime(t.exit, format="%Y.%m.%d %H:%M:%S")
    t = t[t.entry.dt.year > 1971].sort_values("exit").reset_index(drop=True)
    t["bal_before"] = t.balance - t.net          # balance printed right after the close
    t["ret"] = t.net / t.bal_before
    return t


def table(t, deposit):
    rows = []
    b0 = deposit
    for y, g in t.groupby(t.entry.dt.year):
        y0 = pd.Timestamp(f"{y}-01-01")
        y1 = min(pd.Timestamp(f"{y + 1}-01-01"), t.exit.max() + pd.Timedelta(days=1))
        net = g.net.sum()
        gx = t[(t.exit >= y0) & (t.exit < y1)]
        bal = gx.balance.values
        peak = np.maximum.accumulate(np.r_[b0, bal]) if len(bal) else np.array([b0])
        dd = float(((peak - np.r_[b0, bal]) / peak).max() * 100) if len(bal) else 0.0
        wd = max(1, np.busday_count(y0.date(), y1.date()))
        ent = np.sort(g.entry.values.astype("datetime64[s]").astype(np.int64))
        wait = float(np.diff(ent).mean() / 3600) if len(ent) > 1 else np.nan
        day = gx.groupby(gx.exit.dt.normalize()).net.sum()
        wk = day.resample("W").sum(); wk = wk[wk != 0]
        mo = day.resample("ME").sum(); mo = mo[mo != 0]
        tot = day.sum()
        wr = (g.net > 0).mean() * 100
        wr5 = g.win_outs.sum() / max(1, g.outs.sum()) * 100
        ret = net / b0 * 100
        ann = ret * 365.0 / max((y1 - y0).days, 1)
        rows.append(dict(Year=y, NetProfit=round(net, 2), ReturnPct=round(ret, 2), Trades=len(g), WinRate=round(wr, 1),
                         WinRateMT5=round(wr5, 1), TradesPerDay=round(len(g) / wd, 2), AvgWaitH=round(wait, 1),
                         MaxDD=round(dd, 2), GreenDays=f"{(day > 0).mean() * 100:.0f}%", GreenWeeks=f"{(wk > 0).mean() * 100:.0f}%",
                         GreenMonths=f"{int((mo > 0).sum())}/{len(mo)}",
                         BestDayShare=f"{day.max() / tot * 100:.0f}%" if tot > 0 else "n/a",
                         Score=score(ann, wr, len(g) / wd, wait if np.isfinite(wait) else 1e9, dd, float((mo > 0).mean()) if len(mo) else 0)))
        b0 += net
    return pd.DataFrame(rows)


def challenges(t, target=8.0, cons=0.30, days=180):
    starts = pd.date_range(t.entry.min().normalize(), t.exit.max() - pd.Timedelta(days=days), freq="W-MON")
    out = []
    for s in starts:
        g = t[(t.entry >= s) & (t.exit < s + pd.Timedelta(days=days))]
        eq = 100_000.0; hwm = eq; dp = {}; st = "timeout"; d = float(days)
        for r in g.itertuples():
            pnl = eq * r.ret
            eq += pnl; hwm = max(hwm, eq)
            k = r.exit.normalize()
            dp[k] = dp.get(k, 0.0) + pnl
            if eq <= hwm * 0.94 or dp[k] <= -3000.0:
                st = "breach"; d = (r.exit - s).total_seconds() / 86400; break
            prof = eq - 100_000.0
            if prof >= target * 1000.0 and max(dp.values()) <= cons * prof:
                st = "pass"; d = (r.exit - s).total_seconds() / 86400; break
        out.append(dict(start=s, status=st, days=d))
    return pd.DataFrame(out)


if __name__ == "__main__":
    path, dep = sys.argv[1], float(sys.argv[2])
    tgt = float(sys.argv[3]) if len(sys.argv) > 3 else 8.0
    t = load(path)
    pd.set_option("display.width", 260)
    pd.set_option("display.max_columns", 30)
    T = table(t, dep)
    print(T.to_string(index=False))
    print(f"total net {t.net.sum():+,.2f}  final balance {t.balance.iloc[-1]:,.2f}  trades {len(t)}  by stream: "
          + ", ".join(f"{s}:{len(g)}/{g.net.sum():+,.0f}" for s, g in t.groupby("stream")))
    C = challenges(t, tgt)
    by = C.groupby(C.start.dt.year).agg(n=("status", "size"), pass_pct=("status", lambda x: round((x == "pass").mean() * 100, 1)),
                                        breach_pct=("status", lambda x: round((x == "breach").mean() * 100, 1)))
    by["median_days"] = C[C.status == "pass"].groupby(C.start.dt.year).days.median().round(0)
    print(f"challenge replay (+{tgt:.0f}%, best day <= 30%, 3%/6% trailing, 180 d):")
    print(by.to_string())
    print(f"ALL pass {(C.status == 'pass').mean() * 100:.1f}%  breach {(C.status == 'breach').mean() * 100:.1f}%  "
          f"median days {C[C.status == 'pass'].days.median():.0f}")
