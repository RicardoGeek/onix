"""Study 11: cross-asset lead-lag on Pepperstone M15 (2016-2026).  Does what the dollar / silver / equities just did
predict gold's NEXT move?  IC of past cross-asset returns vs forward gold returns, and of the 'gap' between gold's
move and the move implied by the dollar (gold lagging its usual USD response)."""
import pickle
import numpy as np
import pandas as pd

d = pickle.load(open(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\pep_m15_multi.pkl", "rb"))
px = pd.DataFrame({s: v.set_index("time")["close"] for s, v in d.items()}).sort_index()
px = px.dropna(subset=["XAUUSD"])
px = px.ffill(limit=2)
lr = np.log(px).diff()
g = lr["XAUUSD"]
vol = g.rolling(96 * 5, min_periods=200).std()
df = pd.DataFrame(index=px.index)
df["year"] = pd.to_datetime(df.index, unit="s").year
for h in (1, 4, 16):
    df[f"fwd{h}"] = (np.log(px["XAUUSD"]).shift(-h) - np.log(px["XAUUSD"])) / vol
feats = {}
for s in ["EURUSD", "USDJPY", "XAGUSD", "US500", "USDX", "AUDUSD", "USDCHF"]:
    for k in (1, 4):
        r = (np.log(px[s]) - np.log(px[s]).shift(k))
        feats[f"{s}_r{k}"] = r / r.rolling(96 * 5, min_periods=200).std()
for k in (1, 4):
    feats[f"XAU_r{k}"] = (np.log(px["XAUUSD"]) - np.log(px["XAUUSD"]).shift(k)) / vol
# rolling beta of gold on USDX (5-day window), gap = gold move - beta*usd move over last k bars
for k in (1, 4):
    gu = (np.log(px["XAUUSD"]) - np.log(px["XAUUSD"]).shift(k))
    uu = (np.log(px["USDX"]) - np.log(px["USDX"]).shift(k))
    cov = (lr["XAUUSD"] * lr["USDX"]).rolling(480, min_periods=200).mean()
    var = (lr["USDX"] ** 2).rolling(480, min_periods=200).mean()
    beta = (cov / var).shift(1)
    feats[f"gap_usd_k{k}"] = (gu - beta * uu) / vol
    gs = (np.log(px["XAGUSD"]) - np.log(px["XAGUSD"]).shift(k))
    cov2 = (lr["XAUUSD"] * lr["XAGUSD"]).rolling(480, min_periods=200).mean()
    var2 = (lr["XAGUSD"] ** 2).rolling(480, min_periods=200).mean()
    feats[f"gap_xag_k{k}"] = (gu - (cov2 / var2).shift(1) * gs) / vol
F = pd.DataFrame(feats)
df = pd.concat([df, F], axis=1).dropna()
pd.set_option("display.width", 300)
pd.set_option("display.max_columns", 40)
for h in ("fwd1", "fwd4"):
    rows = {}
    for y, gg in df.groupby("year"):
        rows[y] = {f: gg[f].corr(gg[h], method="spearman") for f in F.columns}
    t = pd.DataFrame(rows).T.round(3)
    t.loc["pos"] = (t > 0).sum()
    t.loc["mean"] = t.iloc[:-1].mean()
    print(f"\n=== IC vs gold {h} ===")
    print(t.T.to_string())
