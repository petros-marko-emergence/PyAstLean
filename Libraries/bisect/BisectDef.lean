import Mathlib
import PastaLean.PyAPI.CommonProtocols.Iterable

namespace Libraries.bisect

/-- `bisect.bisect_left(a, x)`: how many elements of `a` are `< x`, i.e. the leftmost index at
which `x` keeps `a` sorted. `pyBisectLeft [1, 3, 3, 5] 3 = 1`. -/
def pyBisectLeft {α : Type} [LinearOrder α] (a : List α) (x : α) : Int :=
  Int.ofNat (a.countP (fun y => decide (y < x)))

/-- `bisect.bisect_right(a, x)`: how many elements of `a` are `≤ x`, i.e. the rightmost such index.
`pyBisectRight [1, 3, 3, 5] 3 = 3`. -/
def pyBisectRight {α : Type} [LinearOrder α] (a : List α) (x : α) : Int :=
  Int.ofNat (a.countP (fun y => decide (y ≤ x)))

end Libraries.bisect
