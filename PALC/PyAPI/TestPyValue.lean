import PastaLean.PyAPI.PyValue

/-! Runtime checks for the `PyValue` boxing fallback. -/

open PastaLean

-- A multi-return function boxes to `PyValue` by coercing each branch — no explicit wrapper.
private def classify (x : Int) : PyValue := if x > 0 then "positive" else (0 : Int)

/-- info: "positive" -/
#guard_msgs in #eval pyStringify (classify 5)
/-- info: "0" -/
#guard_msgs in #eval pyStringify (classify (-3))

-- Each scalar type boxes and prints with Python's `str()` form.
#guard pyStringify (toValue (42 : Int)) == "42"
#guard pyStringify (toValue true) == "True"
#guard pyStringify (toValue "hi") == "hi"
#guard pyStringify (PyValue.none) == "None"
-- A list prints with quoted string elements (Python `repr` inside a container).
#guard pyStringify (PyValue.list [.int 1, .str "a"]) == "[1, 'a']"

-- Truthiness matches Python: 0 / "" / None / [] are falsy.
#guard pyTruthy (PyValue.int 0) == false
#guard pyTruthy (PyValue.int 3) == true
#guard pyTruthy (PyValue.str "") == false
#guard pyTruthy (PyValue.none) == false
#guard pyTruthy (PyValue.list []) == false
#guard pyTruthy (PyValue.list [.int 1]) == true

-- Boxing round-trips by equality.
#guard (toValue (5 : Int)) == PyValue.int 5
