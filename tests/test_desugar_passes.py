"""Differential tests for the syntax-desugaring pre-passes.

Both passes rewrite the Python AST before lowering, so the only thing that matters is that the
rewritten program computes exactly what the original did. Each case executes both and compares.

`REFUSE` cases must raise: the walrus pass has to decline positions where hoisting would change
*when* the expression runs (a `while` test, a short-circuit operand, a comprehension).
"""
import ast
import copy

from pastalean.transpile.for_unpack import desugar_nested_for_targets
from pastalean.transpile.walrus import WalrusError, desugar_walrus

REFUSE = object()

WALRUS_CASES = [
    ("if_test", "def f(nums, target):\n    d = {}\n    for i, x in enumerate(nums):\n"
                "        if (y := target - x) in d:\n            return [d[y], i]\n"
                "        d[x] = i\n    return []\n", "f", ([2, 7, 11, 15], 9)),
    ("return_value", "def f(n):\n    return (m := n * 2) + m\n", "f", (5,)),
    ("for_iter", "def f(xs):\n    t = 0\n    for v in (ys := [x * 2 for x in xs]):\n"
                 "        t += v\n    return t + len(ys)\n", "f", ([1, 2],)),
    ("assign_value", "def f(n):\n    a = (b := n + 1) * 2\n    return a + b\n", "f", (3,)),
    # A `while` test re-evaluates, so the hoisted assignment would run only once.
    ("while_test", "def f(n):\n    c = 0\n    while (c := c + 1) < n:\n        pass\n"
                   "    return c\n", "f", (4,), REFUSE),
    # `and`/`or` evaluate their right operand conditionally.
    ("boolop_operand", "def f(n):\n    if n > 0 and (m := n * 2) > 3:\n        return m\n"
                       "    return 0\n", "f", (2,), REFUSE),
    ("comprehension", "def f(xs):\n    return [(y := x) + y for x in xs]\n", "f", ([1, 2],), REFUSE),
]

FOR_UNPACK_CASES = [
    ("name_then_tuple", "def f(ps):\n    t = 0\n    for i, (a, b) in enumerate(ps):\n"
                        "        t += i * a + b\n    return t\n", "f", ([(1, 2), (3, 4)],)),
    ("tuple_then_tuple", "def f(ps):\n    t = 0\n    for (x1, y1), (x2, y2) in ps:\n"
                         "        t += x1 + y1 + x2 + y2\n    return t\n", "f", ([((1, 2), (3, 4))],)),
    ("deeply_nested", "def f(ps):\n    t = 0\n    for a, (b, (c, d)) in ps:\n"
                      "        t += a + b + c + d\n    return t\n", "f", ([(1, (2, (3, 4)))],)),
    # Starred targets are left untouched for the lowering to reject with its own message.
    ("starred_untouched", "def f(ps):\n    t = 0\n    for i, (a, *rest) in ps:\n"
                          "        t += i + a + len(rest)\n    return t\n", "f", ([(1, (2, 3, 4))],)),
    ("already_flat", "def f(ps):\n    t = 0\n    for a, b in ps:\n        t += a * b\n"
                     "    return t\n", "f", ([(2, 3)],)),
]


def _run(src, entry, args):
    ns = {}
    exec(compile(ast.parse(src), entry, "exec"), ns)  # noqa: S102
    return ns[entry](*copy.deepcopy(list(args)))


def _check(label, transform, cases, error_type):
    ok = True
    for case in cases:
        name, src, entry, args = case[:4]
        expected = case[4] if len(case) > 4 else None
        tree = ast.parse(src)
        try:
            transform(tree)
        except error_type as err:
            good = expected is REFUSE
            ok &= good
            print(f"[{label}:{name}] refused ({err}): {'expected' if good else 'UNEXPECTED'}")
            continue
        if expected is REFUSE:
            ok = False
            print(f"[{label}:{name}] rewritten but should have refused")
            continue
        want = _run(src, entry, args)
        rewritten = {}
        exec(compile(tree, name, "exec"), rewritten)  # noqa: S102
        got = rewritten[entry](*copy.deepcopy(list(args)))
        good = got == want
        ok &= good
        print(f"[{label}:{name}] rewritten ≡ original: {good} (want {want!r}, got {got!r})")
        if not good:
            print(ast.unparse(tree))
    return ok


def main() -> int:
    ok = _check("walrus", desugar_walrus, WALRUS_CASES, WalrusError)
    ok &= _check("for_unpack", desugar_nested_for_targets, FOR_UNPACK_CASES, ())
    print("ALL PASS" if ok else "FAILURES")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
