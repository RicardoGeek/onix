"""Study 34: the 'profitable' ribbon-calculus whale trigger, implemented EXACTLY as pasted:
  same 7 EMAs (3/5/8/12/15/21/30), std thickness, diff velocity, rolling-20 z-score;
  + ATR = rolling-14 mean of True Range;  + macro trend = EMA200 of close;
  valid_buy_trigger = z > 2.5 & close > EMA200 & thickness > 0.5 * ATR.
Variants: LITERAL  = buy every trigger (the pasted code never checks which way the ribbon flares, so it also buys down-spikes);
          UP-FLARE = buy only when the ribbon flares up (EMA3 > EMA30), the obvious intent;
          BOTH     = UP-FLARE + its mirror for sells (close < EMA200, ribbon flares down).
Baseline: the same exits on RANDOM bars on the same side of the EMA200 -> does the trigger add anything over 'be long gold'?
Exits: fixed SL/TP in ATR + time stop of 96 bars; realistic M1 fills (sw_sim2: spread, commission, slippage, swap).
Selection on 2017-2022 only, unseen 2023-2026.  Then a $100k / 0.5% one-position account replay of the best variant per TF.
"""
import sys
import numpy as np
import pandas as pd
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_engine as E
import sw_mtf as M
import sw_sim2 as S2
from sw_mt5report import score

m1a, tfs = V.m1a, V.tfs
PER = [3, 5, 8, 12, 15, 21, 30]
SLS = (0.5, 1.0, 1.5, 2.0, 3.0, 4.0)
TPS = (0.5, 1.0, 1.5, 2.0, 3.0, 4.0)
pd.set_option("display.width", 250)


def fixed(b, periods=PER):
    df = pd.DataFrame({"close": b["c"], "high": b["h"], "low": b["l"]})
    cols = []
    for p in periods:
        df[f"ema_{p}"] = df["close"].ewm(span=p, adjust=False).mean()
        cols.append(f"ema_{p}")
    df["ribbon_thickness"] = df[cols].std(axis=1)
    df["expansion_velocity"] = df["ribbon_thickness"].diff()
    hl = df["high"] - df["low"]
    hc = (df["high"] - df["close"].shift()).abs()
    lc = (df["low"] - df["close"].shift()).abs()
    df["atr"] = pd.concat([hl, hc, lc], axis=1).max(axis=1).rolling(14).mean()
    v = df["expansion_velocity"]
    df["z"] = (v - v.rolling(window=20).mean()) / v.rolling(window=20).std()
    df["macro_trend"] = df["close"].ewm(span=200, adjust=False).mean()
    base = (df["z"] > 2.5) & (df["ribbon_thickness"] > df["atr"] * 0.5)
    df["valid_buy_trigger"] = (base & (df["close"] > df["macro_trend"])).astype(int)
    df["mirror_sell_trigger"] = (base & (df["close"] < df["macro_trend"])).astype(int)
    df["flare"] = np.sign(df[cols[0]] - df[cols[-1]]).astype(int)
    return df


def first_bars(trig):
    return (trig == 1) & (np.r_[0, trig[:-1]] == 0)


def to_events(b, idx, d):
    keep = (idx > 500) & (idx < b["n"] - 1)
    idx, d = idx[keep], d[keep]
    j = b["m1e"][idx]
    ok = (m1a["t"][np.minimum(j, len(m1a["t"]) - 1)] - m1a["t"][j - 1]) <= 1800
    idx, j, d = idx[ok], j[ok], d[ok]
    px = np.where(d > 0, m1a["o"][j] + m1a["spr"][j] + 0.05, m1a["o"][j] - 0.05)
    return idx, j, d.astype(np.int64), px


def outcomes(b, idx, j, d, px, sl, tp, mins, seq=False):
    a = b["atr"][idx]
    mg = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=tp / sl, max_min=96 * mins)
    tr = S2.run_fills(m1a, j, d, px, sl * a, 0 * a, mg, one_at_a_time=seq)
    tr["yr"] = pd.to_datetime(tr.entry_t, unit="s").dt.year.values
    return tr


def std_table(T, start):
    out = []
    for y, g in list(T.groupby(T.entry.dt.year)) + [("ALL", T)]:
        b0 = start + T[T.exit.dt.year < y].net.sum() if y != "ALL" else start
        gx = T[T.exit.dt.year == y] if y != "ALL" else T
        bal = gx.balance.values
        pk = np.maximum.accumulate(np.r_[b0, bal])
        mdd = ((pk - np.r_[b0, bal]) / pk).max() * 100
        y0 = g.entry.min().normalize(); y1 = g.exit.max().normalize() + pd.Timedelta(days=1)
        wd = max(1, np.busday_count(y0.date(), y1.date()))
        e = np.sort(g.entry.values.astype("datetime64[s]").astype(np.int64))
        wait = np.diff(e).mean() / 3600 if len(e) > 1 else np.nan
        net = g.net.sum(); wr = (g.net > 0).mean() * 100
        mo = gx.groupby(gx.exit.dt.to_period("M")).net.sum()
        yrs = max((y1 - y0).days / 365, 0.25); ann = ((b0 + net) / b0) ** (1 / yrs) * 100 - 100
        sc = score(ann, wr, len(g) / wd, wait if np.isfinite(wait) else 1e9, mdd, float((mo > 0).mean()) if len(mo) else 0.0)
        out.append(f"| {y} | {'+' if net >= 0 else '-'}${abs(net):,.0f} ({net / b0 * 100:+.1f}%) | {len(g):,} | {wr:.1f}% | "
                   f"{len(g) / wd:.2f} | {wait:.0f} h | {mdd:.2f}% | {sc} |")
    return out


