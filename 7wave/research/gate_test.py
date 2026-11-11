"""7Wave as the trend filter for the swing-breakout entry that held up in the SevenWave research (its stream A).

Entry and costs are unchanged from xauusd-sevenwave-ea/python_pipeline (sw_study17/sw_study22/sw_sim2):
  a stop order 0.15 ATR(H1) before an unbroken H1 fractal swing high/low (3 bars each side) aged 12-48 H1 bars,
  only in the filter's direction; fill-accurate M1 simulation with hostile costs; Dukascopy 2017-2026.
Management:
  growth : stop 1.5 ATR(H1), trail 2 ATR once +1R, target 3R, max 24h (the research's profit style)
  whale  : stop 1.5 ATR(H1), stop to +0.05R at +1.5R, then trail 3 ATR, target 5R, max 72h (SevenWave v1.31)
Only the trend filter changes (state of the last CLOSED bar of that timeframe):
  No filter                               both directions
  SevenWave ribbon on H4 + D1 (reference) all 7 lines of 10/16/26/41/66/105/168 stacked on H4 and D1
  7Wave ribbon on H4 + D1                 the same with the user's 20/40/60/80/100/120/140
  7Wave ribbon on H4                      H4 only
  7Wave wave on H4 / on H1                a live 7Wave wave (rules 2+4, the indicator's arrows) on that timeframe
Seen 2017-2022 / unseen 2023-2026, as in the SevenWave research.
The standard per-year account table (the user's format) replays one position at a time on $10,000 risking 1% of
the balance per trade (0.01 lot minimum), with the SevenWave 0-100 score.

    C:\\Users\\faker\\mlv\\Scripts\\python.exe 7wave\\research\\gate_test.py [duka|pep]
"""
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.join(HERE, "..", "..", "xauusd-sevenwave-ea", "python_pipeline")
sys.path.insert(0, PIPE)
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
SRC = sys.argv[1] if len(sys.argv) > 1 else "duka"
_argv = list(sys.argv)
sys.argv = [sys.argv[0], SRC]
import sw_study22 as S22  # noqa: E402  (loads the M1 data and builds the bars and H1 pools)
sys.argv = _argv
import sw_engine as E  # noqa: E402
import sw_mtf as M  # noqa: E402
import sw_sim2 as S2  # noqa: E402
from sw_study17 import pool_stop_events_nb  # noqa: E402
import wave_rules as wr  # noqa: E402

OUT = r"C:\Users\faker\Documents\goldie_research\7wave"
m1a, tfs, POOLS = S22.m1a, S22.tfs, S22.POOLS
SEVENWAVE_RIBBON = (10, 16, 26, 41, 66, 105, 168)
OFF, MIN_AGE, MAX_AGE = 0.15, 12, 48
MGMT = {"growth": S22.MGMT["growth"],
        "whale": (dict(tp1_r=1.5, tp1_frac=0.0, be_r=0.05, act_r=1.5, tp2_r=5.0, max_min=4320), 1.5, 3.0)}
SEEN_LAST = 2022


def stack(tf, periods):
    Em = np.vstack([E.ema_nb(tfs[tf]["c"], float(p)) for p in periods])
    sc = np.sign(-np.diff(Em, axis=0)).sum(axis=0)  # +6: all 7 lines stacked up
    return np.where(sc >= 6, 1, np.where(sc <= -6, -1, 0)).astype(np.int64)


def wave(tf):
    T = tfs[tf]
    _, _, w = wr.signals_for(T["o"], T["c"], wr.emas(T["c"]), states=True)
    w[-1] = 0  # the last bar of the data is still forming
    return w


def on_h1(state, tf):
    """State of the last closed `tf` bar at the close of every H1 bar."""
    if tf == "H1":
        return state.astype(np.int64)
    k = M.map_last_closed(tfs[tf], tfs["H1"]["t_close"])
    return np.where(k >= 0, state[np.maximum(k, 0)], 0).astype(np.int64)


def agree(a, b):
    return np.where(a == b, a, 0).astype(np.int64)


def events(trend):
    T = tfs["H1"]
    ph, phi, pl, pli = POOLS["H1"]
    j, d, px, _ = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], trend.astype(np.int64), T["m1s"], T["m1e"],
                                      m1a["o"], m1a["h"], m1a["l"], m1a["spr"], OFF, MIN_AGE, MAX_AGE, 0.05, 3.0)
    return j, d, px


def trades(trend, mode, one_at_a_time=False):
    if trend is None:  # no filter: the long and short breakouts both trade
        n = tfs["H1"]["n"]
        parts = [events(np.ones(n, np.int64)), events(-np.ones(n, np.int64))]
        j, d, px = (np.concatenate([p[q] for p in parts]) for q in range(3))
    else:
        j, d, px = events(trend)
    k = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][j]), 0)
    atr = tfs["H1"]["atr"][k]
    mg, sl_k, tr_k = MGMT[mode]
    return S2.run_fills(m1a, j, d, px, sl_k * atr, tr_k * atr, mg, one_at_a_time=one_at_a_time)


def score(ann_ret_pct, wr, tpd, wait_h, maxdd_pct, green_share):
    """SevenWave 0-100 score (xauusd-sevenwave-ea/python_pipeline/sw_final.py)."""
    s_p = 25 * max(ann_ret_pct, 0) / (max(ann_ret_pct, 0) + 100)
    s_w = 20 * float(np.clip((wr - 50) / 30, 0, 1))
    s_f = 15 * min(1.0, tpd / 1.0)
    s_t = 10 * min(1.0, 24.0 / max(wait_h, 1e-9))
    s_d = 15 * float(np.clip(1 - maxdd_pct / 10.0, 0, 1))
    return round(s_p + s_w + s_f + s_t + s_d + 15 * green_share, 1)


