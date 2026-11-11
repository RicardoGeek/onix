"""Parity: the indicator's bar-by-bar rules 5-6 (tools/setup_check.py) vs the research engine's minute-by-minute
entries (research/gate_test.py, 7Wave ribbon on H4 + D1), both on Pepperstone data.

The research engine starts its EMAs and swing pools at the first M1 bar it has (2023-01), the indicator copy at the
broker's full history (1998), so only 2024 onward is compared.

    C:\\Users\\faker\\mlv\\Scripts\\python.exe 7wave\\research\\setup_parity.py
"""
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
sys.argv = [sys.argv[0], "pep"]
import gate_test as G  # noqa: E402  (loads Pepperstone M1 2023-2026 through the research engine)
import setup_check as SC  # noqa: E402
import wave_rules as wr  # noqa: E402


def to_server(utc_epoch):
    ny = pd.to_datetime(utc_epoch, unit="s").tz_localize("UTC").tz_convert("America/New_York").tz_localize(None)
    return ny + pd.Timedelta(hours=7)  # server time = New York + 7h


def main():
    flt = G.agree(G.on_h1(G.stack("H4", wr.PERIODS), "H4"), G.on_h1(G.stack("D1", wr.PERIODS), "D1"))
    j, d, _ = G.events(flt)
    res = pd.DataFrame({"time": to_server(G.m1a["t"][j]).floor("h"), "dir": d})
    h1, h4, d1, point = SC.fetch("XAUUSD")
    sig = SC.setup_signals(h1, h4, d1, point)
    rep = sig[sig.entry != 0][["time", "entry"]].rename(columns={"entry": "dir"})
    end = res.time.max()
    res = res[(res.time >= "2024-01-01") & (res.time <= end)]
    rep = rep[(rep.time >= "2024-01-01") & (rep.time <= end)]
    a = set(map(tuple, res[["time", "dir"]].astype(str).values))
    b = set(map(tuple, rep[["time", "dir"]].astype(str).values))
    print(f"2024-01 to {end:%Y-%m-%d}: research {len(a)} entries, indicator copy {len(b)}, same bar and direction {len(a & b)}")
    print(f"  match: {len(a & b) / max(len(a), 1):.0%} of the research entries, {len(a & b) / max(len(b), 1):.0%} of the copy's")
    for name, extra in (("only in the research", sorted(a - b)), ("only in the copy", sorted(b - a))):
        print(f"  {name} ({len(extra)}): " + ", ".join(f"{t[:16]} {'BUY' if t[1] == '1' else 'SELL'}" if False else
                                                       f"{x[0][:16]} {'BUY' if x[1] == '1' else 'SELL'}" for x in extra[:12])
              + (" ..." if len(extra) > 12 else ""))


if __name__ == "__main__":
    main()
