#!/usr/bin/env python3
"""LeetCode-mode helpers for the harness.

LeetCode problems are *function-based*, not stdin/stdout: a `class Solution` with an
entry method, tested by calling it with arguments and comparing the return value —
unlike CodeContests, whose solutions read stdin and print stdout.

This module holds the LeetCode-specific pieces the three stages share:

  * `extract_function`   — pull the entry method out of a `Solution` class as a plain
                           top-level `def` (drop `self`), so py2lean transpiles it like
                           any free function.
  * `parse_test_input`   — turn an `input_output` "input" string (`nums = [3,3], target = 6`)
                           into positional argument values, ordered by the signature.
  * `py_lit_to_lean`     — render a Python literal (int / str / bool / nested list / tuple)
                           as a Lean literal; returns None for values we can't render
                           faithfully (e.g. `None`, dict, or a linked-list/tree object).
  * `build_test_harness` — append a `def main : IO Unit` to the converted Lean that calls
                           the (computable `'rn`) function on each test and prints `PASSED p/t`.

A problem is marked LeetCode on disk by a `kind` file containing `leetcode`; the stages
branch on it so CodeContests behaviour is unchanged.
"""
import ast

KIND_FILE = "kind"
KIND_FUNCTION = "function"


def entry_method_name(entry_point):
    """`Solution().twoSum` (or `twoSum`) -> `twoSum`."""
    return entry_point.strip().rstrip("()").split(".")[-1].strip()


def extract_function(completion_src, method_name):
    """Return the entry method as a standalone top-level `def` (with `self` removed),
    or None if it can't be found / isolated. Methods that reference `self.<other>`
    (i.e. depend on sibling methods or fields) are rejected — they aren't self-contained."""
    try:
        tree = ast.parse(completion_src)
    except SyntaxError:
        return None
    target = None
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == method_name:
            target = node
            break
    if target is None:
        return None
    # Reject methods that use `self` for anything (sibling call / attribute): not isolatable.
    for sub in ast.walk(target):
        if isinstance(sub, ast.Attribute) and isinstance(sub.value, ast.Name) and sub.value.id == "self":
            return None
    target.args.args = [a for a in target.args.args if a.arg != "self"]
    target.decorator_list = []
    try:
        return ast.unparse(target)
    except Exception:  # noqa: BLE001
        return None


def _bound_names(tree):
    """Names bound anywhere in `tree` (assign targets, params, def/class names, imports, excepts).
    An over-approximation, which is what we want here: a bound name is never a free reference."""
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
    """Names `src_or_node` reads without binding them first."""
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


def prompt_preamble(prompt_src, fn_src):
    """The part of the dataset's `prompt` that `fn_src` actually depends on, verbatim.

    The LeetCode `prompt` is a fixed module preamble: an import block, `inf = float('inf')`, and
    then linked-list/tree *test scaffolding* (`ListNode`, `tree_node`, `is_same_tree`, …) that the
    `test` function uses to build inputs — solutions never call it. We keep every import as written
    plus exactly the top-level definitions reachable from the extracted function (transitively), and
    drop the unreachable scaffolding. This is dead-code elimination, not a rewrite: every line kept
    is the dataset's own, unmodified, and every line dropped is provably unused by the solution.
    """
    try:
        prompt_tree = ast.parse(prompt_src)
    except SyntaxError:
        return ""
    imports, binders, order = [], {}, []
    for stmt in prompt_tree.body:
        if isinstance(stmt, (ast.Import, ast.ImportFrom)):
            imports.append(stmt)
            continue
        names = _toplevel_binder_names(stmt)
        if names:
            order.append(stmt)
            for nm in names:
                binders[nm] = stmt

    # Transitively close the free names of `fn_src` over the prompt's top-level binders.
    needed, worklist = set(), list(_free_names(fn_src))
    while worklist:
        nm = worklist.pop()
        stmt = binders.get(nm)
        if stmt is None or id(stmt) in needed:
            continue
        needed.add(id(stmt))
        worklist.extend(_free_names(stmt))

    kept = imports + [s for s in order if id(s) in needed]
    return "\n".join(ast.unparse(s) for s in kept)


