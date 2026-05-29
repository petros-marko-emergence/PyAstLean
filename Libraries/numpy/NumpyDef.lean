import Mathlib

namespace Libraries.numpy

/-- Types that can be treated as NumPy numeric entries by the runtime layer. -/
class PyNumpyScalar (α : Type) where
  toFloat : α → Float

export PyNumpyScalar (toFloat)

instance : PyNumpyScalar Float where
  toFloat := id

instance : PyNumpyScalar Rat where
  toFloat := Rat.toFloat

instance : PyNumpyScalar Int where
  toFloat x := Rat.toFloat (x : Rat)

instance : PyNumpyScalar Nat where
  toFloat x := Rat.toFloat (x : Rat)

instance : PyNumpyScalar Bool where
  toFloat b := if b then 1.0 else 0.0

/-- Convert a nonnegative `Int` dimension to `Nat`. -/
def pyNumpyNatFromInt (n : Int) : Nat :=
  if n < 0 then
    panic! "ValueError: numpy dimensions must be nonnegative"
  else
    n.toNat

/-- Number of rows in a matrix. -/
def pyNumpyRows {α} (matrix : List (List α)) : Nat :=
  matrix.length

/-- Number of columns in a matrix, taken from the first row. -/
def pyNumpyCols {α} (matrix : List (List α)) : Nat :=
  match matrix with
  | [] => 0
  | row :: _ => row.length

/-- Check that every row has the same length. -/
def pyNumpyIsRectangular {α} (matrix : List (List α)) : Bool :=
  match matrix with
  | [] => true
  | row :: rows => rows.all (fun r => r.length = row.length)

/-- Check that a matrix is square. -/
def pyNumpyIsSquare {α} (matrix : List (List α)) : Bool :=
  pyNumpyIsRectangular matrix &&
    match matrix with
    | [] => true
    | row :: _ => matrix.length = row.length

/-- Compare the shapes of two matrices. -/
def pyNumpySameShape? {α β} (lhs : List (List α)) (rhs : List (List β)) : Bool :=
  match lhs, rhs with
  | [], [] => true
  | l :: ls, r :: rs => l.length = r.length && pyNumpySameShape? ls rs
  | _, _ => false

/-- Normalize a matrix to `Float` entries. -/
def pyNumpyArray {α} [PyNumpyScalar α] (matrix : List (List α)) : List (List Float) :=
  matrix.map (List.map toFloat)

/-- Return the matrix shape as `(rows, cols)`. -/
def pyNumpyShape {α} (matrix : List (List α)) : Int × Int :=
  if pyNumpyIsRectangular matrix then
    (Int.ofNat matrix.length, Int.ofNat (pyNumpyCols matrix))
  else
    panic! "ValueError: shape() expects a rectangular matrix"

/-- Flatten a matrix into a vector. -/
def pyNumpyFlatten {α} [PyNumpyScalar α] (matrix : List (List α)) : List Float :=
  (pyNumpyArray matrix).flatten

end Libraries.numpy
