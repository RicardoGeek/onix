"""Study 32: standard tables (Year | Net Profit | Trades | Win Rate | Trades/Day | Avg Wait | Max DD | Score) for
  (1) AI-filtered retest scalp (top 19% of the walk-forward meta-labeler, trained 2017-2022), traded 2023-2026,
      $100k, 0.5% risk per trade, one position at a time;
  (2) v1.10 Prop entries with RIDE exit vs SCALP-STYLE exit (20% at +0.3R, BE, trail, 2R cap), continuous $100k account
      2017-2026 under the v1.10 Prop rules (2 slots, 15% room budget, 2.4% day lock, 3% / 6% trailing).
All Python replays on Dukascopy with hostile costs (MT5 confirmation pending for the chosen variant)."""
import sys
import numpy as np
import pandas as pd
from sw_mt5report import score

src31 = open("sw_study31.py", encoding="utf-8-sig").read()
head = src31.split("for lab_name, mg in")[0]
ns = {"__name__": "s31"}
exec(head, ns)
V, S2, X, yr, j, dd, px, R, a, idx = (ns[k] for k in ("V", "S2", "X", "yr", "j", "dd", "px", "R", "a", "idx"))
import lightgbm as lgb


def std_table(T, start):
    """T: entry, exit (datetime), net ($), balance after.  One row per year + ALL."""
    rows = []
    b0 = start
    allT = T.copy()
    for y, g in list(T.groupby(T.entry.dt.year)) + [("ALL", allT)]:
        if y == "ALL":
            b_start = start
            y0, y1 = T.entry.min().normalize(), T.exit.max().normalize() + pd.Timedelta(days=1)
        else:
            b_start = b0
            y0 = pd.Timestamp(f"{y}-01-01"); y1 = min(pd.Timestamp(f"{y + 1}-01-01"), T.exit.max() + pd.Timedelta(days=1))
        net = g.net.sum()
        gx = T[(T.exit >= y0) & (T.exit < y1)]
        bal = gx.balance.values
        peak = np.maximum.accumulate(np.r_[b_start, bal])
        mdd = float(((peak - np.r_[b_start, bal]) / peak).max() * 100) if len(bal) else 0.0
        wd = max(1, np.busday_count(y0.date(), y1.date()))
        ent = np.sort(g.entry.values.astype("datetime64[s]").astype(np.int64))
        wait = float(np.diff(ent).mean() / 3600) if len(ent) > 1 else np.nan
        mo = gx.groupby(gx.exit.dt.to_period("M")).net.sum()
        wr = (g.net > 0).mean() * 100
        years = max((y1 - y0).days / 365.0, 0.25)
        ann = ((b_start + net) / b_start) ** (1 / years) * 100 - 100 if y == "ALL" else net / b_start * 100 * 365 / max((y1 - y0).days, 1)
        rows.append(dict(Year=y, NetProfit=f"{net:+,.0f} ({net / b_start * 100:+.1f}%)", Trades=len(g), WinRate=f"{wr:.1f}%",
                         TradesPerDay=round(len(g) / wd, 2), AvgWait=f"{wait:.0f} h", MaxDD=f"{mdd:.2f}%",
                         Score=score(ann, wr, len(g) / wd, wait if np.isfinite(wait) else 1e9, mdd, float((mo > 0).mean()) if len(mo) else 0)))
        if y != "ALL":
            b0 += net
    return pd.DataFrame(rows)


pd.set_option("display.width", 220)
# ---------------------------------------------------------------- (1) AI retest scalp
mg = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=1.0, max_min=240)
ind = S2.run_fills(V.m1a, j, dd.astype(np.int64), px, R, 0 * a, mg, one_at_a_time=False)
r = np.full(len(idx), np.nan); r[ind.eidx.values] = ind.r.values
y = (r > 0).astype(int)
tr = (yr <= 2022) & np.isfinite(r); te = (yr >= 2023) & np.isfinite(r)
ti = np.flatnonzero(tr); cut = int(len(ti) * 0.8)
params = dict(objective="binary", learning_rate=0.03, num_leaves=15, min_data_in_leaf=80, feature_fraction=0.7,
              bagging_fraction=0.8, bagging_freq=1, lambda_l2=10.0, verbose=-1, num_threads=2, seed=3)
