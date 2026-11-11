"""SevenWave v1.00 research harness: final strategy + compact AI rater + risk-engine equity simulation + report table.

  python sw_final.py duka            # 2017-2026 Dukascopy (walk-forward AI, OOS years 2019+)
  python sw_final.py pep             # 2023-2026 Pepperstone (AI trained on Duka 2017-2022 only)
  python sw_final.py export          # train the deployable ONNX on Duka 2017-2023 (MT5 2024-2026 = out of sample)

Report columns (per year): Net Profit, Trades, Win Rate (position and MT5-deal level), Avg Trades/Day,
Avg Wait between trades, Max DD, Green months, Score (0-100, see score()).
"""
import os
import sys
import time
import numpy as np
import pandas as pd
import lightgbm as lgb
from sklearn.metrics import roc_auc_score
import sw_engine as E
import sw_mtf as M
import sw_sim2 as S2
import sw_ml3 as L3
from sw_study17 import pools_nb, pool_stop_events_nb

OUT = r"C:\Users\faker\Documents\goldie_research\sevenwave"
# Style PROFIT (default): ride the trend tail.  Style WINRATE: 20% partial at 0.3R + break-even.
STYLES = {
    "profit": (dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=3.0, max_min=1440), 1.5, 2.0),
    "winrate": (dict(tp1_r=0.3, tp1_frac=0.2, be_r=0.05, act_r=1.5, tp2_r=2.0, max_min=2880), 2.0, 1.0),
}
STYLE = os.environ.get("SW_STYLE", "profit")
MG, SL_K, TRAIL_K = STYLES[STYLE]
VETO_Q = 0.25
STREAM_RISK = {0: 1.0, 1: 1.0, 2: 0.5, 3: 0.5, 4: 0.35, 5: 0.35}   # risk weight by stream edge (A,B core)
# compact feature set (identical in MQL5 SevenWave/AiRater.mqh, order matters)
FEATS = ["stream", "dir", "age", "h1_order", "h4_order", "d1_order", "h1_w", "h4_w", "d1_w", "h1_d0", "h4_d0",
         "volreg", "cost_atr", "hsin", "hcos", "ret_d1", "pos_d1"]


def feature_matrix(Xfull):
    idx = [L3.FEATS.index(f) for f in FEATS]
    return Xfull[:, idx]


def train(X, y, seed=5):
    params = dict(objective="binary", learning_rate=0.03, num_leaves=7, min_data_in_leaf=60, feature_fraction=0.7,
                  bagging_fraction=0.8, bagging_freq=1, lambda_l2=20.0, verbose=-1, num_threads=2, seed=seed)
    n = len(y)
    cut = int(n * 0.8)
    m = lgb.train(params, lgb.Dataset(X[:cut], y[:cut]), 600, valid_sets=[lgb.Dataset(X[cut:], y[cut:])],
                  callbacks=[lgb.early_stopping(60, verbose=False)])
    pv = m.predict(X[cut:], num_iteration=m.best_iteration)
    return m, float(np.quantile(pv, VETO_Q))


def walk_scores(df, X, test_years, min_iter=20):
    y = (df.r.values > 0).astype(int)
    p = np.full(len(y), np.nan)
    thr = np.full(len(y), np.nan)
    for Y in test_years:
        tr = df.year.values < Y
        te = df.year.values == Y
        if te.sum() == 0 or tr.sum() < 400:
            continue
        m, t = train(X[tr], y[tr])
        p[te] = m.predict(X[te], num_iteration=m.best_iteration)
        thr[te] = t
        auc = roc_auc_score(y[te], p[te]) if len(set(y[te])) > 1 else np.nan
        print(f"  AI {Y}: trained on {tr.sum()} setups, iters={m.best_iteration}, OOS AUC={auc:.3f}")
    return p, thr


