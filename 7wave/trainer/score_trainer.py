"""Score the 7Wave blind replay: does the user's eye pick better waves than taking every signal?

    C:\\Users\\faker\\mlv\\Scripts\\python.exe 7wave\\trainer\\score_trainer.py <7wave_trainer_results_*.csv>

Input: the page's "Download results" export (one row per decision, with the signal's outcome).
Compares the user's takes with their skips and with everything shown, with 95% bootstrap intervals, and ranks the
eye with an AUC on the same scale as the AI (0.5 = coin flip; the scorecard's LightGBM got 0.50-0.52).
"""
import sys

import numpy as np
import pandas as pd
from scipy import stats

BOOT = 4000


def auc3(dec, lab):
    """AUC of a 0/1/2 decision for a 0/1 label (ties count half). Works on 1-D arrays or row-wise on 2-D ones."""
    dec, lab = np.atleast_2d(dec), np.atleast_2d(lab)
    npos, nneg = lab.sum(1), (1 - lab).sum(1)
    with np.errstate(invalid="ignore", divide="ignore"):
        p = [((dec == v) & (lab == 1)).sum(1) / npos for v in (0, 1, 2)]
        q = [((dec == v) & (lab == 0)).sum(1) / nneg for v in (0, 1, 2)]
        a = p[1] * q[0] + p[2] * (q[0] + q[1]) + 0.5 * (p[0] * q[0] + p[1] * q[1] + p[2] * q[2])
    return np.where((npos > 0) & (nneg > 0), a, np.nan)


def takes_minus_all(dec, x):
    """Average of x over the takes minus the average over everything, row-wise."""
    dec, x = np.atleast_2d(dec), np.atleast_2d(x)
    t = dec >= 1
    with np.errstate(invalid="ignore", divide="ignore"):
        return (x * t).sum(1) / t.sum(1) - x.mean(1)


def interval(values):
    v = values[np.isfinite(values)]
    return np.percentile(v, [2.5, 97.5]) if len(v) else (np.nan, np.nan)


def line(label, g):
    if len(g) == 0:
        return f"| {label} | 0 | | | | |"
    return (f"| {label} | {len(g)} | {g.good.mean():.0%} | {g.fake.mean():.0%} | {g.R.mean():+.3f} "
            f"| {g.hold_R.mean():+.3f} |")


def report(df, title, seed=1):
    takes, skips = df[df.decision >= 1], df[df.decision == 0]
    out = [f"## {title}", "",
           "| Group | Signals | Good waves | Fakes | Avg R (bracket) | Avg R (holding) |", "|---|---|---|---|---|---|",
           line("Everything shown", df), line("Takes (Take + Strong)", takes),
           line("Strong takes", df[df.decision == 2]), line("Skips", skips), ""]
    if len(takes) >= 5 and len(skips) >= 5:
        p_good = stats.fisher_exact([[takes.good.sum(), len(takes) - takes.good.sum()],
                                     [skips.good.sum(), len(skips) - skips.good.sum()]])[1]
        p_r = stats.ttest_ind(takes.R, skips.R, equal_var=False).pvalue
        p_h = stats.ttest_ind(takes.hold_R, skips.hold_R, equal_var=False).pvalue
        out.append(f"- Takes vs skips: good waves {takes.good.mean():.0%} vs {skips.good.mean():.0%} (p = {p_good:.3f}); "
                   f"bracket R {takes.R.mean():+.3f} vs {skips.R.mean():+.3f} (p = {p_r:.3f}); "
                   f"holding R {takes.hold_R.mean():+.3f} vs {skips.hold_R.mean():+.3f} (p = {p_h:.3f})")
    dec, good = df.decision.to_numpy(), df.good.to_numpy()
    idx = np.random.default_rng(seed).integers(0, len(df), (BOOT, len(df)))
    for col, name in (("R", "bracket R"), ("hold_R", "holding R")):
        x = df[col].to_numpy()
        lo, hi = interval(takes_minus_all(dec[idx], x[idx]))
        out.append(f"- Takes minus everything, {name}: {takes_minus_all(dec, x)[0]:+.3f} "
                   f"(95% interval {lo:+.3f} to {hi:+.3f})")
    a = auc3(dec, good)[0]
    lo, hi = interval(auc3(dec[idx], good[idx]))
    big = auc3(dec, (df.run_R.to_numpy() >= 5).astype(int))[0]
    out.append(f"- Eye AUC for good waves: {a:.3f} (95% interval {lo:.3f} to {hi:.3f}); for 5R+ runs: {big:.3f}. "
               f"Coin flip = 0.500; the scorecard AI = 0.503 (H1) / 0.519 (M15).")
    return out, (a, lo, hi)


def main():
    df = pd.read_csv(sys.argv[1]).sort_values("decided_at").reset_index(drop=True)
    md = [f"# 7Wave blind replay score ({len(df)} decisions)", ""]
    counts = df.decision_name.value_counts()
    md += [f"Decisions: {', '.join(f'{k} {v}' for k, v in counts.items())}. Median time {df.secs.median():.1f} s; "
           f"{(df.secs < 2).sum()} decisions took under 2 s.", ""]
    body, (a, lo, hi) = report(df, "All decisions")
    md += body + [""]
    for tf, g in df.groupby("tf"):
        md += report(g, f"{tf} only")[0] + [""]
    half = len(df) // 2
    if half >= 30:
        md += report(df.iloc[:half], "First half (learning check)")[0] + [""]
        md += report(df.iloc[half:], "Second half")[0] + [""]
    if not np.isfinite(lo):
        verdict = "Not enough decisions yet to judge."
    elif lo > 0.5:
        verdict = (f"Your eye beats chance at the signal: AUC {a:.3f}, and the whole 95% interval is above 0.5. "
                   "That is information the 14 measured contexts and the AI did not have, so these labels are worth "
                   "teaching a model.")
    else:
        verdict = (f"Not distinguishable from chance yet: AUC {a:.3f}, 95% interval {lo:.3f} to {hi:.3f}, which "
                   "includes 0.5. More decisions narrow the interval.")
    md += ["## Verdict", "", verdict]
    print("\n".join(md))


if __name__ == "__main__":
    main()
