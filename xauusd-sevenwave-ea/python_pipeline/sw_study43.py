"""Study 43: information that is NOT in the gold price bars.
  (a) Economic calendar (MQL5 calendar export, US moderate/high events 2016-12 .. now): are v1.10+ setups that fire near
      high-impact releases (NFP, CPI, FOMC, ...) better or worse?
  (b) Cross-asset context at the trigger (Pepperstone H1, last CLOSED bar): USD index, USDJPY (US-yield proxy), silver, US500.
      Do setups do better when the dollar / yields / silver agree with the gold trade?
  (c) News-surprise drift: after NFP / CPI releases, follow gold's first 5-minute reaction (or trade the surprise sign)
      until +1h / +4h.  Costs: Duka spread model + commission + slippage (news spreads are wider in reality).
Outcomes for (a)/(b): the setups' R under the v1.10 trend-tail management (Dukascopy 2017-2026).
"""
import sys
import numpy as np
import pandas as pd
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_data as SD
import sw_sim2 as S2

m1a = V.m1a
DATA = r"C:\Users\faker\Documents\goldie_research\sevenwave\data"
J, D, PX, AT, SI = V.all_events(use=["A", "B", "G", "P"])
tr = V.outcomes((J, D, PX, AT, SI), "growth")
r = np.full(len(J), np.nan); r[tr.eidx.values] = tr.r.values
t = m1a["t"][J]
yr = pd.to_datetime(t, unit="s").year.values
ok = np.isfinite(r)


def bucket(name, mask):
    m = ok & mask
    c = ok & ~mask
    if m.sum() < 30:
        print(f"  {name:44s} n={m.sum():4d} (too few)")
        return
    py = pd.Series(r[m]).groupby(yr[m]).mean()
    print(f"  {name:44s} n={m.sum():4d} WR {(r[m] > 0).mean() * 100:5.1f}% avgR {r[m].mean():+.3f} | rest n={c.sum():4d} avgR {r[c].mean():+.3f} "
          f"| years+ {int((py > 0).sum())}/{len(py)} | 17-22 {r[m & (yr <= 2022)].mean():+.3f} 23-26 {r[m & (yr >= 2023)].mean():+.3f}")


# ---------------------------------------------------------------- (a) calendar
cal = pd.read_csv(r"C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\Common\Files\sw_calendar_us.csv")
cal["t"] = cal.time_srv.values.astype(np.int64)   # calendar times are UTC
hi = cal[cal.importance == 3].copy()
key = hi[hi.event.str.contains("Nonfarm Payrolls|^CPI|Core CPI|Fed Interest Rate Decision|FOMC Statement|GDP q/q|Retail Sales m/m|PCE", regex=True)]
print(f"calendar: {len(cal)} rows, {len(hi)} high-importance, {len(key)} key releases; e.g. {', '.join(key.event.drop_duplicates().head(10))}")
ht = np.sort(hi.t.unique()); kt = np.sort(key.t.unique())


def mins_since(ts, ev):
    k = np.searchsorted(ev, ts, side="right") - 1
    return np.where(k >= 0, (ts - ev[np.maximum(k, 0)]) / 60.0, 1e9)


def mins_to(ts, ev):
    k = np.searchsorted(ev, ts, side="left")
    return np.where(k < len(ev), (ev[np.minimum(k, len(ev) - 1)] - ts) / 60.0, 1e9)


