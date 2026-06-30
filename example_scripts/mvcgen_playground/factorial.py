from contracts import *


# While-loop product accumulator with an explicit termination measure (Decreases).
# Maintainable invariant: the running product stays >= 1 (so it is never zero / negative).
def factorial(n: int) -> int:
    Requires(n >= 0)
    result = 1
    i = 1
    while i <= n:
        Invariant(result >= 1)
        Decreases(n - i)
        result = result * i
        i = i + 1
    Ensures(result >= 1)
    return result
