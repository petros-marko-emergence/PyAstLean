#!/usr/bin/env python3
"""`CPastaEval` — fetch, convert, evaluate, and plot competitive-programming datasets.

One object owns a dataset directory and drives the whole pipeline:

    from cpasta_eval import CPastaEval

    with CPastaEval("cp_harness/dataset_leetcode", source="leetcode") as ev:
        ev.fetch(num="max")          # once; downloading is the slow network step
        ev.convert()                 # Python -> Lean -> compile-check
        ev.evaluate()                # run Lean and CPython on the test cases
        ev.plot()                    # coverage-by-difficulty chart

Two TEST MODELS, recorded per problem in a `kind` file, so several sources coexist in one dataset:

    "stdio"     the solution reads stdin and prints stdout; tests are `test_<i>.in/.out`
                (CodeContests). Wrapped in a `__main__` guard, then compared per test.
    "function"  the solution is a callable; tests are `tests/tests.json`
                (LeetCode). The converted `fn'rn` is called and its return value compared.

Adding a source means writing one `_save_*` method and registering it in `SOURCES`; convert and
evaluate need no changes because they dispatch on `kind`.

CLI:
    python3 cp_harness/cpasta_eval.py run --source leetcode --num max
    python3 cp_harness/cpasta_eval.py run --skip-fetch --random 29
    python3 cp_harness/cpasta_eval.py convert --dataset cp_harness/dataset_leetcode
"""
from __future__ import annotations

import argparse
import ast
import json
import random
import re
import subprocess
import sys
from pathlib import Path

from pastalean import Session  # `uv pip install -e .`

REPO_ROOT = Path(__file__).resolve().parent.parent

KIND_FILE = "kind"
KIND_FUNCTION = "function"
KIND_STDIO = "stdio"

PYTHON3_LANG_ID = 3          # CodeContests language id for Python 3
ALLOWED_IMPORTS = {"math"}   # CodeContests pre-filter: keep math-only solutions

# `lean --run` prints diagnostics like `…/sol_0.lean:8:6: warning: …` to *stdout*, ahead of the
# program's own output, so they must be stripped before comparing.
_LEAN_DIAG_HEADER = re.compile(r"\.lean:\d+:\d+:\s+(warning|error|info|note)\b")
_PASSED_RE = re.compile(r"PASSED\s+(\d+)/(\d+)")
_FAIL_RE = re.compile(r"^FAIL (\d+): got (.*)$", re.MULTILINE)

CATS = ["didn't compile", "compiled · not all passed", "compiled · all passed"]
COLORS = ["#d9534f", "#f0ad4e", "#5cb85c"]
DIFF_ORDER = ["Easy", "Medium", "Hard"]

# The LeetCode dataset's `prompt` star-imports these; a solution execs standalone only with them.
_PRELUDE = (
    "from typing import *\nfrom math import *\nfrom collections import *\n"
    "from functools import *\nfrom itertools import *\nfrom heapq import *\n"
    "from bisect import *\nimport re\ninf = float('inf')\n"
)


# --------------------------------------------------------------------------------------
# Parsing / normalization helpers
# --------------------------------------------------------------------------------------

def parse_count(s):
    """`--num` value → an int limit, or None for no limit. `max`/`all`/`-1`/`inf` mean unlimited."""
    t = str(s).strip().lower()
    return None if t in ("max", "all", "-1", "inf", "") else int(t)


def parse_max_tests(s):
    """`--max-tests` value → int cap, or 0 (all) for `max`/`all`/`-1`/``."""
    t = str(s).strip().lower()
    return 0 if t in ("max", "all", "-1", "") else int(t)


def sanitize_problem_name(name):
    """The on-disk directory name for a problem."""
    return name.replace("/", "_").replace(" ", "_")


def strip_lean_diagnostics(text):
    """Drop the Lean compile diagnostics `lean --run` writes to stdout, leaving program output."""
    kept = []
    for line in text.splitlines():
        if _LEAN_DIAG_HEADER.search(line) or line.strip().startswith(("Note:", "Hint:")):
            continue
        kept.append(line)
    return "\n".join(kept)


def normalize(text):
    """CP-standard output normalization: strip trailing whitespace per line and overall."""
    return "\n".join(line.rstrip() for line in text.strip().splitlines()).strip()


def summarize_error(status, log_text):
    """A concise one-line reason from a failing stage's output."""
    lines = [ln.rstrip() for ln in (log_text or "").splitlines() if ln.strip()]
    if not lines:
        return "(no error output)"
    if status == "convert_fail":
        for ln in reversed(lines):
            if "Error generating code:" in ln:
                return ln.split("Error generating code:", 1)[1].strip()
        return lines[-1].strip()
    for ln in lines:  # compile_fail: first Lean diagnostic mentioning an error
        low = ln.lower()
        if "error" in low and ":" in ln:
            tail = ln[low.find("error"):]
            for sep in ("): ", "error: "):
                if sep in tail:
                    return tail.split(sep, 1)[1].strip()
            return tail.strip()
    return lines[0].strip()


# --------------------------------------------------------------------------------------
# stdio model: wrap bare top-level code in a `__main__` guard so py2lean emits `def main`
# --------------------------------------------------------------------------------------

