"""7Wave wave scorecard: what happens after every star and arrow, and which context visible at the signal separates
the big waves (the user's screenshots 1-2) from the fakes (screenshots 3-4).

Data   : Dukascopy XAUUSD M1 bid bars (server time = NY+7, the Pepperstone chart clock), 2018-2026.
         Feed check: Pepperstone M1 with real spreads, 2024-2026.
Signals: tools/wave_rules.py, the rules the user checked on the chart (stars, arrows, candle color).
Outcome: hostile costs, the same model as the SevenWave research (xauusd-sevenwave-ea/python_pipeline/sw_engine.py):
         entry at the next M1 open after the signal bar closes, long at the ask (bid + spread);
         R = 1.5 x ATR(14) of the signal timeframe; stop -1R, target +3R, time exit after HORIZON bars;
         stop and target in the same M1 bar -> the stop; gaps through the stop fill at the gap;
         commission $0.08/oz, slippage $0.05 market / $0.10 stop, long swap -$0.80/oz per NY-17:00 rollover
         (x3 on Wednesday).
         good wave = the +3R target before the stop; fake = stopped out before ever reaching +1R.
Context: all known when the signal bar closes (see feature_rows).
Split  : buckets are fixed on 2018-2021 ("seen") and judged on 2022-2026 ("unseen").

    C:\\Users\\faker\\mlv\\Scripts\\python.exe 7wave\\research\\wave_scorecard.py
"""
import os
import sys

import numpy as np
import pandas as pd
from numba import njit

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import wave_rules as wr  # noqa: E402

DATA = r"C:\Users\faker\Documents\goldie_research\sevenwave\data"
OUT = r"C:\Users\faker\Documents\goldie_research\7wave"
os.makedirs(OUT, exist_ok=True)

COMM, SLIP_IN, SLIP_STOP, SWAP_LONG = 0.08, 0.05, 0.10, -0.80
DUKA_SPREAD, DUKA_SPREAD_ROLL, PEP_FLOOR, PEP_MULT = 0.30, 0.60, 0.15, 1.25
R_ATR, TARGET_R = 1.5, 3.0
TFS = {"H1": (60, 120), "M15": (15, 192)}  # bar minutes, time exit after this many bars (5 days H1, 2 days M15)
# holding the waves (SevenWave v1.31 whale handling): no target, at +1.5R the stop goes to +0.05R, then it trails
# 3 x ATR(14) of H1 behind the best price; time exit after HOLD bars (10 days on H1, 4 days on M15)
BE_AT, BE_LOCK, TRAIL_ATR_H1 = 1.5, 0.05, 3.0
HOLD = {"H1": 240, "M15": 384}
FIRST_YEAR, SEEN_LAST = 2018, 2021
NUMERIC = ["slope140", "width", "squeeze", "chop", "star_lead", "atr_ratio", "ext", "waited"]
LABELS = {
    "h4": "H4 ribbon in the signal's direction",
    "d1": "D1 ribbon in the signal's direction",
    "h1": "H1 ribbon in the signal's direction",
    "kind": "Signal type",
    "side": "Direction",
    "session": "Session (UTC)",
    "slope140": "EMA 140 slope over 20 bars, in ATR, signal's direction",
    "width": "Ribbon width EMA20-EMA140 at the signal, in ATR",
    "squeeze": "Average ribbon width over the 60 bars before, in ATR",
    "chop": "Signals in the previous 100 bars",
    "star_lead": "Arrows: bars since the last same-direction star",
    "atr_ratio": "ATR(14) / ATR(100), volatility expansion",
    "ext": "Close minus EMA 140 at the signal, in ATR",
    "waited": "Bars the signal waited for its candle",
}


