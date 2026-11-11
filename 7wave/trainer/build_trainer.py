"""Build the 7Wave blind-replay trainer: one self-contained HTML page of real signals with the future hidden.

    C:\\Users\\faker\\mlv\\Scripts\\python.exe 7wave\\trainer\\build_trainer.py [N_SIGNALS]

Signals: stars and arrows of indicator v1.20 (tools/wave_rules.py, the rules the user checked on the chart) on
Dukascopy XAUUSD H1 and M15, 2018-2026, picked at random with a fixed seed, half H1 and half M15.
Each one carries:
  * the chart up to the bar the signal was drawn on (CONTEXT bars), with no date and no price scale;
  * for the reveal, the bars that followed and the scorecard outcomes (research/wave_scorecard.py, same costs).
Prices are stored as integer cents relative to the signal bar's close; the page rebuilds the 7 EMAs from the
indicator's EMA values just before the window, so its lines are the indicator's lines.

Writes 7wave/trainer/7wave_trainer.html (generated, not in git) and the answer key
C:\\Users\\faker\\Documents\\goldie_research\\7wave\\trainer_pack.csv.
"""
import json
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
sys.path.insert(0, os.path.join(HERE, "..", "research"))
import wave_rules as wr  # noqa: E402
import wave_scorecard as sc  # noqa: E402

OUT_DIR = r"C:\Users\faker\Documents\goldie_research\7wave"
OUT_HTML = os.path.join(HERE, "7wave_trainer.html")
OUT_KEY = os.path.join(OUT_DIR, "trainer_pack.csv")
TEMPLATE = os.path.join(HERE, "trainer_template.html")
N_SIGNALS = int(sys.argv[1]) if len(sys.argv) > 1 else 400
CONTEXT = 320  # bars of history shown before the decision (the widest zoom)
SEED = 2026  # 7 was used while testing the page, and its first signals were described in the chat
DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def pack_tf(m, tf, minutes, horizon, n_pick, rng):
    b = sc.make_bars(m, minutes)
    n = len(b["c"])
    ema = wr.emas(b["c"])
    a14 = sc.atr(b, 14)
    sig, _ = wr.signals_for(b["o"], b["c"], ema)
    h1 = b if minutes == 60 else sc.make_bars(m, 60)
    h1_close, h1_atr = h1["t"] + h1["sec"], sc.atr(h1, 14)
    sig_bars = np.array([s[0] for s in sig])

    eligible = []
    for idx, (i, kind, d, due) in enumerate(sig):
        if i < CONTEXT + 1 or i + horizon >= n - 1:
            continue
        if pd.Timestamp(int(m["t"][b["m1e"][i] - 1]), unit="s").year < sc.FIRST_YEAR:
            continue
        eligible.append(idx)
    picks = sorted(rng.choice(len(eligible), size=min(n_pick, len(eligible)), replace=False))

    out = []
    for p in picks:
        i, kind, d, due = sig[eligible[p]]
        s, e = i - CONTEXT + 1, i + horizon  # window bars s..e; the decision bar is i (index CONTEXT-1)
        j0, j1 = b["m1e"][i], b["m1e"][i + horizon]
        rdist = sc.R_ATR * a14[i]
        r, mfe, reason, jx = sc.simulate(j0, j1, d, rdist, m["o"], m["h"], m["l"], m["c"], m["spr"], m["swapcnt"])
        close_t = b["t"][i] + b["sec"]
        jh = b["m1e"][min(i + sc.HOLD[tf], n - 1)]
        kh = np.searchsorted(h1_close, close_t, side="right") - 1
        run_r = sc.run_length(j0, jh, d, rdist, m["o"], m["h"], m["l"], m["spr"])
        hold_r = sc.trail_trade(j0, jh, d, rdist, sc.TRAIL_ATR_H1 * h1_atr[max(kh, 0)],
                                m["o"], m["h"], m["l"], m["c"], m["spr"], m["swapcnt"])
        entry = m["o"][j0] + m["spr"][j0] + sc.SLIP_IN if d > 0 else m["o"][j0] - sc.SLIP_IN
        exit_bar = int(np.searchsorted(b["m1s"], jx, side="right") - 1)

        base = int(round(b["c"][i] * 100))
        cc = np.round(b["c"][s:e + 1] * 100).astype(np.int64) - base
        oo = np.round(b["o"][s:e + 1] * 100).astype(np.int64) - base - cc
        hh = np.round(b["h"][s:e + 1] * 100).astype(np.int64) - base - cc
        ll = np.round(b["l"][s:e + 1] * 100).astype(np.int64) - base - cc
        lo_k, hi_k = np.searchsorted(sig_bars, s, "left"), np.searchsorted(sig_bars, e, "right")
        marks = [[int(sig[q][0] - s), 1 if sig[q][1] == "star" else 0, int(sig[q][2])] for q in range(lo_k, hi_k)]
        bar_open = pd.Timestamp(int(b["t"][i]), unit="s")  # server time, as MT5 labels the bar
        out.append(dict(
            tf=tf, kind=kind, dir=int(d), wd=DAYS[bar_open.dayofweek], hm=bar_open.strftime("%H:%M"),
            e0=[round(float(v) * 100 - base, 2) for v in ema[s - 1]],
            c=np.diff(cc, prepend=0).tolist(), o=oo.tolist(), h=hh.tolist(), l=ll.tolist(),
            nctx=CONTEXT, mk=marks,
            entry=round(entry * 100 - base, 1), rd=round(rdist * 100, 1), xk=exit_bar - s,
            res=dict(R=round(float(r), 3), why=int(reason), mfe=round(float(mfe), 2), run=round(float(run_r), 2),
                     hold=round(float(hold_r), 3), good=int(reason == 1), fake=int(reason == -1 and mfe < 1.0),
                     date=bar_open.strftime("%Y-%m-%d %H:%M"), year=int(bar_open.year), px=round(float(b["c"][i]), 2)),
        ))
    return out


def main():
    rng = np.random.default_rng(SEED)
    m = sc.load_m1("duka")
    signals = []
    for tf, (minutes, horizon) in sc.TFS.items():
        signals += pack_tf(m, tf, minutes, horizon, N_SIGNALS // 2, rng)
    order = rng.permutation(len(signals))
    signals = [signals[k] for k in order]
    for k, s in enumerate(signals, 1):
        s["id"] = k
    pack = dict(version=1, built=pd.Timestamp.now().strftime("%Y-%m-%d"), context=CONTEXT, signals=signals)

    with open(TEMPLATE, encoding="utf-8") as f:
        html = f.read().replace("__PACK__", json.dumps(pack, separators=(",", ":")))
    with open(OUT_HTML, "w", encoding="utf-8") as f:
        f.write(html)
    key = pd.DataFrame([dict(id=s["id"], tf=s["tf"], kind=s["kind"], dir=s["dir"], **s["res"]) for s in signals])
    key.to_csv(OUT_KEY, index=False)

    print(f"{len(signals)} signals -> {OUT_HTML} ({os.path.getsize(OUT_HTML) / 1e6:.1f} MB)")
    for tf, g in key.groupby("tf"):
        print(f"  {tf}: {len(g)} signals, {g.good.mean():.0%} good waves, {g.fake.mean():.0%} fakes, "
              f"avg R {g.R.mean():+.3f}, years {g.year.min()}-{g.year.max()}")


if __name__ == "__main__":
    main()
