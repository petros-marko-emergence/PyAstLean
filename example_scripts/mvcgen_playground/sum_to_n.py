from contracts import *


# Closed-form accumulator: total = 0+1+...+n = n(n+1)/2.
# Index-style invariant (references the loop counter), so it exercises element=index + division.
def sum_to_n(n: int) -> int:
    Requires(n >= 0)
    total = 0
    for i in range(n + 1):
        Invariant(2 * total == i * (i - 1))
        total = total + i
    Ensures(2 * total == n * (n + 1))
    return total
