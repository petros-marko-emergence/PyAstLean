# Test: Pure computation (no IO, no exceptions)
# CHECK-NOT: PyProofM
# CHECK-NOT: PyExceptId
# CHECK-NOT: IO
def add(a, b):
    return a + b
