# PYASTLEANCHECK START
# TARGET: command
# CHECK: def answer :=
# CHECK: (42 : Int)
# CHECK: def fruits :=
# CHECK: ["apple", "banana", "cherry"]
# CHECK: def scores :=
# CHECK: Std.HashMap.ofList
# CHECK: def greet := fun name ↦
# CHECK: ToString.toString name
# CHECK: def calculate_sum :=
# CHECK: for i in PyAstLean.pyRange
# CHECK: total := total +ₚ i
# CHECK: def not_sure :=
# CHECK: if answer == (42 : Int) then
# CHECK: else
# CHECK: if answer < (42 : Int) then
# CHECK: def main :=
# CHECK: print (greet (1 : Int))
# CHECK: let _ := calculate_sum
# PYASTLEANCHECK END


answer = 42

fruits = ["apple", "banana", "cherry"]
scores = {"math": 95, "science": 90}

def greet(name):
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
