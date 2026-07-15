def list_append_once():
    xs = [1, 2]
    xs.append(3)
    return xs

def list_append_twice():
    xs = [1, 2, 3]
    xs.append(4)
    xs.append(5)
    return xs

def list_len():
    xs = [10, 20, 30, 40]
    return len(xs)

def list_membership():
    xs = [1, 2, 3]
    present = 2 in xs
    missing = 9 in xs
    return present, missing
