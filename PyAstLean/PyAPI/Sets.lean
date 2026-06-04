import Mathlib
import PyAstLean.PyAPI.CommonProtocols.Iterable

namespace PyAstLean

/-!
Python-style sets.

Sets are modeled as a deduplicated `List` so that the existing list-backed protocols
(`pyContains` for `in`, `pyLen` for `len`, `PyIterable` for iteration/comprehensions) apply
unchanged. Elements only need `BEq` for the membership checks. Insertion order is preserved,
which is irrelevant to Python set semantics but keeps output deterministic.

Like the other container runtimes these are immutable values: `s.add(x)` rebuilds the list
and the codegen reassigns the variable (`s := pySetAdd s x`).
-/

/-- Build a set from a list, dropping duplicates (used for `{a, b, c}` literals and `set(xs)`). -/
def pySetFromList {α : Type} [BEq α] (xs : List α) : List α :=
  xs.foldl (fun acc x => if acc.contains x then acc else acc ++ [x]) []

/-- Python `set(iterable)` for any iterable (lists, `range(...)`, comprehensions, strings,
`map`/`zip` results), normalized through `pyIter` so `set("abc")`, `set(range(n))`, etc. work. -/
def pySet {α β : Type} [PyIterable β α] [BEq α] (xs : β) : List α :=
  pySetFromList (pyIter xs)

/-- Python `s.add(x)`: insert `x` if not already present. -/
def pySetAdd {α : Type} [BEq α] (s : List α) (x : α) : List α :=
  if s.contains x then s else s ++ [x]

/-- Python `s.discard(x)`: remove `x` if present (no error if absent). -/
def pySetDiscard {α : Type} [BEq α] (s : List α) (x : α) : List α :=
  s.filter (fun y => y != x)

/-- Python `s.remove(x)`: like `discard` here (we do not raise `KeyError` on absence). -/
def pySetRemove {α : Type} [BEq α] (s : List α) (x : α) : List α :=
  pySetDiscard s x

end PyAstLean
