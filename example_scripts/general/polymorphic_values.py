# Multiple return types and per-variable type mutation, both handled by inference boxing the slot to
# PyAny (the dynamic fallback) and dispatching operations on the runtime tag.

# A function whose branches return different types (str vs int) → its result is PyAny.
def classify(n):
    if n > 0:
        return "positive"
    return 0


# A parameter/local rebound to a different type mid-function, with operations on each type.
def reassigned():
    x = 1
    x = x + 5          # int arithmetic
    x = "hi"           # now a string
    x = x + "world"    # string concatenation on the new type
    return x


# One `add` used at both int and str (the flagship polymorphic case).
def add(a, b):
    return a + b


# A try/except whose branches return different types (int vs str) → the whole function is PyAny,
# so the `PyExcept _` codomain in Exceptions.lean infers `PyAny` on its own.
def describe(x):
    try:
        if x < 0:
            raise ValueError()
        return x            # int
    except ValueError:
        return "negative"   # str


if __name__ == "__main__":
    print(classify(5))       # positive
    print(classify(-3))      # 0
    print(reassigned())      # hiworld
    print(add(3, 4))         # 7
    print(add("x", "y"))     # xy
    d1 = describe(5)         # try branch → int
    print(d1)                # 5
    d2 = describe(-2)        # except branch → str
    print(d2)                # negative
