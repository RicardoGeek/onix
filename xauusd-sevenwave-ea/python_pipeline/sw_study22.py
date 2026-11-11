"""Study 22: cadence-first design.  Ribbon gate x concurrency x daily profit lock, scored on CONSISTENCY.

Every Liquidity-Wave event is simulated independently (its own outcome), then a portfolio engine replays them in time
order: up to K concurrent positions (one per stream-pool trigger), risk per position = base% x stream weight of
equity, total open risk capped, optional daily profit lock (no new entries once today's realised P/L >= lock%).
Metrics (realised P/L by UTC day): CAGR, max DD, green weeks %, green months %, best-day share of profit per month
(prop 'consistency rule': best day / total), trades per weekday.  Selection uses 2017-2022, 2023-2026 is reported.
"""
import sys
import time
import itertools
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E
import sw_mtf as M
import sw_sim2 as S2
from sw_study17 import pools_nb, pool_stop_events_nb

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
t0 = time.time()
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
tfs = M.build_hierarchy(m1a)
tfs["M30"] = M.tf_states(E.make_bars(m1a, 30))
tfs["H2"] = M.tf_states(E.make_bars(m1a, 120))
POOLS = {S: pools_nb(tfs[S]["h"], tfs[S]["l"], 3, 3) for S in ("M30", "H1", "H2")}
STREAMS = [("H1", ("H4", "D1"), 0.15, 12, 48), ("H2", ("H4", "D1"), 0.0, 6, 48), ("H1", ("H4",), 0.15, 12, 120),
           ("H1", ("H1",), 0.15, 12, 48), ("M30", ("H1", "H4"), 0.15, 12, 96), ("H1", ("H4", "D1"), 0.15, 3, 12)]
WEIGHT = np.array([1.0, 1.0, 0.5, 0.5, 0.35, 0.35])
MGMT = {"prop": (dict(tp1_r=0.3, tp1_frac=0.2, be_r=0.05, act_r=1.5, tp2_r=2.0, max_min=2880), 2.0, 1.0),
        "growth": (dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=3.0, max_min=1440), 1.5, 2.0)}


def stacks(periods, need=6):
    out = {}
    for tf in ("H1", "H4", "D1"):
        Em = np.vstack([E.ema_nb(tfs[tf]["c"], float(p)) for p in periods])
        sc = np.sign(-np.diff(Em, axis=0)).sum(axis=0)       # +6 = perfectly stacked up
        thr = 6 if need == 6 else 4                            # 5 of 6 ordered pairs -> score >= 4
        out[tf] = np.where(sc >= thr, 1, np.where(sc <= -thr, -1, 0)).astype(np.int64)
    return out


def events(periods, need=6):
    stk = stacks(periods, need)
    a1 = tfs["H1"]["atr"]
    ej, ed, ep, ea, es = [], [], [], [], []
    for si, (S, filt, off, amin, amax) in enumerate(STREAMS):
        T = tfs[S]
        tr = None
        for h in filt:
            k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
            sd = stk[h][k]
            tr = sd if tr is None else np.where(tr == sd, sd, 0)
        ph, phi, pl, pli = POOLS[S]
        em, d, px, _ = pool_stop_events_nb(ph, phi, pl, pli, T["atr"], tr.astype(np.int64), T["m1s"], T["m1e"],
                                          m1a["o"], m1a["h"], m1a["l"], m1a["spr"], off, amin, amax, 0.05, 3.0)
        k = np.maximum(M.map_last_closed(tfs["H1"], m1a["t"][em]), 0)
        ej.append(em); ed.append(d); ep.append(px); ea.append(a1[k]); es.append(np.full(len(em), si))
    ej = np.concatenate(ej); ed = np.concatenate(ed); ep = np.concatenate(ep); ea = np.concatenate(ea); es = np.concatenate(es)
    o = np.lexsort((es, ej))
    ej, ed, ep, ea, es = ej[o], ed[o], ep[o], ea[o], es[o]
    keep = np.r_[True, np.diff(ej) > 0]
    return ej[keep], ed[keep], ep[keep], ea[keep], es[keep]


def outcomes(ev, mode):
    mg, slk, trk = MGMT[mode]
    ej, ed, ep, ea, es = ev
    tr = S2.run_fills(m1a, ej, ed, ep, slk * ea, trk * ea, mg, one_at_a_time=False, meta={"stream": es})
    return tr.sort_values("entry_t").reset_index(drop=True)


