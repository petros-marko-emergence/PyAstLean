def builtin_casting():
    a = int("42")
    b = str([1, 2, 3])
    c = list("abc")
    d = str(True)
    e = list((1, 2))
    return a, b, c, d, e
