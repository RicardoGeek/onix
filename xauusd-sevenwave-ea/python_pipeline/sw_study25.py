"""Study 25: push R-per-day for prop challenges: higher risk, deeper concurrency (pyramids into proven waves), bigger
trend tails.  Same challenge rules (+8%, best day <= 30%, 3% daily / 6% trailing, 180 days, weekly starts)."""
import time
import itertools
import numpy as np
import pandas as pd
import sw_study22 as S22
import sw_sim2 as S2
import sw_challenge as CH

t0 = time.time()
RIBBONS = {"v1.00": (20, 40, 60, 80, 100, 150, 200), "g5x1.8": (5, 9, 16, 29, 52, 94, 170),
           "g20x1.8": (20, 36, 65, 117, 210, 378, 680)}
MG = {"growth": S22.MGMT["growth"],
      "mid": (dict(tp1_r=1.0, tp1_frac=0.3, be_r=0.05, act_r=1.5, tp2_r=3.0, max_min=2880), 1.5, 1.5),
      "tail4": (dict(tp1_r=1.0, tp1_frac=0.0, be_r=0.05, act_r=1.5, tp2_r=4.0, max_min=2880), 1.5, 2.5),
      "tail6": (dict(tp1_r=1.0, tp1_frac=0.0, be_r=0.05, act_r=2.0, tp2_r=6.0, max_min=4320), 1.5, 3.0)}
rows = []
for rname, per in RIBBONS.items():
    ej, ed, ep, ea, es = S22.events(per, 6)
    for mname, (mg, slk, trk) in MG.items():
        tr = S2.run_fills(S22.m1a, ej, ed, ep, slk * ea, trk * ea, mg, one_at_a_time=False, meta={"stream": es})
        e_r = tr.r.mean()
        for risk, K in itertools.product((1.0, 1.5, 2.0, 3.0), (1, 2, 3, 4)):
            ch = CH.run_challenges(tr, risk, K=K, target=8.0, cons=0.30, daily=3.0, maxdd=6.0, max_days=180, step_days=7)
            a = CH.summarise(ch, 2017, 2022)
            b = CH.summarise(ch, 2023, 2026)
            rows.append(dict(ribbon=rname, mgmt=mname, avgR=round(e_r, 3), risk=risk, K=K,
                             **{f"is_{k}": v for k, v in a.items()}, **{f"oos_{k}": v for k, v in b.items()}))
        print(f"{time.time() - t0:5.0f}s {rname} {mname} avgR(indep)={e_r:+.3f}")
R = pd.DataFrame(rows)
R["is_obj"] = R.is_pass_ - R.is_breach * 3 - R.is_med_days.fillna(180) / 6
R.to_csv(r"C:\Users\faker\Documents\goldie_research\sevenwave\data\challenge_grid2_duka.csv", index=False)
pd.set_option("display.width", 260)
pd.set_option("display.max_columns", 30)
cols = ["ribbon", "mgmt", "avgR", "risk", "K", "is_pass_", "is_breach", "is_timeout", "is_med_days", "is_p75_days",
        "oos_pass_", "oos_breach", "oos_timeout", "oos_med_days", "oos_p75_days"]
print("\n=== top 25 by in-sample objective ===")
print(R.sort_values("is_obj", ascending=False)[cols].head(25).to_string(index=False))