# ----------------------------------------------------------------------------------------------- risk engine
def equity_sim(tr, mode="prop", start=10_000.0, risk_pct=None, daily_dd=None, max_dd=None, lot_cap_oz=5000.0):
    """Sequential account simulation with the SevenWave risk engine (same rules as RiskEngine.mqh).
    Prop:   risk 1.0%/trade of equity, daily DD 3% (vs max(day-start balance, equity)), trailing max DD 6% on HWM;
            every trade is sized so a full stop (+25% slippage buffer) can never breach either floor (it shrinks
            risk as the room shrinks -> 'recovery mode' on a damaged account).
    Growth: risk 2.5% of equity x house-money boost (1 + profit/start, capped 2x), DD governor halves risk at
            half the max-DD budget; daily 8%, trailing 25%."""
    if mode == "prop":
        risk_pct = 0.75 if risk_pct is None else risk_pct
        daily_dd = 3.0 if daily_dd is None else daily_dd
        max_dd = 6.0 if max_dd is None else max_dd
    else:
        risk_pct = 3.0 if risk_pct is None else risk_pct
        daily_dd = 10.0 if daily_dd is None else daily_dd
        max_dd = 30.0 if max_dd is None else max_dd
    bal = start
    hwm = start
    day = None
    day_ref = start
    rows = []
    halted_day = None
    for t in tr.itertuples():
        dt = pd.Timestamp(t.entry_t, unit="s")
        dkey = (dt + pd.Timedelta(hours=2)).normalize()  # broker server day (UTC+2/3 ~ NY close); prop resets there
        if dkey != day:
            day = dkey
            day_ref = max(bal, bal)  # flat between trades -> equity == balance
            halted_day = None
        if halted_day == day:
            continue
        floor_day = day_ref * (1 - daily_dd / 100.0)
        floor_tot = hwm * (1 - max_dd / 100.0)
        room_day = bal - floor_day
        room_tot = bal - floor_tot
        base = bal * risk_pct / 100.0 * STREAM_RISK.get(int(getattr(t, "stream", 2)), 1.0)
        if mode == "growth":
            boost = 1.0 + min(1.0, max(0.0, (bal - start) / start))   # house money: up to 2x once the account doubles
            dd_now = (hwm - bal) / hwm * 100.0
            gov = float(np.clip(1.0 - dd_now / max_dd, 0.25, 1.0))     # risk shrinks linearly with drawdown
            base *= boost * gov
        # never-breach sizing: a full stop (+25% slippage) may use at most 1/2 of today's room and 1/4 of the
        # total room -> it takes many consecutive full losses to approach a floor, and the risk keeps shrinking
        # on the way down (recovery mode) instead of locking the account at the floor.
        risk = min(base, room_day / 1.25 * 0.5, room_tot / 1.25 * 0.25)
        oz = risk / max(t.R, 1e-9)
        min_oz = 1.0  # 0.01 lot = 1 oz
        if oz < min_oz:
            if min_oz * t.R * 1.25 <= min(room_day, room_tot) * 0.5:
                oz = min_oz
            else:
                continue  # cannot trade without breach risk -> wait for tomorrow's room
        oz = min(np.floor(oz), lot_cap_oz)
        pnl = oz * t.R * t.r
        bal += pnl
        hwm = max(hwm, bal)
        rows.append(dict(entry_t=t.entry_t, exit_t=t.exit_t, year=t.year, pnl=pnl, bal=bal, r=t.r, oz=oz,
                         risk_pct=oz * t.R / (bal - pnl) * 100, tp1=t.tp1, stream=getattr(t, "stream", -1)))
        if (day_ref - bal) >= 0.8 * (day_ref - floor_day):
            halted_day = day  # internal daily breaker at 80% of the daily budget
    out = pd.DataFrame(rows)
    if len(out):
        out.attrs["min_bal"] = float(out.bal.min())
        peak = np.maximum.accumulate(np.r_[start, out.bal.values])
        out.attrs["max_dd_pct"] = float(((peak - np.r_[start, out.bal.values]) / peak).max() * 100)
    return out


def score(ann_ret_pct, wr, tpd, wait_h, maxdd_pct, green_share):
    """SevenWave 0-100 score, one block per acceptance criterion:
      profit 25 (saturating: 100%/yr -> 12.5), win-rate 20 (50%->0, 80%+ -> 20), frequency 15 (1+/day -> 15),
      wait 10 (avg wait <= 24h -> 10), drawdown 15 (0% -> 15, >=10% -> 0), green months 15."""
    s_p = 25 * max(ann_ret_pct, 0) / (max(ann_ret_pct, 0) + 100)
    s_w = 20 * float(np.clip((wr - 50) / 30, 0, 1))
    s_f = 15 * min(1.0, tpd / 1.0)
    s_t = 10 * min(1.0, 24.0 / max(wait_h, 1e-9))
    s_d = 15 * float(np.clip(1 - maxdd_pct / 10.0, 0, 1))
    s_g = 15 * green_share
    return round(s_p + s_w + s_f + s_t + s_d + s_g, 1)


