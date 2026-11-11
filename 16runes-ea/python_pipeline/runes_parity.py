"""Parity check: Python 16Runes research replay vs MQL5 EA event log (16runes_events.csv from MT5 Strategy Tester).

Usage:
  python runes_parity.py <16runes_events.csv> [pep|duka]
"""
import os
import sys
import numpy as np
import pandas as pd
import onnxruntime as ort

sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
from runes_study4 import build_dataset, STREAMS
from runes_study7 import extract_features

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ONNX_PATH = os.path.join(ROOT, "MQL5", "Files", "models", "16runes_meta.onnx")
STREAM_NAMES = [s[0] for s in STREAMS]


if __name__ == "__main__":
    ev_path = sys.argv[1]
    src = sys.argv[2] if len(sys.argv) > 2 else "pep"

    m1a, tfs, df = build_dataset(src)
    X = extract_features(df)
    sess = ort.InferenceSession(ONNX_PATH)
    p = np.array([sess.run(None, {"input": X[i:i + 1].astype(np.float32)})[1][0, 1] for i in range(len(X))])
    df["p"] = p
    df["t"] = pd.to_datetime(df["entry_t"], unit="s").astype("datetime64[ns]")
    df["stream_name"] = [STREAM_NAMES[s] for s in df.stream]

    cols = ["srv", "utc", "stream", "rune", "dir", "trig_lvl", "px", "p", "decision"] + [f"f{i}" for i in range(16)]
    ea = pd.read_csv(ev_path, names=cols, skiprows=1)
    ea["t"] = pd.to_datetime(ea.utc, format="%Y.%m.%d %H:%M:%S").astype("datetime64[ns]")
    min_t = ea["t"].min() - pd.Timedelta("5min")
    max_t = ea["t"].max() + pd.Timedelta("5min")
    df_win = df[(df["t"] >= min_t) & (df["t"] <= max_t)].copy()

    print(f"PYTHON ({src}) in tester window: {len(df_win)} triggers")
    print(f"EA (MQL5)                     : {len(ea)} triggers | decisions: {ea.decision.value_counts().to_dict()}")

    m = pd.merge_asof(
        ea.sort_values("t"),
        df_win.sort_values("t"),
        on="t",
        by="dir",
        tolerance=pd.Timedelta("3min"),
        direction="nearest",
        suffixes=("_ea", "_py"),
    )
    matched = m["j"].notna()
    same_stream = matched & (m["stream_ea"] == m["stream_name"])
    same_rune = matched & (m["rune_ea"] == m["rune_py"].map(lambda r: ea.rune.unique()[0] if pd.isna(r) else ""))
    mm = m[matched]
    corr = float(np.corrcoef(mm["p_ea"], mm["p_py"])[0, 1]) if len(mm) > 2 else 1.0
    med_diff = float(np.median(np.abs(mm["p_ea"] - mm["p_py"]))) if len(mm) > 0 else 0.0
    print(f"EA triggers matched to Python (+-3 min, same dir): {matched.mean():.1%} ({int(matched.sum())}/{len(ea)})")
    print(f"Same stream match: {same_stream.mean():.1%}")
    print(f"ONNX score correlation (EA vs Python): r = {corr:.4f} | median |diff| = {med_diff:.5f}")