# --------------------------------------------------------------------------------------------------- data and bars
def load_m1(source):
    z = np.load(os.path.join(DATA, f"{source}_m1.npz"))
    srv = z["srv"].astype(np.int64)
    t = z["t"].astype(np.int64)
    o, h, l, c = (z[k].astype(np.float64) for k in ("open", "high", "low", "close"))
    hr = (t // 3600) % 24
    if source == "duka":  # bid-only feed: flat spread, doubled around the NY-17:00 rollover
        spr = np.where((hr >= 21) & (hr <= 22), DUKA_SPREAD_ROLL, DUKA_SPREAD).astype(np.float64)
    else:
        s = z["spread"].astype(np.float64)
        spr = np.maximum(np.where(np.isfinite(s), s, 0.20), PEP_FLOOR) * PEP_MULT
    sday = srv // 86400
    new_day = np.concatenate([[False], np.diff(sday) > 0])  # server midnight = NY 17:00 rollover
    weekday = (sday + 3) % 7                                  # Monday = 0 (1970-01-01 was a Thursday)
    weight = np.where(weekday == 3, 3, 1)                     # Wednesday NY rollover (server Thursday) counts 3x
    swapcnt = np.cumsum(np.where(new_day, weight, 0)).astype(np.float64)
    return dict(srv=srv, t=t, o=o, h=h, l=l, c=c, spr=spr, swapcnt=swapcnt)


def make_bars(m, minutes):
    """Bars on the server clock, so H4 and D1 match the Pepperstone chart (anchored at server midnight)."""
    key = m["srv"] // (minutes * 60)
    chg = np.flatnonzero(np.diff(key)) + 1
    s = np.concatenate([[0], chg]).astype(np.int64)
    e = np.concatenate([chg, [len(key)]]).astype(np.int64)
    return dict(t=key[s] * minutes * 60, sec=minutes * 60, o=m["o"][s], c=m["c"][e - 1],
                h=np.maximum.reduceat(m["h"], s), l=np.minimum.reduceat(m["l"], s), m1s=s, m1e=e)


def atr(b, n):
    pc = np.concatenate([[b["c"][0]], b["c"][:-1]])
    tr = np.maximum(b["h"] - b["l"], np.maximum(np.abs(b["h"] - pc), np.abs(b["l"] - pc)))
    return pd.Series(tr).rolling(n, min_periods=1).mean().to_numpy()


def ribbon_in_order(b):
    """Close time of each bar, and how many of its 7 lines are in UP order and in DOWN order."""
    ema = wr.emas(b["c"])
    up = np.array([7 - wr.out_of_order(v, 1) for v in ema])
    dn = np.array([7 - wr.out_of_order(v, -1) for v in ema])
    return b["t"] + b["sec"], up, dn


# --------------------------------------------------------------------------------------------------- the trade
@njit(cache=False)
def simulate(j0, j1, d, rdist, o, h, l, c, spr, swapcnt):
    """Bracket trade on M1 bars j0..j1-1.
    Returns (R after costs, best excursion in R, 1 target / -1 stop / 0 time, M1 index of the exit)."""
    if d > 0:
        entry = o[j0] + spr[j0] + SLIP_IN
    else:
        entry = o[j0] - SLIP_IN
    stop = entry - d * rdist
    target = entry + d * TARGET_R * rdist
    mfe = 0.0
    reason = 0
    exit_px = 0.0
    jx = j1 - 1
    for j in range(j0, j1):
        if d > 0:
            if l[j] <= stop:
                px = stop
                if j > j0 and o[j] < stop:
                    px = o[j]
                exit_px = px - SLIP_STOP
                reason = -1
                jx = j
                break
            if h[j] - entry > mfe:
                mfe = h[j] - entry
            if h[j] >= target:
                exit_px = target
                reason = 1
                jx = j
                break
        else:
            if h[j] + spr[j] >= stop:
                px = stop
                if j > j0 and o[j] + spr[j] > stop:
                    px = o[j] + spr[j]
                exit_px = px + SLIP_STOP
                reason = -1
                jx = j
                break
            if entry - (l[j] + spr[j]) > mfe:
                mfe = entry - (l[j] + spr[j])
            if l[j] + spr[j] <= target:
                exit_px = target
                reason = 1
                jx = j
                break
    if reason == 0:
        if d > 0:
            exit_px = c[jx] - SLIP_IN
        else:
            exit_px = c[jx] + spr[jx] + SLIP_IN
    pnl = (exit_px - entry) * d - COMM
    if d > 0:
        pnl += SWAP_LONG * (swapcnt[jx] - swapcnt[j0])
    return pnl / rdist, mfe / rdist, reason, jx


@njit(cache=False)
def run_length(j0, j1, d, rdist, o, h, l, spr):
    """How far the wave went: best favorable move (in R) before the -1R stop, with no target."""
    entry = o[j0] + spr[j0] + SLIP_IN if d > 0 else o[j0] - SLIP_IN
    stop = entry - d * rdist
    best = 0.0
    for j in range(j0, j1):
        if d > 0:
            if l[j] <= stop:
                break
            if h[j] - entry > best:
                best = h[j] - entry
        else:
            if h[j] + spr[j] >= stop:
                break
            if entry - (l[j] + spr[j]) > best:
                best = entry - (l[j] + spr[j])
    return best / rdist


@njit(cache=False)
def trail_trade(j0, j1, d, rdist, trail, o, h, l, c, spr, swapcnt):
    """-1R stop, no target; at +1.5R the stop moves to +0.05R and then trails `trail` behind the best price.
    A stop moved on an M1 bar only counts from the next M1 bar. Returns R after costs."""
    entry = o[j0] + spr[j0] + SLIP_IN if d > 0 else o[j0] - SLIP_IN
    stop = entry - d * rdist
    best = entry
    secured = False
    exit_px = 0.0
    jx = j1 - 1
    done = False
    for j in range(j0, j1):
        if d > 0:
            if l[j] <= stop:
                px = stop
                if j > j0 and o[j] < stop:
                    px = o[j]
                exit_px = px - SLIP_STOP
                jx = j
                done = True
                break
            if h[j] > best:
                best = h[j]
            if not secured and best - entry >= BE_AT * rdist:
                secured = True
                stop = max(stop, entry + BE_LOCK * rdist)
            if secured:
                stop = max(stop, best - trail)
        else:
            if h[j] + spr[j] >= stop:
                px = stop
                if j > j0 and o[j] + spr[j] > stop:
                    px = o[j] + spr[j]
                exit_px = px + SLIP_STOP
                jx = j
                done = True
                break
            if l[j] + spr[j] < best:
                best = l[j] + spr[j]
            if not secured and entry - best >= BE_AT * rdist:
                secured = True
                stop = min(stop, entry - BE_LOCK * rdist)
            if secured:
                stop = min(stop, best + trail)
    if not done:
        exit_px = c[jx] - SLIP_IN if d > 0 else c[jx] + spr[jx] + SLIP_IN
    pnl = (exit_px - entry) * d - COMM
    if d > 0:
        pnl += SWAP_LONG * (swapcnt[jx] - swapcnt[j0])
    return pnl / rdist


def session(hour):
    if hour >= 22 or hour < 6:
        return "Asia 22-06"
    if hour < 12:
        return "London 06-12"
    if hour < 17:
        return "New York 12-17"
    return "Evening 17-22"


def ribbon_class(n_in_order):
    return np.where(n_in_order == 7, "all 7 in order", np.where(n_in_order >= 4, "4-6 in order", "0-3 in order"))


# --------------------------------------------------------------------------------------------------- signals + context
def feature_rows(m, src, tf, minutes, horizon):
    b = make_bars(m, minutes)
    n = len(b["c"])
    ema = wr.emas(b["c"])
    a14, a100 = atr(b, 14), atr(b, 100)
    sig, _ = wr.signals_for(b["o"], b["c"], ema)
    htf = {"h4": ribbon_in_order(make_bars(m, 240)), "d1": ribbon_in_order(make_bars(m, 1440))}
    h1 = b if minutes == 60 else make_bars(m, 60)
    h1_close, h1_atr = h1["t"] + h1["sec"], atr(h1, 14)
    if minutes < 60:
        htf["h1"] = ribbon_in_order(h1)
    sig_bars = np.array([s[0] for s in sig])
    last_star = {1: -10 ** 9, -1: -10 ** 9}
    rows = []
    for i, kind, d, due in sig:
        if kind == "star":
            last_star[d] = i
        j0 = b["m1e"][i]
        if i < 120 or j0 >= len(m["o"]):
            continue
        j1 = b["m1e"][min(i + horizon, n - 1)]
        t_utc = pd.Timestamp(int(m["t"][j0 - 1]), unit="s")
        if t_utc.year < FIRST_YEAR or j1 <= j0:
            continue
        rdist = R_ATR * a14[i]
        r, mfe, reason, _ = simulate(j0, j1, d, rdist, m["o"], m["h"], m["l"], m["c"], m["spr"], m["swapcnt"])
        close_t = b["t"][i] + b["sec"]
        jh = b["m1e"][min(i + HOLD[tf], n - 1)]
        kh = np.searchsorted(h1_close, close_t, side="right") - 1
        trail = TRAIL_ATR_H1 * h1_atr[max(kh, 0)]
        run_r = run_length(j0, jh, d, rdist, m["o"], m["h"], m["l"], m["spr"])
        hold_r = trail_trade(j0, jh, d, rdist, trail, m["o"], m["h"], m["l"], m["c"], m["spr"], m["swapcnt"])
        row = dict(src=src, tf=tf, bar=i, time_srv=pd.Timestamp(int(b["t"][i]), unit="s"), time_utc=t_utc,
                   year=t_utc.year, hour=t_utc.hour, session=session(t_utc.hour), kind=kind, dir=d,
                   side="long" if d > 0 else "short", R=r, mfe=mfe, reason=reason, good=int(reason == 1),
                   fake=int(reason == -1 and mfe < 1.0), waited=i - due, run_R=run_r, hold_R=hold_r)
        for k, (ct, up, dn) in htf.items():
            kk = np.searchsorted(ct, close_t, side="right") - 1  # last higher-timeframe bar closed by now
            row[k + "_in"] = (up if d > 0 else dn)[kk] if kk >= 0 else np.nan
        a = a14[i]
        row["slope140"] = (ema[i, 6] - ema[i - 20, 6]) * d / a
        row["width"] = (ema[i, 0] - ema[i, 6]) * d / a
        row["squeeze"] = float(np.mean(np.abs(ema[i - 60:i, 0] - ema[i - 60:i, 6]) / a14[i - 60:i]))
        row["chop"] = int(np.searchsorted(sig_bars, i, "left") - np.searchsorted(sig_bars, i - 100, "left"))
        row["star_lead"] = (i - last_star[d]) if (kind == "arrow" and i - last_star[d] <= 200) else np.nan
        row["atr_ratio"] = a / a100[i]
        row["ext"] = (b["c"][i] - ema[i, 6]) * d / a
        rows.append(row)
    df = pd.DataFrame(rows)
    for k in htf:
        df[k] = ribbon_class(df[k + "_in"].to_numpy())
    return df


# --------------------------------------------------------------------------------------------------- reports
def trading_days(m):
    days = pd.Series(pd.to_datetime(m["srv"] // 86400 * 86400, unit="s")).drop_duplicates()
    return days.groupby(days.dt.year).size()


def year_table(df, tdays):
    out = ["| Year | Signals | Signals/day | Avg wait | Good waves (+3R first) | Fakes (stopped before +1R) "
           "| Avg R after costs | Total R |", "|---|---|---|---|---|---|---|---|"]

    def line(label, g, days):
        wait = g["time_utc"].sort_values().diff().dt.total_seconds().mean() / 3600
        return (f"| {label} | {len(g)} | {len(g) / days:.2f} | {wait:.0f} h | {g.good.mean():.0%} | {g.fake.mean():.0%} "
                f"| {g.R.mean():+.3f} | {g.R.sum():+.1f} |")

    for y, g in df.groupby("year"):
        out.append(line(str(y), g, tdays.get(y, 252)))
    out.append(line("**All**", df, sum(tdays.get(y, 252) for y in df.year.unique())))
    return "\n".join(out)


def split_table(df, col):
    seen, unseen = df[df.year <= SEEN_LAST], df[df.year > SEEN_LAST]
    if col in NUMERIC:
        x = df[col]
        lo, hi = np.nanquantile(seen[col], [1 / 3, 2 / 3])
        b = np.where(x.isna(), "n/a", np.where(x <= lo, f"low (<= {lo:.2f})",
                                               np.where(x <= hi, f"mid ({lo:.2f}-{hi:.2f})", f"high (> {hi:.2f})")))
        df = df.assign(bucket=b)
    else:
        df = df.assign(bucket=df[col].astype(str))
    seen, unseen = df[df.year <= SEEN_LAST], df[df.year > SEEN_LAST]
    s_r = seen.groupby("bucket").R.mean()
    s_r = s_r[seen.groupby("bucket").size() >= 20].drop("n/a", errors="ignore")
    best, worst = (s_r.idxmax(), s_r.idxmin()) if len(s_r) >= 2 else (None, None)
    wins = tot = 0
    if best is not None:
        for _, g in df.groupby("year"):
            gb, gw = g[g.bucket == best], g[g.bucket == worst]
            if len(gb) >= 5 and len(gw) >= 5:
                tot += 1
                wins += gb.R.mean() > gw.R.mean()
    out = [f"**{LABELS.get(col, col)}**" + (f" (best on seen years: {best}; it beat {worst} in {wins} of {tot} years)"
                                            if best is not None else ""),
           "", "| Bucket | Seen 2018-21: n | Good | Avg R | Unseen 2022-26: n | Good | Avg R |", "|---|---|---|---|---|---|---|"]
    for k in sorted(df.bucket.unique()):
        s, u = seen[seen.bucket == k], unseen[unseen.bucket == k]
        out.append(f"| {k} | {len(s)} | {s.good.mean():.0%} | {s.R.mean():+.3f} | {len(u)} | {u.good.mean():.0%} "
                   f"| {u.R.mean():+.3f} |")
    return "\n".join(out), (best, worst, wins, tot)


def hold_report(df, tf):
    days = {"H1": "10 days", "M15": "4 days"}[tf]
    out = [f"**How far the waves ran** (no target, -1R stop, up to {days}): "
           f"{(df.run_R >= 3).mean():.0%} reached 3R, {(df.run_R >= 5).mean():.0%} reached 5R, "
           f"{(df.run_R >= 10).mean():.0%} reached 10R.", "",
           "**Holding them** (no target; at +1.5R the stop locks +0.05R, then trails 3 ATR(H1); time exit after "
           f"{days}):", "", "| Year | Signals | Winners | Avg R after costs | Total R | Best trade |", "|---|---|---|---|---|---|"]
    for y, g in df.groupby("year"):
        out.append(f"| {y} | {len(g)} | {(g.hold_R > 0).mean():.0%} | {g.hold_R.mean():+.3f} | {g.hold_R.sum():+.1f} "
                   f"| {g.hold_R.max():+.1f}R |")
    out.append(f"| **All** | {len(df)} | {(df.hold_R > 0).mean():.0%} | {df.hold_R.mean():+.3f} | "
               f"{df.hold_R.sum():+.1f} | {df.hold_R.max():+.1f}R |")
    for col in ("h4", "atr_ratio", "session"):
        x = df
        if col == "atr_ratio":
            lo, hi = np.nanquantile(df[df.year <= SEEN_LAST][col], [1 / 3, 2 / 3])
            x = df.assign(atr_ratio=np.where(df[col] <= lo, "low", np.where(df[col] <= hi, "mid", "high")))
        parts = []
        for k, g in x.groupby(col):
            s, u = g[g.year <= SEEN_LAST], g[g.year > SEEN_LAST]
            parts.append(f"{k}: seen {s.hold_R.mean():+.3f} (n {len(s)}), unseen {u.hold_R.mean():+.3f} (n {len(u)})")
        out.append(f"- Holding, by {LABELS[col]}: " + "; ".join(parts))
    return "\n".join(out)


def walk_forward(df, feats):
    import lightgbm as lgb
    from sklearn.metrics import roc_auc_score
    X = df[feats].astype(float)
    out = ["| Test year | Train years | AUC | Top half: n / good / avg R | Bottom half: n / good / avg R |",
           "|---|---|---|---|---|"]
    all_p, all_y, all_r, wins, tot = [], [], [], 0, 0
    for y in range(FIRST_YEAR + 2, df.year.max() + 1):
        tr, te = df.year < y, df.year == y
        if te.sum() < 20:
            continue
        mdl = lgb.LGBMClassifier(n_estimators=300, learning_rate=0.03, num_leaves=7, min_child_samples=25,
                                 subsample=0.8, subsample_freq=1, colsample_bytree=0.8, reg_lambda=1.0, verbose=-1)
        mdl.fit(X[tr], df.good[tr])
        p = mdl.predict_proba(X[te])[:, 1]
        g = df[te].assign(p=p)
        top, bot = g[g.p >= np.median(p)], g[g.p < np.median(p)]
        auc = roc_auc_score(g.good, p) if g.good.nunique() == 2 else np.nan
        tot += 1
        wins += top.R.mean() > bot.R.mean()
        all_p += list(p)
        all_y += list(g.good)
        all_r += list(g.R)
        out.append(f"| {y} | {FIRST_YEAR}-{y - 1} | {auc:.3f} | {len(top)} / {top.good.mean():.0%} / {top.R.mean():+.3f} "
                   f"| {len(bot)} / {bot.good.mean():.0%} / {bot.R.mean():+.3f} |")
    pooled = roc_auc_score(all_y, all_p)
    return "\n".join(out), pooled, wins, tot


def main():
    md = ["# 7Wave wave scorecard (raw output)", ""]
    duka = load_m1("duka")
    tdays = trading_days(duka)
    frames = {}
    for tf, (minutes, horizon) in TFS.items():
        df = feature_rows(duka, "duka", tf, minutes, horizon)
        frames[tf] = df
        df.to_csv(os.path.join(OUT, f"scorecard_duka_{tf}.csv"), index=False)
        md += [f"## {tf}: every star and arrow, Dukascopy {FIRST_YEAR}-2026", "", year_table(df, tdays), ""]
        for kind, g in df.groupby("kind"):
            md.append(f"- {kind}s: {len(g)}, good {g.good.mean():.0%}, fakes {g.fake.mean():.0%}, avg R {g.R.mean():+.3f}")
        md += ["", hold_report(df, tf), ""]
        cols = ["h4", "d1"] + (["h1"] if tf == "M15" else []) + ["kind", "side", "session"] + NUMERIC
        summary = []
        for col in cols:
            text, (best, worst, wins, tot) = split_table(df, col)
            md += [text, ""]
            summary.append((col, best, worst, wins, tot))
        md += ["**Consistency summary** (best vs worst bucket from the seen years, per year 2018-2026):", ""]
        md += [f"- {LABELS.get(c, c)}: {b} beat {w} in {wn}/{t} years" for c, b, w, wn, t in summary if b is not None]
        feats = [c + "_in" for c in (["h4", "d1"] + (["h1"] if tf == "M15" else []))] + NUMERIC + ["dir", "hour"]
        df["kind_arrow"] = (df.kind == "arrow").astype(int)
        feats.append("kind_arrow")
        table, pooled, wins, tot = walk_forward(df, feats)
        md += ["", f"**Walk-forward AI (LightGBM, {len(feats)} features, label = good wave)**: pooled out-of-sample "
                   f"AUC {pooled:.3f}; top half beat bottom half in {wins} of {tot} test years.", "", table, ""]
    # feed check: the same signals and outcomes on Pepperstone M1 with its real spreads
    pep = load_m1("pep")
    ptd = trading_days(pep)
    for tf, (minutes, horizon) in TFS.items():
        p = feature_rows(pep, "pep", tf, minutes, horizon)
        p = p[p.year >= 2024]
        d = frames[tf][(frames[tf].year >= 2024) & (frames[tf].time_utc <= p.time_utc.max())]
        p.to_csv(os.path.join(OUT, f"scorecard_pep_{tf}.csv"), index=False)
        md += [f"## Feed check {tf}: Pepperstone (real spreads) vs Dukascopy, 2024-2026", "",
               "Pepperstone:", "", year_table(p, ptd), "", "Dukascopy, same window:", "", year_table(d, tdays), "",
               f"- Holding: Pepperstone avg {p.hold_R.mean():+.3f}R (n {len(p)}), Dukascopy avg {d.hold_R.mean():+.3f}R "
               f"(n {len(d)})"]
        for name, g in (("Pepperstone", p), ("Dukascopy", d)):
            parts = [f"{k}: n {len(x)}, good {x.good.mean():.0%}, avg R {x.R.mean():+.3f}" for k, x in g.groupby("h4")]
            md.append(f"- {name} by H4 ribbon: " + "; ".join(parts))
        md.append("")
    path = os.path.join(OUT, "scorecard_raw.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(md))
    print("\n".join(md))
    print(f"\nwritten: {path}")


if __name__ == "__main__":
    main()
