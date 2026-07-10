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

class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def norm_sq(self):
        return self.x*self.x \
             + self.y*self.y

obj = Point(1,2)
norm = obj.norm_sq()

def classify(nums: list[int]):
    total = 0
    for n in nums:
        if n % 2 == 0:
            total += n
        else:
            total -= n
    return total

def divide_add(a, b, c):
    try:
        result = a / b
        while result < c:
            result += 1
        return result
    except ZeroDivisionError:
        print("Division by zero error")
        return -1
    finally:
        print("PastaLean handles exceptions gracefully.")

def transform_and_cube(a,b):
    c = a + b
    d = a - b
    e = c * d
    return e ** 3
    