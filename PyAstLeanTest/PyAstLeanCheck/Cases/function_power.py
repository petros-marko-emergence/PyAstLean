# PYASTLEANCHECK START
# TARGET: command
# CHECK: def
# CHECK: := fun
# CHECK: ^ₚ
# CHECK: (4 : Int)
# PYASTLEANCHECK END

def exp(n):
    return n**4