def report(eq, tr, start, label):
    rows = []
    eq = eq.copy()
    eq["dt"] = pd.to_datetime(eq.entry_t, unit="s")
    bal0 = start
    for y, g in eq.groupby("year"):
        b_start = bal0
        b_end = g.bal.iloc[-1]
        peak = np.maximum.accumulate(np.r_[b_start, g.bal.values])
        dd = ((peak - np.r_[b_start, g.bal.values]) / peak).max() * 100
        t = np.sort(g.entry_t.values)
        span = max(1.0, (pd.Timestamp(f"{y}-12-31").value // 10 ** 9 - pd.Timestamp(f"{y}-01-01").value // 10 ** 9) / 86400)
        span = min(span, (t[-1] - pd.Timestamp(f"{y}-01-01").value // 10 ** 9) / 86400 + 1)
        tdays = span * 5 / 7
        waits = np.diff(t) / 3600
        mon = g.groupby(g.dt.dt.to_period("M")).pnl.sum()
        wr_pos = (g.r > 0).mean() * 100
        # MT5 deal-level win rate: positions that hit TP1 produce a profitable partial deal + the remainder deal
        deals_win = (g.tp1 == 1).sum() + (g.r > 0).sum()
        deals_all = (g.tp1 == 1).sum() + len(g)
        wr_deal = deals_win / deals_all * 100
        ann = (b_end / b_start - 1) * 100 * (365.0 / span)
        rows.append(dict(Year=y, NetProfit=round(b_end - b_start, 0), RetPct=round((b_end / b_start - 1) * 100, 1),
                         Trades=len(g), WinRate=round(wr_pos, 1), WinRateMT5=round(wr_deal, 1),
                         TradesPerDay=round(len(g) / tdays, 2), AvgWaitH=round(float(waits.mean()) if len(waits) else np.nan, 1),
                         MaxDD=round(dd, 2), Green=f"{int((mon > 0).sum())}/{len(mon)}",
                         Score=score(ann, wr_pos, len(g) / tdays, float(waits.mean()) if len(waits) else 1e9, dd,
                                     (mon > 0).mean())))
        bal0 = b_end
    out = pd.DataFrame(rows)
    print(f"\n=== {label} (start ${start:,.0f}) ===")
    print(out.to_string(index=False))
    return out


def build_all(src):
    m1a, tfs = L3.prep(src)
    L3.MG.update(MG)
    L3.SL_K, L3.TRAIL_K = SL_K, TRAIL_K
    df, Xfull = L3.events(m1a, tfs)
    return m1a, tfs, df, feature_matrix(Xfull)


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "duka"
    t0 = time.time()
    if what in ("duka", "pep"):
        m1a, tfs, df, X = build_all(what)
        print(f"{what}: {len(df)} setups ({time.time() - t0:.0f}s); by stream {df.stream.value_counts().sort_index().to_dict()}")
        if what == "duka":
            p, thr = walk_scores(df, X, list(range(2019, 2027)))
            keep = np.isfinite(p) & (p >= thr)
            period = df.year.values >= 2019
        else:
            # AI trained on Duka 2017-2022 only (never saw any Pepperstone bar)
            _, _, dfd, Xd = build_all("duka")
            sel = dfd.year.values <= 2022
            m, t = train(Xd[sel], (dfd.r.values[sel] > 0).astype(int))
            p = m.predict(X, num_iteration=m.best_iteration)
            thr = np.full(len(p), t)
            keep = p >= thr
            period = np.ones(len(df), bool)
        for lab, msk in (("RULES ONLY", period), ("RULES + AI VETO", period & keep)):
            d = df[msk]
            tr = S2.run_fills(m1a, d.j.values, d.dir.values, d.px.values, d.R.values, d.trail.values, MG,
                              meta={"stream": d.stream.values})
            st = E.year_stats(tr)
            print(f"\n##### {lab}: trade-level R stats")
            print(st.to_string(index=False))
            for mode, start in (("prop", 100_000.0), ("growth", 10_000.0)):
                eq = equity_sim(tr, mode, start)
                rep = report(eq, tr, start, f"{STYLE.upper()} style | {lab} | {mode.upper()} mode")
                print(f"   -> final ${eq.bal.iloc[-1]:,.0f}, overall max DD {eq.attrs.get('max_dd_pct', 0):.2f}%, "
                      f"mean score {rep.Score.mean():.1f}")
        df.assign(p=p).to_pickle(os.path.join(OUT, "data", f"final_{what}.pkl"))
    print(f"{time.time() - t0:.0f}s")

