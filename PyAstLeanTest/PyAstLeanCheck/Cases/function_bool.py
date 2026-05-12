# PYASTLEANCHECK START
# TARGET: command
# CHECK: def
# CHECK: := fun
# CHECK: a
# CHECK: &&
# CHECK: ||
# PYASTLEANCHECK END

def func(a, b, c):
    return a and b and c or a and b
