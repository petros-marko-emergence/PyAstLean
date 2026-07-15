def len_protocols():
    xs = [1, 2, 3]
    s = "hello"
    d = {"a": 1}
    lx = len(xs)
    ls = len(s)
    ld = len(d)
    return lx, ls, ld

def iteration_protocols():
    xs = [4, 5, 6]
    return [x for x in xs]
