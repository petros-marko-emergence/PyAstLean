from contracts import *
import math


# Kitchen-sink: two loops (with invariants), if/else, exponentiation, try/except, and the math
# library — a small "summary statistic" over a list of measurements.
def analyze(xs: list[int], threshold: int) -> float:
    Requires(len(xs) > 0)

    # Loop 1: running total + count of entries above the threshold.
    total = 0
    count = 0
    for x in xs:
        Invariant(count >= 0)
        total = total + x
        if x > threshold:
            count = count + 1

    # Loop 2: sum of squares (uses exponentiation).
    ss = 0
    for x in xs:
        Invariant(ss >= 0)
        ss = ss + x ** 2

    # if/else + math library + exception handling.
    if count > 0:
        try:
            avg = total / count
            spread = math.sqrt(float(ss))
        except ZeroDivisionError:
            avg = 0.0
            spread = 0.0
    else:
        avg = 0.0
        spread = 0.0

    result = avg + spread
    Ensures(result >= 0.0)
    return result
