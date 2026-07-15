def dict_views():
    d = {"a": 1, "b": 2, "c": 3}
    its = d.items()
    ks = d.keys()
    vs = d.values()
    return its, ks, vs

def dict_len():
    d = {"x": 10, "y": 20}
    return len(d)
