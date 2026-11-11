"""SevenWave research engine: M15 7-EMA ribbon bars + tick-pessimistic M1 trade simulator (numba).

Cost model is deliberately hostile (see COSTS):
  * entries at the NEXT M1 open after the M15 signal close, long at ask (= bid + spread), short at bid;
  * spread = max(real per-bar spread, floor) * 1.25 on Pepperstone bars, a flat $0.30 ($0.60 in the rollover
    hours) on bid-only Dukascopy bars;
  * commission $0.08/oz round trip, $0.05/oz slippage on market entries/exits, $0.10/oz on stop exits;
  * stop and target in the same M1 bar -> the stop wins; gaps through the stop fill at the gap price;
  * long swap -$0.80/oz per NY-17:00 rollover (x3 on Wednesday), short swap credited at $0.
"""
import numpy as np
import pandas as pd
from numba import njit

COSTS = dict(comm=0.08, slip_in=0.05, slip_stop=0.10, swap_long=-0.80, swap_short=0.0,
             duka_spread=0.30, duka_spread_roll=0.60, pep_floor=0.15, pep_mult=1.25)

DEFAULT_PERIODS = (20, 40, 60, 80, 100, 150, 200)


# ----------------------------------------------------------------------------------------------- bars / indicators
def m1_arrays(m1: pd.DataFrame, source: str):
    t = m1["t"].values.astype(np.int64)
    o = m1["open"].values.astype(np.float64)
    h = m1["high"].values.astype(np.float64)
    l = m1["low"].values.astype(np.float64)
    c = m1["close"].values.astype(np.float64)
    hr = (t // 3600) % 24
    if source == "duka":
        spr = np.where((hr >= 21) & (hr <= 22), COSTS["duka_spread_roll"], COSTS["duka_spread"]).astype(np.float64)
    else:
        s = m1["spread"].values.astype(np.float64)
        s = np.where(np.isfinite(s), s, 0.20)
        spr = np.maximum(s, COSTS["pep_floor"]) * COSTS["pep_mult"]
    ny = pd.to_datetime(t, unit="s").tz_localize("UTC").tz_convert("America/New_York")
    nyh = ny.hour.values * 60 + ny.minute.values
    nyday = ny.tz_localize(None).normalize().values.astype("datetime64[D]").astype(np.int64)
    tday = nyday + (nyh >= 17 * 60).astype(np.int64)  # gold trading day rolls at NY 17:00
    dow = ny.dayofweek.values.astype(np.int64)        # NY local weekday (Mon=0)
    return dict(t=t, o=o, h=h, l=l, c=c, spr=spr, tday=tday, nydow=dow)


def make_bars(m1a: dict, minutes: int):
    t = m1a["t"]
    key = t // (minutes * 60)
    chg = np.flatnonzero(np.diff(key)) + 1
    start = np.concatenate([[0], chg]).astype(np.int64)
    end = np.concatenate([chg, [len(t)]]).astype(np.int64)
    b = dict(t=key[start] * minutes * 60, o=m1a["o"][start], c=m1a["c"][end - 1],
             h=np.maximum.reduceat(m1a["h"], start), l=np.minimum.reduceat(m1a["l"], start),
             m1s=start, m1e=end, spr=np.add.reduceat(m1a["spr"], start) / (end - start), minutes=minutes)
    b["n"] = len(start)
    return b


@njit(cache=True)
def ema_nb(x, n):
    out = np.empty_like(x)
    a = 2.0 / (n + 1.0)
    out[0] = x[0]
    for i in range(1, len(x)):
        out[i] = x[i] * a + out[i - 1] * (1.0 - a)
    return out


@njit(cache=True)
def atr_nb(h, l, c, n):
    out = np.empty_like(c)
    s = 0.0
    for i in range(len(c)):
        tr = h[i] - l[i] if i == 0 else max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1]))
        if i < n:
            s += tr
            out[i] = s / (i + 1)
        else:
            out[i] = out[i - 1] + (tr - out[i - 1]) / n
    return out


def add_ribbon(b: dict, periods=DEFAULT_PERIODS, atr_n=14):
    E = np.vstack([ema_nb(b["c"], float(p)) for p in periods])  # (7, n) fast -> slow
    b["E"] = np.ascontiguousarray(E)
    b["periods"] = tuple(periods)
    b["atr"] = atr_nb(b["h"], b["l"], b["c"], atr_n)
    d = np.diff(E, axis=0)
    b["stack_bull"] = np.all(d < 0, axis=0)   # fast above slow, strictly ordered
    b["stack_bear"] = np.all(d > 0, axis=0)
    b["bull"] = b["stack_bull"] & (b["c"] > E[0])
    b["bear"] = b["stack_bear"] & (b["c"] < E[0])
    return b


