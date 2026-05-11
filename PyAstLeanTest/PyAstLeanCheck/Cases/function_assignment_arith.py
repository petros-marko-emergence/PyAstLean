# PYASTLEANCHECK START
# TARGET: command
# CHECK: def
# CHECK: := fun
# CHECK: let [[V1:[A-Za-z_][A-Za-z0-9_]*]] :=
# CHECK: +ₚ
# CHECK: let [[V2:[A-Za-z_][A-Za-z0-9_]*]] :=
# CHECK: *ₚ
# CHECK: let [[V1]] :=
# CHECK: -ₚ
# CHECK: [[V1]] +ₚ [[V2]]
# PYASTLEANCHECK END

def f(n):
    x = n + 1
    y = x * 2
    x = y - 1
    return x + y
