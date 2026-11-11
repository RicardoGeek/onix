"""Study 35: HIGH-WIN-RATE mean-reversion engines on gold (our data: gold mean-reverts at 1h/1d/5d on top of its drift).

Families (signal at the CLOSE of bar i of the timeframe, entry at the next M1 open, realistic M1 fills, hostile costs):
  RSI2   Connors: RSI(2) < X in an uptrend (mirror for shorts); exit at the first close above SMA(5)
  IBS    internal bar strength (c-l)/(h-l) < X in an uptrend; exit at the first close above the previous bar's high
  D7     'double 7s': close = 7-bar low in an uptrend; exit at the first 7-bar-high close
  BB     close below the 20/2 Bollinger band in an uptrend; exit at the first close above SMA(20)
Trend gate: SMA200 of the same timeframe, or the D1 / H4+D1 geometric 7-EMA stacks (the v1.10 hierarchy).
Every trade also has a catastrophic stop (k x ATR of the timeframe) and a max-bars time exit.
Selection on 2017-2022 (Dukascopy), unseen 2023-2026.  Independent outcomes AND a one-position time-ordered replay.
"""
import sys
import itertools
import numpy as np
import pandas as pd
from numba import njit
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", sys.argv[1] if len(sys.argv) > 1 else "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_mtf as M
import sw_sim2 as S2

m1a, tfs = V.m1a, V.tfs
COMM, SLIP_STOP, SLIP_MKT, SWAP_L = S2.COMM, S2.SLIP_STOP, S2.SLIP_MKT, S2.SWAP_LONG * 1.4   # 1.4x: triple Wednesday averaged


@njit(cache=True)
def rsi_wilder(c, n):
    out = np.full(len(c), np.nan)
    up = 0.0; dn = 0.0
    for i in range(1, len(c)):
        ch = c[i] - c[i - 1]
        u = ch if ch > 0 else 0.0
        d = -ch if ch < 0 else 0.0
        if i <= n:
            up += u / n; dn += d / n
            if i == n:
                out[i] = 100.0 if dn == 0 else 100.0 - 100.0 / (1.0 + up / dn)
        else:
            up = (up * (n - 1) + u) / n; dn = (dn * (n - 1) + d) / n
            out[i] = 100.0 if dn == 0 else 100.0 - 100.0 / (1.0 + up / dn)
    return out


@njit(cache=True)
def sim_mr(ev_bar, ev_dir, ev_stop, m1e, exitL, exitS, max_bars, mo, mh, ml, mspr, mtday, one_at_a_time):
    """M1-level fills.  Entry at mo[m1e[i]] (+spread for longs, +slippage).  Each M1 bar: stop first (gap-aware).
    At the last M1 bar of each signal-timeframe bar k: if exit flag (or max bars) -> exit at the next M1 open."""
    ne = len(ev_bar); nm = len(mo)
    pnl = np.full(ne, np.nan); xi = np.full(ne, -1, np.int64); why = np.zeros(ne, np.int64); taken = np.zeros(ne, np.int64)
    busy_until = -1
    for e in range(ne):
        i = ev_bar[e]; d = ev_dir[e]; S = ev_stop[e]
        j0 = m1e[i]
        if j0 + 1 >= nm or i + 1 >= len(m1e):
            continue
        if one_at_a_time and j0 <= busy_until:
            continue
        ep = mo[j0] + mspr[j0] + SLIP_MKT if d > 0 else mo[j0] - SLIP_MKT
        stop = ep - d * S
        b = i + 1                       # signal-timeframe bar that contains j0
        q = j0
        xp = np.nan
        w = 0
        while q < nm:
            # stop (bid for longs, ask for shorts)
            if d > 0 and ml[q] <= stop:
                xp = min(mo[q], stop) - SLIP_STOP; w = 1; break
            if d < 0 and mh[q] + mspr[q] >= stop:
                xp = max(mo[q] + mspr[q], stop) + SLIP_STOP; w = 1; break
            if b < len(m1e) and q == m1e[b] - 1:          # last M1 of bar b -> bar b closed
                flag = exitL[b] if d > 0 else exitS[b]
                if flag or (b - i) >= max_bars:
                    if q + 1 < nm:
                        xp = (mo[q + 1] - SLIP_MKT) if d > 0 else (mo[q + 1] + mspr[q + 1] + SLIP_MKT)
                        q = q + 1
                    w = 2 if flag else 3
                    break
                b += 1
            q += 1
        if w == 0:
            continue
        rolls = mtday[min(q, nm - 1)] - mtday[j0]
        swap = SWAP_L * rolls if d > 0 else 0.0
        pnl[e] = d * (xp - ep) - COMM + swap
        xi[e] = q; why[e] = w; taken[e] = 1
        busy_until = q
    return pnl, xi, why, taken


def sma(x, n):
    return pd.Series(x).rolling(n, min_periods=n).mean().values


def stack_on(T, tfname):
    st, _ = V.stacks()
    k = np.maximum(M.map_last_closed(tfs[tfname], T["t_close"]), 0)
    return st[tfname][k]


