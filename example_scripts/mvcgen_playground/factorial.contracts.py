from contracts import *

def factorial(n: int) -> int:
    Requires(n >= 0)
    Ensures(Result() >= 1)
    result = 1
    i = 1
    while i <= n:
        Invariant(1 <= i)
        Invariant(i <= n + 1)
        Invariant(result >= 1)
        Decreases(n + 1 - i)
        result = result * i
        i = i + 1
    return result