def portfolio(tr, K, base_pct, lock_pct, start=100_000.0, risk_cap_mult=3.0):
    """Replay independent outcomes with at most K open positions; realised P/L booked on the exit day."""
    eq = start
    open_pos = []          # (exit_t, pnl_pct_of_entry_equity * risk_amt) -> store (exit_t, pnl_dollars, risk_dollars)
    day_pnl = {}
    taken = []
    for t in tr.itertuples():
        # realise positions closed before this entry
        still = []
        for (xt, pnl, rk, stream) in open_pos:
            if xt <= t.entry_t:
                eq += pnl
                dkey = xt // 86400
                day_pnl[dkey] = day_pnl.get(dkey, 0.0) + pnl
            else:
                still.append((xt, pnl, rk, stream))
        open_pos = still
        if len(open_pos) >= K:
            continue
        dkey = t.entry_t // 86400
        if lock_pct > 0 and day_pnl.get(dkey, 0.0) >= eq * lock_pct / 100.0:
            continue
        risk = eq * base_pct / 100.0 * WEIGHT[int(t.stream)]
        open_risk = sum(p[2] for p in open_pos)
        if open_risk + risk > eq * base_pct / 100.0 * risk_cap_mult:
            continue
        pnl = risk * t.r
        open_pos.append((t.exit_t, pnl, risk, int(t.stream)))
        taken.append((t.entry_t, t.exit_t, pnl, t.r))
    for (xt, pnl, rk, stream) in open_pos:
        eq += pnl
        day_pnl[xt // 86400] = day_pnl.get(xt // 86400, 0.0) + pnl
    return pd.Series(day_pnl).sort_index(), pd.DataFrame(taken, columns=["entry_t", "exit_t", "pnl", "r"]), eq


def metrics(day, taken, start, y0, y1):
    d = day[(day.index >= pd.Timestamp(f"{y0}-01-01").value // 86400 // 10 ** 9) &
            (day.index < pd.Timestamp(f"{y1 + 1}-01-01").value // 86400 // 10 ** 9)]
    if len(d) == 0:
        return {}
    idx = pd.to_datetime(d.index * 86400, unit="s")
    s = pd.Series(d.values, index=idx)
    bal = start + s.cumsum()
    peak = np.maximum.accumulate(np.r_[start, bal.values])
    dd = float(((peak - np.r_[start, bal.values]) / peak).max() * 100)
    wk = s.resample("W").sum()
    wk = wk[wk != 0]
    mo = s.resample("ME").sum()
    best_share = []
    for m, g in s.groupby(s.index.to_period("M")):
        tot = g.sum()
        if tot > 0:
            best_share.append(g.max() / tot)
    tk = taken[(taken.entry_t >= pd.Timestamp(f"{y0}-01-01").value // 10 ** 9) &
               (taken.entry_t < pd.Timestamp(f"{y1 + 1}-01-01").value // 10 ** 9)]
    yrs = max((idx[-1] - idx[0]).days / 365.0, 0.5)
    cagr = (bal.iloc[-1] / start) ** (1 / yrs) * 100 - 100
    wd = max(1, np.busday_count(idx[0].date(), idx[-1].date()))
    return dict(cagr=cagr, dd=dd, green_w=(wk > 0).mean() * 100, green_m=(mo > 0).mean() * 100,
                best_day_share=float(np.median(best_share)) * 100 if best_share else np.nan,
                best_day_share_max=float(np.max(best_share)) * 100 if best_share else np.nan,
                tpd=len(tk) / wd, wr=(tk.r > 0).mean() * 100 if len(tk) else np.nan)


if __name__ == "__main__":
    RIBBONS = {"v1.00 20-200": (20, 40, 60, 80, 100, 150, 200)}
    for f in (5, 10, 20, 30):
        for r in (1.6, 1.8, 2.0):
            p = tuple(int(round(f * r ** k)) for k in range(7))
            if len(set(p)) == 7:
                RIBBONS[f"geom {f}x{r}"] = p
    rows = []
    for (rname, per), need in itertools.product(RIBBONS.items(), (6, 5)):
        ev = events(per, need)
        for mode in ("prop", "growth"):
            tr = outcomes(ev, mode)
            base = 0.75 if mode == "prop" else 3.0
            for K, lock in ((1, 0.0), (2, 0.0), (3, 0.0), (3, 1.0 if mode == "prop" else 4.0), (5, 1.0 if mode == "prop" else 4.0)):
                start = 100_000.0 if mode == "prop" else 10_000.0
                day, taken, eqf = portfolio(tr, K, base, lock, start)
                mi = metrics(day, taken, start, 2017, 2022)
                mo = metrics(day, taken, start, 2023, 2026)
                if not mi or not mo:
                    continue
                rows.append(dict(ribbon=rname + ("" if need == 6 else " 5/6"), mode=mode, K=K, lock=lock,
                                 **{f"is_{k}": round(v, 1) for k, v in mi.items()}, **{f"oos_{k}": round(v, 1) for k, v in mo.items()}))
        print(f"{time.time() - t0:5.0f}s {rname} need={need}: {len(ev[0])} events")
    R = pd.DataFrame(rows)
    # cadence objective (selection on 2017-2022 only): reward return, green weeks, low best-day share, low DD, frequency
    R["is_obj"] = (R.is_cagr.clip(lower=-50) / np.where(R["mode"] == "prop", 5.0, 25.0) + R.is_green_w / 10 - R.is_best_day_share / 20
                   - R.is_dd / np.where(R["mode"] == "prop", 2.0, 8.0) + R.is_tpd * 3)
    R.to_csv(rf"C:\Users\faker\Documents\goldie_research\sevenwave\data\cadence_{src}.csv", index=False)
    pd.set_option("display.width", 300)
    pd.set_option("display.max_columns", 40)
    for mode in ("prop", "growth"):
        print(f"\n=== {mode.upper()}: top 12 by in-sample cadence objective (2017-2022) -> check 2023-2026 ===")
        cols = ["ribbon", "K", "lock", "is_cagr", "is_dd", "is_green_w", "is_green_m", "is_best_day_share", "is_tpd", "is_wr",
                "oos_cagr", "oos_dd", "oos_green_w", "oos_green_m", "oos_best_day_share", "oos_best_day_share_max", "oos_tpd", "oos_wr"]
        print(R[R["mode"] == mode].sort_values("is_obj", ascending=False)[cols].head(12).to_string(index=False))
        print("v1.00 baseline (K=1, no lock):")
        print(R[(R["mode"] == mode) & (R.ribbon == "v1.00 20-200") & (R.K == 1) & (R.lock == 0)][cols].to_string(index=False))

