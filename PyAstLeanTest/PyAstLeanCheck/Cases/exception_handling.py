# PYASTLEANCHECK START
# TARGET: command
# CHECK: def fail := fun (x : Int) ↦
# CHECK: if x < (0 : Int) then
# CHECK: throw (PyAstLean.PyException.mk "ValueError"
# CHECK: ToString.toString "negative")
# CHECK: return String.append
# CHECK: PyAstLean.PyExcept _)
# CHECK: def call_fail := fun (x : Int) ↦
# CHECK: let mut y := (← fail x)
# CHECK: return y
# CHECK: PyAstLean.PyExcept _)
# CHECK: def safe := fun (n : Int) ↦
# CHECK: try
# CHECK: return (← fail n)
# CHECK: catch caught =>
# CHECK: if PyAstLean.PyException.kind caught == "ValueError" then
# CHECK: let err := caught
# CHECK: return String.append
# CHECK: PyAstLean.PyExcept _)
# PYASTLEANCHECK END

def fail(x: int):
    if x < 0:
        raise ValueError("negative")
    return f"value {x}"

def call_fail(x: int):
    y = fail(x)
    return y

def safe(n: int):
    try:
        return fail(n)
    except ValueError as err:
        return f"bad value: {err.msg}"