# ----------------------------------------------------------------------------------------------- signals
@njit(cache=True)
def fresh_signals_nb(bull, bear, regap):
    """Fresh wave = first full alignment (close beyond EMA-fast, all 7 EMAs ordered) whose previous full alignment
    was the opposite direction (a ribbon flip) or ended >= regap bars ago.  Direction per bar (0 = none)."""
    n = len(bull)
    sig = np.zeros(n, np.int64)
    last_bull = -10 ** 9
    last_bear = -10 ** 9
    for i in range(1, n):
        if bull[i] and not bull[i - 1]:
            if last_bear > last_bull or (i - last_bull) >= regap:
                sig[i] = 1
        if bear[i] and not bear[i - 1]:
            if last_bull > last_bear or (i - last_bear) >= regap:
                sig[i] = -1
        if bull[i]:
            last_bull = i
        if bear[i]:
            last_bear = i
    return sig


# ----------------------------------------------------------------------------------------------- simulator
@njit(cache=True)
def simulate_nb(sig_bar, sig_dir, sl_dist,
                bh, bl, bc, batr, bE, bm1e,
                mt, mo, mh, ml, mc, mspr, mtday, mdow,
                tp1_r, tp1_frac, be_r, trail_mode, trail_k, trail_act_r, tp2_r, max_bars, exit_ema,
                comm, slip_in, slip_stop, swap_long, swap_short, max_gap_sec, one_at_a_time):
    """One position at a time.  Per taken signal: R multiple net of every cost.
    trail_mode: 0 none, 1 ribbon EMA[trail_k] - 0.25 ATR, 2 chandelier trail_k*ATR from the best price,
                3 previous M15 bar extreme - trail_k*ATR.  Trailing starts once MFE >= trail_act_r.
    exit_ema >= 0: market exit at next M1 open when an M15 close crosses ribbon EMA[exit_ema] against the trade.
    max_bars > 0: market exit after that many closed M15 bars."""
    ns = len(sig_bar)
    taken = np.zeros(ns, np.int64)
    out_r = np.zeros(ns); out_pnl = np.zeros(ns); out_risk = np.zeros(ns)
    out_et = np.zeros(ns, np.int64); out_xt = np.zeros(ns, np.int64)
    out_tp1 = np.zeros(ns, np.int64); out_mfe = np.zeros(ns); out_mae = np.zeros(ns)
    out_ep = np.zeros(ns); out_why = np.zeros(ns, np.int64); out_bars = np.zeros(ns, np.int64)
    nb = len(bc)
    nm = len(mc)
    busy_until = -1
    for s in range(ns):
        i = sig_bar[s]
        d = sig_dir[s]
        if i + 1 >= nb:
            continue
        j = bm1e[i]
        if j >= nm:
            continue
        if one_at_a_time and j <= busy_until:
            continue
        if mt[j] - mt[j - 1] > max_gap_sec:   # next price after a weekend / daily break: stale signal
            continue
        R = sl_dist[s]
        if not (R > 0):
            continue
        if d == 1:
            ep = mo[j] + mspr[j] + slip_in
        else:
            ep = mo[j] - slip_in
        sl = ep - d * R
        tp1 = ep + d * tp1_r * R
        use_tp2 = tp2_r > 0
        tp2 = ep + d * tp2_r * R
        pos = 1.0
        realized = 0.0
        done_tp1 = False
        ext = ep
        worst = ep
        bars_held = 0
        reason = 5
        swap = 0.0
        last_day = mtday[j]
        pending = False
        b_cur = i + 1
        k = j
        while k < nm:
            if mtday[k] != last_day:
                mult = 3.0 if mdow[k] == 2 else 1.0   # Wednesday NY 17:00 rollover charges 3 nights
                swap += pos * (swap_long if d == 1 else swap_short) * mult
                last_day = mtday[k]
            sp = mspr[k]
            if pending:
                px = (mo[k] - slip_in) if d == 1 else (mo[k] + sp + slip_in)
                realized += pos * d * (px - ep)
                pos = 0.0
                break
            if d == 1:
                o_ = mo[k]; h_ = mh[k]; l_ = ml[k]; c_ = mc[k]
            else:
                o_ = mo[k] + sp; h_ = mh[k] + sp; l_ = ml[k] + sp; c_ = mc[k] + sp
            # ---- stop first (pessimistic): gap through stop fills at open
            if d * (o_ - sl) <= 0:
                px = o_ - d * slip_stop
                realized += pos * d * (px - ep); pos = 0.0; reason = 1
                break
            adverse = l_ if d == 1 else h_
            favor = h_ if d == 1 else l_
            if d * (adverse - sl) <= 0:
                px = sl - d * slip_stop
                realized += pos * d * (px - ep); pos = 0.0; reason = 1
                break
            if d * (favor - ext) > 0:
                ext = favor
            if d * (adverse - worst) < 0:
                worst = adverse
            if (not done_tp1) and tp1_frac > 0 and d * (favor - tp1) >= 0:
                realized += tp1_frac * d * (tp1 - ep)
                pos -= tp1_frac
                done_tp1 = True
                nsl = ep + d * be_r * R
                if d * (nsl - sl) > 0:
                    sl = nsl
                if d * (c_ - sl) <= 0:
                    px = sl - d * slip_stop
                    realized += pos * d * (px - ep); pos = 0.0; reason = 1
                    break
            if use_tp2 and d * (favor - tp2) >= 0:
                realized += pos * d * (tp2 - ep); pos = 0.0; reason = 2
                break
            # ---- M15 close of bar b_cur?
            if b_cur < nb and k == bm1e[b_cur] - 1:
                b = b_cur
                bars_held += 1
                a_ = batr[b]
                mfe_now = d * (ext - ep) / R
                if mfe_now >= trail_act_r:
                    lvl = sl
                    if trail_mode == 1:
                        lvl = bE[int(trail_k), b] - d * 0.25 * a_
                    elif trail_mode == 2:
                        lvl = ext - d * trail_k * a_
                    elif trail_mode == 3:
                        lvl = (bl[b] if d == 1 else bh[b]) - d * trail_k * a_
                    if trail_mode > 0 and d * (lvl - sl) > 0 and d * (bc[b] - lvl) > 0:
                        sl = lvl
                if exit_ema >= 0 and d * (bc[b] - bE[exit_ema, b]) < 0:
                    pending = True
                    reason = 4
                if max_bars > 0 and bars_held >= max_bars and not pending:
                    pending = True
                    reason = 3
                b_cur += 1
            k += 1
        if pos > 0:
            k = nm - 1
            realized += pos * d * (mc[k] - ep)
        pnl = realized - comm + swap
        taken[s] = 1
        out_pnl[s] = pnl; out_risk[s] = R; out_r[s] = pnl / R
        out_et[s] = mt[j]; out_xt[s] = mt[min(k, nm - 1)]
        out_tp1[s] = 1 if done_tp1 else 0
        out_mfe[s] = d * (ext - ep) / R; out_mae[s] = d * (worst - ep) / R
        out_ep[s] = ep; out_why[s] = reason; out_bars[s] = bars_held
        busy_until = k
    return taken, out_r, out_pnl, out_risk, out_et, out_xt, out_tp1, out_mfe, out_mae, out_ep, out_why, out_bars


