"""Check the 7Wave EA's trades against RULES.md (step 2) and summarise them.

Entries: every EA trade must sit on a bar where the indicator copy (setup_check.py, broker bars) armed the same side
at the same level, and every entry of the copy must be traded unless the EA was already in a trade.
Exits: every trade is replayed minute by minute on the broker's M1 bars with the growth rules (stop 1R = 1.5 ATR,
target 3R, trail 2 ATR behind the best price from +1R on completed M1 bars, 24 h time exit), starting from the EA's
own fill, and the replay's exit is compared with the EA's.

    C:\\Users\\faker\\mlv\\Scripts\\python.exe 7wave\\tools\\ea_check.py [trade_log.csv]
"""
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import setup_check as SC  # noqa: E402

LOG = r"C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\Common\Files\7wave_ea_trades_tester.csv"
TARGET_R, TRAIL_FROM_R, TRAIL_PER_R, MAX_HOLD = 3.0, 1.0, 2.0 / 1.5, pd.Timedelta(hours=24)


def load_log(path):
    df = pd.read_csv(path)
    df["signal_bar"] = pd.to_datetime(df.signal_bar, format="%Y.%m.%d %H:%M")
    for c in ("fill_time", "exit_time"):
        df[c] = pd.to_datetime(df[c], format="%Y.%m.%d %H:%M:%S")
    df["dir"] = np.where(df.side == "BUY", 1, -1)
    return df


def replay(t, m1, point):
    """The growth rules from the EA's fill, on M1 bars (stop first inside a bar, as in the research)."""
    d, fill, risk = t.dir, t.fill, t.risk
    sl, tp, best, trail = fill - d * risk, fill + d * TARGET_R * risk, fill, TRAIL_PER_R * risk
    k0 = m1.index.searchsorted(t.fill_time.floor("min"))
    times, o, h, l, c, s = (m1.index, m1.open.to_numpy(), m1.high.to_numpy(), m1.low.to_numpy(), m1.close.to_numpy(),
                            m1.spread.to_numpy() * point)
    moved = False
    for k in range(k0, len(m1)):
        sp = s[k] if d < 0 else 0.0
        adverse, favor, cls, opn = (l[k], h[k], c[k], o[k]) if d > 0 else (h[k] + sp, l[k] + sp, c[k] + sp, o[k] + sp)
        if k > k0 and d * (opn - sl) <= 0:
            return times[k], opn, "trail" if moved else "stop"
        if d * (adverse - sl) <= 0:
            return times[k], sl, "trail" if moved else "stop"
        if k > k0:
            if d * (favor - tp) >= 0:
                return times[k], tp, "target"
            if d * (favor - best) > 0:
                best = favor
        if d * (best - fill) >= TRAIL_FROM_R * risk:
            lvl = best - d * trail
            if d * (lvl - sl) > 0 and d * (cls - lvl) > 0:
                sl, moved = lvl, True
        if times[k] - t.fill_time.floor("min") >= MAX_HOLD and k + 1 < len(m1):
            return times[k + 1], o[k + 1] + (s[k + 1] if d < 0 else 0.0), "time"
    return times[-1], c[-1], "open"


def score(ann_ret_pct, wr, tpd, wait_h, maxdd_pct, green_share):
    s_p = 25 * max(ann_ret_pct, 0) / (max(ann_ret_pct, 0) + 100)
    s_w = 20 * float(np.clip((wr - 50) / 30, 0, 1))
    s_f = 15 * min(1.0, tpd / 1.0)
    s_t = 10 * min(1.0, 24.0 / max(wait_h, 1e-9))
    s_d = 15 * float(np.clip(1 - maxdd_pct / 10.0, 0, 1))
    return round(s_p + s_w + s_f + s_t + s_d + 15 * green_share, 1)


