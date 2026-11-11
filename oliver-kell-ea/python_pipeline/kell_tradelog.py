"""OliverKell report from the EA's closed trade log (oliver_kell_trades.csv, one row per CLOSED position, exact P/L).

Usage:
  python kell_tradelog.py <oliver_kell_trades.csv> <deposit> [target%]
"""
import sys
import numpy as np
import pandas as pd

sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
from sw_mt5report import score


def load(path):
    t = pd.read_csv(path)
    t["entry"] = pd.to_datetime(t.entry, format="%Y.%m.%d %H:%M:%S")
    t["exit"] = pd.to_datetime(t.exit, format="%Y.%m.%d %H:%M:%S")
    t = t[t.entry.dt.year > 1971].sort_values("exit").reset_index(drop=True)
    t["bal_before"] = t.balance - t.net
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
        gp = g[g.net > 0].net.sum()
        gl = abs(g[g.net < 0].net.sum())
        pf = gp / gl if gl > 1e-6 else 99.9
        ret = net / b0 * 100
        ann = ret * 365.0 / max((y1 - y0).days, 1)
        rows.append(dict(
            Year=y, NetProfit=round(net, 2), ReturnPct=round(ret, 2), PF=round(pf, 2),
            Trades=len(g), WinRate=round(wr, 1), WinRateMT5=round(wr5, 1),
            TradesPerDay=round(len(g) / wd, 2), AvgWaitH=round(wait, 1),
            MaxDD=round(dd, 2),
            GreenDays=f"{(day > 0).mean() * 100:.0f}%" if len(day) else "0%",
            GreenWeeks=f"{(wk > 0).mean() * 100:.0f}%" if len(wk) else "0%",
            GreenMonths=f"{int((mo > 0).sum())}/{len(mo)}",
            BestDayShare=f"{day.max() / tot * 100:.0f}%" if tot > 0 else "n/a",
            Score=score(ann, wr, len(g) / wd, wait if np.isfinite(wait) else 1e9, dd,
                        float((mo > 0).mean()) if len(mo) else 0)
        ))
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
    gp = t[t.net > 0].net.sum()
    gl = abs(t[t.net < 0].net.sum())
    pf = gp / gl if gl > 1e-6 else 99.9
    print(f"\nTotal Net: ${t.net.sum():+,.2f}  Final Balance: ${t.balance.iloc[-1]:,.2f}  PF: {pf:.2f}  Trades: {len(t)}")
    print("By Stream:", ", ".join(f"{s}: {len(g)} trades (${g.net.sum():+,.0f})" for s, g in t.groupby("stream")))
    print("By Setup :", ", ".join(f"{r}: {len(g)} (${g.net.sum():+,.0f})" for r, g in t.groupby("setup")))
    if len(t) > 10 and (t.exit.max() - t.entry.min()).days > 180:
        C = challenges(t, tgt)
        if len(C) > 0:
            print(f"\nWeekly $100k Prop Challenge Replay (+{tgt:.0f}%, best day <= 30%, 3% daily / 6% total DD, 180d):")
            print(f"  Pass: {(C.status == 'pass').mean() * 100:.1f}%  Breach: {(C.status == 'breach').mean() * 100:.1f}%  "
                  f"Median Pass Days: {C[C.status == 'pass'].days.median():.0f}")
