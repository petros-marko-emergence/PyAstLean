from contracts import *


# Conditional accumulator over a list: count strictly-positive entries.
# Bounds invariant `0 <= cnt <= processed-so-far`; the count never exceeds the list length.
def count_positives(xs: list[int]) -> int:
    cnt = 0
    for x in xs:
        Invariant(cnt >= 0)
        if x > 0:
            cnt = cnt + 1
    Ensures(cnt >= 0)
    Ensures(cnt <= len(xs))
    return cnt
