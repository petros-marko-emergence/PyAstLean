# Test: Pure exception handling (no IO)
# CHECK: PyExceptId
# CHECK-NOT: PyProofM
# CHECK-NOT: IO
def divide(a, b):
    try:
        return a / b
    except:
        return 0
