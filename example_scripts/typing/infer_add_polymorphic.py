# One `add` definition, called at int and str in the same program: the params are used at genuinely
# different types (`.any`), so they box to PyValue and dispatch on the runtime tag. Runs off a single
# definition -> prints 7 then xy.

def add(a, b):
    return a + b


if __name__ == "__main__":
    print(add(3, 4))
    print(add("x", "y"))
