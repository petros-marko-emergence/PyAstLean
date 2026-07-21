from functools import reduce

def builtin_functional():
    xs = [1, 2, 3, 4]
    ys = [10, 20, 30]
    letters = "cab"
    mapped = map(lambda x: x + 1, xs)
    filtered = filter(lambda x: x % 2 == 0, xs)
    zipped = zip(xs, ys)
    enumerated = enumerate(letters)
    total = sum(xs)
    smallest = min(xs)
    largest = max(xs)
    reduced = reduce(lambda acc, x: acc + x, xs, 0)
    return mapped, filtered, zipped, enumerated, total, smallest, largest, reduced


def functools_reduced():
    xs = [1, 2, 3]
    return reduce(lambda acc, x: acc + x, xs, 0)


def reduce_no_init_literal():
    return reduce(lambda acc, x: acc + x, [1, 2, 3])
