"""SevenWave MT5 report -> per-year table (the user's standard fields + SevenWave score).

  python sw_mt5report.py <report name or .htm path> [deposit]

Positions are rebuilt from the Deals table (one position at a time: an IN deal opens, OUT deals reduce volume until
flat; partial closes belong to their position).  Per entry year:
  Net Profit, Trades (positions), Win Rate (positions with net P/L > 0), Win Rate MT5 (profitable OUT deals, the way
  the MT5 report counts "Profit Trades"), Avg Trades/Day (per weekday), Avg Wait (hours between entries, calendar),
  Max DD (balance, %), Green months, Score (0-100, sw_final.score).
"""
import html
import os
import re
import sys
from pathlib import Path
import numpy as np
import pandas as pd

REPORTS = Path(os.environ["APPDATA"]) / "MetaQuotes" / "Terminal" / "73B7A2420D6397DFF9014A20F1201F97" / "claude_reports"


def _num(s):
    s = s.replace("\xa0", "").replace(" ", "")
    try:
        return float(s) if s not in ("", "-") else 0.0
    except ValueError:
        return float("nan")


def read(name):
    p = Path(name) if str(name).endswith(".htm") else REPORTS / f"{name}.htm"
    text = p.read_text(encoding="utf-16")
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", text[text.find("<b>Deals</b>"):], flags=re.S)
    out = []
    for r in rows:
        c = [html.unescape(re.sub(r"<[^>]+>", "", x)).strip() for x in re.findall(r"<td[^>]*>(.*?)</td>", r, flags=re.S)]
        if len(c) != 13 or not re.match(r"\d{4}\.\d{2}\.\d{2}", c[0]):
            continue
        out.append(dict(time=pd.Timestamp(c[0].replace(".", "-", 2)), type=c[3], direction=c[4], volume=_num(c[5]),
                        price=_num(c[6]), commission=_num(c[8]), swap=_num(c[9]), profit=_num(c[10]),
                        balance=_num(c[11]), comment=c[12]))
    summ = {}
    flat = html.unescape(re.sub(r"<[^>]+>", "|", text))
    for key in ("Total Net Profit", "Profit Factor", "Balance Drawdown Maximal", "Equity Drawdown Maximal",
                "History Quality", "Total Trades", "Profit Trades (% of total)", "Initial Deposit"):
        m = re.search(re.escape(key) + r":[|\s]+([^|]*?\S[^|]*?)\s*\|", flat)
        if m:
            summ[key] = m.group(1).strip()
    return pd.DataFrame(out), summ


def positions(d):
    d = d[d.type.isin(["buy", "sell"])].sort_values("time").reset_index(drop=True)
    pos, cur, vol = [], None, 0.0
    for r in d.itertuples():
        net = r.profit + r.commission + r.swap
        if r.direction == "in":
            if cur is not None and vol > 1e-9:
                pos.append(cur)
            cur = dict(entry=r.time, side=r.type, vol=r.volume, net=net, outs=[], exit=r.time, comment=r.comment)
            vol = r.volume
        elif cur is not None:
            cur["net"] += net
            cur["outs"].append(net)
            cur["exit"] = r.time
            vol -= r.volume
            if vol <= 1e-9:
                pos.append(cur)
                cur, vol = None, 0.0
    if cur is not None:
        pos.append(cur)
    return pd.DataFrame(pos)


def score(ann_ret_pct, wr, tpd, wait_h, maxdd_pct, green_share):
    s_p = 25 * max(ann_ret_pct, 0) / (max(ann_ret_pct, 0) + 100)
    s_w = 20 * float(np.clip((wr - 50) / 30, 0, 1))
    s_f = 15 * min(1.0, tpd / 1.0)
    s_t = 10 * min(1.0, 24.0 / max(wait_h, 1e-9))
    s_d = 15 * float(np.clip(1 - maxdd_pct / 10.0, 0, 1))
    s_g = 15 * green_share
    # a losing period cannot score well: -25%/yr halves the score, -50%/yr or worse zeroes it
    mult = 1.0 if ann_ret_pct >= 0 else max(0.0, 1.0 + ann_ret_pct / 50.0)
    return round((s_p + s_w + s_f + s_t + s_d + s_g) * mult, 1)


