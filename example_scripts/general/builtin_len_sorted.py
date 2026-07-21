def builtin_len_sorted():
    xs = [5, 1, 3]
    s = "dbca"
    d = {"z": 9, "a": 1, "m": 4}
    lx = len(xs)
    ls = len(s)
    ld = len(d)
    sx = sorted(xs)
    ss = sorted(s)
    sd = sorted(d)
    return lx, ls, ld, sx, ss, sd


def in_place_sort():
    xs = [4, 1, 3, 2]
    xs.sort()
    return xs
