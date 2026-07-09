#!/usr/bin/env python3
"""Plot LeetCode coverage by difficulty — one grouped bar chart.

Reads a fetched + converted + evaluated dataset and buckets every function-model
(LeetCode) problem, by difficulty, into three outcomes:

    * didn't compile          — convert_fail / compile_fail
    * compiled, not all passed — Lean elaborated but some (or no) test cases failed
    * compiled, all passed     — Lean elaborated and every test case passed

X axis = difficulty (Easy / Medium / Hard); three bars each; Y axis = #problems.

Usage:
    python3 cp_harness/plot.py --dataset cp_harness/dataset_leetcode
    python3 cp_harness/plot.py --dataset <dir> --out coverage.png
"""
import argparse
import json
from pathlib import Path

CATS = ["didn't compile", "compiled · not all passed", "compiled · all passed"]
COLORS = ["#d9534f", "#f0ad4e", "#5cb85c"]  # red / amber / green
DIFF_ORDER = ["Easy", "Medium", "Hard"]


def classify(prob_dir):
    """(difficulty, category_index) for a function-model problem, or None to skip."""
    kind_f = prob_dir / "kind"
    if not (kind_f.exists() and kind_f.read_text().strip() == "function"):
        return None
    meta_f = prob_dir / "meta.json"
    diff = "Unknown"
    if meta_f.exists():
        diff = json.loads(meta_f.read_text()).get("difficulty") or "Unknown"

    status_f = prob_dir / "lean" / "sol_0.status"
    if not status_f.exists():
        return None  # not converted yet — not counted
    if status_f.read_text().strip() != "ok":
        return diff, 0  # didn't compile

    eval_f = prob_dir / "eval" / "sol_0.json"
    if not eval_f.exists():
        return diff, 1  # compiled, but no evaluation → not-all-passed
    lean = json.loads(eval_f.read_text()).get("lean", {})
    passed, total = lean.get("passed", 0), lean.get("total", 0)
    return (diff, 2) if (total > 0 and passed == total) else (diff, 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dataset", default="cp_harness/dataset_leetcode", help="Dataset directory")
    ap.add_argument("--out", default=None, help="PNG path (default: <dataset>/coverage_by_difficulty.png)")
    ap.add_argument("--title", default=None, help="Chart title override")
    args = ap.parse_args()

    dataset = Path(args.dataset)
    if not dataset.is_dir():
        print(f"ERROR: dataset not found: {dataset}")
        return 1

    counts = {}  # difficulty -> [c0, c1, c2]
    n = 0
    for prob in sorted(p for p in dataset.iterdir() if p.is_dir() and not p.name.startswith(".")):
        r = classify(prob)
        if r is None:
            continue
        diff, ci = r
        counts.setdefault(diff, [0, 0, 0])[ci] += 1
        n += 1

    # order difficulties Easy/Medium/Hard first, then any extras
    diffs = [d for d in DIFF_ORDER if d in counts] + [d for d in counts if d not in DIFF_ORDER]
    if not diffs:
        print("No converted function-model problems found. Run fetch → convert → evaluate first.")
        return 1

    # text summary
    print(f"{n} problem(s) classified across {len(diffs)} difficulty level(s):")
    print(f"  {'difficulty':<10}{'no-compile':>12}{'partial':>10}{'all-pass':>10}{'total':>8}")
    for d in diffs:
        c = counts[d]
        print(f"  {d:<10}{c[0]:>12}{c[1]:>10}{c[2]:>10}{sum(c):>8}")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    x = np.arange(len(diffs))
    w = 0.26
    fig, ax = plt.subplots(figsize=(max(6, 2.2 * len(diffs)), 5))
    for i, cat in enumerate(CATS):
        vals = [counts[d][i] for d in diffs]
        bars = ax.bar(x + (i - 1) * w, vals, w, label=cat, color=COLORS[i], edgecolor="white")
        ax.bar_label(bars, padding=2, fontsize=9)
    ax.set_xticks(x)
    ax.set_xticklabels(diffs)
    ax.set_ylabel("number of problems")
    ax.set_xlabel("difficulty")
    ax.set_title(args.title or f"PastaLean on LeetCode — coverage by difficulty  (n = {n})")
    ax.legend(frameon=False)
    ax.spines[["top", "right"]].set_visible(False)
    ax.margins(y=0.12)

    out = Path(args.out) if args.out else dataset / "coverage_by_difficulty.png"
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    print(f"\nSaved chart → {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