def build(tfname):
    T = tfs[tfname]
    c, h, l = T["c"], T["h"], T["l"]
    n = T["n"]
    s5, s20, s200 = sma(c, 5), sma(c, 20), sma(c, 200)
    sd20 = pd.Series(c).rolling(20, min_periods=20).std().values
    r2 = rsi_wilder(c.astype(np.float64), 2)
    ibs = (c - l) / np.maximum(h - l, 1e-9)
    lo7 = pd.Series(c).rolling(7).min().values; hi7 = pd.Series(c).rolling(7).max().values
    prevh = np.r_[np.nan, h[:-1]]; prevl = np.r_[np.nan, l[:-1]]
    gates = {"SMA200": np.where(c > s200, 1, np.where(c < s200, -1, 0))}
    gates["D1 stack"] = stack_on(T, "D1") if tfname != "D1" else V.stacks()[0]["D1"]
    h4 = stack_on(T, "H4") if tfname != "H4" else V.stacks()[0]["H4"]
    gates["H4+D1 stacks"] = np.where(h4 == gates["D1 stack"], h4, 0)
    fam = {}
    for X in (5, 10, 15, 25):
        fam[f"RSI2<{X}"] = (r2 < X, r2 > 100 - X, c > s5, c < s5)
    for X in (0.1, 0.2, 0.3):
        fam[f"IBS<{X}"] = (ibs < X, ibs > 1 - X, c > prevh, c < prevl)
    fam["D7"] = (c <= lo7, c >= hi7, c >= hi7, c <= lo7)
    fam["BB20/2"] = (c < s20 - 2 * sd20, c > s20 + 2 * sd20, c > s20, c < s20)
    return T, gates, fam


rows = []
keep = {}
for tfname in ("H1", "H4", "D1"):
    T, gates, fam = build(tfname)
    a = np.maximum(T["atr"], 1e-9)
    yrs = pd.to_datetime(T["t"], unit="s").year.values
    for (fname, (Lsig, Ssig, Lx, Sx)), (gname, g), stopk, mb, sides in itertools.product(
            fam.items(), gates.items(), (2.0, 3.0, 4.0), (5, 10), ("long", "both")):
        sigL = Lsig & (g == 1)
        sigS = Ssig & (g == -1) if sides == "both" else np.zeros(T["n"], bool)
        idx = np.flatnonzero(sigL | sigS)
        idx = idx[(idx > 300) & (idx < T["n"] - 2)]
        if len(idx) < 60:
            continue
        d = np.where(sigL[idx], 1, -1).astype(np.int64)
        S = stopk * a[idx]
        p, xi, why, tk = sim_mr(idx.astype(np.int64), d, S, T["m1e"].astype(np.int64), Lx.astype(np.bool_), Sx.astype(np.bool_),
                                mb, m1a["o"], m1a["h"], m1a["l"], m1a["spr"], m1a["tday"].astype(np.int64), False)
        ok = tk == 1
        r = p[ok] / S[ok]; y = yrs[idx][ok]
        if len(r) < 60:
            continue
        ins, oos = r[y <= 2022].mean(), r[y >= 2023].mean()
        py = pd.Series(r).groupby(y).mean()
        days = (T["t"][idx[-1]] - T["t"][idx[0]]) / 86400 * 5 / 7
        key = (tfname, fname, gname, stopk, mb, sides)
        rows.append(dict(tf=tfname, fam=fname, gate=gname, stop=stopk, maxb=mb, sides=sides, n=int(ok.sum()),
                         per_day=round(ok.sum() / days, 2), wr=round((r > 0).mean() * 100, 1), avgR_17_22=round(ins, 3),
                         avgR_23_26=round(oos, 3), yrs_pos=f"{int((py > 0).sum())}/{len(py)}"))
        keep[key] = (idx, d, S, Lx, Sx, mb)
    print("done", tfname, flush=True)

R = pd.DataFrame(rows)
R.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\study35_meanrev.csv", index=False)
pd.set_option("display.width", 250); pd.set_option("display.max_rows", 200)
print("\n=== top 30 by 2017-2022 avg R (independent outcomes) ===")
top = R.sort_values("avgR_17_22", ascending=False).head(30)
print(top.to_string(index=False))
print("\n=== top 20 by win rate with avgR_17_22 > 0.05 ===")
print(R[R.avgR_17_22 > 0.05].sort_values("wr", ascending=False).head(20).to_string(index=False))

# one-position replay for the top 12 (by in-sample avg R)
print("\n=== one-at-a-time replay, top 12 ===")
for row in top.head(12).itertuples():
    T = tfs[row.tf]
    idx, d, S, Lx, Sx, mb = keep[(row.tf, row.fam, row.gate, row.stop, row.maxb, row.sides)]
    p, xi, why, tk = sim_mr(idx.astype(np.int64), d, S, T["m1e"].astype(np.int64), Lx.astype(np.bool_), Sx.astype(np.bool_),
                            mb, m1a["o"], m1a["h"], m1a["l"], m1a["spr"], m1a["tday"].astype(np.int64), True)
    ok = tk == 1
    r = p[ok] / S[ok]; y = pd.to_datetime(T["t"][idx[ok]], unit="s").year.values
    py = pd.Series(r).groupby(y).sum()
    print(f"{row.tf} {row.fam} {row.gate} SL{row.stop} max{row.maxb} {row.sides}: n={ok.sum()} WR={(r > 0).mean() * 100:.1f}% "
          f"avgR={r.mean():+.3f} 17-22 {r[y <= 2022].mean():+.3f} 23-26 {r[y >= 2023].mean():+.3f} | per-year sumR "
          + " ".join(f"{k}:{v:+.1f}" for k, v in py.items()))