def run(b, m1a, sig_bar, sig_dir, sl_dist, p, one_at_a_time=True):
    C = COSTS
    res = simulate_nb(np.asarray(sig_bar, np.int64), np.asarray(sig_dir, np.int64), np.asarray(sl_dist, np.float64),
                      b["h"], b["l"], b["c"], b["atr"], b["E"], b["m1e"],
                      m1a["t"], m1a["o"], m1a["h"], m1a["l"], m1a["c"], m1a["spr"], m1a["tday"], m1a["nydow"],
                      float(p.get("tp1_r", 0.5)), float(p.get("tp1_frac", 0.5)), float(p.get("be_r", 0.05)),
                      int(p.get("trail_mode", 1)), float(p.get("trail_k", 2)), float(p.get("trail_act_r", 0.5)),
                      float(p.get("tp2_r", 0.0)), int(p.get("max_bars", 0)), int(p.get("exit_ema", -1)),
                      C["comm"], C["slip_in"], C["slip_stop"], C["swap_long"], C["swap_short"],
                      int(p.get("max_gap_sec", 1800)), bool(one_at_a_time))
    taken, r, pnl, risk, et, xt, tp1, mfe, mae, ep, why, bars = res
    m = taken == 1
    sb = np.asarray(sig_bar)[m]
    df = pd.DataFrame({"sidx": np.flatnonzero(m), "bar": sb, "dir": np.asarray(sig_dir)[m], "r": r[m],
                       "pnl_oz": pnl[m], "risk_oz": risk[m], "entry_t": et[m], "exit_t": xt[m], "tp1": tp1[m],
                       "mfe": mfe[m], "mae": mae[m], "entry_px": ep[m], "why": why[m], "bars": bars[m]})
    df["entry_dt"] = pd.to_datetime(df["entry_t"], unit="s")
    df["year"] = df["entry_dt"].dt.year
    return df


def _stats(g, y):
    n = len(g)
    if n == 0:
        return dict(year=y, n=0)
    gp = g.loc[g.r > 0, "r"].sum()
    gl = -g.loc[g.r < 0, "r"].sum()
    t = np.sort(g["entry_t"].values)
    span_days = max(1.0, (t[-1] - t[0]) / 86400.0)
    gaps = np.diff(t) / 3600.0
    mon = g.groupby(g["entry_dt"].dt.to_period("M"))["r"].sum()
    return dict(year=y, n=n, wr=round(100 * (g["r"] > 0).mean(), 1), avg_r=round(g["r"].mean(), 3),
                sum_r=round(g["r"].sum(), 1), pf=round(gp / gl, 2) if gl > 0 else np.inf,
                tpd=round(n / (span_days * 5 / 7), 2), wait_h=round(float(gaps.mean()) if len(gaps) else np.nan, 1),
                max_wait_h=round(float(gaps.max()) if len(gaps) else np.nan, 1),
                green_m=f"{int((mon > 0).sum())}/{len(mon)}")


def year_stats(tr: pd.DataFrame):
    rows = [_stats(g, y) for y, g in tr.groupby("year")]
    rows.append(_stats(tr, "ALL"))
    return pd.DataFrame(rows)
