# Un-inferrable parameters that are used as containers (subscript / iterate / len) box to PyValue,
# so the program stays total. In prove mode each PyValue binder is flagged as unprovable.

# `data` has no annotation and its element type is never pinned (indexing is ambiguous), so it boxes
# to PyValue and `data[0]` still elaborates via the delegating PyGetItem instance.
def first_item(data):
    return data[0]


# `xs` used by len() and a for-loop; still un-inferrable, boxed to PyValue.
def count_items(xs):
    n = 0
    for _ in xs:
        n = n + 1
    return n


if __name__ == "__main__":
    print(first_item([10, 20, 30]))
    print(first_item(["a", "b"]))
    print(count_items([1, 2, 3, 4]))
