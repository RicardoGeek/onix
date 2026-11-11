"""Study 26: consistency-guarded prop challenges.  Daily profit cap (bank the day at <= 30% of the target) x risk x
concurrency x management, 180-day and 365-day limits.  Selection = 2017-2022 starts, unseen = 2023-2026 starts."""
import time
import itertools
import numpy as np
import pandas as pd
import sw_study22 as S22
import sw_sim2 as S2
import sw_challenge as CH

t0 = time.time()
RIBBONS = {"v1.00": (20, 40, 60, 80, 100, 150, 200), "g5x1.8": (5, 9, 16, 29, 52, 94, 170)}
MG = {"prop": S22.MGMT["prop"], "growth": S22.MGMT["growth"],
      "mid": (dict(tp1_r=1.0, tp1_frac=0.3, be_r=0.05, act_r=1.5, tp2_r=3.0, max_min=2880), 1.5, 1.5),
      "tail6": (dict(tp1_r=1.0, tp1_frac=0.0, be_r=0.05, act_r=2.0, tp2_r=6.0, max_min=4320), 1.5, 3.0)}
rows = []
for rname, per in RIBBONS.items():
    ej, ed, ep, ea, es = S22.events(per, 6)
    for mname, (mg, slk, trk) in MG.items():
        tr = S2.run_fills(S22.m1a, ej, ed, ep, slk * ea, trk * ea, mg, one_at_a_time=False, meta={"stream": es})
        for risk, K, cap, days in itertools.product((1.0, 1.5, 2.0), (1, 2), (0.0, 2.4, 1.6), (180, 365)):
            ch = CH.run_challenges(tr, risk, K=K, target=8.0, cons=0.30, daily=3.0, maxdd=6.0, max_days=days,
                                   step_days=7, day_cap_pct=cap)
            a = CH.summarise(ch, 2017, 2022)
            b = CH.summarise(ch, 2023, 2026)
            rows.append(dict(ribbon=rname, mgmt=mname, risk=risk, K=K, cap=cap, limit=days,
                             **{f"is_{k}": v for k, v in a.items()}, **{f"oos_{k}": v for k, v in b.items()}))
        print(f"{time.time() - t0:5.0f}s {rname} {mname}")
R = pd.DataFrame(rows)
R["is_obj"] = R.is_pass_ - R.is_breach * 3 - R.is_med_days.fillna(R.limit) / 6
R.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\challenge_grid3_duka.csv", index=False)
pd.set_option("display.width", 260)
pd.set_option("display.max_columns", 30)
cols = ["ribbon", "mgmt", "risk", "K", "cap", "is_pass_", "is_breach", "is_timeout", "is_med_days", "is_p75_days",
        "oos_pass_", "oos_breach", "oos_timeout", "oos_med_days", "oos_p75_days"]
for lim in (180, 365):
    print(f"\n=== {lim}-day limit: top 15 by in-sample objective ===")
    print(R[R.limit == lim].sort_values("is_obj", ascending=False)[cols].head(15).to_string(index=False))
