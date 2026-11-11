"""Study 24: optimise SevenWave for PROP CHALLENGES (cadence + consistency), selection on 2017-2022 start dates only.

Grid: ribbon gate x management x risk per trade x concurrency.  Challenge: +8% target, best day <= 30% of profit,
3% daily / 6% trailing floors, 180-day limit, a new $100k challenge every week.
"""
import sys
import time
import itertools
import numpy as np
import pandas as pd
import sw_study22 as S22
import sw_sim2 as S2
import sw_challenge as CH

t0 = time.time()
RIBBONS = {"v1.00": (20, 40, 60, 80, 100, 150, 200), "g5x1.8": (5, 9, 16, 29, 52, 94, 170),
           "g20x1.8": (20, 36, 65, 117, 210, 378, 680), "g30x1.8": (30, 54, 97, 175, 315, 567, 1020)}
MG = {"prop": S22.MGMT["prop"], "growth": S22.MGMT["growth"],
      "mid": (dict(tp1_r=1.0, tp1_frac=0.3, be_r=0.05, act_r=1.5, tp2_r=3.0, max_min=2880), 1.5, 1.5)}
rows = []
for rname, per in RIBBONS.items():
    ev = S22.events(per, 6)
    ej, ed, ep, ea, es = ev
    for mname, (mg, slk, trk) in MG.items():
        tr = S2.run_fills(S22.m1a, ej, ed, ep, slk * ea, trk * ea, mg, one_at_a_time=False, meta={"stream": es})
        for risk, K in itertools.product((0.5, 0.75, 1.0, 1.5, 2.0), (1, 2)):
            ch = CH.run_challenges(tr, risk, K=K, target=8.0, cons=0.30, daily=3.0, maxdd=6.0, max_days=180, step_days=7)
            a = CH.summarise(ch, 2017, 2022)
            b = CH.summarise(ch, 2023, 2026)
            rows.append(dict(ribbon=rname, mgmt=mname, risk=risk, K=K, **{f"is_{k}": v for k, v in a.items()},
                             **{f"oos_{k}": v for k, v in b.items()}))
        print(f"{time.time() - t0:5.0f}s {rname} {mname}")
R = pd.DataFrame(rows)
R["is_obj"] = R.is_pass_ - R.is_breach * 2 - R.is_med_days.fillna(180) / 6
R.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\challenge_grid_duka.csv", index=False)
pd.set_option("display.width", 260)
pd.set_option("display.max_columns", 30)
cols = ["ribbon", "mgmt", "risk", "K", "is_n", "is_pass_", "is_breach", "is_timeout", "is_med_days", "is_p75_days",
        "oos_n", "oos_pass_", "oos_breach", "oos_timeout", "oos_med_days", "oos_p75_days"]
print("\n=== top 20 by in-sample objective (pass% - 2*breach% - median days/6) ===")
print(R.sort_values("is_obj", ascending=False)[cols].head(20).to_string(index=False))
print("\n=== v1.00 EA defaults (prop mgmt, 0.75%, K=1) ===")
print(R[(R.ribbon == "v1.00") & (R.mgmt == "prop") & (R.risk == 0.75) & (R.K == 1)][cols].to_string(index=False))
