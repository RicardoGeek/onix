"""SevenWave data layer: one clean UTC M1 gold dataset for research, training and verification.

Sources (all real broker / LP data, nothing synthetic):
  DUKA : Dukascopy XAUUSD M1 bid bars 2016-12 .. 2026-09 (binary files made for the XAUUSD_D custom symbol,
         float64 rows: server_epoch, open, high, low, close, volume; server time = New York + 7h).
  PEP  : Pepperstone XAUUSD M1 bars 2023-01 .. 2026-09 with per-bar average/max spread
         (Common\\Files\\of_pep_XAUUSD_20230101.csv, server time = New York + 7h).
  LIVE : (optional) fresh Pepperstone M1 bars pulled through the MetaTrader5 API up to today.

Everything is converted to UTC with the real US DST calendar (server = NY + 7h on these feeds), so the research
never depends on any broker's clock.  Cached as .npz in goldie_research\\sevenwave\\data.

  python sw_data.py            # build caches
"""
import os
import sys
import numpy as np
import pandas as pd

ROOT = r"C:\Users\faker\Documents\goldie_research\sevenwave"
DATA = os.path.join(ROOT, "data")
PEP_TERMINAL = r"C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\73B7A2420D6397DFF9014A20F1201F97"
FILES = os.path.join(PEP_TERMINAL, "MQL5", "Files")
COMMON = r"C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
os.makedirs(DATA, exist_ok=True)


def server_to_utc(server_epoch: np.ndarray) -> np.ndarray:
    """Server time (NY+7h, i.e. UTC+2 winter / UTC+3 summer) epoch seconds -> UTC epoch seconds."""
    ny_local = pd.to_datetime(server_epoch.astype(np.int64) - 7 * 3600, unit="s")
    loc = ny_local.tz_localize("America/New_York", ambiguous="NaT", nonexistent="shift_forward")
    utc = loc.tz_convert("UTC").tz_localize(None)
    out = utc.values.astype("datetime64[s]").astype(np.int64)
    bad = pd.isna(loc)
    if bad.any():  # ambiguous fall-back hour (market is closed then anyway): assume EST
        out[bad] = server_epoch[bad].astype(np.int64) - 2 * 3600
    return out


def load_duka() -> pd.DataFrame:
    parts = []
    for name in ("duka_xau_m1.bin", "duka_xau_m1_2022b.bin"):
        a = np.fromfile(os.path.join(FILES, name), dtype="<f8").reshape(-1, 6)
        parts.append(a)
    a = np.concatenate(parts)
    srv = a[:, 0].astype(np.int64)
    df = pd.DataFrame({"srv": srv, "open": a[:, 1], "high": a[:, 2], "low": a[:, 3], "close": a[:, 4], "vol": a[:, 5]})
    df = df.drop_duplicates("srv", keep="last").sort_values("srv").reset_index(drop=True)
    df["t"] = server_to_utc(df["srv"].values)
    df["spread"] = np.nan  # bid-only feed: spread modelled from PEP (see cost model)
    return df


def load_pep_csv() -> pd.DataFrame:
    p = os.path.join(COMMON, "of_pep_XAUUSD_20230101.csv")
    d = pd.read_csv(p)
    df = pd.DataFrame({"srv": d["t"].astype(np.int64), "open": d["o"], "high": d["h"], "low": d["l"], "close": d["c"],
                       "vol": d["n"].astype(float), "spread": d["sp"].astype(float), "spread_max": d["spx"].astype(float)})
    df = df.drop_duplicates("srv", keep="last").sort_values("srv").reset_index(drop=True)
    df["t"] = server_to_utc(df["srv"].values)
    return df


def load_pep_live(start_srv: int) -> pd.DataFrame:
    """Fresh Pepperstone M1 bars via the MetaTrader5 API (terminal must be installed; it is started if needed)."""
    import MetaTrader5 as mt5
    exe = r"C:\Program Files\Pepperstone MetaTrader 5\terminal64.exe"
    if not mt5.initialize(path=exe):
        print("MT5 initialize failed", mt5.last_error())
        return pd.DataFrame()
    try:
        info = mt5.symbol_info("XAUUSD")
        point = info.point if info else 0.01
        mt5.symbol_select("XAUUSD", True)
        frm = pd.Timestamp(start_srv, unit="s").to_pydatetime()
        to = pd.Timestamp.now().to_pydatetime() + pd.Timedelta(days=2)
        r = mt5.copy_rates_range("XAUUSD", mt5.TIMEFRAME_M1, frm, to)
        if r is None or len(r) == 0:
            print("no live bars", mt5.last_error())
            return pd.DataFrame()
        r = pd.DataFrame(r)
    finally:
        mt5.shutdown()
    df = pd.DataFrame({"srv": r["time"].astype(np.int64), "open": r["open"], "high": r["high"], "low": r["low"],
                       "close": r["close"], "vol": r["tick_volume"].astype(float),
                       "spread": r["spread"].astype(float) * point, "spread_max": r["spread"].astype(float) * point})
    df["t"] = server_to_utc(df["srv"].values)
    return df


def save(df: pd.DataFrame, name: str):
    cols = {c: df[c].values for c in df.columns}
    np.savez_compressed(os.path.join(DATA, name + ".npz"), **cols)
    print(f"{name}: {len(df):,} bars  {pd.Timestamp(df['t'].iloc[0], unit='s')} .. {pd.Timestamp(df['t'].iloc[-1], unit='s')} UTC")


def load(name: str) -> pd.DataFrame:
    z = np.load(os.path.join(DATA, name + ".npz"))
    return pd.DataFrame({k: z[k] for k in z.files})


if __name__ == "__main__":
    duka = load_duka()
    save(duka, "duka_m1")
    pep = load_pep_csv()
    if "--live" in sys.argv:
        live = load_pep_live(int(pep["srv"].iloc[-1]) - 86400)
        if len(live):
            pep = pd.concat([pep, live]).drop_duplicates("srv", keep="last").sort_values("srv").reset_index(drop=True)
    save(pep, "pep_m1")
