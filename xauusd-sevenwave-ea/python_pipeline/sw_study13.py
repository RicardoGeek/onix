"""Study 13: multi-timeframe structure hierarchy.  Entries on a decision timeframe (fresh ribbon realign or BOS flip),
split by how many HIGHER timeframes agree (ribbon stack and/or break-of-structure direction).
Fixed TP/SL grid in decision-TF ATR, pessimistic M1 path, per-year expectancy."""
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


def report(label, b, idx, d):
    if len(idx) < 60:
        return
    j = b["m1e"][idx]
    ok = j < len(m1a["t"])
    idx, d, j = idx[ok], d[ok], j[ok]
    gapok = (m1a["t"][j] - m1a["t"][j - 1]) <= 1800
    idx, d, j = idx[gapok], d[gapok], j[gapok]
    a = b["atr"][idx]
    mfe, _ = V.excursions_nb(j, d, a, m1a["o"], m1a["h"], m1a["l"], m1a["spr"], V.YS, 7200)
    s, rows = V.table(mfe, cost_usd / a, label)
    y_, x_ = sorted(rows, key=lambda r: -r[3])[0][:2]
    yi = list(V.YS).index(y_)
    per = []
    for yy in range(2017, 2027):
        m = years_m1[j] == yy
        if m.sum() < 4:
            per.append("  .  "); continue
        w = mfe[m, yi] >= x_
        per.append(f"{np.mean((w * x_ - (~w) * y_ - cost_usd / a[m]) / y_):+.2f}")
    days = (m1a["t"][j[-1]] - m1a["t"][j[0]]) / 86400 * 5 / 7
    npos = sum(1 for p in per if p.strip() not in (".",) and float(p) > 0)
    print(f"{s[:128]} [{len(idx) / days:.2f}/d] +yrs={npos} | {' '.join(per)}")


for dec in ("M15", "H1", "H4"):
    b = tfs[dec]
    dec_t = b["t_close"]
    higher = order[order.index(dec) + 1:]
    hmap = {h: M.map_last_closed(tfs[h], dec_t) for h in higher}
    n = b["n"]
    # candidate families on the decision TF
    rib = b["ribbon"]
    realign = np.zeros(n, np.int64)
    realign[1:] = np.where((rib[1:] == 1) & (rib[:-1] != 1), 1, np.where((rib[1:] == -1) & (rib[:-1] != -1), -1, 0))
    bosf = np.zeros(n, np.int64)
    bosf[1:] = np.where(b["bos"][1:] != b["bos"][:-1], b["bos"][1:], 0)
    for fam_name, fam in (("realign", realign), ("BOS-flip", bosf)):
        idx_all = np.flatnonzero(fam != 0)
        idx_all = idx_all[(idx_all > 300) & (idx_all < n - 1)]
        d_all = fam[idx_all]
        # agreement counts
        agree_stack = np.zeros(len(idx_all), np.int64)
        agree_bos = np.zeros(len(idx_all), np.int64)
        valid = np.ones(len(idx_all), bool)
        for h in higher:
            hi = hmap[h][idx_all]
            valid &= hi >= 200 if h != "D1" else hi >= 30
            hi = np.maximum(hi, 0)
            agree_stack += (tfs[h]["stackd"][hi] == d_all).astype(np.int64)
            agree_bos += (tfs[h]["bos"][hi] == d_all).astype(np.int64)
        idx_all, d_all, agree_stack, agree_bos = idx_all[valid], d_all[valid], agree_stack[valid], agree_bos[valid]
        nh = len(higher)
        print(f"\n##### decision {dec} {fam_name}: {len(idx_all)} events, higher={higher}")
        report(f"{dec} {fam_name} ALL", b, idx_all, d_all)
        for k in range(nh + 1):
            m = agree_stack == k
            report(f"{dec} {fam_name} stack-agree={k}/{nh}", b, idx_all[m], d_all[m])
        for k in range(nh + 1):
            m = agree_bos == k
            report(f"{dec} {fam_name} BOS-agree={k}/{nh}", b, idx_all[m], d_all[m])
        m = (agree_stack == nh) & (agree_bos == nh)
        report(f"{dec} {fam_name} FULL stack+BOS", b, idx_all[m], d_all[m])