def account_table(tr, days, start=10_000.0, risk_pct=1.0):
    """The user's standard table: one position at a time, risk_pct of the balance per trade, compounding."""
    bal, peak, rows = start, start, []
    for t in tr.sort_values("entry_t").itertuples():
        oz = max(1.0, np.floor(bal * risk_pct / 100.0 / t.R))  # 0.01 lot = 1 oz minimum
        pnl = oz * t.R * t.r
        bal += pnl
        peak = max(peak, bal)
        rows.append(dict(entry_t=t.entry_t, exit_t=t.exit_t, year=t.year, pnl=pnl, bal=bal, dd=(peak - bal) / peak * 100,
                         r=t.r))
    eq = pd.DataFrame(rows)
    out = ["| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |",
           "|---|---|---|---|---|---|---|---|"]
    bal0 = start
    for y, g in eq.groupby("year"):
        net = g.pnl.sum()
        pct = net / bal0 * 100
        months = pd.to_datetime(g.exit_t, unit="s").dt.to_period("M")
        green = (g.groupby(months).pnl.sum() > 0).mean()
        wait = np.diff(np.sort(g.entry_t.to_numpy())).mean() / 3600 if len(g) > 1 else np.nan
        wr = (g.r > 0).mean() * 100
        tpd = len(g) / days.get(y, 252)
        out.append(f"| {y} | ${net:+,.0f} ({pct:+.1f}%) | {len(g)} | {wr:.0f}% | {tpd:.2f} | {wait:.0f} h "
                   f"| {g.dd.max():.1f}% | {score(pct, wr, tpd, wait, g.dd.max(), green)} |")
        bal0 += net
    total = eq.pnl.sum()
    out.append(f"| **All** | ${total:+,.0f} ({total / start * 100:+.0f}%) | {len(eq)} | {(eq.r > 0).mean() * 100:.0f}% "
               f"| {len(eq) / sum(days.get(y, 252) for y in eq.year.unique()):.2f} "
               f"| {np.diff(np.sort(eq.entry_t.to_numpy())).mean() / 3600:.0f} h | {eq.dd.max():.1f}% | |")
    return "\n".join(out)


def main():
    filters = {
        "No filter": None,
        "SevenWave ribbon on H4 + D1 (reference)": agree(on_h1(stack("H4", SEVENWAVE_RIBBON), "H4"),
                                                          on_h1(stack("D1", SEVENWAVE_RIBBON), "D1")),
        "7Wave ribbon on H4 + D1": agree(on_h1(stack("H4", wr.PERIODS), "H4"), on_h1(stack("D1", wr.PERIODS), "D1")),
        "7Wave ribbon on H4": on_h1(stack("H4", wr.PERIODS), "H4"),
        "7Wave wave on H4": on_h1(wave("H4"), "H4"),
        "7Wave wave on H1": on_h1(wave("H1"), "H1"),
    }
    tday = pd.Series(m1a["tday"], index=pd.to_datetime(m1a["t"], unit="s").year)
    days = tday.groupby(level=0).nunique()
    md = [f"# 7Wave as the trend filter for the swing breakout (raw output, {SRC})", ""]
    for name in ("SevenWave ribbon on H4 + D1 (reference)", "7Wave ribbon on H4 + D1"):
        md += [f"## Account table: {name}, growth management, one position at a time, $10,000 at 1% risk", "",
               account_table(trades(filters[name], "growth", one_at_a_time=True), days.to_dict()), ""]
    for mode in MGMT:
        md += [f"## Management: {mode}", "",
               "| Filter | Trades | Trades/day | Win rate | Avg R | Seen 2017-22: avg R / total R / green years "
               "| Unseen 2023-26: avg R / total R / green years | One position at a time: total R seen / unseen |",
               "|---|---|---|---|---|---|---|---|"]
        per_year = {}
        for name, trend in filters.items():
            tr = trades(trend, mode)
            one = trades(trend, mode, one_at_a_time=True)
            tag = name.split(" (")[0].replace(" ", "_").replace("+", "and")
            tr.to_csv(os.path.join(OUT, f"gate_{SRC}_{mode}_{tag}.csv"), index=False)
            s, u = tr[tr.year <= SEEN_LAST], tr[tr.year > SEEN_LAST]
            ys, yu = s.groupby("year").r.sum(), u.groupby("year").r.sum()
            os_, ou = one[one.year <= SEEN_LAST].r.sum(), one[one.year > SEEN_LAST].r.sum()
            tpd = len(tr) / days.loc[sorted(tr.year.unique())].sum()
            md.append(f"| {name} | {len(tr)} | {tpd:.2f} | {(tr.r > 0).mean():.0%} | {tr.r.mean():+.3f} "
                      f"| {s.r.mean():+.3f} / {s.r.sum():+.1f} / {(ys > 0).sum()} of {len(ys)} "
                      f"| {u.r.mean():+.3f} / {u.r.sum():+.1f} / {(yu > 0).sum()} of {len(yu)} | {os_:+.1f} / {ou:+.1f} |")
            per_year[name] = tr.groupby("year").r.mean()
        py = pd.DataFrame(per_year)
        md += ["", f"Average R per trade by year ({mode}):", "",
               "| Year | " + " | ".join(py.columns) + " |", "|---|" + "---|" * len(py.columns)]
        for y, row in py.iterrows():
            md.append(f"| {y} | " + " | ".join(f"{v:+.3f}" for v in row.values) + " |")
        md.append("")
    path = os.path.join(OUT, f"gate_test_raw_{SRC}.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(md))
    print("\n".join(md))


if __name__ == "__main__":
    main()