def has_main_entry(source):
    """True if the source already defines `main` or uses a `__main__` guard."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "main":
            return True
        if isinstance(node, ast.If):
            test = node.test
            if isinstance(test, ast.Compare) and isinstance(test.left, ast.Name) \
                    and test.left.id == "__name__":
                return True
    return False


def wrap_for_main(source):
    """Wrap bare top-level code under `if __name__ == "__main__":`, keeping imports at module
    scope (Lean and Python both need them there). No-op when a `main` entry already exists."""
    if has_main_entry(source):
        return source
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return source
    import_lines = set()
    for node in tree.body:
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            import_lines.update(range(node.lineno, (node.end_lineno or node.lineno) + 1))
    imports, body = [], []
    for i, line in enumerate(source.splitlines(), start=1):
        (imports if i in import_lines else body).append(line)
    indented = "\n".join(("    " + ln) if ln.strip() else ln for ln in body)
    parts = ([("\n".join(imports))] if any(l.strip() for l in imports) else []) \
        + ['if __name__ == "__main__":', indented]
    return "\n".join(parts) + "\n"


def imported_modules(source):
    """Top-level module names a source imports, or None if it does not parse."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return None
    modules = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules.update(a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            modules.add(node.module.split(".")[0])
    return modules


# --------------------------------------------------------------------------------------
# function model (LeetCode): extract the entry method, render test cases, build a Lean harness
# --------------------------------------------------------------------------------------

def entry_method_name(entry_point):
    """`Solution().twoSum` (or `twoSum`) → `twoSum`."""
    return entry_point.strip().rstrip("()").split(".")[-1].strip()


def extract_function(completion_src, method_name):
    """The entry method as a standalone top-level `def` with `self` dropped, or None. Methods that
    touch `self.<x>` depend on siblings and are not isolatable."""
    try:
        tree = ast.parse(completion_src)
    except SyntaxError:
        return None
    target = next((n for n in ast.walk(tree)
                   if isinstance(n, ast.FunctionDef) and n.name == method_name), None)
    if target is None:
        return None
    for sub in ast.walk(target):
        if isinstance(sub, ast.Attribute) and isinstance(sub.value, ast.Name) \
                and sub.value.id == "self":
            return None
    target.args.args = [a for a in target.args.args if a.arg != "self"]
    target.decorator_list = []
    try:
        return ast.unparse(target)
    except Exception:  # noqa: BLE001
        return None


def _bound_names(tree):
    """Names bound anywhere in `tree`: assign targets, params, def/class names, imports, excepts."""
    bound = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store):
            bound.add(n.id)
        elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            bound.add(n.name)
        elif isinstance(n, ast.arg):
            bound.add(n.arg)
        elif isinstance(n, ast.alias):
            bound.add((n.asname or n.name).split(".")[0])
        elif isinstance(n, ast.ExceptHandler) and n.name:
            bound.add(n.name)
    return bound


def _free_names(src_or_node):
    """Names read without being bound first."""
    tree = ast.parse(src_or_node) if isinstance(src_or_node, str) else src_or_node
    bound = _bound_names(tree)
    return {n.id for n in ast.walk(tree)
            if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load) and n.id not in bound}


def _toplevel_binder_names(stmt):
    """The top-level names a prompt statement binds (`def f`, `class C`, `inf = ...`)."""
    if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        return {stmt.name}
    if isinstance(stmt, ast.Assign):
        return {t.id for t in stmt.targets if isinstance(t, ast.Name)}
    if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
        return {stmt.target.id}
    return set()


def _reachable_statements(stmts, seed_names):
    """The top-level statements of `stmts` that `seed_names` reaches transitively, in source order."""
    binders, order = {}, []
    for stmt in stmts:
        names = _toplevel_binder_names(stmt)
        if names:
            order.append(stmt)
            for nm in names:
                binders[nm] = stmt
    needed, worklist = set(), list(seed_names)
    while worklist:
        stmt = binders.get(worklist.pop())
        if stmt is None or id(stmt) in needed:
            continue
        needed.add(id(stmt))
        worklist.extend(_free_names(stmt))
    return [s for s in order if id(s) in needed]


def prompt_preamble(prompt_src, fn_src):
    """The dataset's `prompt`, verbatim, keeping every import plus only the top-level definitions
    `fn_src` reaches transitively.

    Keeps `inf = float('inf')` when the solution reads `inf`; drops the unreached `ListNode` /
    `tree_node` test scaffolding.
    """
    try:
        prompt_tree = ast.parse(prompt_src)
    except SyntaxError:
        return ""
    imports = [s for s in prompt_tree.body if isinstance(s, (ast.Import, ast.ImportFrom))]
    kept = imports + _reachable_statements(prompt_tree.body, _free_names(fn_src))
    return "\n".join(ast.unparse(s) for s in kept)


def completion_helpers(completion_src, fn_src):
    """The completion's own top-level helpers that the entry method needs.

    A solution may define a sibling class or function beside `class Solution` (a
    `BinaryIndexedTree`, a `SegmentTree`). Extracting only the entry method drops those and the
    file no longer runs at all, so keep the ones it reaches.
    """
    try:
        tree = ast.parse(completion_src)
    except SyntaxError:
        return ""
    kept = _reachable_statements(tree.body, _free_names(fn_src))
    return "\n\n".join(ast.unparse(s) for s in kept)


def self_contained_source(prompt_src, completion_src, fn_src):
    """The dataset's preamble + the completion's reachable helpers + the extracted function, each
    pruned to what the solution actually uses."""
    helpers = completion_helpers(completion_src, fn_src)
    body = (helpers + "\n\n" + fn_src) if helpers else fn_src
    pre = prompt_preamble(prompt_src, body)
    return (pre + "\n\n" + body) if pre else body


def param_names(fn_src):
    """Positional parameter names of the first top-level `def`, in order."""
    tree = ast.parse(fn_src)
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef))
    return [a.arg for a in fn.args.args]


def parse_test_input(input_str, order):
    """`'nums = [3,3], target = 6'` + `['nums','target']` → `[[3,3], 6]`."""
    call = ast.parse(f"__f__({input_str})", mode="eval").body
    if not isinstance(call, ast.Call):
        raise ValueError("input is not a call-args string")
    kw = {k.arg: ast.literal_eval(k.value) for k in call.keywords}
    pos = [ast.literal_eval(a) for a in call.args]
    args = []
    for i, name in enumerate(order):
        if name in kw:
            args.append(kw[name])
        elif i < len(pos):
            args.append(pos[i])
        else:
            raise ValueError(f"missing argument {name!r}")
    return args


