import Mathlib
import PastaLean.PyAPI.CommonProtocols.Iterable

namespace Libraries.bisect

/-- The `a[lo:hi]` window (Python defaults: `lo=0`, `hi=len(a)`, encoded here as `hi < 0`). -/
private def bisectWindow {α : Type} (a : List α) (lo hi : Int) : Nat × List α :=
  let loN := lo.toNat
  let hiN := if hi < 0 then a.length else hi.toNat
  (loN, (a.drop loN).take (hiN - loN))

/-- `bisect.bisect_left(a, x, lo=0, hi=len(a))`: the leftmost index in `a[lo:hi]` at which `x` keeps
`a` sorted. `pyBisectLeft [1, 3, 3, 5] 3 = 1`. -/
def pyBisectLeft {α : Type} [LinearOrder α] (a : List α) (x : α) (lo : Int := 0) (hi : Int := -1) : Int :=
  let (loN, w) := bisectWindow a lo hi
  Int.ofNat loN + Int.ofNat (w.countP (fun y => decide (y < x)))

/-- `bisect.bisect_right(a, x, lo=0, hi=len(a))`: the rightmost such index in `a[lo:hi]`.
`pyBisectRight [1, 3, 3, 5] 3 = 3`. -/
def pyBisectRight {α : Type} [LinearOrder α] (a : List α) (x : α) (lo : Int := 0) (hi : Int := -1) : Int :=
  let (loN, w) := bisectWindow a lo hi
  Int.ofNat loN + Int.ofNat (w.countP (fun y => decide (y ≤ x)))

end Libraries.bisect
