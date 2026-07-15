def basic_types():
    a = 1
    b = 2.5
    c = "hello"
    d = True
    e = [1, 2]
    f = (1, "a")
    g, h = 3, 4.5
    m, n, p = 5, "world", False
    tup1 = ("foo", 42)
    tup2 = (g, h)

def fstring():
    s1 = "Hello"
    s2 = "World"
    s3 = s1 + ", " + s2 + "!"
    return f"This is a string: {s3} and this is a number: {1+2}"

def annotated_vars():
    x: int = 10
    y: int = 20
    return x + y