def py_lit_to_lean(v):
    """Render a Python literal as a Lean literal, or None if unrenderable (dict, None, object)."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return f"({v} : Int)"
    if isinstance(v, float):
        return f"({v} : Float)"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if v is None:
        return None
    if isinstance(v, (list, tuple)):
        parts = [py_lit_to_lean(x) for x in v]
        return None if any(p is None for p in parts) else "[" + ", ".join(parts) + "]"
    return None


def build_test_harness(converted_lean, fn_name, cases):
    """Append a `main` calling the computable `fn'rn` twin on each case, printing `PASSED p/t` and a
    `FAIL <idx>: got <value>` line per failing case. Cases with an unrenderable argument or expected
    value are skipped. Returns (source, runnable_indices)."""
    rn = f"{fn_name}'rn"
    checks, runnable = [], []
    for idx, (args, expected) in enumerate(cases):
        arg_lits = [py_lit_to_lean(a) for a in args]
        exp_lit = py_lit_to_lean(expected)
        if exp_lit is None or any(a is None for a in arg_lits):
            continue
        call = rn + " " + " ".join(f"({a})" for a in arg_lits)
        checks.append("  _t := _t + 1")
        # Print what Lean actually computed, so a failure is debuggable without a rerun. Every
        # renderable expected type (Int/Float/String/Bool/List) has a `Repr` instance.
        checks.append(f'  if ({call}) == ({exp_lit}) then _p := _p + 1 '
                      f'else IO.println s!"FAIL {idx}: got {{repr ({call})}}"')
        runnable.append(idx)
    body = "\n".join(
        [converted_lean.rstrip(), "", "def main : IO Unit := do",
         "  let mut _p := 0", "  let mut _t := 0"]
        + checks + ['  IO.println s!"PASSED {_p}/{_t}"', ""])
    return body, runnable


def load_callable(fn_src, method):
    """Exec `fn_src` (with the star-import prelude) and return the `method` callable, or None."""
    ns = {}
    try:
        exec(_PRELUDE + fn_src, ns)  # noqa: S102
    except Exception:  # noqa: BLE001
        return None
    fn = ns.get(method)
    if callable(fn):
        return fn
    try:
        name = next(n.name for n in ast.parse(fn_src).body if isinstance(n, ast.FunctionDef))
    except (SyntaxError, StopIteration):
        return None
    return ns.get(name)


def run_python_check(fn_src, method, cases):
    """Run the groundtruth against `cases` (whose expected values it produced). Returns (p, t)."""
    fn = load_callable(fn_src, method)
    if fn is None:
        return 0, 0
    passed = total = 0
    for args, expected in cases:
        total += 1
        try:
            if fn(*args) == expected:
                passed += 1
        except Exception:  # noqa: BLE001
            pass
    return passed, total


# --------------------------------------------------------------------------------------
# The harness
# --------------------------------------------------------------------------------------

class CPastaEval:
    """Fetch, convert, evaluate, and plot one CP dataset directory."""

    def __init__(self, dataset, *, source=None, timeout=15, max_tests=0, skip_python=False,
                 random_n=None, seed=0, problems=None, max_solutions=3, split="test",
                 exclude_file="cp_harness/excluded_problems.txt"):
        self.dataset = Path(dataset)
        self.source = source
        self.timeout = timeout
        self.max_tests = max_tests
        self.skip_python = skip_python
        self.random_n = random_n
        self.seed = seed
        self.problem_names = list(problems) if problems else None
        self.max_solutions = max_solutions
        self.split = split
        self.exclude_file = Path(exclude_file)
        self._session = None

    # -- lifecycle ---------------------------------------------------------------------

    @property
    def session(self):
        """The warm Lean backend, booted on first use. Strict: no `pyUnsupported` degradation."""
        if self._session is None:
            self._session = Session(target="command", mode="both", best_effort=False).start()
        return self._session

    def close(self):
        if self._session is not None:
            self._session.close()
            self._session = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()

    @property
    def tmp_dir(self):
        d = self.dataset / ".tmp"
        d.mkdir(parents=True, exist_ok=True)
        return d

    # -- selection ---------------------------------------------------------------------

    def all_problems(self):
        """Every problem directory, sorted by name."""
        if not self.dataset.is_dir():
            return []
        return sorted(p for p in self.dataset.iterdir()
                      if p.is_dir() and not p.name.startswith("."))

    def problems(self):
        """The problem directories this run operates on: `problems` filter, then `random_n`.

        Seeded, so convert / evaluate / plot all see the *same* subset for a given seed.
        """
        probs = self.all_problems()
        if self.problem_names:
            wanted = set(self.problem_names)
            probs = [p for p in probs if p.name in wanted]
        if self.random_n is not None and self.random_n < len(probs):
            probs = sorted(random.Random(self.seed).sample(probs, self.random_n))
        return probs

    def kind_of(self, prob_dir):
        """The test model a problem was fetched under: `"function"` or `"stdio"`."""
        kind_file = prob_dir / KIND_FILE
        return kind_file.read_text().strip() if kind_file.exists() else KIND_STDIO

    def load_excluded(self):
        """Problem names never to (re-)download; `#` comments and blanks ignored."""
        if not self.exclude_file.exists():
            return set()
        names = set()
        for line in self.exclude_file.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                names.add(line)
        return names

    # -- fetch -------------------------------------------------------------------------

    def fetch(self, num=10):
        """Download `num` problems (None / 'max' = the whole dataset) from `self.source`."""
        if self.source not in self.SOURCES:
            raise ValueError(f"--source must be one of {sorted(self.SOURCES)}, got {self.source!r}")
        if isinstance(num, str):
            num = parse_count(num)
        self.dataset.mkdir(parents=True, exist_ok=True)
        return self.SOURCES[self.source](self, num)

    def _stream(self, repo, split):
        try:
            from datasets import load_dataset
        except ImportError as e:  # pragma: no cover
            raise SystemExit("ERROR: `datasets` not installed. Run: pip install datasets") from e
        return load_dataset(repo, split=split, streaming=True)

    def _fetch_loop(self, stream, save, num, excluded, log_every):
        kept = scanned = 0
        for item in stream:
            scanned += 1
            if save(item, excluded):
                kept += 1
            if not self.problem_names and num is not None and kept >= num:
                break
            if scanned % log_every == 0:
                print(f"    ...scanned {scanned}, kept {kept}")
        print(f"\n[*] Done. Kept {kept} problem(s) into {self.dataset}")
        return 0

    def fetch_codecontests(self, num):
        """DeepMind CodeContests, Python3 solutions importing only `math`. Model: stdio."""
        excluded = self.load_excluded()
        print(f"[*] Streaming CodeContests ({self.split} split)...")
        stream = self._stream("deepmind/code_contests", self.split)
        return self._fetch_loop(stream, self._save_codecontests_problem, num, excluded, 50)

    def fetch_leetcode(self, num):
        """`newfacade/LeetCodeDataset`: the entry method as a free function. Model: function."""
        excluded = self.load_excluded()
        print("[*] Streaming newfacade/LeetCodeDataset (train split)...")
        stream = self._stream("newfacade/LeetCodeDataset", "train")
        return self._fetch_loop(stream, self._save_leetcode_problem, num, excluded, 100)

    #: Source adapters. Each writes the normalized layout and tags every problem with its `kind`.
    SOURCES = {
        "codecontests": fetch_codecontests,   # stdio model
        "leetcode": fetch_leetcode,           # function model
    }

    def _save_codecontests_problem(self, item, excluded):
        name = item["name"]
        if self.problem_names and name not in self.problem_names:
            return False
        prob_name = sanitize_problem_name(name)
        if prob_name in excluded:
            return False

        languages, sources = item["solutions"]["language"], item["solutions"]["solution"]
        math_only = [
            sources[i] for i, lang in enumerate(languages)
            if lang == PYTHON3_LANG_ID
            and (mods := imported_modules(sources[i])) is not None
            and mods.issubset(ALLOWED_IMPORTS)
        ]
        inputs = (item["public_tests"]["input"] + item["private_tests"]["input"]
                  + item["generated_tests"]["input"])
        outputs = (item["public_tests"]["output"] + item["private_tests"]["output"]
                   + item["generated_tests"]["output"])
        if not math_only or not inputs:
            return False

        prob_dir = self.dataset / prob_name
        prob_dir.mkdir(parents=True, exist_ok=True)
        (prob_dir / KIND_FILE).write_text(KIND_STDIO)
        (prob_dir / "problem.txt").write_text(item.get("description", ""))
        sols_dir = prob_dir / "solutions"
        sols_dir.mkdir(exist_ok=True)
        for i, src in enumerate(math_only[: self.max_solutions]):
            (sols_dir / f"sol_{i}.py").write_text(src)
        tests_dir = prob_dir / "tests"
        tests_dir.mkdir(exist_ok=True)
        for i, (inp, outp) in enumerate(zip(inputs, outputs)):
            (tests_dir / f"test_{i}.in").write_text(inp)
            (tests_dir / f"test_{i}.out").write_text(outp)
        print(f"[+] {prob_name}: {len(math_only[: self.max_solutions])} math-only solution(s), "
              f"{len(inputs)} test(s)")
        return True

    def _save_leetcode_problem(self, item, excluded):
        task_id = item.get("task_id") or f"q{item.get('question_id')}"
        if self.problem_names and task_id not in self.problem_names:
            return False
        prob_name = sanitize_problem_name(task_id)
        if prob_name in excluded:
            return False

        method = entry_method_name(item.get("entry_point", ""))
        fn_src = extract_function(item.get("completion", ""), method)
        if not fn_src:
            return False  # not a self-contained function
        try:
            params = param_names(fn_src)
        except SyntaxError:
            return False
        cases = item.get("input_output") or []
        if not cases:
            return False

        prob_dir = self.dataset / prob_name
        prob_dir.mkdir(parents=True, exist_ok=True)
        (prob_dir / KIND_FILE).write_text(KIND_FUNCTION)
        (prob_dir / "problem.txt").write_text(item.get("problem_description", ""))
        (prob_dir / "meta.json").write_text(json.dumps(
            {"task_id": task_id, "method": method, "params": params,
             "difficulty": item.get("difficulty")}, indent=2))

        sols_dir = prob_dir / "solutions"
        sols_dir.mkdir(exist_ok=True)
        # The dataset's `prompt` preamble binds `inf`, `Counter`, `List`, … which the completion
        # reads freely; without it the extracted function is not even valid Python.
        prompt = item.get("prompt", "")
        completion = item.get("completion", "")
        (sols_dir / "sol_0.py").write_text(
            self_contained_source(prompt, completion, fn_src) + "\n")
        (sols_dir / "_prompt.py").write_text(prompt + "\n")  # untouched, for provenance

        tests_dir = prob_dir / "tests"
        tests_dir.mkdir(exist_ok=True)
        (tests_dir / "tests.json").write_text(json.dumps(list(cases), indent=2))
        (tests_dir / "asserts.py").write_text(item.get("test", "") + "\n")
        print(f"[+] {task_id}: fn `{method}({', '.join(params)})`, {len(cases)} test(s)")
        return True

    # -- convert -----------------------------------------------------------------------

    def compile_check(self, lean_path):
        """Elaborate a generated Lean file; return (ok, error_text)."""
        proc = subprocess.run(["lake", "env", "lean", str(lean_path)],
                              cwd=REPO_ROOT, capture_output=True, text=True)
        return (True, "") if proc.returncode == 0 else (False, proc.stderr or proc.stdout)

    def convert_solution(self, sol_path, lean_dir, wrap):
        """Translate one solution and compile-check it. Returns (status, concise_error_or_None)."""
        name = sol_path.stem
        source = sol_path.read_text()
        # stdio solutions are bare top-level code; function solutions must NOT be wrapped, or the
        # `def` ends up nested inside the guard and disappears.
        if wrap:
            src_path = self.tmp_dir / f"{name}_wrapped.py"
            src_path.write_text(wrap_for_main(source))
        else:
            src_path = sol_path

        status_path = lean_dir / f"{name}.status"
        log_path = lean_dir / f"{name}.log"

        try:
            result = self.session.translate_file(src_path)
        except Exception as e:  # noqa: BLE001  (a backend crash must not kill the sweep)
            result = None
            error_text = f"{type(e).__name__}: {e}"
        else:
            error_text = result.error or "empty output"

        if result is None or not result.ok or not (result.lean_code or "").strip():
            status_path.write_text("convert_fail")
            log_path.write_text(error_text)
            return "convert_fail", summarize_error("convert_fail", error_text)

        lean_path = lean_dir / f"{name}.lean"
        lean_path.write_text(result.lean_code)

        ok, err = self.compile_check(lean_path)
        if not ok:
            status_path.write_text("compile_fail")
            log_path.write_text(err)
            return "compile_fail", summarize_error("compile_fail", err)

        status_path.write_text("ok")
        log_path.unlink(missing_ok=True)
        return "ok", None

    def convert(self):
        """Translate + compile-check every selected problem. Writes `convert_summary.json`."""
        problems, totals, histogram = {}, {"ok": 0, "convert_fail": 0, "compile_fail": 0}, {}
        for prob_dir in self.problems():
            sols_dir = prob_dir / "solutions"
            if not sols_dir.is_dir():
                continue
            lean_dir = prob_dir / "lean"
            lean_dir.mkdir(exist_ok=True)
            wrap = self.kind_of(prob_dir) != KIND_FUNCTION

            prob_results = {}
            for sol_path in sorted(sols_dir.glob("sol_*.py")):
                status, error = self.convert_solution(sol_path, lean_dir, wrap)
                prob_results[sol_path.name] = {"status": status}
                if error is not None:
                    prob_results[sol_path.name]["error"] = error
                    histogram[error] = histogram.get(error, 0) + 1
                totals[status] += 1
                print(f"[{status:>12}] {prob_dir.name}/{sol_path.name}"
                      + (f"  -- {error}" if error else ""))
            problems[prob_dir.name] = prob_results

        top_errors = dict(sorted(histogram.items(), key=lambda kv: kv[1], reverse=True))
        summary = {"totals": totals, "errors_by_frequency": top_errors, "problems": problems}
        (self.dataset / "convert_summary.json").write_text(json.dumps(summary, indent=2))

        print(f"\n[*] Conversion: {totals['ok']} ok, {totals['compile_fail']} compile_fail, "
              f"{totals['convert_fail']} convert_fail")
        if top_errors:
            print("[*] Most common failures:")
            for reason, count in list(top_errors.items())[:10]:
                print(f"      {count:>3}x  {reason}")
        print(f"[*] Summary written to {self.dataset / 'convert_summary.json'}")
        return summary

    # -- evaluate ----------------------------------------------------------------------

    def _run_process(self, cmd, input_text=None, cwd=None):
        try:
            proc = subprocess.run(cmd, input=input_text, capture_output=True, text=True,
                                  timeout=self.timeout, cwd=cwd)
        except subprocess.TimeoutExpired:
            return None, "timeout"
        except Exception as e:  # noqa: BLE001
            return None, str(e)
        if proc.returncode != 0:
            return None, f"exit {proc.returncode}: {proc.stderr[:200]}"
        return proc.stdout, None

    def run_python(self, sol_path, input_text):
        return self._run_process(["python3", str(sol_path)], input_text)

    def run_lean(self, lean_path, input_text):
        out, err = self._run_process(["lake", "env", "lean", "--run", str(lean_path)],
                                     input_text, cwd=REPO_ROOT)
        return (strip_lean_diagnostics(out), None) if err is None else (None, err)

    def run_lean_harness(self, harness_src, tmp_path):
        """Run a function-model harness. Returns `(counts, failures, error)` where `counts` is
        `(passed, total)` or None, and `failures` maps a failing case index to what Lean computed."""
        tmp_path.write_text(harness_src)
        try:
            proc = subprocess.run(["lake", "env", "lean", "--run", str(tmp_path)],
                                  cwd=REPO_ROOT, capture_output=True, text=True, timeout=self.timeout)
        except subprocess.TimeoutExpired:
            return None, {}, "timeout"
        except Exception as e:  # noqa: BLE001
            return None, {}, str(e)
        out = strip_lean_diagnostics(proc.stdout)
        failures = {int(i): got.strip() for i, got in _FAIL_RE.findall(out)}
        if (m := _PASSED_RE.search(out)):
            return (int(m.group(1)), int(m.group(2))), failures, None
        if proc.returncode != 0:
            return None, failures, f"exit {proc.returncode}: {(proc.stderr or out)[:200]}"
        return None, failures, "no PASSED line in output"

    def load_function_cases(self, prob_dir, params, method):
        """`(args, expected)` per test, where **expected is what the groundtruth produces** — the
        dataset's `output` string mis-types string/None returns through `literal_eval`."""
        tests_file = prob_dir / "tests" / "tests.json"
        if not tests_file.exists():
            return []
        fn = load_callable((prob_dir / "solutions" / "sol_0.py").read_text(), method)
        if fn is None:
            return []
        cases = []
        for c in json.loads(tests_file.read_text()):
            try:
                args = parse_test_input(c["input"], params)
            except (ValueError, SyntaxError, KeyError):
                continue
            try:
                cases.append((args, fn(*args)))
            except Exception:  # noqa: BLE001
                continue  # the reference itself errors here → can't judge
        return cases

    def _evaluate_function_problem(self, prob_dir, lean_dir):
        meta = json.loads((prob_dir / "meta.json").read_text())
        method, params = meta["method"], meta["params"]
        cases = self.load_function_cases(prob_dir, params, method)
        if self.max_tests:
            cases = cases[: self.max_tests]
        report, deltas = {}, {"lean_pass": 0, "lean_total": 0, "py_pass": 0, "py_total": 0, "solutions": 0}
        diverged = []
        if not cases:
            return report, deltas, diverged

        eval_dir = prob_dir / "eval"
        eval_dir.mkdir(exist_ok=True)
        for status_path in sorted(lean_dir.glob("sol_*.status")):
            if status_path.read_text().strip() != "ok":
                continue
            name = status_path.stem
            harness, runnable = build_test_harness(
                (lean_dir / f"{name}.lean").read_text(), method, cases)
            n = len(runnable)
            print(f"[*] {prob_dir.name}/{name} (function) over {n} renderable test(s)...")
            harness_path = self.tmp_dir / f"{prob_dir.name}_{name}_harness.lean"
            res, got_by_idx, err = self.run_lean_harness(harness, harness_path)
            lean_pass, lean_total = res if res else (0, n)

            py_pass = py_total = 0
            if not self.skip_python:
                py_src = (prob_dir / "solutions" / f"{name}.py").read_text()
                py_pass, py_total = run_python_check(py_src, method, cases)

            # Record each failing case with its input, the expected value, and what Lean computed,
            # so a divergence is debuggable from the JSON without rerunning.
            failures = [{"index": i, "args": cases[i][0], "expected": cases[i][1],
                         "lean_got": got_by_idx[i]}
                        for i in sorted(got_by_idx) if i < len(cases)]
            (eval_dir / f"{name}.json").write_text(json.dumps({
                "model": "function", "method": method,
                "lean": {"passed": lean_pass, "total": lean_total, "error": err},
                "python": {"passed": py_pass, "total": py_total},
                "skipped_unrenderable": len(cases) - n,
                "harness": str(harness_path),
                "failures": failures,
            }, indent=2, default=str))
            report[name] = {
                "lean": f"{lean_pass}/{lean_total}" + (f" ({err})" if err else ""),
                "python": f"{py_pass}/{py_total}" if py_total else "skipped",
            }
            print(f"    lean {lean_pass}/{lean_total}"
                  + (f"  python {py_pass}/{py_total}" if py_total else "")
                  + (f"   [{err}]" if err else ""))
            deltas["lean_pass"] += lean_pass
            deltas["lean_total"] += lean_total
            deltas["py_pass"] += py_pass
            deltas["py_total"] += py_total
            deltas["solutions"] += 1

            # A compiling solution that disagrees with CPython is a runtime/API bug — the same
            # `lean_wrong_python_right` bucket the stdio model reports.
            if lean_pass < py_pass or (err and py_total):
                diverged.append({
                    "problem": prob_dir.name, "solution": name, "model": "function",
                    "classification": "lean_wrong_python_right",
                    "lean": f"{lean_pass}/{lean_total}", "python": f"{py_pass}/{py_total}",
                    "lean_error": err, "harness": str(harness_path),
                    "failures": failures[:5],
                })
        return report, deltas, diverged

    def _evaluate_runner(self, runner, target_path, tests):
        """Run `runner` over `tests`; return (passed, total, per-test details incl. output)."""
        passed, details = 0, []
        for inp_path, out_path in tests:
            expected = normalize(out_path.read_text())
            actual, err = runner(target_path, inp_path.read_text())
            if err is not None:
                details.append({"test": inp_path.name, "result": "error", "error": err, "output": None})
                continue
            norm = normalize(actual)
            if norm == expected:
                passed += 1
                details.append({"test": inp_path.name, "result": "pass", "output": norm})
            else:
                details.append({"test": inp_path.name, "result": "fail", "output": norm,
                                "got": norm[:200], "want": expected[:200]})
        return passed, len(tests), details

    @staticmethod
    def _collect_divergences(prob_name, sol_name, tests, lean_details, py_details):
        """Per-test Lean-vs-Python disagreements. `lean_wrong_python_right` marks a runtime/API bug."""
        expected_by_test = {inp.name: normalize(out.read_text()) for inp, out in tests}
        py_by_test = {d["test"]: d for d in py_details}
        diffs = []
        for ld in lean_details:
            pd = py_by_test.get(ld["test"])
            if pd is None or ld.get("output") == pd.get("output"):
                continue  # absent, or they agree (including both-errored: None == None)
            lean_ok, py_ok = ld["result"] == "pass", pd["result"] == "pass"
            if py_ok and not lean_ok:
                classification = "lean_wrong_python_right"
            elif lean_ok and not py_ok:
                classification = "lean_right_python_wrong"
            else:
                classification = "both_wrong"
            diffs.append({
                "problem": prob_name, "solution": sol_name, "test": ld["test"],
                "classification": classification,
                "lean_output": (ld["output"][:200] if ld.get("output") is not None else None),
                "python_output": (pd["output"][:200] if pd.get("output") is not None else None),
                "expected": expected_by_test.get(ld["test"], "")[:200],
                "lean_error": ld.get("error"), "python_error": pd.get("error"),
            })
        return diffs

    def _evaluate_stdio_problem(self, prob_dir, lean_dir, tests_dir):
        tests = [(i, i.with_suffix(".out")) for i in sorted(tests_dir.glob("test_*.in"))
                 if i.with_suffix(".out").exists()]
        if self.max_tests:
            tests = tests[: self.max_tests]
        report, deltas = {}, {"lean_pass": 0, "lean_total": 0, "py_pass": 0, "py_total": 0, "solutions": 0}
        if not tests:
            return report, deltas, []

        eval_dir = prob_dir / "eval"
        eval_dir.mkdir(exist_ok=True)
        divergences = []
        for status_path in sorted(lean_dir.glob("sol_*.status")):
            if status_path.read_text().strip() != "ok":
                continue
            name = status_path.stem
            py_path = prob_dir / "solutions" / f"{name}.py"
            print(f"[*] {prob_dir.name}/{name} over {len(tests)} test(s)...")
            lean_pass, lean_total, lean_details = self._evaluate_runner(
                self.run_lean, lean_dir / f"{name}.lean", tests)

            py_pass = py_total = 0
            py_details = []
            if not self.skip_python and py_path.exists():
                py_pass, py_total, py_details = self._evaluate_runner(self.run_python, py_path, tests)
                divergences.extend(
                    self._collect_divergences(prob_dir.name, name, tests, lean_details, py_details))

            (eval_dir / f"{name}.json").write_text(json.dumps({
                "lean": {"passed": lean_pass, "total": lean_total, "details": lean_details},
                "python": {"passed": py_pass, "total": py_total, "details": py_details},
            }, indent=2))
            report[name] = {"lean": f"{lean_pass}/{lean_total}",
                            "python": f"{py_pass}/{py_total}" if py_total else "skipped"}
            print(f"    lean {lean_pass}/{lean_total}"
                  + (f"   python {py_pass}/{py_total}" if py_total else ""))
            deltas["lean_pass"] += lean_pass
            deltas["lean_total"] += lean_total
            deltas["py_pass"] += py_pass
            deltas["py_total"] += py_total
            deltas["solutions"] += 1
        return report, deltas, divergences

    def evaluate(self):
        """Run Lean (and CPython) on the test cases. Writes `eval_report.json` + divergences."""
        report = {}
        agg = {"lean_pass": 0, "lean_total": 0, "py_pass": 0, "py_total": 0, "solutions": 0}
        divergences = []

        for prob_dir in self.problems():
            lean_dir, tests_dir = prob_dir / "lean", prob_dir / "tests"
            if not (lean_dir.is_dir() and tests_dir.is_dir()):
                continue
            if self.kind_of(prob_dir) == KIND_FUNCTION:
                prob_report, deltas, diffs = self._evaluate_function_problem(prob_dir, lean_dir)
            else:
                prob_report, deltas, diffs = self._evaluate_stdio_problem(prob_dir, lean_dir, tests_dir)
            if prob_report:
                report[prob_dir.name] = prob_report
                for k, v in deltas.items():
                    agg[k] += v
            divergences.extend(diffs)

        report["_summary"] = agg
        (self.dataset / "eval_report.json").write_text(json.dumps(report, indent=2))
        self._write_divergences(divergences)
        self._print_eval_summary(agg, divergences)
        return report

    def _write_divergences(self, divergences):
        by_class = {}
        for d in divergences:
            by_class[d["classification"]] = by_class.get(d["classification"], 0) + 1
        api_bugs = [d for d in divergences if d["classification"] == "lean_wrong_python_right"]
        # A `lean_error` (timeout / crash) is a runtime bug; otherwise Lean ran and answered wrong.
        runtime_error = [d for d in api_bugs if d.get("lean_error")]
        wrong_output = [d for d in api_bugs if not d.get("lean_error")]
        (self.dataset / "eval_divergences.json").write_text(json.dumps({
            "summary": {
                "total_divergences": len(divergences), "by_classification": by_class,
                "api_bugs": len(api_bugs), "api_bugs_wrong_output": len(wrong_output),
                "api_bugs_runtime_error": len(runtime_error),
            },
            # Most actionable first: wrong-output API bugs, then runtime errors, then the rest.
            "divergences": wrong_output + runtime_error
            + [d for d in divergences if d["classification"] != "lean_wrong_python_right"],
        }, indent=2))
        self._api_bugs = (api_bugs, wrong_output, runtime_error)

    def _print_eval_summary(self, agg, divergences):
        api_bugs, wrong_output, runtime_error = getattr(self, "_api_bugs", ([], [], []))
        print("\n===== Evaluation summary =====")
        print(f"Solutions evaluated: {agg['solutions']}")
        if agg["lean_total"]:
            print(f"Lean   pass rate: {agg['lean_pass']}/{agg['lean_total']} "
                  f"({agg['lean_pass'] / agg['lean_total']:.1%})")
        if agg["py_total"]:
            print(f"Python pass rate: {agg['py_pass']}/{agg['py_total']} "
                  f"({agg['py_pass'] / agg['py_total']:.1%})")
        if not self.skip_python:
            print(f"Lean-vs-Python divergences: {len(divergences)} "
                  f"(API bugs — Lean wrong, Python right: {len(api_bugs)} "
                  f"= {len(wrong_output)} wrong-output + {len(runtime_error)} runtime-error)")
            for d in wrong_output[:20]:
                print(f"    {d['problem']}/{d['solution']} {d['test']}")
            if len(wrong_output) > 20:
                print(f"    … and {len(wrong_output) - 20} more (see eval_divergences.json)")
        print(f"Report written to {self.dataset / 'eval_report.json'}")

    # -- plot --------------------------------------------------------------------------

    @staticmethod
    def classify(prob_dir):
        """`(difficulty, category_index)` for a function-model problem, or None to skip.

        0 = didn't compile, 1 = compiled but not all tests passed, 2 = compiled and all passed.
        """
        kind_f = prob_dir / KIND_FILE
        if not (kind_f.exists() and kind_f.read_text().strip() == KIND_FUNCTION):
            return None
        meta_f = prob_dir / "meta.json"
        diff = (json.loads(meta_f.read_text()).get("difficulty") or "Unknown") \
            if meta_f.exists() else "Unknown"

        status_f = prob_dir / "lean" / "sol_0.status"
        if not status_f.exists():
            return None  # not converted yet
        if status_f.read_text().strip() != "ok":
            return diff, 0
        eval_f = prob_dir / "eval" / "sol_0.json"
        if not eval_f.exists():
            return diff, 1
        lean = json.loads(eval_f.read_text()).get("lean", {})
        passed, total = lean.get("passed", 0), lean.get("total", 0)
        return (diff, 2) if (total > 0 and passed == total) else (diff, 1)

    def plot(self, out=None, title=None):
        """Grouped bar chart of coverage by difficulty; also prints the table. Returns the PNG path."""
        counts, n = {}, 0
        for prob in self.problems():
            r = self.classify(prob)
            if r is None:
                continue
            diff, ci = r
            counts.setdefault(diff, [0, 0, 0])[ci] += 1
            n += 1

        diffs = [d for d in DIFF_ORDER if d in counts] + [d for d in counts if d not in DIFF_ORDER]
        if not diffs:
            print("No converted function-model problems found. Run fetch → convert → evaluate first.")
            return None

        print(f"{n} problem(s) classified across {len(diffs)} difficulty level(s):")
        print(f"  {'difficulty':<10}{'no-compile':>12}{'partial':>10}{'all-pass':>10}{'total':>8}")
        for d in diffs:
            c = counts[d]
            print(f"  {d:<10}{c[0]:>12}{c[1]:>10}{c[2]:>10}{sum(c):>8}")

        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import numpy as np

        x, w = np.arange(len(diffs)), 0.26
        fig, ax = plt.subplots(figsize=(max(6, 2.2 * len(diffs)), 5))
        for i, cat in enumerate(CATS):
            bars = ax.bar(x + (i - 1) * w, [counts[d][i] for d in diffs], w,
                          label=cat, color=COLORS[i], edgecolor="white")
            ax.bar_label(bars, padding=2, fontsize=9)
        ax.set_xticks(x)
        ax.set_xticklabels(diffs)
        ax.set_ylabel("number of problems")
        ax.set_xlabel("difficulty")
        ax.set_title(title or f"PastaLean on LeetCode — coverage by difficulty  (n = {n})")
        ax.legend(frameon=False)
        ax.spines[["top", "right"]].set_visible(False)
        ax.margins(y=0.12)

        out_path = Path(out) if out else self.dataset / "coverage_by_difficulty.png"
        fig.tight_layout()
        fig.savefig(out_path, dpi=150)
        print(f"\nSaved chart → {out_path}")
        return out_path

    # -- the whole pipeline ------------------------------------------------------------

    def run(self, num=10, *, skip_fetch=False, skip_convert=False, plot=True):
        """fetch → convert → evaluate → plot, skipping whichever stages you ask it to."""
        banner = f" harness:  {self.dataset}"
        if self.random_n is not None:
            banner += f"  |  random {self.random_n}, seed {self.seed} " \
                      f"(replay: --random {self.random_n} --seed {self.seed})"
        print("=" * 70, banner, "=" * 70, sep="\n")

        if skip_fetch or skip_convert:
            print("\n>>> [1/4] Fetch (skipped — reusing existing dataset)")
        else:
            print(f"\n>>> [1/4] Fetch (source: {self.source})")
            self.fetch(num)

        if skip_convert:
            print("\n>>> [2/4] Convert (skipped — reusing already-converted Lean)")
        else:
            print("\n>>> [2/4] Convert (Python -> Lean -> compile-check)")
            self.convert()

        print("\n>>> [3/4] Evaluate (run Lean vs Python on test cases)")
        self.evaluate()

        if plot:
            print("\n>>> [4/4] Plot coverage by difficulty")
            self.plot()
        return self


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------