def year_table(df, money, days):
    """The user's standard table from a per-trade money column (closed-trade equity on $10,000)."""
    start, out = 10_000.0, ["| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |",
                            "|---|---|---|---|---|---|---|---|"]
    eq = start + df[money].cumsum()
    peak = np.maximum.accumulate(np.r_[start, eq.to_numpy()])[1:]
    dd = (peak - eq) / peak * 100
    bal0 = start
    for y, g in df.groupby(df.fill_time.dt.year):
        net, wr = g[money].sum(), (g[money] > 0).mean() * 100
        wait = g.fill_time.diff().dt.total_seconds().mean() / 3600
        green = (g.groupby(g.exit_time.dt.to_period("M"))[money].sum() > 0).mean()
        tpd = len(g) / days[y]
        out.append(f"| {y} | ${net:+,.2f} ({net / bal0 * 100:+.2f}%) | {len(g)} | {wr:.0f}% | {tpd:.2f} | {wait:.0f} h "
                   f"| {dd[g.index].max():.2f}% | {score(net / bal0 * 100, wr, tpd, wait, dd[g.index].max(), green)} |")
        bal0 += net
    net = df[money].sum()
    out.append(f"| **All** | ${net:+,.2f} ({net / start * 100:+.2f}%) | {len(df)} | {(df[money] > 0).mean() * 100:.0f}% "
               f"| {len(df) / sum(days.values()):.2f} | {df.fill_time.diff().dt.total_seconds().mean() / 3600:.0f} h "
               f"| {dd.max():.2f}% | |")
    return "\n".join(out)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else LOG
    ea = load_log(path)
    h1, h4, d1, point = SC.fetch("XAUUSD")
    sig = SC.setup_signals(h1, h4, d1, point).set_index("time")

    # ---- entries
    print(f"# 7Wave EA check: {len(ea)} trades, {ea.fill_time.min():%Y-%m-%d} to {ea.exit_time.max():%Y-%m-%d}\n")
    rows = sig.reindex(ea.signal_bar)
    armed = np.where(ea.dir.to_numpy() > 0, rows.long_level.to_numpy(), rows.short_level.to_numpy())
    same_level = np.abs(armed - ea.level.to_numpy()) <= 0.011
    copy_entry = rows.entry.to_numpy() == ea.dir.to_numpy()
    in_bar = (ea.fill_time >= ea.signal_bar) & (ea.fill_time < ea.signal_bar + pd.Timedelta(hours=1))
    print(f"Entries: {same_level.sum()} of {len(ea)} on a bar where the indicator copy armed the same side at the same "
          f"level; {in_bar.sum()} filled inside their signal bar; the copy marks the entry on {copy_entry.sum()}.")
    for t, ok_l, ok_e, a in zip(ea.itertuples(), same_level, copy_entry, armed):
        if not ok_l or not ok_e:
            print(f"  - {t.signal_bar:%Y-%m-%d %H:%M} {t.side} EA level {t.level:.2f}, copy level "
                  f"{'none' if np.isnan(a) else f'{a:.2f}'}, copy entry {'yes' if ok_e else 'no'}")
    span = (sig.index >= ea.signal_bar.min()) & (sig.index <= ea.exit_time.max())
    copy_ent = sig[span & (sig.entry != 0)]
    traded = set(zip(ea.signal_bar, ea.dir))
    missed = []
    for tm, r in copy_ent.iterrows():
        if (tm, r.entry) in traded:
            continue
        busy = ((ea.fill_time < tm) & (ea.exit_time > tm)).any()
        missed.append((tm, r.entry, busy))
    print(f"Copy entries in the same span: {len(copy_ent)}; traded by the EA {len(copy_ent) - len(missed)}; "
          f"skipped while a trade was open {sum(b for *_, b in missed)}; skipped while flat {sum(not b for *_, b in missed)}.")
    for tm, d, busy in missed:
        if not busy:
            print(f"  - not traded while flat: {tm:%Y-%m-%d %H:%M} {'BUY' if d > 0 else 'SELL'}")

    # ---- exits
    import MetaTrader5 as mt5
    mt5.initialize(path=r"C:\Program Files\Pepperstone MetaTrader 5\terminal64.exe")
    try:
        r = mt5.copy_rates_range("XAUUSD", mt5.TIMEFRAME_M1, (ea.fill_time.min() - pd.Timedelta(days=1)).to_pydatetime(),
                                 (ea.exit_time.max() + pd.Timedelta(days=3)).to_pydatetime())
    finally:
        mt5.shutdown()
    m1 = pd.DataFrame(r)
    m1.index = pd.to_datetime(m1.time, unit="s")
    rep = [replay(t, m1, point) for t in ea.itertuples()]
    ea["rp_time"], ea["rp_px"], ea["rp_why"] = zip(*rep)
    ea["why_same"] = ea.why == ea.rp_why
    ea["min_diff"] = (ea.exit_time.dt.floor("min") - ea.rp_time).dt.total_seconds().abs() / 60
    ea["r_diff"] = (ea.exit - ea.rp_px).abs() / ea.risk
    print(f"\nExits: replay gives the same reason on {ea.why_same.sum()} of {len(ea)}; same minute (+-1) on "
          f"{(ea.min_diff <= 1).sum()}; exit price within 0.05R on {(ea.r_diff <= 0.05).sum()}.")
    print("  reasons, EA:", ea.why.value_counts().to_dict(), "| replay:", ea.rp_why.value_counts().to_dict())
    for t in ea[~ea.why_same | (ea.min_diff > 1) | (ea.r_diff > 0.05)].itertuples():
        print(f"  - {t.fill_time:%Y-%m-%d %H:%M} {t.side}: EA {t.why} at {t.exit_time:%m-%d %H:%M} {t.exit:.2f} | "
              f"replay {t.rp_why} at {t.rp_time:%m-%d %H:%M} {t.rp_px:.2f}")

    # ---- results
    days = {y: len(pd.bdate_range(f"{y}-01-01", min(pd.Timestamp(f"{y}-12-31"), ea.exit_time.max()))) for y in
            ea.fill_time.dt.year.unique()}
    print(f"\nResults: {len(ea)} trades, {(ea.R > 0).mean():.0%} winners, avg {ea.R.mean():+.3f}R, total {ea.R.sum():+.1f}R; "
          f"by year: " + ", ".join(f"{y} {g.R.sum():+.1f}R ({len(g)})" for y, g in ea.groupby(ea.fill_time.dt.year)))
    print("\nAs traded, 0.01 lot on $10,000:\n")
    print(year_table(ea, "profit_usd", days))
    bal, money = 10_000.0, []
    for r_ in ea.R:  # the same trades at 1% of the balance risked per trade, compounding
        money.append(bal * 0.01 * r_)
        bal += money[-1]
    ea["at_1pct"] = money
    print("\nThe same trades at 1% risk per trade (what step 3's risk engine would size):\n")
    print(year_table(ea, "at_1pct", days))


if __name__ == "__main__":
    main()
