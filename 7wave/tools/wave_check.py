"""Independent Python replica of 7Wave rules 2-4 (RULES.md), to cross-check the stars and arrows on the chart.

Reads bars from the running Pepperstone terminal (read-only) and lists where the signals should be.
Times are broker server time, the same as on the chart. The rules themselves live in wave_rules.py.

    C:\\Users\\faker\\mlv\\Scripts\\python.exe 7wave\\tools\\wave_check.py [SYMBOL] [DAYS] [LAST_K]
"""
import os
import sys

import MetaTrader5 as mt5
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wave_rules import STAR_MIN_IN_ORDER, emas, signals_for  # noqa: E402

PATH = r"C:\Program Files\Pepperstone MetaTrader 5\terminal64.exe"
SYMBOL = sys.argv[1] if len(sys.argv) > 1 else "XAUUSD"
DAYS = int(sys.argv[2]) if len(sys.argv) > 2 else 14
LAST_K = int(sys.argv[3]) if len(sys.argv) > 3 else 10
TFS = {"H1": mt5.TIMEFRAME_H1, "M15": mt5.TIMEFRAME_M15, "M5": mt5.TIMEFRAME_M5}
BARS = 20000   # enough history for the EMAs and the states to settle
SETTLE = 2000  # bars skipped before counting

if not mt5.initialize(path=PATH):
    print("initialize failed:", mt5.last_error())
    sys.exit(1)
try:
    for name, tf in TFS.items():
        df = pd.DataFrame(mt5.copy_rates_from_pos(SYMBOL, tf, 0, BARS))
        df["time"] = pd.to_datetime(df["time"], unit="s")  # broker server time, as on the chart
        ema = emas(df["close"].to_numpy())
        sig, st = signals_for(df["open"].to_numpy(), df["close"].to_numpy(), ema, settle=SETTLE)
        last = df["time"].iloc[-1]
        days = (last - df["time"].iloc[SETTLE]).days or 1
        arrows = [s for s in sig if s[1] == "arrow" and s[0] >= SETTLE]
        stars = [s for s in sig if s[1] == "star" and s[0] >= SETTLE]
        print(f"{SYMBOL} {name}: {df['time'].iloc[SETTLE]:%Y-%m-%d} to {last:%Y-%m-%d %H:%M} ({days} days)")
        print(f"  arrows: one every {days / max(len(arrows), 1):.2f} days ({st['arrow_waited']} waited for "
              f"their candle, {st['arrow_cancelled']} cancelled while waiting)")
        print(f"  stars : one every {days / max(len(stars), 1):.2f} days ({st['star_waited']} waited for "
              f"their candle, {st['star_cancelled']} cancelled while waiting, {st['star_rejected']} full crosses "
              f"with fewer than {STAR_MIN_IN_ORDER} lines in the old order)")
        for i, kind, d, due in sig[-LAST_K:]:
            waited = f"  (due {df['time'][due]:%a %m-%d %H:%M}, waited for its candle)" if due != i else ""
            print(f"  {df['time'][i]:%a %Y-%m-%d %H:%M}  {kind:<5} {'UP' if d > 0 else 'DOWN':<4} "
                  f"EMA140 = {ema[i][6]:.2f}{waited}")
finally:
    mt5.shutdown()
