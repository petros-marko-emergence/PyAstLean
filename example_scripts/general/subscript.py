arr = [1, 2, 3]
result = arr[0]

def foo():
    x = "hi"
    y = x[0]
    y *= 10
    z = y[2:-3]
    return z

def bar():
    x = "hi"
    y = x[100:-2000]
    return y
