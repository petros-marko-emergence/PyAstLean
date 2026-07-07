from contracts import *


# Early-return linear search (mirrors early_return_break.lean): return the first index whose value
# equals k, or -1. The loop invariant is "k absent from the prefix scanned so far".
def find_first(xs: list[int], k: int) -> int:
    for i in range(len(xs)):
        Invariant(k not in xs[:i])
        if xs[i] == k:
            return i
    return -1
