# PYASTLEANCHECK START
# TARGET: command
# CHECK: def
# CHECK: := fun
# CHECK: Id.run
# CHECK: let mut [[SUM:[A-Za-z_][A-Za-z0-9_]*]] :=
# CHECK: let mut [[IDX:[A-Za-z_][A-Za-z0-9_]*]] :=
# CHECK: while . <= .
# CHECK: [[SUM]] := [[SUM]] +ₚ [[IDX]]
# CHECK: [[IDX]] := [[IDX]] +ₚ
# CHECK: return [[SUM]]
# PYASTLEANCHECK END

def sum_to_n(n):
    total = 0
    i = 1
    while i <= n:
        total = total + i
        i = i + 1
    return total
