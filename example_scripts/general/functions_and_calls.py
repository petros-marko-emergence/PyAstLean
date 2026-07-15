def add(a, b):
    return a + b

def call_add(n):
    return add(n, 1)

def keyword_call(n):
    return add(a=n, b=2)

def many_args(a, b, c, d, e):
    return a + b + c + d + e

def complex_func(x, y, z):
    res = x * y
    res += z
    return res
