#!/usr/bin/env python3
"""Fetch CP problems from DeepMind CodeContests whose Python3 solutions only import `math`.

For each kept problem we save:
    <out>/<problem>/problem.txt              the statement
    <out>/<problem>/solutions/sol_<i>.py     math-only Python3 solutions
    <out>/<problem>/tests/test_<i>.in/.out   the (long) test cases

A solution is kept only if a static scan of its imports finds nothing but `math`. This is a
deliberately conservative pre-filter: solutions that pass the import check may still fail to
convert/compile downstream — those are reported by the convert stage, not here.

Usage:
    python3 cp_harness/fetch.py --num 20 --out cp_harness/dataset
    python3 cp_harness/fetch.py --problems <name1> <name2> --out cp_harness/dataset
"""

import argparse
import ast
import json
import os
import sys
from pathlib import Path

import _function as fh

PYTHON3_LANG_ID = 3  # CodeContests language id for Python 3
ALLOWED_IMPORTS = {"math"}


def parse_count(s):
    """`--num` value → an int limit, or None for 'no limit' (the whole dataset).
    Accepts `max` / `all` / `-1` / `inf` (case-insensitive) as unlimited."""
    t = str(s).strip().lower()
    if t in ("max", "all", "-1", "inf", ""):
        return None
    return int(t)


def imported_modules(source):
    """Return the set of top-level module names a Python source imports, or None if it
    does not parse (syntactically invalid solutions are dropped)."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return None
    modules = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                modules.add(alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                modules.add(node.module.split(".")[0])
    return modules


def is_math_only(source):
    """True if the solution parses and imports nothing outside the allowed set."""
    mods = imported_modules(source)
    if mods is None:
        return False
    return mods.issubset(ALLOWED_IMPORTS)


def sanitize_problem_name(name):
    """The on-disk directory name for a CodeContests problem `name`."""
    return name.replace("/", "_").replace(" ", "_")


def load_excluded(exclude_path):
    """Read the persistent exclude list (one sanitized problem name per line; `#` comments and
    blank lines ignored). Problems listed here are never (re-)downloaded — used to drop problems
    that are not usable for exact-match correctness checking (e.g. special-judge / multiple-valid
    -answer problems where even a correct solution's output differs from the stored expected)."""
    path = Path(exclude_path)
    if not path.exists():
        return set()
    names = set()
    for line in path.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            names.add(line)
    return names


def save_problem(out_dir, name, item, max_solutions):
    prob_name = sanitize_problem_name(name)
    prob_dir = out_dir / prob_name

    languages = item["solutions"]["language"]
    sources = item["solutions"]["solution"]
    math_only = [
        sources[i]
        for i, lang in enumerate(languages)
        if lang == PYTHON3_LANG_ID and is_math_only(sources[i])
    ]
    if not math_only:
        return False

    all_inputs = (
        item["public_tests"]["input"]
        + item["private_tests"]["input"]
        + item["generated_tests"]["input"]
    )
    all_outputs = (
        item["public_tests"]["output"]
        + item["private_tests"]["output"]
        + item["generated_tests"]["output"]
    )
    if not all_inputs:
        return False

    prob_dir.mkdir(parents=True, exist_ok=True)
    (prob_dir / "kind").write_text("stdio")   # test model: stdin → stdout
    (prob_dir / "problem.txt").write_text(item.get("description", ""))

    sols_dir = prob_dir / "solutions"
    sols_dir.mkdir(exist_ok=True)
    for i, src in enumerate(math_only[:max_solutions]):
        (sols_dir / f"sol_{i}.py").write_text(src)

    tests_dir = prob_dir / "tests"
    tests_dir.mkdir(exist_ok=True)
    for i, (inp, outp) in enumerate(zip(all_inputs, all_outputs)):
        (tests_dir / f"test_{i}.in").write_text(inp)
        (tests_dir / f"test_{i}.out").write_text(outp)

    print(
        f"[+] {prob_name}: {len(math_only[:max_solutions])} math-only solution(s), "
        f"{len(all_inputs)} test(s)"
    )
    return True


def save_leetcode_problem(out_dir, item, max_solutions):
    """Save one LeetCode problem: the entry method extracted as a standalone function,
    the `input_output` test cases, and a `kind` marker. Returns True if kept."""
    task_id = item.get("task_id") or f"q{item.get('question_id')}"
    prob_dir = out_dir / sanitize_problem_name(task_id)

    method = fh.entry_method_name(item.get("entry_point", ""))
    fn_src = fh.extract_function(item.get("completion", ""), method)
    if not fn_src:
        return False  # couldn't isolate a self-contained function
    try:
        params = fh.param_names(fn_src)
    except SyntaxError:
        return False

    cases = item.get("input_output") or []
    if not cases:
        return False

    prob_dir.mkdir(parents=True, exist_ok=True)
    (prob_dir / fh.KIND_FILE).write_text(fh.KIND_FUNCTION)
    (prob_dir / "problem.txt").write_text(item.get("problem_description", ""))
    (prob_dir / "meta.json").write_text(json.dumps(
        {"task_id": task_id, "method": method, "params": params,
         "difficulty": item.get("difficulty")}, indent=2))

    sols_dir = prob_dir / "solutions"
    sols_dir.mkdir(exist_ok=True)
    # sol_0 = the reference completion's entry method, as a free function (this is what py2lean converts).
    (sols_dir / "sol_0.py").write_text(fn_src + "\n")
    # reference_test.py = the ORIGINAL, self-contained groundtruth: the dataset's import prelude
    # (typing/collections/ListNode/…) + the full `Solution` completion + the assert-based `test` +
    # a `check(entry_point)` call. Running it should exit 0 — i.e. the groundtruth passes 100%.
    prompt = item.get("prompt", "")
    completion = item.get("completion", "")
    test = item.get("test", "")
    entry = item.get("entry_point", method)
    (sols_dir / "reference_test.py").write_text(
        f"{prompt}\n\n{completion}\n\n{test}\n\ncheck({entry})\n"
    )

    tests_dir = prob_dir / "tests"
    tests_dir.mkdir(exist_ok=True)
    (tests_dir / "tests.json").write_text(json.dumps(list(cases), indent=2))
    (tests_dir / "asserts.py").write_text(test + "\n")  # the original assert-based tests, as-is

    print(f"[+] {task_id}: fn `{method}({', '.join(params)})`, {len(cases)} test(s)")
    return True


def fetch_leetcode(args):
    try:
        from datasets import load_dataset
    except ImportError:
        print("ERROR: `datasets` not installed. Run: pip install datasets", file=sys.stderr)
        return 1
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    print("[*] Streaming newfacade/LeetCodeDataset (train split)...")
    ds = load_dataset("newfacade/LeetCodeDataset", split="train", streaming=True)
    excluded = load_excluded(args.exclude_file)
    kept = scanned = 0
    for item in ds:
        scanned += 1
        task = item.get("task_id", "")
        if args.problems and task not in args.problems:
            continue
        if sanitize_problem_name(task) in excluded:
            continue
        if save_leetcode_problem(out_dir, item, args.max_solutions):
            kept += 1
        if not args.problems and args.num is not None and kept >= args.num:
            break
        if scanned % 100 == 0:
            print(f"    ...scanned {scanned}, kept {kept}")
    print(f"\n[*] Done. Kept {kept} LeetCode problem(s) into {out_dir}")
    return 0


def fetch_codecontests(args):
    """Adapter: DeepMind CodeContests, math-only Python3 solutions (stdio model)."""
    excluded = load_excluded(args.exclude_file)
    if excluded:
        print(f"[*] Excluding {len(excluded)} problem(s) from {args.exclude_file}")
    try:
        from datasets import load_dataset
    except ImportError:
        print("ERROR: `datasets` not installed. Run: pip install datasets", file=sys.stderr)
        return 1
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"[*] Streaming CodeContests ({args.split} split)...")
    ds = load_dataset("deepmind/code_contests", split=args.split, streaming=True)
    kept = scanned = 0
    for item in ds:
        scanned += 1
        name = item["name"]
        if args.problems and name not in args.problems:
            continue
        if sanitize_problem_name(name) in excluded:
            continue  # never re-download excluded (non-exact-judge / unusable) problems
        if save_problem(out_dir, name, item, args.max_solutions):
            kept += 1
        if not args.problems and args.num is not None and kept >= args.num:
            break
        if scanned % 50 == 0:
            print(f"    ...scanned {scanned}, kept {kept}")
    print(f"\n[*] Done. Kept {kept} problem(s) with math-only solutions into {out_dir}")
    return 0


