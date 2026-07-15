def dict_get_variants():
    d = {"apple": 10, "banana": 20}
    found = d.get("apple")
    missing = d.get("pear")
    fallback = d.get("pear", 999)
    return found, missing, fallback


def dict_get_len_mix():
    d = {"x": 7, "y": 9}
    got = d.get("x", 0)
    size = len(d)
    return got, size
