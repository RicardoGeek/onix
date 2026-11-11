"""Study 14: drill into the hierarchy edge.  Decision TF realign entries (M5 / M15 / H1) gated by higher-TF agreement
variants and higher-TF trend age ("fresh" higher-TF waves vs mature), fixed TP/SL grid, per-year."""
import sys
import numpy as np
import pandas as pd
from sw_data import load
import sw_engine as E
import sw_events as V
import sw_mtf as M

src = sys.argv[1] if len(sys.argv) > 1 else "duka"
m1 = load("duka_m1" if src == "duka" else "pep_m1")
m1 = m1[m1["t"] >= pd.Timestamp("2017-01-01").value // 10 ** 9].reset_index(drop=True)
m1a = E.m1_arrays(m1, src)
tfs = M.build_hierarchy(m1a)
years_m1 = pd.to_datetime(m1a["t"], unit="s").year.values
cost_usd = 0.07 + 0.05 + 0.05
order = ["M5", "M15", "H1", "H4", "D1"]


def stack_age(st):
    age = np.zeros(len(st), np.int64)
    for i in range(1, len(st)):
        age[i] = age[i - 1] + 1 if (st[i] != 0 and st[i] == st[i - 1]) else (1 if st[i] != 0 else 0)
    return age


for k in tfs:
    tfs[k]["sage"] = stack_age(tfs[k]["stackd"])


def evaluate(label, b, idx, d, show=True):
    if len(idx) < 60:
        return None
    j = b["m1e"][idx]
    ok = (j < len(m1a["t"]))
    idx, d, j = idx[ok], d[ok], j[ok]
    ok = (m1a["t"][j] - m1a["t"][j - 1]) <= 1800
    idx, d, j = idx[ok], d[ok], j[ok]
    a = b["atr"][idx]
    mfe, _ = V.excursions_nb(j, d, a, m1a["o"], m1a["h"], m1a["l"], m1a["spr"], V.YS, 7200)
    s, rows = V.table(mfe, cost_usd / a, label)
    y_, x_, w_, e_ = sorted(rows, key=lambda r: -r[3])[0]
    yi = list(V.YS).index(y_)
    per = []
    for yy in range(2017, 2027):
        m = years_m1[j] == yy
        if m.sum() < 4:
            per.append(np.nan); continue
        w = mfe[m, yi] >= x_
        per.append(np.mean((w * x_ - (~w) * y_ - cost_usd / a[m]) / y_))
    per = np.array(per)
    days = (m1a["t"][j[-1]] - m1a["t"][j[0]]) / 86400 * 5 / 7
    if show:
        print(f"{label:58s} n={len(idx):5d} [{len(idx) / days:.2f}/d] SL{y_}/TP{x_} wr={w_:.2f} ev={e_:+.3f} "
              f"+yrs={int(np.nansum(per > 0))}/{int(np.sum(np.isfinite(per)))} | " +
              " ".join("  .  " if not np.isfinite(p) else f"{p:+.2f}" for p in per))
    return e_


for dec in ("M5", "M15", "H1"):
    b = tfs[dec]
    n = b["n"]
    dt = b["t_close"]
    higher = order[order.index(dec) + 1:]
    hm = {h: np.maximum(M.map_last_closed(tfs[h], dt), 0) for h in higher}
    rib = b["ribbon"]
    realign = np.zeros(n, np.int64)
    realign[1:] = np.where((rib[1:] == 1) & (rib[:-1] != 1), 1, np.where((rib[1:] == -1) & (rib[:-1] != -1), -1, 0))
    idx = np.flatnonzero(realign != 0)
    idx = idx[(idx > 3000) & (idx < n - 1)]
    d = realign[idx]
    st = {h: tfs[h]["stackd"][hm[h][idx]] for h in higher}
    bo = {h: tfs[h]["bos"][hm[h][idx]] for h in higher}
    rb = {h: tfs[h]["ribbon"][hm[h][idx]] for h in higher}
    ag = {h: tfs[h]["sage"][hm[h][idx]] for h in higher}
    print(f"\n######## decision {dec}: {len(idx)} realign events; higher {higher}")
    allst = np.all([st[h] == d for h in higher], axis=0)
    evaluate(f"{dec} all-higher stacked", b, idx[allst], d[allst])
    top2 = higher[-2:]
    m2 = np.all([st[h] == d for h in top2], axis=0)
    evaluate(f"{dec} {'+'.join(top2)} stacked", b, idx[m2], d[m2])
    m3 = m2 & (bo[higher[0]] == d)
    evaluate(f"{dec} {'+'.join(top2)} stacked + {higher[0]} BOS", b, idx[m3], d[m3])
    m4 = np.all([rb[h] == d for h in higher], axis=0)
    evaluate(f"{dec} all-higher ribbon (price beyond fast EMA)", b, idx[m4], d[m4])
    m5 = allst & np.all([bo[h] == d for h in higher], axis=0)
    evaluate(f"{dec} all-higher stacked + all BOS", b, idx[m5], d[m5])
    # pullback depth: decision TF must have been out of alignment >= P bars (a real pullback, not a flicker)
    prev_out = np.zeros(len(idx), np.int64)
    for q, i in enumerate(idx):
        c = 0
        while i - 1 - c > 0 and rib[i - 1 - c] != d[q] and c < 200:
            c += 1
        prev_out[q] = c
    for P in (2, 4, 8, 16):
        mm = allst & (prev_out >= P)
        evaluate(f"{dec} all-higher stacked, pullback>={P} bars", b, idx[mm], d[mm])
    # higher-TF trend age (in that TF's bars): fresh vs mature
    h1 = higher[0]
    for lo, hi in ((1, 12), (12, 48), (48, 10 ** 9)):
        mm = allst & (ag[h1] >= lo) & (ag[h1] < hi)
        evaluate(f"{dec} all-higher stacked, {h1} stack age {lo}-{hi if hi < 1e9 else 'inf'}", b, idx[mm], d[mm])
    hT = higher[-2] if len(higher) >= 2 else higher[0]
    for lo, hi in ((1, 12), (12, 60), (60, 10 ** 9)):
        mm = allst & (ag[hT] >= lo) & (ag[hT] < hi)
        evaluate(f"{dec} all-higher stacked, {hT} stack age {lo}-{hi if hi < 1e9 else 'inf'}", b, idx[mm], d[mm])
    for dd, nm in ((1, "LONG"), (-1, "SHORT")):
        mm = allst & (d == dd)
        evaluate(f"{dec} all-higher stacked {nm} only", b, idx[mm], d[mm])
