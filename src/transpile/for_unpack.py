"""Flatten nested `for`-loop tuple targets into a plain target plus unpack assignments.

    for i, (a, b) in pairs:      =>      for i, __for_unpack_1 in pairs:
        body                                 a, b = __for_unpack_1
                                             body

The `for` lowering only binds `Name` elements, so `for i, (a, b) in …` fails with "Only Name targets
are supported in for-loop tuple unpacking". Tuple *assignment* already handles the nested form, so
rewriting one into the other is enough.

Targets containing `*rest` are left alone: starred unpacking is unsupported anyway, and the existing
error message is clearer than anything this pass would produce.
"""
from __future__ import annotations

import ast

_TUPLE = (ast.Tuple, ast.List)


def _has_starred(node):
    return any(isinstance(n, ast.Starred) for n in ast.walk(node))


def _split_assign(assign, fresh, out):
    """Emit `assign` as assignments whose targets nest at most one level, appending to `out`."""
    target = assign.targets[0]
    if not (isinstance(target, _TUPLE) and any(isinstance(e, _TUPLE) for e in target.elts)):
        out.append(assign)
        return
    elts, deferred = [], []
    for elt in target.elts:
        if isinstance(elt, _TUPLE):
            name = fresh()
            elts.append(ast.Name(id=name, ctx=ast.Store()))
            deferred.append(ast.Assign(targets=[elt], value=ast.Name(id=name, ctx=ast.Load())))
        else:
            elts.append(elt)
    assign.targets = [ast.Tuple(elts=elts, ctx=ast.Store())]
    out.append(assign)
    for nested in deferred:
        _split_assign(nested, fresh, out)


def _rewrite_for(node, fresh):
    target = node.target
    if not isinstance(target, _TUPLE) or _has_starred(target):
        return
    elts, assigns = [], []
    for elt in target.elts:
        if isinstance(elt, ast.Name):
            elts.append(elt)
        elif isinstance(elt, _TUPLE):
            name = fresh()
            elts.append(ast.Name(id=name, ctx=ast.Store()))
            assigns.append(ast.Assign(targets=[elt], value=ast.Name(id=name, ctx=ast.Load())))
        else:
            return  # a subscript/attribute element: leave it to the existing diagnostic
    if not assigns:
        return
    node.target = ast.Tuple(elts=elts, ctx=ast.Store())
    flattened = []
    for assign in assigns:
        _split_assign(assign, fresh, flattened)
    node.body = flattened + node.body


def desugar_nested_for_targets(tree):
    """Rewrite `tree` in place so every `for` target binds only plain names."""
    counter = [0]

    def fresh():
        counter[0] += 1
        return f"__for_unpack_{counter[0]}"

    for node in ast.walk(tree):
        if isinstance(node, (ast.For, ast.AsyncFor)):
            _rewrite_for(node, fresh)
    ast.fix_missing_locations(tree)
    return tree
