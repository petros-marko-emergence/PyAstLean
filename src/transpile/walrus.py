"""Desugar the walrus operator (`x := e`) into a plain assignment before the statement.

    if (y := target - x) in d:      =>      y = target - x
        return [d[y], i]                    if y in d:
                                                return [d[y], i]

`NamedExpr` has no Lean counterpart, so we hoist it. That is only sound where the expression is
evaluated exactly once and unconditionally. `desugar_walrus` therefore rewrites `if`/`return`/
assignment/`for`-iterator positions and raises `WalrusError` everywhere else — a `while` test (which
re-evaluates), a short-circuit operand of `and`/`or`, an `if`-expression branch, a comprehension, or
a lambda. Hoisting out of those would change *when* the expression runs, or bind a name Python never
would.
"""
from __future__ import annotations

import ast


class WalrusError(NotImplementedError):
    """A walrus in a position that cannot be hoisted without changing evaluation order."""


# Statement fields whose expression is evaluated exactly once, before the statement's body.
_HOISTABLE_FIELDS = {
    ast.If: ("test",),
    ast.Return: ("value",),
    ast.Assign: ("value",),
    ast.AugAssign: ("value",),
    ast.AnnAssign: ("value",),
    ast.Expr: ("value",),
    ast.For: ("iter",),
    ast.Assert: ("test",),
}

# Contexts that evaluate their operands conditionally or repeatedly.
_UNSAFE_PARENTS = (ast.BoolOp, ast.IfExp, ast.Lambda,
                   ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)


def _walruses(node):
    return [n for n in ast.walk(node) if isinstance(n, ast.NamedExpr)]


def _guard_unsafe(expr):
    """Raise if a walrus sits under a conditionally-evaluated or repeated context."""
    for parent in ast.walk(expr):
        if isinstance(parent, _UNSAFE_PARENTS):
            if _walruses(parent):
                raise WalrusError(
                    f"walrus inside {type(parent).__name__} is evaluated conditionally; "
                    "hoisting it would change evaluation order")


class _Hoister(ast.NodeTransformer):
    """Replace each `NamedExpr` with its target, collecting the assignments to emit before it."""

    def __init__(self):
        self.assigns = []

    def visit_NamedExpr(self, node):
        self.generic_visit(node)   # nested walruses bind first
        self.assigns.append(ast.Assign(targets=[node.target], value=node.value))
        return ast.Name(id=node.target.id, ctx=ast.Load())


def _rewrite_body(body):
    out = []
    for stmt in body:
        out.extend(_rewrite_stmt(stmt))
    return out


def _rewrite_stmt(stmt):
    if isinstance(stmt, ast.While) and _walruses(stmt.test):
        raise WalrusError("walrus in a `while` test is re-evaluated each iteration")

    prelude = []
    for field in _HOISTABLE_FIELDS.get(type(stmt), ()):
        expr = getattr(stmt, field, None)
        if expr is None or not _walruses(expr):
            continue
        _guard_unsafe(expr)
        hoister = _Hoister()
        setattr(stmt, field, hoister.visit(expr))
        prelude.extend(hoister.assigns)

    for field in ("body", "orelse", "finalbody"):
        block = getattr(stmt, field, None)
        if isinstance(block, list) and block and isinstance(block[0], ast.stmt):
            setattr(stmt, field, _rewrite_body(block))
    for handler in getattr(stmt, "handlers", []) or []:
        handler.body = _rewrite_body(handler.body)

    if _walruses(stmt):
        raise WalrusError(f"walrus in an unsupported position ({type(stmt).__name__})")
    return prelude + [stmt]


def desugar_walrus(tree):
    """Rewrite `tree` in place, replacing every `NamedExpr` with a preceding assignment.
    `_rewrite_stmt` recurses into nested blocks, so only the module body is walked here."""
    if not _walruses(tree):
        return tree
    tree.body = _rewrite_body(tree.body)
    ast.fix_missing_locations(tree)
    return tree
