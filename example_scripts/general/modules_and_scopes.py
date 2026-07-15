GLOBAL_VAR = 42

def get_global():
    return GLOBAL_VAR

def pass_func():
    if True:
        pass
    x = 1
    x += 1
    pass

answer = 42

fruits = ["apple", "banana", "cherry"]
scores = {"math": 95, "science": 90}

def greet(name: int):
  return f"Hello, {name}!"

def calculate_sum():
    total = 0
    for i in range(10):
        total += i
    return total

def not_sure():
    if answer == 42:
        return "The answer to the Ultimate Question of Life, The Universe, and Everything."
    elif answer < 42:
        return "The sky is the limit."
    else:
        return "I don't know the answer."

if __name__ == "__main__":
    for _ in range(10):
        print(greet(1))
        calculate_sum()

    get_global()
