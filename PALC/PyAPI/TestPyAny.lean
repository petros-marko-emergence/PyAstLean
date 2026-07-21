import PastaLean.PyAPI.PyAny

/-! Runtime checks for the `PyAny` boxing fallback. -/

open PastaLean

-- A multi-return function boxes to `PyAny` by coercing each branch — no explicit wrapper.
private def classify (x : Int) : PyAny := if x > 0 then "positive" else (0 : Int)

/-- info: "positive" -/
#guard_msgs in #eval pyStringify (classify 5)
/-- info: "0" -/
#guard_msgs in #eval pyStringify (classify (-3))

-- Each scalar type boxes and prints with Python's `str()` form.
#guard pyStringify (toValue (42 : Int)) == "42"
#guard pyStringify (toValue true) == "True"
#guard pyStringify (toValue "hi") == "hi"
#guard pyStringify (PyAny.none) == "None"
-- A list prints with quoted string elements (Python `repr` inside a container).
#guard pyStringify (PyAny.list [.int 1, .str "a"]) == "[1, 'a']"

-- Truthiness matches Python: 0 / "" / None / [] are falsy.
#guard pyTruthy (PyAny.int 0) == false
#guard pyTruthy (PyAny.int 3) == true
#guard pyTruthy (PyAny.str "") == false
#guard pyTruthy (PyAny.none) == false
#guard pyTruthy (PyAny.list []) == false
#guard pyTruthy (PyAny.list [.int 1]) == true

def add (a b : PyAny) : PyAny := a +ₚ b

/-- info: PastaLean.PyAny.int 8 -/
#guard_msgs in
#eval add 3 5

/-- info: PastaLean.PyAny.str "hiworld" -/
#guard_msgs in
#eval add "hi" "world"

/-- info: PastaLean.PyAny.none -/
#guard_msgs in
#eval add 3 "neg" -- type mismatch: int + str is not defined

/-
If this seems odd, the below snippet is from Python Repl:
```python
>>> True + True
2
```
-/
/-- info: PastaLean.PyAny.int 2 -/
#guard_msgs in
#eval add true true


-- Boxing round-trips by equality.
#guard (toValue (5 : Int)) == PyAny.int 5
