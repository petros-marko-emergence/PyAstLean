#!/usr/bin/env python3
"""Run the converted Lean solutions against CP test cases and report correctness.

For every solution that the convert stage marked `ok`, this runs the generated Lean program
once per test case (`lake env lean --run`), feeding `test_<i>.in` on stdin and comparing the
program's stdout to `test_<i>.out` (whitespace-normalized, the standard CP comparison).

As a baseline it also runs the original Python solution against the same tests, so the report
shows whether the Lean translation preserves correctness — not just whether it passes.

Results:
  <problem>/eval/<sol>.json     per-test pass/fail + timing for that solution
  eval_report.json              dataset-wide summary (python vs lean pass rates)

Note: `lake env lean --run` reloads Mathlib (~4s) per invocation, so this is a correctness
harness, not a speed benchmark. Use --max-tests to cap tests per solution while iterating.

Usage:
    python3 cp_harness/evaluate.py --dataset cp_harness/dataset
    python3 cp_harness/evaluate.py --dataset cp_harness/dataset --max-tests 5 --timeout 15
"""

import argparse
import ast
import json
import re
import subprocess
import sys
from pathlib import Path

import _function as fh

REPO_ROOT = Path(__file__).resolve().parent.parent

# A Lean compiler diagnostic header, e.g. `…/sol_0.lean:8:6: warning: unused variable `i``.
# `lake env lean --run` prints these (and their `Note:`/`Hint:` follow-ups) to *stdout* before the
# program's own output, so they must be stripped before comparing against the expected output.
_LEAN_DIAG_HEADER = re.compile(r"\.lean:\d+:\d+:\s+(warning|error|info|note)\b")


def strip_lean_diagnostics(text):
    """Remove Lean compile diagnostics (`…lean:L:C: warning/…`, and `Note:`/`Hint:` follow-ups)
    that `lean --run` emits to stdout, leaving only the program's actual output."""
    kept = []
    for line in text.splitlines():
        stripped = line.strip()
        if _LEAN_DIAG_HEADER.search(line):
            continue
        if stripped.startswith(("Note:", "Hint:")):
            continue
        kept.append(line)
    return "\n".join(kept)


def _maxtests(s):
    """`--max-tests` value → int cap, or 0 (= all) for 'max'/'all'/''."""
    t = str(s).strip().lower()
    return 0 if t in ("max", "all", "-1", "") else int(t)


def normalize(text):
    """CP-standard output normalization: strip trailing whitespace per line and overall."""
    lines = [line.rstrip() for line in text.strip().splitlines()]
    return "\n".join(lines).strip()


