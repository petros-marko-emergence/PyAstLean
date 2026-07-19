# Default parameter values (Python `def f(a, b=10)`) become Lean `optParam` binders
# (`def f (a) (b := 10)`), so a call with fewer args applies the defaults instead of being a partial
# application. Covered here: free functions, methods, and constructors — including the `None`-default
# node pattern (`TreeNode.left`) whose field types must be `Option TreeNode`.
from typing import Optional


def add(a, b=10):
    return a + b


def greet(name, greeting="hi", times=2):
    return greeting + name * times


class Counter:
    def __init__(self, start=0, step=1):
        self.value = start
        self.step = step

    def bumped(self, by=1):
        return self.value + by * self.step


class TreeNode:
    def __init__(self, val=0, left=None, right=None):
        self.val = val
        self.left = left
        self.right = right


if __name__ == "__main__":
    print(add(5))                  # 15  (b defaults to 10)
    print(add(5, 20))              # 25  (b given)
    print(greet("x"))              # hixx (greeting, times default)
    print(greet("x", "yo", 1))     # yox  (all given)
    c = Counter()                  # both default
    print(c.bumped())              # 1   (by defaults to 1)
    print(c.bumped(5))             # 5
    c2 = Counter(10, 2)
    print(c2.bumped(3))            # 16  (10 + 3*2)
    leaf = TreeNode(2)             # left/right default to None
    print(leaf.val)                # 2
    root = TreeNode(1, leaf)       # partial: right defaults to None
    print(root.val)                # 1
