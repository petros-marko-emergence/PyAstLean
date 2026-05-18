import Mathlib
import PyAstLean.PyAPI.Dicts

namespace PyAstLean

/--
Protocol for Python-style `pop`.

Different runtime types may use different key/index types and element/value types, so
the protocol carries both as associated types.
-/
class PyPop (α : Type) where
  Key : Type
  Elem : Type
  /--
  For dictionary-like types, `default` is used when the key is missing.
  For list-like types, `default` is used when the index is out of bounds.
  -/
  pyPop : α → Key → Option Elem → (Option Elem × α)

/--
Codegen should target this stable name; concrete types extend the behavior by adding
`PyPop` instances.
-/
def pyPop {α : Type} [inst : PyPop α] (container : α) (key : inst.Key)
    (default : Option inst.Elem := none) : (Option inst.Elem × α) :=
  inst.pyPop container key default

/--
Local list-pop helper kept here to avoid importing `PyAstLean.PyAPI.Lists`, which
currently exposes other public method names that clash with dictionary names.
-/
def pyProtocolListPop (xs : List α) (idx : Int) (default : Option α := none) : (Option α × List α) :=
  if 0 <= idx then
    let natIdx := idx.toNat
    if hUpper : natIdx < xs.length then
      let value := xs.get ⟨natIdx, hUpper⟩
      (some value, xs.eraseIdx natIdx)
    else
      (default, xs)
  else
    (default, xs)

/-- Popping from List -/
instance : PyPop (List α) where
  Key := Int
  Elem := α
  pyPop xs idx default := pyProtocolListPop xs idx default

/-- Instance for popping from a HashMap. -/
instance [BEq α] [Hashable α] : PyPop (Std.HashMap α β) where
  Key := α
  Elem := β
  pyPop m key default := pyDictPop m key default

end PyAstLean