# ---- source registry ------------------------------------------------------------
# A *source adapter* pulls one HuggingFace dataset and writes the normalized on-disk
# layout, tagging every problem with a `kind` file naming its TEST MODEL:
#
#   "stdio"     the solution reads stdin / prints stdout; tests are `test_<i>.in/.out`
#               (CodeContests). convert wraps it in a `__main__` guard; evaluate feeds stdin.
#   "function"  the solution is a callable; tests are `tests/tests.json` [{input, output}]
#               (LeetCode). convert transpiles the bare function; evaluate calls it.
#
# To support a NEW dataset, write one adapter `fetch_<name>(args)` that normalizes it into
# one of these two models and register it below. convert.py / evaluate.py need no changes —
# they dispatch purely on the `kind` marker, so any new function/stdio dataset works for free.
SOURCES = {
    "codecontests": fetch_codecontests,   # stdio model
    "leetcode": fetch_leetcode,           # function model
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source", required=True, choices=sorted(SOURCES),
        help="Dataset adapter (required, no default): " + ", ".join(sorted(SOURCES)),
    )
    parser.add_argument("--out", default="cp_harness/dataset", help="Output directory")
    parser.add_argument(
        "--num", type=parse_count, default=10,
        help="Number of problems to keep, or 'max'/'all' for the whole dataset",
    )
    parser.add_argument("--max-solutions", type=int, default=3, help="Max solutions per problem")
    parser.add_argument("--problems", nargs="*", default=None, help="Specific problem names/ids")
    parser.add_argument("--split", default="test", help="CodeContests split (test/valid/train)")
    parser.add_argument(
        "--exclude-file", default="cp_harness/excluded_problems.txt",
        help="Problem names to never (re-)download (one per line, # comments)",
    )
    args = parser.parse_args()
    return SOURCES[args.source](args)


if __name__ == "__main__":
    raise SystemExit(main())
