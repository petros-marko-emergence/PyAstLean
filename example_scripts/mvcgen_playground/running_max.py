from contracts import *


# Running maximum over a non-empty list. Monotone invariant: the running max never drops below
# the first element. (A full "m ≥ every seen element" invariant is the harder follow-up.)
def running_max(xs: list[int]) -> int:
    Requires(len(xs) > 0)
    m = xs[0]
    for x in xs:
        Invariant(m >= xs[0])
        if x > m:
            m = x
    Ensures(m >= xs[0])
    return m
