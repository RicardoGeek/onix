"""Parity check: Python research replay vs the MQL5 EA event log (sevenwave_events.csv from the tester).

Python side: Pepperstone M1 2023-01..  (same 1-year warm-up the MT5 tester gives a 2024-01-01 start), the 6 streams,
the EXPORTED ONNX model + threshold, and the mode's management, one position at a time.
  python sw_parity.py <events.csv> [prop|growth]
"""
import json
import os
import sys
import numpy as np
import pandas as pd
import onnxruntime as ort
import sw_engine as E
import sw_sim2 as S2
import sw_ml3 as L3
import sw_final as F

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODES = {"prop": (dict(tp1_r=0.3, tp1_frac=0.2, be_r=0.05, act_r=1.5, tp2_r=2.0, max_min=2880), 2.0, 1.0),
         "growth": (dict(tp1_r=0.5, tp1_frac=0.0, be_r=0.05, act_r=1.0, tp2_r=3.0, max_min=1440), 1.5, 2.0)}
NAMES = ["A", "B", "C", "E", "F", "G"]


def python_events(mode):
    mg, slk, trk = MODES[mode]
    L3.MG.update(mg)
    L3.SL_K, L3.TRAIL_K = slk, trk
    m1a, tfs = L3.prep("pep", start="2023-01-01")
    df, Xfull = L3.events(m1a, tfs)
    X = F.feature_matrix(Xfull).astype(np.float32)
    sess = ort.InferenceSession(os.path.join(ROOT, "MQL5", "Files", "models", "sevenwave_rater.onnx"))
    p = np.array([sess.run(None, {"input": X[i:i + 1]})[1][0, 1] for i in range(len(X))])
    meta = json.load(open(os.path.join(ROOT, "python_pipeline", "models", "sevenwave_rater_meta.json")))
    df["p"] = p
    df["veto"] = p < meta["threshold"]
    df["t"] = pd.to_datetime(m1a["t"][df.j.values], unit="s")
    return m1a, df, X, mg


if __name__ == "__main__":
    ev_path = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else "prop"
    m1a, df, X, mg = python_events(mode)
    df = df[df.t >= "2024-01-01"].copy()
    keep = df[~df.veto]
    tr = S2.run_fills(m1a, keep.j.values, keep.dir.values, keep.px.values, keep.R.values, keep.trail.values, mg,
                      meta={"stream": keep.stream.values})
    tr["t"] = pd.to_datetime(tr.entry_t, unit="s")
    print(f"PYTHON: {len(df)} triggers 2024+, vetoed {int(df.veto.sum())}, traded {len(tr)}")
    ea = pd.read_csv(ev_path)
    ea["t"] = pd.to_datetime(ea.utc, format="%Y.%m.%d %H:%M:%S").astype("datetime64[ns]")
    print(f"EA    : {len(ea)} triggers, decisions {ea.decision.value_counts().to_dict()}")
    # match triggers within 2 minutes, same direction and stream
    df["t"] = df.t.astype("datetime64[ns]")
    tr["t"] = tr.t.astype("datetime64[ns]")
    df["key_t"] = df.t.dt.floor("min")
    ea["key_t"] = ea.t.dt.floor("min")
    m = pd.merge_asof(ea.sort_values("t"), df.assign(stream_name=[NAMES[s] for s in df.stream]).sort_values("t"),
                      on="t", by="dir", tolerance=pd.Timedelta("3min"), direction="nearest", suffixes=("_ea", "_py"))
    matched = m["j"].notna()
    same_stream = matched & (m["stream_ea"] == m["stream_name"])
    print(f"EA triggers matched to a Python trigger (+-3 min, same dir): {matched.mean():.1%}, same stream {same_stream.mean():.1%}")
    mm = m[matched]
    fcols = [f"f{i}" for i in range(17)]
    print(f"AI score correlation EA vs Python on matched triggers: {np.corrcoef(mm['p_ea'], mm['p_py'])[0, 1]:.3f}, "
          f"median |diff| {np.median(np.abs(mm['p_ea'] - mm['p_py'])):.4f}")
    # trades
    et = ea[ea.decision == "trade"].copy()
    pm = pd.merge_asof(et.sort_values("t"), tr.sort_values("t"), on="t", by="dir", tolerance=pd.Timedelta("3min"),
                       direction="nearest")
    print(f"EA trades matched to Python trades: {pm['r'].notna().mean():.1%} ({int(pm['r'].notna().sum())}/{len(et)}); "
          f"Python trades {len(tr)}")
    st = E.year_stats(tr)
    print("PYTHON per-year (R):")
    print(st.to_string(index=False))


