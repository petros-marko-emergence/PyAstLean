from contracts import *


# Multi-loop pipeline with assert checkpoints between phases (mirrors pipeline.lean).
# Accumulator-style invariants (acc = prefix sum, cnt = prefix length) — no closed form.
def pipeline(xs: list[int]) -> int:
    acc = 0
    for x in xs:
        acc = acc + x
    Assert(acc == sum(xs))
    acc = acc * 2
    cnt = 0
    for x in xs:
        cnt = cnt + 1
    Assert(cnt == len(xs))
    result = acc + cnt
    Ensures(result == 2 * sum(xs) + len(xs))
    return result
