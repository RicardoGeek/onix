"""Study 41b: Kronos skill, contamination-aware.  Kronos was released 2025-08 and pre-trained on 12B candles from 45 exchanges,
which may include gold before mid-2025.  So compare its skill on years it may have seen (2018-2024) with the truly unseen
period after its release (2025-09 .. end of data), and test it as a filter on the setups of the unseen period only.
  python -I sw_study41b.py [n_seen] [n_unseen]
"""
import sys
sys.path.insert(0, r"C:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
sys.path.insert(0, r"C:\Users\faker\Documents\goldie_research\kronos\repo")
import os
import numpy as np
import pandas as pd
import torch
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_mtf as M
from model import Kronos, KronosTokenizer, KronosPredictor

N_SEEN = int(_argv[1]) if len(_argv) > 1 else 200
N_UNSEEN = int(_argv[2]) if len(_argv) > 2 else 300
LOOK, H = 256, 12
torch.set_num_threads(os.cpu_count() or 2)
pred = KronosPredictor(Kronos.from_pretrained("NeoQuasar/Kronos-small"), KronosTokenizer.from_pretrained("NeoQuasar/Kronos-Tokenizer-base"),
                       device="cpu", max_context=512)
H1 = V.tfs["H1"]
ts = pd.to_datetime(H1["t"], unit="s")
dfH = pd.DataFrame({"open": H1["o"], "high": H1["h"], "low": H1["l"], "close": H1["c"]})


def forecast(bar_idx, batch=16):
    out = np.full(len(bar_idx), np.nan)
    for s in range(0, len(bar_idx), batch):
        ks = bar_idx[s:s + batch]
        dl = [dfH.iloc[k - LOOK + 1:k + 1].reset_index(drop=True) for k in ks]
        xl = [pd.Series(ts[k - LOOK + 1:k + 1]).reset_index(drop=True) for k in ks]
        yl = [pd.Series(pd.date_range(ts[k] + pd.Timedelta(hours=1), periods=H, freq="h")) for k in ks]
        res = pred.predict_batch(dl, xl, yl, pred_len=H, T=1.0, top_p=0.9, sample_count=1, verbose=False)
        for i, r in enumerate(res):
            out[s + i] = float(r["close"].values[-1] - dl[i]["close"].values[-1])
    return out


def skill(name, idx):
    f = forecast(idx)
    real = H1["c"][idx + H] - H1["c"][idx]
    ok = np.isfinite(f) & (real != 0)
    hit = (np.sign(f[ok]) == np.sign(real[ok])).astype(float)
    ic = np.corrcoef(f[ok], real[ok])[0, 1]
    rng = np.random.default_rng(3)
    boots = [np.corrcoef(*(lambda b: (f[ok][b], real[ok][b]))(rng.integers(0, ok.sum(), ok.sum())))[0, 1] for _ in range(500)]
    print(f"{name}: n={ok.sum()} hit {hit.mean() * 100:.1f}% (+/- {hit.std() / np.sqrt(len(hit)) * 100:.1f}), IC {ic:+.3f} "
          f"[95% {np.percentile(boots, 2.5):+.3f}, {np.percentile(boots, 97.5):+.3f}]", flush=True)
    return f, real


rng = np.random.default_rng(21)
t_end = H1["t"][H1["n"] - H - 2]
seen = np.flatnonzero((H1["t"] >= pd.Timestamp("2018-01-01").value // 10**9) & (H1["t"] < pd.Timestamp("2025-01-01").value // 10**9))
unseen = np.flatnonzero((H1["t"] >= pd.Timestamp("2025-09-01").value // 10**9) & (H1["t"] <= t_end))
print(f"data ends {ts[H1['n'] - 1]}; unseen pool {len(unseen)} H1 bars", flush=True)
skill("SEEN? 2018-2024 random H1", np.sort(rng.choice(seen, N_SEEN, replace=False)))
skill("UNSEEN 2025-09+ random H1", np.sort(rng.choice(unseen, min(N_UNSEEN, len(unseen)), replace=False)))

J, D, PX, AT, SI = V.all_events(use=["A", "B", "G", "P"])
tr = V.outcomes((J, D, PX, AT, SI), "growth")
r = np.full(len(J), np.nan); r[tr.eidx.values] = tr.r.values
k1 = M.map_last_closed(H1, V.m1a["t"][J])
sel = np.flatnonzero(np.isfinite(r) & (V.m1a["t"][J] >= pd.Timestamp("2025-09-01").value // 10**9))
fs = forecast(k1[sel])
agree = fs * D[sel]
rr = r[sel]
for nm, m in (("all unseen setups", np.isfinite(agree)), ("Kronos agrees", agree > 0), ("Kronos disagrees", agree <= 0)):
    print(f"  {nm:20s} n={m.sum():4d} WR {(rr[m] > 0).mean() * 100:5.1f}% avgR {rr[m].mean():+.3f}", flush=True)
