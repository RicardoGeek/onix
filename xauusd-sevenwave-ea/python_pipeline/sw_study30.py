"""Study 30: the user's retest-scalp and early-entry ideas, v1.10 ribbon 10/16/26/41/66/105/168, hostile costs.

RETEST (R): M15 ribbon fully stacked in the trend direction + gate TFs stacked the same way.  Bar i 'tests the band':
  its extreme reaches EMA[band] (band 0 = EMA10, 1 = EMA16, 2 = EMA26) against the trend, and it CLOSES back on the trend
  side of EMA10 (rejection).  Entry: market at the next M1 open.  SL: beyond the retest bar's extreme + 0.1 ATR(M15)
  (min 0.5 ATR(M15)).  Exit: scalp target m x R, or ride (trail), time stop.
EARLY (X): EMA10 crosses EMA41 (halfway through the ribbon) with price beyond EMA10, gate TFs stacked or not yet.
Each family: independent outcomes per year AND a time-ordered one-position replay (the trades an account really gets).
Selection = 2017-2022, unseen = 2023-2026.
"""
import sys
import time
import itertools
import numpy as np
import pandas as pd
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", sys.argv[1] if len(sys.argv) > 1 else "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_engine as E
import sw_mtf as M
import sw_sim2 as S2

m1a, tfs = V.m1a, V.tfs
T = tfs["M15"]
Em = np.vstack([E.ema_nb(T["c"], float(p)) for p in V.RIBBON])
a15 = T["atr"]
sc = np.sign(-np.diff(Em, axis=0)).sum(axis=0)
stk15 = np.where(sc >= 6, 1, np.where(sc <= -6, -1, 0))
st_all, _ = V.stacks()


def gate(names):
    if not names:
        return np.ones(T["n"], np.int64) * 2           # 2 = no gate
    o = None
    for h in names:
        k = np.maximum(M.map_last_closed(tfs[h], T["t_close"]), 0)
        sd = st_all[h][k]
        o = sd if o is None else np.where(o == sd, sd, 0)
    return o.astype(np.int64)


def retest_events(band, g, need_stack=True, bearish_candle=False):
    n = T["n"]
    d = np.zeros(n, np.int64)
    up = (stk15 == 1) if need_stack else (Em[0] > Em[3])
    dn = (stk15 == -1) if need_stack else (Em[0] < Em[3])
    # long: low dips to EMA[band] and closes back above EMA10 ; short mirror
    L = up & (T["l"] <= Em[band]) & (T["c"] > Em[0]) & ((g == 1) | (g == 2))
    S = dn & (T["h"] >= Em[band]) & (T["c"] < Em[0]) & ((g == -1) | (g == 2))
    if bearish_candle:
        L &= T["c"] > T["o"]
        S &= T["c"] < T["o"]
    d[L] = 1
    d[S] = -1
    return d


def early_events(g):
    n = T["n"]
    d = np.zeros(n, np.int64)
    cu = (Em[0] > Em[3]) & np.r_[False, Em[0][:-1] <= Em[3][:-1]] & (T["c"] > Em[0]) & ((g == 1) | (g == 2))
    cd = (Em[0] < Em[3]) & np.r_[False, Em[0][:-1] >= Em[3][:-1]] & (T["c"] < Em[0]) & ((g == -1) | (g == 2))
    d[cu] = 1
    d[cd] = -1
    return d


def to_fills(d, sl_mode="bar"):
    idx = np.flatnonzero(d != 0)
    idx = idx[(idx > 3000 if V.m1a["t"][0] < 1.6e9 else idx > 1500) & (idx < T["n"] - 1)]
    j = T["m1e"][idx]
    ok = (m1a["t"][np.minimum(j, len(m1a["t"]) - 1)] - m1a["t"][j - 1]) <= 1800
    idx, j = idx[ok], j[ok]
    dd = d[idx]
    px = np.where(dd > 0, m1a["o"][j] + m1a["spr"][j] + 0.05, m1a["o"][j] - 0.05)
    a = a15[idx]
    if sl_mode == "bar":
        ext = np.where(dd > 0, T["l"][idx] - 0.1 * a, T["h"][idx] + 0.1 * a)
        R = np.maximum(np.abs(px - ext), 0.5 * a)
    else:
        R = 1.5 * a
    return j, dd, px, R, a