def _add_common(p, *, dataset_default="cp_harness/dataset"):
    p.add_argument("--dataset", default=dataset_default, help="Dataset directory")
    p.add_argument("--random", type=int, default=None, metavar="N",
                   help="Operate on a random subset of N problems (same --seed => same subset)")
    p.add_argument("--seed", type=int, default=0, help="Seed for --random")
    p.add_argument("--problems", nargs="*", default=None, metavar="NAME",
                   help="Restrict to these problem directory names")


def _add_eval_opts(p):
    p.add_argument("--timeout", type=int, default=15, help="Per-run timeout (seconds)")
    p.add_argument("--max-tests", type=parse_max_tests, default=0,
                   help="Cap tests per solution (0 or 'max'/'all' = all)")
    p.add_argument("--skip-python", action="store_true", help="Skip the Python baseline run")


def _harness(args):
    return CPastaEval(
        args.dataset,
        source=getattr(args, "source", None),
        timeout=getattr(args, "timeout", 15),
        max_tests=getattr(args, "max_tests", 0),
        skip_python=getattr(args, "skip_python", False),
        random_n=args.random,
        seed=args.seed,
        problems=args.problems,
        max_solutions=getattr(args, "max_solutions", 3),
        split=getattr(args, "split", "test"),
    )


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("fetch", help="Download problems into the dataset directory")
    _add_common(p)
    p.add_argument("--source", required=True, choices=sorted(CPastaEval.SOURCES),
                   help="Dataset adapter (no default)")
    p.add_argument("--num", default="10", help="Problems to keep, or 'max'/'all' for the whole set")
    p.add_argument("--max-solutions", type=int, default=3, help="Max solutions per problem")
    p.add_argument("--split", default="test", help="CodeContests split (test/valid/train)")

    p = sub.add_parser("convert", help="Translate to Lean and compile-check")
    _add_common(p)

    p = sub.add_parser("evaluate", help="Run Lean and CPython on the test cases")
    _add_common(p)
    _add_eval_opts(p)

    p = sub.add_parser("plot", help="Chart coverage by difficulty")
    _add_common(p)
    p.add_argument("--out", default=None, help="PNG path")
    p.add_argument("--title", default=None, help="Chart title override")

    p = sub.add_parser("run", help="fetch -> convert -> evaluate -> plot")
    _add_common(p)
    _add_eval_opts(p)
    p.add_argument("--source", choices=sorted(CPastaEval.SOURCES), help="Required unless skipping fetch")
    p.add_argument("--num", default="10", help="Problems to fetch, or 'max'/'all'")
    p.add_argument("--max-solutions", type=int, default=3, help="Max solutions per problem")
    p.add_argument("--split", default="test", help="CodeContests split")
    p.add_argument("--skip-fetch", action="store_true", help="Reuse the existing dataset")
    p.add_argument("--skip-convert", action="store_true", help="Reuse already-converted Lean")
    p.add_argument("--no-plot", action="store_true", help="Skip the chart")

    args = ap.parse_args(argv)

    if args.cmd in ("convert", "evaluate", "plot", "run") and not Path(args.dataset).is_dir():
        if not (args.cmd == "run" and not args.skip_fetch):
            print(f"ERROR: dataset dir not found: {args.dataset}", file=sys.stderr)
            return 1

    with _harness(args) as ev:
        if args.cmd == "fetch":
            return ev.fetch(args.num) or 0
        if args.cmd == "convert":
            ev.convert()
        elif args.cmd == "evaluate":
            ev.evaluate()
        elif args.cmd == "plot":
            ev.plot(out=args.out, title=args.title)
        elif args.cmd == "run":
            skip_fetch = args.skip_fetch or args.skip_convert
            if not skip_fetch and not args.source:
                print("ERROR: --source is required to fetch (or pass --skip-fetch).", file=sys.stderr)
                return 2
            ev.run(args.num, skip_fetch=skip_fetch, skip_convert=args.skip_convert,
                   plot=not args.no_plot)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