def run_python(sol_path, input_text, timeout):
    try:
        proc = subprocess.run(
            ["python3", str(sol_path)],
            input=input_text,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if proc.returncode != 0:
            return None, f"exit {proc.returncode}: {proc.stderr[:200]}"
        return proc.stdout, None
    except subprocess.TimeoutExpired:
        return None, "timeout"
    except Exception as e:  # noqa: BLE001
        return None, str(e)


def run_lean(lean_path, input_text, timeout):
    try:
        proc = subprocess.run(
            ["lake", "env", "lean", "--run", str(lean_path)],
            cwd=REPO_ROOT,
            input=input_text,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if proc.returncode != 0:
            return None, f"exit {proc.returncode}: {proc.stderr[:200]}"
        # `lean --run` prints compile diagnostics to stdout ahead of the program output; drop them.
        return strip_lean_diagnostics(proc.stdout), None
    except subprocess.TimeoutExpired:
        return None, "timeout"
    except Exception as e:  # noqa: BLE001
        return None, str(e)


_PASSED_RE = re.compile(r"PASSED\s+(\d+)/(\d+)")


def run_lean_harness(harness_src, tmp_path, timeout):
    """Write a function-model harness to `tmp_path`, run it with `lean --run`, and parse
    its `PASSED p/t` line. Returns (passed, total) or (None, error)."""
    tmp_path.write_text(harness_src)
    try:
        proc = subprocess.run(
            ["lake", "env", "lean", "--run", str(tmp_path)],
            cwd=REPO_ROOT, capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None, "timeout"
    except Exception as e:  # noqa: BLE001
        return None, str(e)
    out = strip_lean_diagnostics(proc.stdout)
    m = _PASSED_RE.search(out)
    if m:
        return (int(m.group(1)), int(m.group(2))), None
    if proc.returncode != 0:
        return None, f"exit {proc.returncode}: {(proc.stderr or out)[:200]}"
    return None, "no PASSED line in output"


def load_function_cases(prob_dir, params, method):
    """Turn each `tests/tests.json` input into an (args, expected) pair, where **expected
    is what the groundtruth Python produces** for that input (not the dataset's `output`
    string, which mis-types string/None returns via `literal_eval`). This makes the Python
    baseline 100% by construction and gives Lean the true reference value to match."""
    tests_file = prob_dir / "tests" / "tests.json"
    if not tests_file.exists():
        return []
    raw = json.loads(tests_file.read_text())
    fn = fh.load_callable((prob_dir / "solutions" / "sol_0.py").read_text(), method)
    if fn is None:
        return []
    cases = []
    for c in raw:
        try:
            args = fh.parse_test_input(c["input"], params)
        except (ValueError, SyntaxError, KeyError):
            continue
        try:
            expected = fn(*args)  # groundtruth output = the true expected value
        except Exception:  # noqa: BLE001
            continue  # the reference itself errors here → can't judge, skip
        cases.append((args, expected))
    return cases


def evaluate_function_problem(prob_dir, lean_dir, tmp_dir, timeout, max_tests, skip_python):
    """Function-model evaluation (LeetCode-style): call the converted `'rn` function on
    each test case and compare its return value. Returns {sol_name: report} and agg deltas."""
    meta = json.loads((prob_dir / "meta.json").read_text())
    method, params = meta["method"], meta["params"]
    cases = load_function_cases(prob_dir, params, method)
    if max_tests:
        cases = cases[:max_tests]
    prob_report, deltas = {}, {"lean_pass": 0, "lean_total": 0, "py_pass": 0, "py_total": 0, "solutions": 0}
    if not cases:
        return prob_report, deltas

    eval_dir = prob_dir / "eval"
    eval_dir.mkdir(exist_ok=True)
    for status_path in sorted(lean_dir.glob("sol_*.status")):
        if status_path.read_text().strip() != "ok":
            continue
        name = status_path.stem
        converted = (lean_dir / f"{name}.lean").read_text()
        harness, n = fh.build_test_harness(converted, method, cases)
        print(f"[*] {prob_dir.name}/{name} (function) over {n} renderable test(s)...")
        res, err = run_lean_harness(harness, tmp_dir / f"{prob_dir.name}_{name}_harness.lean", timeout)
        lean_pass, lean_total = (res if res else (0, n))
        lean_note = err

        py_pass = py_total = 0
        if not skip_python:
            py_src = (prob_dir / "solutions" / f"{name}.py").read_text()
            py_pass, py_total = fh.run_python_check(py_src, method, cases)

        (eval_dir / f"{name}.json").write_text(json.dumps({
            "model": "function", "method": method,
            "lean": {"passed": lean_pass, "total": lean_total, "error": lean_note},
            "python": {"passed": py_pass, "total": py_total},
        }, indent=2))
        prob_report[name] = {
            "lean": f"{lean_pass}/{lean_total}" + (f" ({lean_note})" if lean_note else ""),
            "python": f"{py_pass}/{py_total}" if py_total else "skipped",
        }
        print(f"    lean {lean_pass}/{lean_total}" + (f"  python {py_pass}/{py_total}" if py_total else "")
              + (f"   [{lean_note}]" if lean_note else ""))
        deltas["lean_pass"] += lean_pass; deltas["lean_total"] += lean_total
        deltas["py_pass"] += py_pass; deltas["py_total"] += py_total
        deltas["solutions"] += 1
    return prob_report, deltas


def evaluate_runner(runner, target_path, tests, timeout):
    """Run `runner` over the test list; return (passed, total, per_test details).

    Each detail records the normalized program output (`output`, `None` on error) so callers can
    compare two runners (Lean vs Python) directly, not just against the expected file.
    """
    passed = 0
    details = []
    for inp_path, out_path in tests:
        input_text = inp_path.read_text()
        expected = normalize(out_path.read_text())
        actual, err = runner(target_path, input_text, timeout)
        if err is not None:
            details.append({"test": inp_path.name, "result": "error", "error": err, "output": None})
            continue
        norm = normalize(actual)
        if norm == expected:
            passed += 1
            details.append({"test": inp_path.name, "result": "pass", "output": norm})
        else:
            details.append({
                "test": inp_path.name,
                "result": "fail",
                "output": norm,
                "got": norm[:200],
                "want": expected[:200],
            })
    return passed, len(tests), details


def collect_divergences(prob_name, sol_name, tests, lean_details, py_details):
    """Compare Lean vs Python output per test and return the divergence records.

    A divergence is any test where the two produce different output. Each is classified — the
    `lean_wrong_python_right` class is the one that matters for runtime/API debugging: Lean ran
    (compiled fine) but disagreed with CPython while CPython was correct, i.e. our runtime/API
    diverges from Python's semantics here.
    """
    expected_by_test = {inp.name: normalize(out.read_text()) for inp, out in tests}
    py_by_test = {d["test"]: d for d in py_details}
    diffs = []
    for ld in lean_details:
        test = ld["test"]
        pd = py_by_test.get(test)
        if pd is None:
            continue
        lean_out, py_out = ld.get("output"), pd.get("output")
        if lean_out == py_out:
            continue  # agree (including both-errored: None == None)
        lean_ok = ld["result"] == "pass"
        py_ok = pd["result"] == "pass"
        if py_ok and not lean_ok:
            classification = "lean_wrong_python_right"  # <- our API/runtime is messing up
        elif lean_ok and not py_ok:
            classification = "lean_right_python_wrong"
        else:
            classification = "both_wrong"
        diffs.append({
            "problem": prob_name,
            "solution": sol_name,
            "test": test,
            "classification": classification,
            "lean_output": (lean_out[:200] if lean_out is not None else None),
            "python_output": (py_out[:200] if py_out is not None else None),
            "expected": expected_by_test.get(test, "")[:200],
            "lean_error": ld.get("error"),
            "python_error": pd.get("error"),
        })
    return diffs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", default="cp_harness/dataset", help="Dataset directory")
    parser.add_argument("--timeout", type=int, default=15, help="Per-run timeout (seconds)")
    parser.add_argument(
        "--max-tests", type=_maxtests, default=0,
        help="Cap tests per solution (0 or 'max'/'all' = all tests)",
    )
    parser.add_argument(
        "--skip-python", action="store_true", help="Skip the Python baseline run"
    )
    args = parser.parse_args()

    dataset = Path(args.dataset)
    if not dataset.is_dir():
        print(f"ERROR: dataset dir not found: {dataset}", file=sys.stderr)
        return 1

    report = {}
    agg = {"lean_pass": 0, "lean_total": 0, "py_pass": 0, "py_total": 0, "solutions": 0}
    divergences = []  # Lean-vs-Python output mismatches on compiling solutions
    tmp_dir = dataset / ".tmp"
    tmp_dir.mkdir(exist_ok=True)

    for prob_dir in sorted(p for p in dataset.iterdir() if p.is_dir() and not p.name.startswith(".")):
        lean_dir = prob_dir / "lean"
        tests_dir = prob_dir / "tests"
        if not (lean_dir.is_dir() and tests_dir.is_dir()):
            continue

        # Function-model problems (LeetCode-style) are tested by calling the converted
        # function, not by stdin/stdout — dispatch on the `kind` marker fetch wrote.
        kind_file = prob_dir / "kind"
        kind = kind_file.read_text().strip() if kind_file.exists() else "stdio"
        if kind == "function":
            prob_report, deltas = evaluate_function_problem(
                prob_dir, lean_dir, tmp_dir, args.timeout, args.max_tests, args.skip_python
            )
            if prob_report:
                report[prob_dir.name] = prob_report
                for k, v in deltas.items():
                    agg[k] += v
            continue

        tests = []
        for inp_path in sorted(tests_dir.glob("test_*.in")):
            out_path = inp_path.with_suffix(".out")
            if out_path.exists():
                tests.append((inp_path, out_path))
        if args.max_tests:
            tests = tests[: args.max_tests]
        if not tests:
            continue

        eval_dir = prob_dir / "eval"
        eval_dir.mkdir(exist_ok=True)

        prob_report = {}
        for status_path in sorted(lean_dir.glob("sol_*.status")):
            if status_path.read_text().strip() != "ok":
                continue
            name = status_path.stem
            lean_path = lean_dir / f"{name}.lean"
            py_path = prob_dir / "solutions" / f"{name}.py"

            print(f"[*] {prob_dir.name}/{name} over {len(tests)} test(s)...")
            lean_pass, lean_total, lean_details = evaluate_runner(
                run_lean, lean_path, tests, args.timeout
            )

            py_pass = py_total = 0
            py_details = []
            if not args.skip_python and py_path.exists():
                py_pass, py_total, py_details = evaluate_runner(
                    run_python, py_path, tests, args.timeout
                )
                # Compare Lean against Python directly to surface runtime/API divergences.
                divergences.extend(
                    collect_divergences(prob_dir.name, name, tests, lean_details, py_details)
                )

            result = {
                "lean": {"passed": lean_pass, "total": lean_total, "details": lean_details},
                "python": {"passed": py_pass, "total": py_total, "details": py_details},
            }
            (eval_dir / f"{name}.json").write_text(json.dumps(result, indent=2))
            prob_report[name] = {
                "lean": f"{lean_pass}/{lean_total}",
                "python": f"{py_pass}/{py_total}" if py_total else "skipped",
            }
            print(
                f"    lean {lean_pass}/{lean_total}"
                + (f"   python {py_pass}/{py_total}" if py_total else "")
            )

            agg["lean_pass"] += lean_pass
            agg["lean_total"] += lean_total
            agg["py_pass"] += py_pass
            agg["py_total"] += py_total
            agg["solutions"] += 1

        if prob_report:
            report[prob_dir.name] = prob_report

    report["_summary"] = agg
    (dataset / "eval_report.json").write_text(json.dumps(report, indent=2))

    # Divergence summary: where compiling Lean disagreed with CPython. The `lean_wrong_python_right`
    # bucket pinpoints runtime/API bugs (Lean ran but produced the wrong answer Python got right).
    by_class = {}
    for d in divergences:
        by_class.setdefault(d["classification"], 0)
        by_class[d["classification"]] += 1
    api_bugs = [d for d in divergences if d["classification"] == "lean_wrong_python_right"]
    # Split the API bugs: a *wrong output* (Lean ran to completion but printed the wrong answer)
    # is a semantic runtime/API bug; a *runtime error/timeout* is a crash/hang/perf issue. The
    # wrong-output ones are the most actionable for fixing PyAPI semantics.
    wrong_output = [d for d in api_bugs if d["lean_output"] is not None]
    runtime_error = [d for d in api_bugs if d["lean_output"] is None]
    divergence_report = {
        "summary": {
            "total_divergences": len(divergences),
            "by_classification": by_class,
            "api_bugs": len(api_bugs),
            "api_bugs_wrong_output": len(wrong_output),
            "api_bugs_runtime_error": len(runtime_error),
        },
        # Most actionable first: wrong-output API bugs, then runtime errors, then the rest.
        "divergences": wrong_output + runtime_error
            + [d for d in divergences if d["classification"] != "lean_wrong_python_right"],
    }
    (dataset / "eval_divergences.json").write_text(json.dumps(divergence_report, indent=2))

    print("\n===== Evaluation summary =====")
    print(f"Solutions evaluated: {agg['solutions']}")
    if agg["lean_total"]:
        print(f"Lean   pass rate: {agg['lean_pass']}/{agg['lean_total']} "
              f"({agg['lean_pass'] / agg['lean_total']:.1%})")
    if agg["py_total"]:
        print(f"Python pass rate: {agg['py_pass']}/{agg['py_total']} "
              f"({agg['py_pass'] / agg['py_total']:.1%})")
    if not args.skip_python:
        print(f"Lean-vs-Python divergences: {len(divergences)} "
              f"(API bugs — Lean wrong, Python right: {len(api_bugs)} "
              f"= {len(wrong_output)} wrong-output + {len(runtime_error)} runtime-error)")
        if wrong_output:
            print("  Wrong-output API bugs (semantic — most actionable):")
            for d in wrong_output[:20]:
                print(f"    {d['problem']}/{d['solution']} {d['test']}")
            if len(wrong_output) > 20:
                print(f"    … and {len(wrong_output) - 20} more (see eval_divergences.json)")
        print(f"Divergence detail written to {dataset / 'eval_divergences.json'}")
    print(f"Report written to {dataset / 'eval_report.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