rng = np.random.default_rng(7)
rows, best_per_tf = [], {}
for tfname, mins in (("M5", 5), ("M15", 15), ("H1", 60)):
    b = tfs[tfname] if tfname in tfs else M.tf_states(E.make_bars(m1a, mins))
    df = fixed(b)
    buy = df["valid_buy_trigger"].values
    sell = df["mirror_sell_trigger"].values
    fl = df["flare"].values
    above = df["close"].values > df["macro_trend"].values
    variants = {
        "LITERAL (as pasted)": (np.flatnonzero(first_bars(buy)), None),
        "UP-FLARE buys": (np.flatnonzero(first_bars(buy * (fl > 0))), None),
        "BOTH (+ mirror sells)": (np.flatnonzero(first_bars(buy * (fl > 0))), np.flatnonzero(first_bars(sell * (fl < 0)))),
    }
    days = (b["t"][-1] - b["t"][500]) / 86400 * 5 / 7
    for vname, (ib, isell) in variants.items():
        idx = ib if isell is None else np.r_[ib, isell]
        d = np.ones(len(ib), np.int64) if isell is None else np.r_[np.ones(len(ib), np.int64), -np.ones(len(isell), np.int64)]
        o = np.argsort(idx, kind="stable"); idx, d = idx[o], d[o]
        idx, j, d, px = to_events(b, idx, d)
        best = None
        for sl in SLS:
            for tp in TPS:
                tr = outcomes(b, idx, j, d, px, sl, tp, mins)
                ins = tr.r[tr.yr <= 2022].mean(); oos = tr.r[tr.yr >= 2023].mean()
                if best is None or ins > best[2]:
                    best = (sl, tp, ins, oos, tr)
        sl, tp, ins, oos, tr = best
        py = tr.groupby("yr").r.mean()
        # baseline: random bars on the same side of the EMA200, same exits
        side_ok = np.flatnonzero((above if isell is None else np.ones(len(above), bool)))
        side_ok = side_ok[(side_ok > 500) & (side_ok < b["n"] - 1)]
        rb = np.sort(rng.choice(side_ok, size=min(4000, len(side_ok)), replace=False))
        rd = np.ones(len(rb), np.int64) if isell is None else np.where(above[rb], 1, -1).astype(np.int64)
        rb, rj, rd, rpx = to_events(b, rb, rd)
        bt = outcomes(b, rb, rj, rd, rpx, sl, tp, mins)
        rows.append(dict(tf=tfname, variant=vname, trades=len(idx), per_day=round(len(idx) / days, 2), SL_TP=f"SL{sl}/TP{tp} ATR",
                         win=round((tr.r > 0).mean() * 100, 1), avgR_2017_22=round(ins, 3), avgR_2023_26=round(oos, 3),
                         yrs_pos=f"{int((py > 0).sum())}/{len(py)}",
                         random_bar_2017_22=round(bt.r[bt.yr <= 2022].mean(), 3), random_bar_2023_26=round(bt.r[bt.yr >= 2023].mean(), 3)))
        if tfname not in best_per_tf or ins > best_per_tf[tfname][0]:
            best_per_tf[tfname] = (ins, vname, sl, tp, b, idx, j, d, px, mins)
    print(f"done {tfname}", flush=True)

R = pd.DataFrame(rows)
print("\n=== 'profitable' whale ribbon (ATR floor + EMA200), best SL/TP picked on 2017-2022, avg R per trade net of costs ===")
print(R.to_string(index=False))
R.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\whale_fixed.csv", index=False)

for tfname, (ins, vname, sl, tp, b, idx, j, d, px, mins) in best_per_tf.items():
    tr = outcomes(b, idx, j, d, px, sl, tp, mins, seq=True).sort_values("exit_t")
    eq = 1e5; recs = []
    for t in tr.itertuples():
        pnl = eq * 0.005 * t.r; eq += pnl
        recs.append((pd.Timestamp(t.entry_t, unit="s"), pd.Timestamp(t.exit_t, unit="s"), pnl, eq))
    T = pd.DataFrame(recs, columns=["entry", "exit", "net", "balance"])
    print(f"\n### {tfname} best variant on 2017-2022: {vname}, SL {sl} / TP {tp} ATR, $100k 0.5% risk, one at a time -> ${eq:,.0f}")
    print("| Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score |")
    print("|---|---|---|---|---|---|---|---|")
    print("\n".join(std_table(T, 1e5)))