def table(name, deposit=None, end=None):
    d, summ = read(name)
    if deposit is None:
        deposit = _num(summ.get("Initial Deposit", "0")) or float(d.balance.iloc[0])
    P = positions(d)
    bal_series = d[d.type.isin(["buy", "sell", "balance"])].sort_values("time")
    rows = []
    b0 = deposit
    for y, g in P.groupby(P.entry.dt.year):
        y0 = pd.Timestamp(f"{y}-01-01")
        y1 = min(pd.Timestamp(f"{y + 1}-01-01"), pd.Timestamp(end) if end else pd.Timestamp(f"{y + 1}-01-01"),
                 P.exit.max() + pd.Timedelta(days=1))
        net = g.net.sum()
        bal = bal_series[(bal_series.time >= y0) & (bal_series.time < y1)].balance.values
        peak = np.maximum.accumulate(np.r_[b0, bal]) if len(bal) else np.array([b0])
        dd = float(((peak - np.r_[b0, bal]) / peak).max() * 100) if len(bal) else 0.0
        wd = max(1, np.busday_count(y0.date(), y1.date()))
        cal_days = (y1 - y0).days
        t = np.sort(g.entry.values.astype("datetime64[s]").astype(np.int64))
        waits = np.diff(t) / 3600.0
        wait_h = float(waits.mean()) if len(waits) else float("nan")
        outs = [x for o in g.outs for x in o]
        wr_mt5 = 100.0 * np.mean([x > 0 for x in outs]) if outs else float("nan")
        mon = g.groupby(g.entry.dt.to_period("M")).net.sum()
        ret = net / b0 * 100
        ann = ret * 365.0 / max(cal_days, 1)
        wr = 100.0 * (g.net > 0).mean()
        tpd = len(g) / wd
        rows.append(dict(Year=y, NetProfit=round(net, 2), ReturnPct=round(ret, 2), Trades=len(g), WinRate=round(wr, 1),
                         WinRateMT5=round(wr_mt5, 1), TradesPerTradingDay=round(tpd, 2),
                         TradesPerCalendarDay=round(len(g) / max(cal_days, 1), 2), AvgWaitHours=round(wait_h, 1),
                         AvgWaitTradingDays=round(wait_h / 24 * 5 / 7, 2) if np.isfinite(wait_h) else np.nan,
                         MaxBalDDPct=round(dd, 2), GreenMonths=f"{int((mon > 0).sum())}/{len(mon)}",
                         Score=score(ann, wr, tpd, wait_h if np.isfinite(wait_h) else 1e9, dd, float((mon > 0).mean()))))
        b0 += net
    T = pd.DataFrame(rows)
    # aggregate row
    if len(P):
        t = np.sort(P.entry.values.astype("datetime64[s]").astype(np.int64))
        waits = np.diff(t) / 3600.0
        allouts = [x for o in P.outs for x in o]
        mon = P.groupby(P.entry.dt.to_period("M")).net.sum()
        span0, span1 = P.entry.min().normalize(), P.exit.max().normalize() + pd.Timedelta(days=1)
        wd = max(1, np.busday_count(span0.date(), span1.date()))
        bal = bal_series.balance.values
        peak = np.maximum.accumulate(np.r_[deposit, bal])
        dd = float(((peak - np.r_[deposit, bal]) / peak).max() * 100)
        net = P.net.sum()
        yrs = max((span1 - span0).days / 365.0, 1e-9)
        ann = ((deposit + net) / deposit) ** (1 / yrs) * 100 - 100
        wr = 100.0 * (P.net > 0).mean()
        T.loc[len(T)] = dict(Year="ALL", NetProfit=round(net, 2), ReturnPct=round(net / deposit * 100, 2), Trades=len(P),
                             WinRate=round(wr, 1), WinRateMT5=round(100.0 * np.mean([x > 0 for x in allouts]), 1),
                             TradesPerTradingDay=round(len(P) / wd, 2),
                             TradesPerCalendarDay=round(len(P) / max((span1 - span0).days, 1), 2),
                             AvgWaitHours=round(float(waits.mean()), 1), AvgWaitTradingDays=round(float(waits.mean()) / 24 * 5 / 7, 2),
                             MaxBalDDPct=round(dd, 2), GreenMonths=f"{int((mon > 0).sum())}/{len(mon)}",
                             Score=score(ann, wr, len(P) / wd, float(waits.mean()), dd, float((mon > 0).mean())))
    return T, summ, P


if __name__ == "__main__":
    name = sys.argv[1]
    dep = float(sys.argv[2]) if len(sys.argv) > 2 else None
    T, summ, P = table(name, dep)
    pd.set_option("display.width", 250)
    pd.set_option("display.max_columns", 30)
    print(summ)
    print(T.to_string(index=False))
    mon = P.groupby(P.entry.dt.to_period("M")).net.sum().round(0)
    print("monthly net:", " ".join(f"{k}:{v:+.0f}" for k, v in mon.items()))
    T.to_csv(REPORTS / f"{Path(name).stem}_table.csv", index=False)