def evaluate(label, d, mg, sl_mode="bar", trail_k=0.0):
    j, dd, px, R, a = to_fills(d, sl_mode)
    if len(j) < 100:
        return None
    ind = S2.run_fills(m1a, j, dd, px, R, trail_k * a, mg, one_at_a_time=False)
    seq = S2.run_fills(m1a, j, dd, px, R, trail_k * a, mg, one_at_a_time=True)
    out = dict(label=label, n=len(ind), tpd=len(ind) / ((ind.entry_t.max() - ind.entry_t.min()) / 86400 * 5 / 7),
               wr=(ind.r > 0).mean() * 100, avgR=ind.r.mean())
    for nm, tr in (("ind", ind), ("seq", seq)):
        yr = tr.groupby("year").r.sum()
        cut = 2022 if V.m1a["t"][0] < 1.6e9 else 2024
        out[f"{nm}_is"] = yr[yr.index <= cut].sum()
        out[f"{nm}_oos"] = yr[yr.index > cut].sum()
        out[f"{nm}_pos"] = f"{int((yr[yr.index <= cut] > 0).sum())}/{int((yr.index <= cut).sum())}+{int((yr[yr.index > cut] > 0).sum())}/{int((yr.index > cut).sum())}"
        out[f"{nm}_avg"] = tr.r.mean()
        out[f"{nm}_n"] = len(tr)
    out["seq_wr"] = (seq.r > 0).mean() * 100
    return out


SCALP = {f"TP{m}R": dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.0, act_r=99.0, tp2_r=m, max_min=240) for m in (0.5, 1.0, 1.5)}
RIDE = dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=3.0, max_min=1440)
rows = []
t0 = time.time()
for gname, gl in (("M15+H1", ("H1",)), ("M15+H1+H4", ("H1", "H4")), ("M15+H1+H4+D1", ("H1", "H4", "D1"))):
    g = gate(gl)
    for band, candle in itertools.product((0, 1, 2), (False, True)):
        d = retest_events(band, g, True, candle)
        for mname, mg in SCALP.items():
            r = evaluate(f"RETEST {gname} band=EMA{V.RIBBON[band]} {'bear/bull candle ' if candle else ''}{mname}", d, mg)
            if r: rows.append(r)
        r = evaluate(f"RETEST {gname} band=EMA{V.RIBBON[band]} {'candle ' if candle else ''}RIDE", d, RIDE, trail_k=1.0)
        if r: rows.append(r)
    for mname, mg in list(SCALP.items()) + [("RIDE", RIDE)]:
        r = evaluate(f"EARLY {gname} EMA10x41 {mname}", early_events(g), mg, trail_k=1.0 if mname == "RIDE" else 0.0)
        if r: rows.append(r)
    print(f"{time.time() - t0:5.0f}s gate {gname}")
for mname, mg in list(SCALP.items()) + [("RIDE", RIDE)]:
    r = evaluate(f"EARLY no-gate EMA10x41 {mname}", early_events(gate(())), mg, trail_k=1.0 if mname == "RIDE" else 0.0)
    if r: rows.append(r)
R = pd.DataFrame(rows)
R.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\retest_scalp.csv", index=False)
pd.set_option("display.width", 280)
pd.set_option("display.max_columns", 30)
pd.set_option("display.max_colwidth", 60)
cols = ["label", "n", "tpd", "wr", "avgR", "ind_is", "ind_oos", "ind_pos", "seq_n", "seq_wr", "seq_avg", "seq_is", "seq_oos", "seq_pos"]
print("\n=== ranked by SEQUENTIAL (real account) in-sample R, 2017-2022 ===")
print(R.sort_values("seq_is", ascending=False)[cols].head(25).round(3).to_string(index=False))


