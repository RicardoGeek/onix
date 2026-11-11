"""Study 41: Kronos (AAAI 2026 K-line foundation model, NeoQuasar/Kronos-small, zero-shot) on gold.
  (a) skill: at random H1 closes, does the sign of Kronos' 12-bar-ahead forecast match the realised 12h move?
  (b) filter: for every v1.10+ setup, does Kronos agree with the trade direction, and are agreeing setups better?
Context = the last 400 closed H1 bars (OHLC, Dukascopy), prediction 12 bars, 5 sampled paths averaged.
  python -I sw_study41.py [n_random] [max_setups]
"""
import sys
import time
sys.path.insert(0, r"C:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
sys.path.insert(0, r"C:\Users\faker\Documents\goldie_research\kronos\repo")
import numpy as np
import pandas as pd
import torch
from sklearn.metrics import roc_auc_score
_argv = list(sys.argv)
sys.argv = [sys.argv[0], "x", "duka"]
import sw_v110 as V
sys.argv = _argv
import sw_mtf as M
from model import Kronos, KronosTokenizer, KronosPredictor

N_RAND = int(sys.argv[1]) if len(sys.argv) > 1 else 600
N_SET = int(sys.argv[2]) if len(sys.argv) > 2 else 100000
LOOK = int(sys.argv[3]) if len(sys.argv) > 3 else 400
SAMPLES = int(sys.argv[4]) if len(sys.argv) > 4 else 5
import os
torch.set_num_threads(os.cpu_count() or 4)
print('threads', torch.get_num_threads(), 'look', LOOK, 'samples', SAMPLES, flush=True)
tok = KronosTokenizer.from_pretrained("NeoQuasar/Kronos-Tokenizer-base")
mdl = Kronos.from_pretrained("NeoQuasar/Kronos-small")
pred = KronosPredictor(mdl, tok, device="cpu", max_context=512)
H1 = V.tfs["H1"]
H = 12
ts = pd.to_datetime(H1["t"], unit="s")
dfH = pd.DataFrame({"open": H1["o"], "high": H1["h"], "low": H1["l"], "close": H1["c"]})


def forecast(bar_idx, batch=16):
    """bar_idx = index of the LAST closed H1 bar of the context; returns predicted close at +H minus last close."""
    out = np.full(len(bar_idx), np.nan)
    for s in range(0, len(bar_idx), batch):
        ks = bar_idx[s:s + batch]
        dl, xl, yl = [], [], []
        for k in ks:
            dl.append(dfH.iloc[k - LOOK + 1:k + 1].reset_index(drop=True))
            xl.append(pd.Series(ts[k - LOOK + 1:k + 1]).reset_index(drop=True))
            yl.append(pd.Series(pd.date_range(ts[k] + pd.Timedelta(hours=1), periods=H, freq="h")))
        res = pred.predict_batch(dl, xl, yl, pred_len=H, T=1.0, top_p=0.9, sample_count=SAMPLES, verbose=False)
        for i, r in enumerate(res):
            out[s + i] = float(r["close"].values[-1] - dl[i]["close"].values[-1])
    return out


t0 = time.time()
# ---------------------------------------------------------------- (a) skill at random H1 closes
rng = np.random.default_rng(11)
cand = np.arange(LOOK + 10, H1["n"] - H - 1)
ri = np.sort(rng.choice(cand, N_RAND, replace=False))
f = forecast(ri)
real = H1["c"][ri + H] - H1["c"][ri]
ok = np.isfinite(f) & (real != 0)
hit = (np.sign(f[ok]) == np.sign(real[ok])).mean()
ic = np.corrcoef(f[ok], real[ok])[0, 1]
yrs = ts[ri].year.values
print(f"(a) {ok.sum()} random H1 points: direction hit rate {hit * 100:.1f}% (50% = no skill), IC {ic:+.3f}, "
      f"{time.time() - t0:.0f}s", flush=True)
for y in range(2017, 2027):
    s = ok & (yrs == y)
    if s.sum() > 10:
        print(f"    {y}: hit {(np.sign(f[s]) == np.sign(real[s])).mean() * 100:.1f}% n={s.sum()}")

# ---------------------------------------------------------------- (b) setups
J, D, PX, AT, SI = V.all_events(use=["A", "B", "G", "P"])
tr = V.outcomes((J, D, PX, AT, SI), "growth")
r = np.full(len(J), np.nan); r[tr.eidx.values] = tr.r.values
k1 = M.map_last_closed(H1, V.m1a["t"][J])
sel = np.flatnonzero(np.isfinite(r) & (k1 > LOOK + 5))[:N_SET]
fs = forecast(k1[sel])
agree = fs * D[sel] / np.maximum(AT[sel], 1e-9)          # Kronos' predicted 12h move in the trade direction, in ATR(H1)
rr = r[sel]; y2 = pd.to_datetime(V.m1a["t"][J[sel]], unit="s").year.values
ok2 = np.isfinite(agree)
print(f"\n(b) {ok2.sum()} setups: AUC(agree -> win) {roc_auc_score(rr[ok2] > 0, agree[ok2]):.3f}, "
      f"corr(agree, R) {np.corrcoef(agree[ok2], rr[ok2])[0, 1]:+.3f}, {time.time() - t0:.0f}s")
for nm, m in (("Kronos agrees", ok2 & (agree > 0)), ("Kronos disagrees", ok2 & (agree <= 0)),
              ("top third agreement", ok2 & (agree >= np.nanquantile(agree, 2 / 3))),
              ("bottom third", ok2 & (agree <= np.nanquantile(agree, 1 / 3)))):
    py = pd.Series(rr[m]).groupby(y2[m]).mean()
    print(f"  {nm:22s} n={m.sum():5d} WR {(rr[m] > 0).mean() * 100:5.1f}% avgR {rr[m].mean():+.3f} | years+ {int((py > 0).sum())}/{len(py)} | "
          + " ".join(f"{k}:{v:+.2f}" for k, v in py.items()))
np.savez(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\kronos_study41.npz", ri=ri, f=f, real=real, sel=sel, fs=fs, r=rr)
