# PYASTLEANCHECK START
# TARGET: command
# CHECK: def read_int_list :=
# CHECK: let mut xs :=
# CHECK: PyAstLean.pyInputIO ""
# CHECK: PyAstLean.pyStringSplit
# CHECK: PyAstLean.pyMap pyInt
# CHECK: PyAstLean.pyList
# CHECK: return xs
# PYASTLEANCHECK END

def read_int_list():
    xs = list(map(int, input().split()))
    return xs