def self_contained_source(prompt_src, fn_src):
    """The dataset's own preamble (pruned to what the solution uses) + the extracted function."""
    pre = prompt_preamble(prompt_src, fn_src)
    return (pre + "\n\n" + fn_src) if pre else fn_src


def param_names(fn_src):
    """Positional parameter names of a top-level `def`, in order."""
    tree = ast.parse(fn_src)
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef))
    return [a.arg for a in fn.args.args]


def parse_test_input(input_str, order):
    """`'nums = [3,3], target = 6'` + order `['nums','target']` -> `[[3,3], 6]`.
    Raises on anything not literal-evaluable."""
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
    """Render a Python literal as a Lean literal, or None if unrenderable."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return f"({v} : Int)"
    if isinstance(v, float):
        return f"({v} : Float)"
    if isinstance(v, str):
        esc = v.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{esc}"'
    if v is None:
        return None
    if isinstance(v, (list, tuple)):
        parts = [py_lit_to_lean(x) for x in v]
        if any(p is None for p in parts):
            return None
        return "[" + ", ".join(parts) + "]"
    return None  # dict / set / object → unsupported


def build_test_harness(converted_lean, fn_name, cases):
    """Append a `main` that runs the test `cases` to the converted Lean.

    `fn_name` is the *base* function name; we call the computable `'rn` twin.
    `cases` is a list of (args_list, expected_value). Cases with an unrenderable
    argument or expected value are skipped. Returns (harness_source, n_runnable)."""
    rn = f"{fn_name}'rn"
    checks = []
    n = 0
    for idx, (args, expected) in enumerate(cases):
        arg_lits = [py_lit_to_lean(a) for a in args]
        exp_lit = py_lit_to_lean(expected)
        if exp_lit is None or any(a is None for a in arg_lits):
            continue
        call = rn + " " + " ".join(f"({a})" for a in arg_lits)
        checks.append(f"  _t := _t + 1")
        checks.append(
            f"  if ({call}) == ({exp_lit}) then _p := _p + 1 "
            f'else IO.println "FAIL test {idx}"'
        )
        n += 1
    body = "\n".join(
        [converted_lean.rstrip(), "", "def main : IO Unit := do", "  let mut _p := 0", "  let mut _t := 0"]
        + checks
        + ['  IO.println s!"PASSED {_p}/{_t}"', ""]
    )
    return body, n


# The dataset's `prompt` imports everything under the sun; mirror that so a groundtruth
# solution runs exactly as it would on LeetCode.
_PRELUDE = (
    "from typing import *\n"
    "from math import *\n"
    "from collections import *\n"
    "from functools import *\n"
    "from itertools import *\n"
    "from heapq import *\n"
    "from bisect import *\n"
    "import re\n"
    "inf = float('inf')\n"
)


def load_callable(fn_src, method):
    """Exec `fn_src` (with the standard import prelude) and return the `method` callable,
    or None if it doesn't define/parse."""
    ns = {}
    try:
        exec(_PRELUDE + fn_src, ns)  # noqa: S102
    except Exception:  # noqa: BLE001
        return None
    fn = ns.get(method)
    if callable(fn):
        return fn
    # fall back to the sole top-level def name
    try:
        name = next(n.name for n in ast.parse(fn_src).body if isinstance(n, ast.FunctionDef))
    except (SyntaxError, StopIteration):
        return None
    return ns.get(name)


def run_python_check(fn_src, method, cases):
    """Sanity baseline: run the groundtruth function against `cases` (whose `expected` was
    itself produced by the groundtruth), so a correct solution scores 100%. Returns
    (passed, total)."""
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