s_hi, n_hi = mins_since(t, ht), mins_to(t, ht)
s_k, n_k = mins_since(t, kt), mins_to(t, kt)
day = (t // 86400)
kday = np.isin(day, np.unique(kt // 86400))
print(f"\n(a) {ok.sum()} setups; base WR {(r[ok] > 0).mean() * 100:.1f}% avgR {r[ok].mean():+.3f}")
bucket("0-30 min after a high-impact US release", s_hi <= 30)
bucket("30-120 min after a high-impact release", (s_hi > 30) & (s_hi <= 120))
bucket("within 60 min BEFORE a high-impact release", n_hi <= 60)
bucket("0-60 min after a KEY release (NFP/CPI/FOMC..)", s_k <= 60)
bucket("within 120 min BEFORE a key release", n_k <= 120)
bucket("on a key-release day", kday)
bucket("no high release within +-3h", (s_hi > 180) & (n_hi > 180))

# ---------------------------------------------------------------- (b) cross-asset context
def xasset(name):
    z = np.load(rf"{DATA}\x_{name}_h1.npz")
    tu = SD.server_to_utc(z["srv"].astype(np.int64)) + 3600         # bar CLOSE time in UTC
    c = z["c"]
    k = np.searchsorted(tu, t, side="right") - 1                     # last bar closed before the trigger
    def chg(h):
        kk = np.maximum(k - h, 0)
        v = np.where(k >= h, c[np.maximum(k, 0)] - c[kk], np.nan)
        return np.where(k >= 0, v, np.nan)
    return chg(24), chg(120)


print(f"\n(b) cross-asset context at the trigger (agree = supports the gold trade direction)")
for name, inverse in (("USDX", True), ("USDJPY", True), ("XAGUSD", False), ("US500", False), ("NAS100", False)):
    c24, c120 = xasset(name)
    sgn = -1 if inverse else 1
    for lab, cc in (("24h", c24), ("5d", c120)):
        valid = np.isfinite(cc)
        agree = valid & (np.sign(cc) * sgn == D)
        bucket(f"{name} {lab} agrees ({'opposite' if inverse else 'same'} move)", agree)

# ---------------------------------------------------------------- (c) news-surprise drift (NFP / CPI)
print("\n(c) NFP / CPI releases: follow gold's first 5-minute reaction (or the surprise) from +5 min")
mt = m1a["t"]; mo, mc, sp = m1a["o"], m1a["c"], m1a["spr"]
a1 = V.tfs["H1"]
for evname, pat in (("NFP", "Nonfarm Payrolls$"), ("CPI m/m", "^CPI m/m"), ("Core CPI m/m", "^Core CPI m/m")):
    ev = key[key.event.str.contains(pat, regex=True)].drop_duplicates("t")
    rows = []
    for e in ev.itertuples():
        j0 = np.searchsorted(mt, e.t)
        if j0 + 300 >= len(mt) or abs(mt[j0] - e.t) > 120:
            continue
        k = np.searchsorted(a1["t_close"], e.t, side="right") - 1
        atr = a1["atr"][max(k, 0)]
        move5 = mc[j0 + 4] - mo[j0]
        sur = (e.actual - e.forecast) if np.isfinite(e.actual) and np.isfinite(e.forecast) else np.nan
        for hold in (60, 240):
            je = min(j0 + 5 + hold, len(mt) - 1)
            for side in ("follow5", "surprise"):
                d = np.sign(move5) if side == "follow5" else (-np.sign(sur) if np.isfinite(sur) else 0.0)  # USD-positive surprise -> gold down
                if d == 0:
                    continue
                ep = mo[j0 + 5] + (sp[j0 + 5] if d > 0 else 0.0) + 0.05 * d
                xp = mo[je] + (sp[je] if d < 0 else 0.0) - 0.05 * d
                pnl = d * (xp - ep) - S2.COMM
                rows.append(dict(ev=evname, hold=hold, side=side, year=pd.Timestamp(e.t, unit="s").year, r=pnl / max(atr, 1e-9),
                                 big=abs(move5) > 0.5 * atr))
    R = pd.DataFrame(rows)
    if R.empty:
        continue
    for (hold, side), g in R.groupby(["hold", "side"]):
        for lab, gg in (("all", g), ("first move > 0.5 ATR", g[g.big])):
            if len(gg) < 15:
                continue
            py = gg.groupby("year").r.mean()
            print(f"  {evname:12s} {side:8s} hold {hold:3d}m {lab:21s} n={len(gg):3d} WR {(gg.r > 0).mean() * 100:5.1f}% "
                  f"avg {gg.r.mean():+.3f} ATR | years+ {int((py > 0).sum())}/{len(py)}")
