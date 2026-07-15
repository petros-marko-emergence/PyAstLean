import PastaLean.PyAPI.PyPrint
import PastaLean.PyAPI.CommonProtocols.Truthy
import PastaLean.PyAPI.CommonProtocols.GetItem
import PastaLean.PyAPI.CommonProtocols.SetItem
import PastaLean.PyAPI.CommonProtocols.Length
import PastaLean.PyAPI.CommonProtocols.Iterable
import PastaLean.PyAPI.Operators

/-!
# `PyValue` — the dynamic-value fallback

When type inference cannot give a value a single Lean type — a variable that is an `int` on one path
and a `str` on another, a function that returns different types per branch — the value is boxed as a
`PyValue`. Every Python value maps into `PyValue`, so a boxed slot always type-checks; the cost is
that a boxed value is not provable (it is not a commutative ring), which is why boxing is a last
resort the code generator warns about.

Boxing is automatic at the boundary: a `CoeTail` instance means `return 1` and `return "neg"` in the
same function both coerce to `PyValue` with no explicit wrapper. (`PyValue` rather than `PyAny`
because `PyAny` is already the `any()`-builtin typeclass in `CommonProtocols/AnyFunc.lean`.)
-/

namespace PastaLean

/-- A boxed Python value: whatever a slot could not be given a single static type. -/
inductive PyValue where
  | int   (n : Int)
  | bool  (b : Bool)
  | str   (s : String)
  | float (q : Rat)
  | list  (xs : List PyValue)
  | none
  deriving Inhabited, Repr, BEq

namespace PyValue

/-- Python `str()` of a boxed value; `repr` is the form shown *inside* a container (strings quoted). -/
partial def toStr (repr : Bool) : PyValue → String
  | .int n   => toString n
  | .bool b  => if b then "True" else "False"
  | .str s   => if repr then "'" ++ s ++ "'" else s
  | .float q => toString (Rat.toFloat q)
  | .none    => "None"
  | .list xs => "[" ++ String.intercalate ", " (xs.map (toStr true)) ++ "]"

end PyValue

/-- Box a value of a known type into `PyValue`. -/
class PyToValue (α : Type) where
  toValue : α → PyValue

export PyToValue (toValue)

instance : PyToValue PyValue where toValue := id
instance : PyToValue Int     where toValue := .int
instance : PyToValue Nat     where toValue n := .int n
instance : PyToValue Bool    where toValue := .bool
instance : PyToValue String  where toValue := .str
instance : PyToValue Char    where toValue c := .str (String.singleton c)
instance : PyToValue Rat     where toValue := .float
instance : PyToValue Unit    where toValue _ := .none
instance {α : Type} [PyToValue α] : PyToValue (List α)   where toValue xs := .list (xs.map toValue)
instance {α : Type} [PyToValue α] : PyToValue (Option α) where
  toValue | some x => toValue x | none => .none

/-- Automatic boxing at a boundary: a branch of a known type coerces to `PyValue`, so the two arms
of `if c then 1 else "neg"` unify at `PyValue` with no explicit wrapper. Concrete source types only —
a generic `CoeTail α PyValue` has no synthesization order (the source `α` is unconstrained). -/
instance : CoeTail Int PyValue    where coe := .int
instance : CoeTail Nat PyValue    where coe n := .int n
instance : CoeTail Bool PyValue   where coe := .bool
instance : CoeTail String PyValue where coe := .str
instance : CoeTail Char PyValue   where coe c := .str (String.singleton c)
instance : CoeTail Rat PyValue    where coe := .float
instance : CoeTail (List PyValue) PyValue where coe := .list
instance : CoeTail (List Int) PyValue     where coe xs := .list (xs.map .int)
instance : CoeTail (List String) PyValue  where coe xs := .list (xs.map .str)

-- Numerals are polymorphic via `OfNat`, not coercion, so a bare `0`/`5` in a boxed position needs
-- these (codegen usually emits typed literals like `(0 : Int)`, which coerce, but not always).
instance (n : Nat) : OfNat PyValue n where ofNat := .int n
instance : Neg PyValue where neg | .int n => .int (-n) | .float q => .float (-q) | v => v

/-! ### Dynamic arithmetic — dispatch on the runtime tag

This is what makes a boxed polymorphic function like `def add(a, b): return a + b` run at *both* `int`
and `str`: `a +ₚ b` is one definition that inspects the constructors at runtime. Same-type operands
combine as Python does (`int+int`, `str++str`, `list++list`); numeric operands promote to `float`;
`bool` counts as `0`/`1`. A genuine mismatch (`1 + "a"`) yields `none` rather than raising — a soft
failure that keeps the operation total. -/

namespace PyValue

private def asNum : PyValue → Option (Sum Int Rat)
  | .int n => some (.inl n)
  | .bool b => some (.inl (if b then 1 else 0))
  | .float q => some (.inr q)
  | _ => .none

/-- Apply integer/rational ops to two numeric boxes, promoting to `float` if either is a float. -/
private def numBinop (fi : Int → Int → Int) (fq : Rat → Rat → Rat) (a b : PyValue) : Option PyValue :=
  match asNum a, asNum b with
  | some (.inl x), some (.inl y) => some (.int (fi x y))
  | some x, some y =>
      let toRat : Sum Int Rat → Rat := fun | .inl n => (n : Rat) | .inr q => q
      some (.float (fq (toRat x) (toRat y)))
  | _, _ => .none

def add : PyValue → PyValue → PyValue
  | .str a, .str b => .str (a ++ b)
  | .list a, .list b => .list (a ++ b)
  | a, b => (numBinop (· + ·) (· + ·) a b).getD .none

def sub (a b : PyValue) : PyValue := (numBinop (· - ·) (· - ·) a b).getD .none
def mul : PyValue → PyValue → PyValue
  | .str a, .int n => .str (String.join (List.replicate n.toNat a))
  | .int n, .str a => .str (String.join (List.replicate n.toNat a))
  | a, b => (numBinop (· * ·) (· * ·) a b).getD .none

end PyValue

instance : PyHAdd PyValue PyValue PyValue where hAdd := PyValue.add
instance : PyHSub PyValue PyValue PyValue where hSub := PyValue.sub
instance : PyHMul PyValue PyValue PyValue where hMul := PyValue.mul

/-! ### Container protocols — delegate to the boxed value's own instance

A boxed slot that is indexed, iterated, or `len`-ed dispatches on the runtime tag and reuses the
concrete `List`/`String` instance (no reimplementation); the element is reboxed as `PyValue`. This
is why an un-inferred parameter can still be subscripted (`x[i]`, `x[i]=v`), looped, or measured. -/

instance : PyGetItem PyValue Int PyValue where
  getItem v i :=
    match v with
    | .list xs => pyListGetItem xs i
    | .str s => .str (pyStringGetItemStr s i)
    | _ => .none

instance : PySetItem PyValue Int PyValue where
  setItem v i x :=
    match v with
    | .list xs => .list (pySetItem xs i x)
    | _ => v

instance : PyLen PyValue where
  pyLen
    | .list xs => xs.length
    | .str s => s.length
    | _ => 0

instance : PyIterable PyValue PyValue where
  toPyList
    | .list xs => xs
    | .str s => s.toList.map (fun c => .str c.toString)
    | _ => []

instance : PyPrintable PyValue where pyStringify := PyValue.toStr false
instance : PyTruthy PyValue where
  truthy
    | .int n => n != 0
    | .bool b => b
    | .str s => !s.isEmpty
    | .float q => q != 0
    | .none => false
    | .list xs => !xs.isEmpty

end PastaLean
