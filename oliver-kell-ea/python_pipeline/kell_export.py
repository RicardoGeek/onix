"""Train + export the Oliver Kell ONNX Meta-Labeler (native MT5 contract, zipmap=False).

Training data: Dukascopy 2017-01 .. 2023-12 Oliver Kell Cycle setups across 5 streams (H1, H2, M30, M15, M5).
2024-2026 is NEVER seen during training or threshold selection, so 2024-2026 is 100% out-of-sample.

Outputs:
  MQL5/Files/models/oliver_kell_meta.onnx          input "input" float32[1,16] -> "label" int64[1], "probabilities" float32[1,2]
  MQL5/Include/OliverKell/AiModelMeta.mqh          thresholds + feature order + training stamp
  python_pipeline/models/oliver_kell_meta.json
"""
import os
import sys
import json
import numpy as np
import pandas as pd
import onnx
import onnxruntime as ort
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\xauusd-sevenwave-ea\python_pipeline")
sys.path.insert(0, r"c:\Users\faker\Documents\dev\onix\16runes-ea\python_pipeline")
from kell_study1 import SETUP_NAMES
from kell_study4 import STREAMS
from kell_study8 import build_final_dataset, extract_final_features, KELL_FEATS_16
from runes_study10_moonshot import portfolio_moonshot_nb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ONNX_PATH = os.path.join(ROOT, "MQL5", "Files", "models", "oliver_kell_meta.onnx")
META_MQH = os.path.join(ROOT, "MQL5", "Include", "OliverKell", "AiModelMeta.mqh")
META_JSON = os.path.join(ROOT, "python_pipeline", "models", "oliver_kell_meta.json")
TRAIN_END_YEAR = 2023

if __name__ == "__main__":
    m1a_d, tfs_d, df_d = build_final_dataset("duka")
    X = extract_final_features(df_d)
    r = df_d["r"].values
    yr = df_d["year"].values
    sel = yr <= TRAIN_END_YEAR
    y = (r > 0.0).astype(np.int64)

    clf = Pipeline([
        ("sc", StandardScaler()),
        ("lr", LogisticRegression(C=0.05, max_iter=500, random_state=42))
    ])
    clf.fit(X[sel], y[sel])

    onx = convert_sklearn(
        clf,
        initial_types=[("input", FloatTensorType([1, X.shape[1]]))],
        options={id(clf.named_steps["lr"]): {"zipmap": False}},
        target_opset=13,
    )
    os.makedirs(os.path.dirname(ONNX_PATH), exist_ok=True)
    onnx.save(onx, ONNX_PATH)

    sess = ort.InferenceSession(ONNX_PATH)
    print("ONNX inputs :", [(i.name, i.shape, i.type) for i in sess.get_inputs()])
    print("ONNX outputs:", [(o.name, o.shape, o.type) for o in sess.get_outputs()])

    p_ref = clf.predict_proba(X)[:, 1]
    p_onx = np.array([sess.run(None, {"input": X[i:i + 1].astype(np.float32)})[1][0, 1] for i in range(len(X))])
    max_diff = float(np.max(np.abs(p_ref - p_onx)))
    print(f"ONNX parity max |diff| across all {len(X)} rows = {max_diff:.2e}")

    thr_htf  = float(np.quantile(p_onx[sel], 0.12))
    thr_m5   = float(np.quantile(p_onx[sel], 0.35))
    thr_high = float(np.quantile(p_onx[sel], 0.65))
    print(f"Trained on {sel.sum()} setups (2017-{TRAIN_END_YEAR}): thr_htf(q12)={thr_htf:.6f}, thr_m5(q35)={thr_m5:.6f}, thr_high(q65)={thr_high:.6f}")

    w_arr = np.array([1.0, 1.0, 0.90, 0.80, 0.60])
    df_d["p"] = p_onx
    sub = df_d[((df_d.stream < 4) & (df_d.p >= thr_htf)) | ((df_d.stream == 4) & (df_d.p >= thr_m5))].reset_index(drop=True)
    for mode_nm, res_htf, two_st, wtp, hi_m in [
        ("Prop (3 slots, M5 reserves 2, 5R Exhaustion TP)", 2, False, 5.0, 1.15),
        ("Growth Moonshot (3 slots, M5 reserves 1, 2-Stage Scale-In, 7R Exhaustion TP)", 1, True, 7.0, 1.30),
    ]:
        tk, pr, a1, a2, _ = portfolio_moonshot_nb(
            sub.j.values, sub.dir.values, sub.px.values, sub.R.values, sub.trail.values, sub.stream.values,
            m1a_d["t"], m1a_d["o"], m1a_d["h"], m1a_d["l"], m1a_d["c"], m1a_d["spr"], m1a_d["tday"], m1a_d["nydow"],
            3, res_htf, two_st, 1.5, 0.05, 2.75, 1.60, 1.0, 3.0, wtp, 1.5, 1440, 4320, 0.07, 0.10, 0.05, -0.80, 0.0
        )
        m = tk == 1
        sw = w_arr[sub.stream.values[m]] * np.where(sub.p.values[m] >= thr_high, hi_m, 1.0)
        tot_r = (pr[m] + (a1[m] + 0.5 * a2[m]) * (1.0 if two_st else 0.0)) * sw
        yrs = sub.year.values[m]
        by_y = pd.Series(tot_r).groupby(yrs).sum()
        print(f"  Weighted [{mode_nm}]: probes={m.sum()}  total={tot_r.sum():+.1f}R  green_yrs={int((by_y > 0).sum())}/{len(by_y)}")
        print("    Years:", "  ".join(f"{y}:{v:+.1f}R" for y, v in by_y.items()))

    meta = dict(
        features=KELL_FEATS_16,
        thr_htf=thr_htf,
        thr_m5=thr_m5,
        thr_high=thr_high,
        train_years=f"2017-{TRAIN_END_YEAR}",
        n_train=int(sel.sum()),
        model_type="StandardScaler + LogisticRegression(C=0.05)",
        setups=SETUP_NAMES,
        streams=[s[0] for s in STREAMS],
        weights=w_arr.tolist(),
    )
    os.makedirs(os.path.dirname(META_JSON), exist_ok=True)
    with open(META_JSON, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)

    os.makedirs(os.path.dirname(META_MQH), exist_ok=True)
    with open(META_MQH, "w", encoding="utf-8") as fh:
        fh.write("//+------------------------------------------------------------------+\n")
        fh.write("//| AiModelMeta.mqh - generated by python_pipeline/kell_export.py    |\n")
        fh.write("//+------------------------------------------------------------------+\n")
        fh.write("#ifndef OLIVERKELL_AIMODELMETA_MQH\n#define OLIVERKELL_AIMODELMETA_MQH\n")
        fh.write(f"#define OK_AI_FEATURES {len(KELL_FEATS_16)}\n")
        fh.write(f"#define OK_AI_THR_HTF  {thr_htf:.8f}\n")
        fh.write(f"#define OK_AI_THR_M5   {thr_m5:.8f}\n")
        fh.write(f"#define OK_AI_THR_HIGH {thr_high:.8f}\n")
        fh.write(f"#define OK_AI_STAMP    \"Duka 2017-{TRAIN_END_YEAR}, {int(sel.sum())} setups, LogReg C=0.05\"\n")
        fh.write("// feature order: " + ", ".join(KELL_FEATS_16) + "\n#endif\n")

    print("Exported:", ONNX_PATH, META_MQH, META_JSON)
