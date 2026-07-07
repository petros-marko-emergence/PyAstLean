from contracts import *

def foo():
    x = ["hi", "hello", "hey"]
    y = " ".join(x)
    print(y)

def my_condition(x) -> bool:
    if x > 0:
        return True
    else:
        return False

def returnsFive() -> int:
  Ensures(my_condition(5))
  return 5

def caller() -> None:
  x = returnsFive()
  print (x)

caller()

def sum_upto(n: int) -> int:
    Requires(n >= 0)
    s = 0
    i = 0
    while i < n:
        Invariant(0 <= i <= n)
        Invariant(s == i * (i - 1) // 2)
        Decreases(n - i)
        s += i
        i += 1
    Ensures(s == n * (n - 1) // 2)
    return s

print(sum_upto(5))