mdl = lgb.train(params, lgb.Dataset(X[ti[:cut]], y[ti[:cut]]), 800, valid_sets=[lgb.Dataset(X[ti[cut:]], y[ti[cut:]])],
                callbacks=[lgb.early_stopping(80, verbose=False)])
p = mdl.predict(X)
thr = np.quantile(p[ti[cut:]], 0.81)
sel = te & (p >= thr)
seq = S2.run_fills(V.m1a, j[sel], dd[sel].astype(np.int64), px[sel], R[sel], 0 * a[sel], mg, one_at_a_time=True)
eq = 100_000.0; rows = []
for t in seq.sort_values("exit_t").itertuples():
    pnl = eq * 0.005 * t.r; eq += pnl
    rows.append((pd.Timestamp(t.entry_t, unit="s"), pd.Timestamp(t.exit_t, unit="s"), pnl, eq))
T1 = pd.DataFrame(rows, columns=["entry", "exit", "net", "balance"])
print("\n### (1) AI-filtered RETEST SCALP (top 19%), $100k, 0.5% risk, 2023-2026 (unseen by the AI)")
print(std_table(T1, 100_000.0).to_string(index=False))

# ---------------------------------------------------------------- (2) Prop: ride vs scalp-style exit
W = np.array([1, 1, 0, 0, 0, .6, .8, 0], float)
ev = V.all_events(use=["A", "B", "G", "P"])


def acct(trd, frac=0.15, K=2, risk_in=0.5, start=1e5, daily=3.0, maxdd=6.0, cap=2.4):
    eq = start; hwm = start; op = []; dp = {}; dref = start; cur = None; out = []
    for t in trd.itertuples():
        keep = []
        for q in sorted(op, key=lambda z: z[0]):
            if q[0] <= t.entry_t:
                k = q[0] // 86400; pnl = q[1]
                if cap > 0 and pnl > 0: pnl = min(pnl, max(0.0, eq * cap / 100 - dp.get(k, 0.0)))
                eq += pnl; hwm = max(hwm, eq); dp[k] = dp.get(k, 0.0) + pnl
                out.append((pd.Timestamp(q[3], unit="s"), pd.Timestamp(q[0], unit="s"), pnl, eq))
            else: keep.append(q)
        op = keep
        k = t.entry_t // 86400
        if k != cur: cur = k; dref = eq
        if dref - eq >= dref * daily / 100 * 0.8 or len(op) >= K: continue
        if cap > 0 and dp.get(k, 0.0) >= eq * cap / 100 * 0.999: continue
        room = min(eq - dref * (1 - daily / 100), eq - hwm * (1 - maxdd / 100))
        risk = min(eq * risk_in / 100.0 * W[int(t.stream)], room * frac / 1.25 - sum(z[2] for z in op))
        if risk <= eq * 2e-4: continue
        op.append([t.exit_t, risk * t.r, risk, t.entry_t])
    return pd.DataFrame(out, columns=["entry", "exit", "net", "balance"]).sort_values("exit").reset_index(drop=True)


for mode, title in (("growth", "RIDE exit (v1.10 today)"), ("prop", "SCALP-STYLE exit (20% at +0.3R, BE, 2R cap)")):
    trd = V.outcomes(ev, mode).sort_values("entry_t").reset_index(drop=True)
    T2 = acct(trd)
    print(f"\n### (2) PROP $100k, v1.10 entries, {title}, continuous 2017-2026")
    print(std_table(T2, 100_000.0).to_string(index=False))
